/// Node 运行时宿主：为每个源起一个本机 Node 进程承载 drpyS 服务。
///
/// 实测结论（见 `.workbuddy-ai/tmp/x1probe/`）：
///   - 源是**完整的 Node 程序**，导出 `{start, stop}`；`start()` 监听 `127.0.0.1:9988`
///   - 端口**硬编码 9988**
///   - `start()` 的 Promise 可能 reject（`Cannot read properties of undefined
///     (reading 'slice')`），但**发生在监听之后**，服务仍可用 → 必须 catch
///   - 源会向 **CWD 写文件**（`wexfnwconfig.json` 等）→ 必须给独立工作目录
///
/// 因此本宿主负责：准备目录 → 生成 bootstrap 脚本 → 起进程 → 等端口就绪
/// → 静默吞掉已知的非致命 rejection → 退出时回收进程。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Node 进程的状态。
enum NodeStatus { stopped, starting, running, failed }

/// 一个运行中的源服务实例。
class SourceRuntime {
  final String sourceId;
  final String workDir;
  final String entryFile;
  final int port;

  NodeStatus status = NodeStatus.stopped;
  String? lastError;
  Process? _process;
  final List<String> _log = <String>[];

  SourceRuntime({
    required this.sourceId,
    required this.workDir,
    required this.entryFile,
    required this.port,
  });

  /// 最近的日志（环形，最多 200 行）。
  List<String> get log => List.unmodifiable(_log);

  String get baseUrl => 'http://127.0.0.1:$port';

  bool get isRunning => status == NodeStatus.running;

  /// 启动 Node 服务。
  ///
  /// [nodeExecutable] 是 `node.exe` 的路径。启动后轮询 [port] 直到 `/health`
  /// 返回 200，或超时。
  Future<void> start({required String nodeExecutable}) async {
    if (status == NodeStatus.running) return;
    status = NodeStatus.starting;
    lastError = null;

    // 独立工作目录 —— 源会往 CWD 写文件，绝不能落到安装目录
    final wd = Directory(workDir);
    if (!wd.existsSync()) wd.createSync(recursive: true);

    final boot = File(p.join(workDir, '_bootstrap.cjs'));
    boot.writeAsStringSync(_bootstrapScript(entryFile));

    try {
      // 清理代理环境变量（实测踩坑，务必保留）
      //
      // 本机实测：环境里存在 HTTP_PROXY/HTTPS_PROXY 指向一个**仅对父进程
      // 有效**的本地代理端口（如 127.0.0.1:59439）。子进程继承后，源内部的
      // undici/fetch 会尝试走这个代理，结果连接被拒：
      //     upstream connect failed: 由于目标计算机积极拒绝 (os error 10061)
      // 于是 /config、/spider/* 等所有需要出网的接口全部 502。
      //
      // 源的出网应当直连（或走系统级代理），不能继承宿主进程的临时代理。
      // 这里显式把 4 个变量置空；同时用 NO_PROXY 兜底放通本地回环。
      final env = Map<String, String>.from(Platform.environment)
        ..['HTTP_PROXY'] = ''
        ..['HTTPS_PROXY'] = ''
        ..['http_proxy'] = ''
        ..['https_proxy'] = ''
        ..['NO_PROXY'] = '127.0.0.1,localhost'
        ..['no_proxy'] = '127.0.0.1,localhost';

      final proc = await Process.start(
        nodeExecutable,
        [boot.path],
        workingDirectory: workDir,
        environment: env,
        runInShell: false,
      );
      _process = proc;

      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onLine);

      unawaited(proc.exitCode.then((code) {
        if (status != NodeStatus.stopped) {
          status = NodeStatus.failed;
          lastError = 'Node 进程退出（code=$code）';
        }
      }));
    } catch (e) {
      status = NodeStatus.failed;
      lastError = '无法启动 Node：$e';
      throw SourceRuntimeException(lastError!);
    }

    final ok = await _waitForHealth(port);
    if (!ok) {
      status = NodeStatus.failed;
      lastError = lastError ?? '等待服务就绪超时（端口 $port 无响应）';
      throw SourceRuntimeException(lastError!);
    }
    status = NodeStatus.running;
  }

  /// 停止并回收进程。
  Future<void> stop() async {
    status = NodeStatus.stopped;
    final proc = _process;
    _process = null;
    if (proc == null) return;
    try {
      proc.kill(ProcessSignal.sigterm);
      await proc.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (_) {
      // 进程可能已自行退出
    }
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    _log.add(line);
    if (_log.length > 200) _log.removeAt(0);

    // `start()` 的非致命 rejection：源码实测会抛
    // `Cannot read properties of undefined (reading 'slice')`，
    // 但服务已监听成功。记录但不视为失败。
    if (line.contains('start rejected') || line.contains('start() rejected')) {
      lastError = line;
    }
  }

  /// 轮询 `/health` 直到 200 或超时（最多 30 秒）。
  Future<bool> _waitForHealth(int port) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 2);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (_process == null) return false;
        try {
          final req = await client
              .getUrl(Uri.parse('http://127.0.0.1:$port/health'))
              .timeout(const Duration(seconds: 2));
          final resp = await req.close().timeout(const Duration(seconds: 2));
          final body = await resp.transform(utf8.decoder).join();
          if (resp.statusCode == 200 && body.contains('CatVodSpiderios')) {
            return true;
          }
        } catch (_) {
          // 尚未监听，继续等
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    } finally {
      client.close(force: true);
    }
    return false;
  }

  /// 生成 bootstrap 脚本。
  ///
  /// 要点：
  ///   - 用相对路径 require，避免 Windows 反斜杠转义问题
  ///   - `process.on('unhandledRejection')` 吞掉已知非致命 rejection
  ///   - 原样转发源的所有 stdout，便于诊断
  static String _bootstrapScript(String entryFile) => '''
// 由 WebHTV 桌面端自动生成 —— 请勿手工修改
const path = require('path');
const entry = ${jsonEncode(entryFile)};

process.on('unhandledRejection', (err) => {
  // 源实测会抛 "Cannot read properties of undefined (reading 'slice')"，
  // 发生在服务已监听之后，属已知非致命问题。记录但不退出。
  console.log('[host] unhandledRejection: ' + (err && err.message ? err.message : String(err)));
});

process.on('uncaughtException', (err) => {
  console.log('[host] uncaughtException: ' + (err && err.message ? err.message : String(err)));
});

(async () => {
  try {
    const mod = require(path.resolve(entry));
    if (!mod || typeof mod.start !== 'function') {
      console.log('[host] fatal: 源没有导出 start() 函数');
      process.exit(1);
    }
    await mod.start();
  } catch (err) {
    // start() 的 rejection 不一定是致命的（可能已监听成功），
    // 因此只记录，让进程继续存活；由客户端的 /health 探测决定成败。
    console.log('[host] start rejected: ' + (err && err.message ? err.message : String(err)));
  }
})();

// 保持进程存活
setInterval(() => {}, 1 << 30);
''';
}

class SourceRuntimeException implements Exception {
  final String message;
  const SourceRuntimeException(this.message);

  @override
  String toString() => 'SourceRuntimeException: $message';
}
