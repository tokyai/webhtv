/// iOS 端 Node 运行时绑定（进程内 Node，非子进程）。
///
/// ## 为什么 iOS 走完全不同的路径
///
/// Windows/Linux/macOS 桌面端可以 `Process.start(node.exe, [boot])` 起一个
/// **独立 Node 进程**，靠 HTTP（127.0.0.1:9988）与宿主通信，宿主死则用
/// 心跳/PID 看护把它带走。**iOS 做不到**：
///
///   1. iOS **禁止 spawn 子进程**（App Store 沙盒限制，`fork/exec` 直接
///      失败）。没有独立的 `node` 可执行文件可起。
///   2. 因此 iOS 走 **nodejs-mobile** 路线：把 Node 引擎作为**静态/动态库
///      链接进 App 本体**，在**宿主进程内**跑事件循环。
///
/// ## 谁提供 C 符号
///
/// `ios/flutter_node`（手工 vendor 的本地 pod）里：
///   - `Frameworks/NodeMobile.framework` = com.janeasystems.NodeMobile，
///     只导出一个 C 入口 `node_start(argc, argv)`（2 参、阻塞、跑完整个
///     事件循环才返回）。
///   - `Classes/NodeWrapper.c` 补齐了 camelCase 三件套
///     `nodeStart` / `nodeStartThread` / `nodeStop`（按原版
///     flutter_node.framework 的反汇编逐条还原），内部用
///     `dlsym(RTLD_DEFAULT, "node_start")` 解析真实符号。
///
/// ## 为什么必须用 `nodeStartThread` 而不是 `nodeStart`
///
/// `nodeStart` 是**阻塞**的（在调用者线程上跑完整个事件循环），在 Flutter
/// 的 platform/UI 线程上调用会**冻结界面**。`nodeStartThread` 起一个
/// pthread 跑 `node_start` 后立即返回，是唯一正确用法。
///
/// ## 为什么这里不需要心跳看护
///
/// Node 与宿主在**同一进程**里。宿主进程一死，Node 事件循环随之消失，
/// 不存在「孤儿 Node 占着 9988」的问题。心跳文件与 `process.ppid` 判据
/// 在 iOS 上既不可靠（ppid 恒为自身）也无必要。
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// `int nodeStartThread(int argc, char** argv, void* cb)`
typedef _NodeStartThreadNative = Int32 Function(Int32 argc, Pointer<Pointer<Utf8>> argv, Pointer<Void> cb);
typedef _NodeStartThreadDart = int Function(int argc, Pointer<Pointer<Utf8>> argv, Pointer<Void> cb);

/// `int nodeStop(void)`
typedef _NodeStopNative = Int32 Function();
typedef _NodeStopDart = int Function();

/// 进程内 Node 的启动器。
///
/// 单例语义 —— nodejs-mobile 的 `NodeWrapper.c` 用 `g_running/g_thread_valid`
/// 保证同时只有一个 Node 实例；重复启动会返回 -1。
class IosNodeRuntime {
  IosNodeRuntime._();

  static _NodeStartThreadDart? _startThread;
  static _NodeStopDart? _stop;

  /// Node 是否已启动过一次（用于幂等保护）。
  static bool _started = false;

  /// 最近一次启动的返回码：0 成功，-1 失败。
  static int lastStartResult = -1;

  /// 解析并缓存 C 符号。
  ///
  /// 用 `DynamicLibrary.process()` —— **不是** `DynamicLibrary.open('NodeMobile')`。
  /// 原因：`NodeWrapper.c` 编进 `flutter_node` 这个 pod 后，符号落在主可执行
  /// 文件（或它与 pod 合并出的动态库）的全局符号表里，而不是一个按路径
  /// 可 dlopen 的独立镜像。原版 flutter_node.framework 的 AOT 快照里也没有
  /// 任何 "NodeMobile"/"flutter_node" 路径字符串，印证了这一点。
  static void _ensureSymbols() {
    if (_startThread != null) return;
    final lib = DynamicLibrary.process();
    _startThread = lib.lookupFunction<_NodeStartThreadNative, _NodeStartThreadDart>('nodeStartThread');
    _stop = lib.lookupFunction<_NodeStopNative, _NodeStopDart>('nodeStop');
  }

  /// 在独立线程里启动 Node 并立即返回。
  ///
  /// [argv] 必须至少含两项：`[可执行名, 脚本路径]`。
  /// 与桌面端 `Process.start(nodeExe, [boot])` 的 argv 形状保持一致，
  /// 这样 bootstrap 脚本里 `__dirname` / `process.argv[1]` 的用法无需改动。
  ///
  /// 返回 true 表示已成功交给 Node（不代表服务已就绪），false 表示启动失败。
  /// 是否真正可用请由调用方轮询 `/health` 判定。
  static bool start(List<String> argv) {
    if (!Platform.isIOS) {
      throw StateError('IosNodeRuntime 只能在 iOS 上使用');
    }
    if (_started) {
      // 进程内 Node 刻意不重启（NodeMobile 无 node_stop 导出，无法真实停止），
      // 重复调用只会让 NodeWrapper 返回 -1。
      return lastStartResult == 0;
    }
    _ensureSymbols();

    final args = argv.isEmpty ? const ['node'] : argv;
    // argv 用 C 字符串数组传给 Node，必须在整段 Node 生命周期内保持有效，
    // 因此用 calloc 分配（不能是会被 GC 回收的 Dart 内存）。
    final argvPtr = calloc<Pointer<Utf8>>(args.length);
    for (var i = 0; i < args.length; i++) {
      argvPtr[i] = args[i].toNativeUtf8();
    }

    final rc = _startThread!(args.length, argvPtr, nullptr);
    lastStartResult = rc;
    _started = true;
    return rc == 0;
  }

  /// 重置标志位。
  ///
  /// ⚠️ NodeMobile **没有** `node_stop` 导出，`nodeStop` 只是把
  /// `g_running`/`g_thread_valid` 清零，**并不会真正停止事件循环**。
  /// 这与安卓侧「内嵌 Node 刻意不停止（进程级单例）」的结论一致。
  /// 这里保留该调用只是为了语义完整，不要指望它释放端口。
  static void stop() {
    if (!Platform.isIOS) return;
    try {
      _ensureSymbols();
      _stop?.call();
    } catch (_) {
      // 忽略：停止失败不影响进程退出
    }
  }
}
