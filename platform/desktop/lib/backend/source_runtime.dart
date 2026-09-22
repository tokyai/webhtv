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

  /// 心跳定时器。每 5 秒 touch 一次 `.host-alive`，让 Node 子进程知道宿主还活着。
  /// 宿主消失后子进程会在约 15 秒内自杀，避免端口 9988 被孤儿永久占用。
  Timer? _heartbeat;

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
    // `pid` 是 dart:io 的顶层 getter，返回当前（宿主）进程 PID。
    // Node 侧用它作快速判据：ppid 一旦不等于它，说明宿主已退出。
    boot.writeAsStringSync(_bootstrapScript(entryFile, pid));

    // 心跳：先删陈旧文件再新建，避免继承上一个宿主留下的新鲜 mtime
    // （会让子进程误以为宿主一直在，从而在宿主已死后继续占着端口）。
    _touchHeartbeat();

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
      await stop();
      throw SourceRuntimeException(lastError!);
    }
    status = NodeStatus.running;

    // 服务就绪后开始维持心跳（每 5 秒），子进程侧 TTL 为 15 秒。
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _touchHeartbeat(),
    );
  }

  /// touch 心跳文件（`.host-alive`）。
  ///
  /// 用**写内容**而非 `setLastModified` —— 后者在部分文件系统上不更新 mtime，
  /// 会导致子进程误判宿主已死。
  ///
  /// 注意：这里**只覆写、不删除**。早期实现是「先 delete 再 create」以保证
  /// mtime 绝对新鲜，但那会开一个竞态窗口：Node 若恰好在此刻 `statSync`，
  /// 会读到文件不存在而判定心跳丢失。覆写同样推进 mtime，且没有这个窗口。
  void _touchHeartbeat() {
    try {
      final f = File(p.join(workDir, '.host-alive'));
      if (!f.existsSync()) f.createSync(recursive: true);
      f.writeAsStringSync('${DateTime.now().millisecondsSinceEpoch}');
    } catch (_) {
      // 心跳失败不致命：子进程有宽限期，短暂失败不会触发退出
    }
  }

  /// 停止并回收进程。
  ///
  /// Windows 注意事项：Dart 在 Windows 上**不支持 `sigterm`** —— 调用会抛
  /// `UnsupportedError`，且 POSIX「优雅退出」语义在 Windows 没有对应物
  /// （只有 `TerminateProcess`）。因此这里在 Windows 直接走 `sigkill`，
  /// 在类 Unix 上先试 `sigterm` 给 5 秒窗口，超时再 `sigkill`。
  ///
  /// 另外要理解：源是在 bootstrap 壳进程内 `require()` 运行的，**不是**壳的子
  /// 进程；杀掉壳就等于杀掉服务，不存在「子进程逃逸」问题。
  Future<void> stop() async {
    status = NodeStatus.stopped;
    _heartbeat?.cancel();
    _heartbeat = null;
    final proc = _process;
    _process = null;
    if (proc == null) return;

    if (Platform.isWindows) {
      // Windows 只有强杀
      try {
        proc.kill(ProcessSignal.sigkill);
        await proc.exitCode.timeout(const Duration(seconds: 5));
      } catch (_) {
        // 进程可能已自行退出
      }
      return;
    }

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
  ///   - **宿主看护**：心跳 + PID 双判据，宿主消失后自行退出（防孤儿）
  ///   - 原样转发源的所有 stdout，便于诊断
  static String _bootstrapScript(String entryFile, int hostPid) => '''
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

// ---------------------------------------------------------------------------
// 宿主看护（防孤儿进程）
//
// 为什么需要：本进程监听固定的 9988 端口。若宿主（Flutter 应用）被强杀、
// 崩溃或未走正常退出路径，本进程**不会自动消失**，端口就此被永久占住；
// 下次启动时预检会发现 9988 被占，用户看到「端口被占用」却找不到凶手。
//
// ⚠️ 不能只依赖宿主侧的 `AppLifecycleListener.onExitRequested`：
//   Flutter Windows 的该回调基于 `IsLastWindowOfProcess()` 判定，只要进程内
//   存在**任意其它顶层窗口**（native 库常会创建隐藏辅助窗口 —— 例如图形/
//   播放库），引擎就认为「这不是最后一个窗口」，**回调不会被派发**，
//   窗口直接关闭。见 flutter/flutter#192304。
//   因此必须在本进程内自保。
//
// 双判据，任一成立即退出：
//   A. 心跳文件：宿主每 5 秒 touch，超时 15 秒即认为宿主已死（**主判据**，
//      语义准确，不受 PID 复用影响）
//   B. 父进程 PID：`process.ppid` 不等于启动时记录的宿主 PID，立即退出
//      （**快速判据**，秒级发现；仅作加速，单独使用不可靠）
// ---------------------------------------------------------------------------
const fs = require('fs');
const hbPath = path.join(__dirname, '.host-alive');
const HB_TTL_MS = 15000;
const HOST_PID = $hostPid;

let hbMissingSince = 0;
let pidMismatchTicks = 0;

setInterval(() => {
  // ---- 判据 B：父进程 PID 变化（快速路径）----
  // 只在明确不等时才计数，连续 2 次（约 4 秒）确认，避免进程组重排误判。
  if (HOST_PID > 0 && process.ppid !== HOST_PID) {
    pidMismatchTicks++;
    if (pidMismatchTicks >= 2) {
      console.log('[host] 宿主 PID 已变化 (ppid=' + process.ppid +
        ', expected=' + HOST_PID + ')，自行退出以释放端口 9988');
      process.exit(0);
    }
  } else {
    pidMismatchTicks = 0;
  }

  // ---- 判据 A：心跳文件（主路径）----
  let alive = false;
  try {
    const st = fs.statSync(hbPath);
    alive = (Date.now() - st.mtimeMs) < HB_TTL_MS;
  } catch (_) {
    alive = false;
  }
  if (alive) {
    hbMissingSince = 0;
    return;
  }
  if (hbMissingSince === 0) {
    hbMissingSince = Date.now();
    return;
  }
  // 给予宽限期：宿主可能在启动早期还没写心跳
  if (Date.now() - hbMissingSince > 3000) {
    console.log('[host] 宿主心跳丢失，自行退出以释放端口 9988');
    process.exit(0);
  }
}, 2000);

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
