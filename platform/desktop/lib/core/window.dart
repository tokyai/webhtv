import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// 桌面端窗口控制（Windows）。
///
/// 项目没有引入 `window_manager` 插件，这里用已有的 `ffi` 依赖直接调
/// `user32.dll` / `kernel32.dll`，避免新增平台插件与构建配置。
///
/// 全屏语义与窗口最大化一致（`SW_MAXIMIZE`），切回时用 `SW_RESTORE`
/// 恢复成切换前的窗口状态。
///
/// ## 为什么不用 `GetForegroundWindow`
///
/// 早期实现用 `GetForegroundWindow()` 拿句柄再 `ShowWindow`，这是**错的**：
/// 当本进程不是前台窗口时，它会去最大化**别人家的窗口**。
///
/// 现在的做法取自 Flutter 官方 `flutter_window.cpp` 的思路 ——
/// `GetActiveWindow()`（本线程的活动窗口）优先，
/// 其次 `GetForegroundWindow()`，最后按进程 id 在窗口链里找。
///
/// ⚠️ 刻意**不用** `EnumWindows` + FFI 回调：
/// `NativeCallable.isolateLocal` 需要回调在顶层且生命周期管理容易出错，
/// 这里改用 `GetWindow` + `GW_HWNDNEXT` 手动遍历窗口链，纯 Dart 循环、
/// 无回调、无内存分配，更稳也更易读。
class DesktopWindow {
  DesktopWindow._();

  static const int _swMaximize = 3;
  static const int _swRestore = 9;

  // GetWindow 的 uCmd
  static const int _gwOwner = 4;
  static const int _gwHwndNext = 2;
  static const int _gwHwndPrev = 3;

  static bool _bound = false;
  static bool _supported = false;

  /// 是否处于「我们主动设的全屏」状态（右键再次点击时用于还原）
  static bool _fullscreen = false;

  static bool get isFullscreen => _fullscreen;

  static void _bind() {
    if (_bound) return;
    _bound = true;
    if (!Platform.isWindows) return;
    try {
      final user32 = DynamicLibrary.open('user32.dll');
      final kernel32 = DynamicLibrary.open('kernel32.dll');

      _showWindowImpl = user32.lookupFunction<
          Int32 Function(IntPtr, Int32),
          int Function(int, int)>('ShowWindow');
      _isWindowVisibleImpl = user32.lookupFunction<
          Int32 Function(IntPtr),
          int Function(int)>('IsWindowVisible');
      _getActiveWindowImpl =
          user32.lookupFunction<IntPtr Function(), int Function()>(
              'GetActiveWindow');
      _getForegroundWindowImpl =
          user32.lookupFunction<IntPtr Function(), int Function()>(
              'GetForegroundWindow');
      _getWindowImpl = user32.lookupFunction<
          IntPtr Function(IntPtr, Uint32),
          int Function(int, int)>('GetWindow');
      _getWindowThreadProcessIdImpl = user32.lookupFunction<
          Uint32 Function(IntPtr, Pointer<Uint32>),
          int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
      _getCurrentProcessIdImpl =
          kernel32.lookupFunction<Uint32 Function(), int Function()>(
              'GetCurrentProcessId');

      _supported = true;
    } catch (_) {
      _supported = false;
    }
  }

  static int Function(int, int)? _showWindowImpl;
  static int Function(int)? _isWindowVisibleImpl;
  static int Function()? _getActiveWindowImpl;
  static int Function()? _getForegroundWindowImpl;
  static int Function(int, int)? _getWindowImpl;
  static int Function(int, Pointer<Uint32>)? _getWindowThreadProcessIdImpl;
  static int Function()? _getCurrentProcessIdImpl;

  /// 本进程 id
  static int get processId {
    _bind();
    if (!_supported) return 0;
    return _getCurrentProcessIdImpl?.call() ?? 0;
  }

  /// 缓存的「本进程主窗口」句柄
  static int _cachedHwnd = 0;

  /// 该窗口是否属于本进程
  static bool _isOwn(int hwnd) {
    final pidFn = _getWindowThreadProcessIdImpl;
    if (pidFn == null || hwnd == 0) return false;
    final buf = calloc<Uint32>();
    try {
      pidFn(hwnd, buf);
      return buf.value == processId;
    } finally {
      calloc.free(buf);
    }
  }

  /// 沿窗口链（`GW_HWNDNEXT`）找属于本进程的可见顶层窗口。
  ///
  /// 逐个 `GetWindow` 遍历，最多看 2048 个窗口防死循环。
  static int _scanOwnWindow() {
    final getWinFn = _getWindowImpl;
    final visibleFn = _isWindowVisibleImpl;
    if (getWinFn == null || visibleFn == null) return 0;
    // 从当前活动窗口起，沿链向后走；走完再从头（桌面窗口）扫一遍。
    var hwnd = _getActiveWindowImpl?.call() ?? 0;
    if (hwnd == 0) hwnd = _getForegroundWindowImpl?.call() ?? 0;

    var guard = 0;
    // 先向后（Z 序下方）
    var cur = hwnd;
    while (cur != 0 && guard < 2048) {
      if (visibleFn(cur) != 0 &&
          getWinFn(cur, _gwOwner) == 0 &&
          _isOwn(cur)) {
        return cur;
      }
      cur = getWinFn(cur, _gwHwndNext);
      guard++;
    }
    // 再向前（Z 序上方）—— GetWindow 的 PREV 是 3
    cur = hwnd;
    guard = 0;
    while (cur != 0 && guard < 2048) {
      if (visibleFn(cur) != 0 &&
          getWinFn(cur, _gwOwner) == 0 &&
          _isOwn(cur)) {
        return cur;
      }
      cur = getWinFn(cur, _gwHwndPrev);
      guard++;
    }
    return 0;
  }

  /// 本应用主窗口句柄。
  ///
  /// 优先用 [`GetActiveWindow`]（本线程活动窗口，本就是我们要操作的窗口）；
  /// 它属于本进程时直接用，否则退回扫描窗口链。
  static int get windowHandle {
    if (_cachedHwnd != 0 && _isWindowVisibleImpl?.call(_cachedHwnd) == 1) {
      return _cachedHwnd;
    }
    final active = _getActiveWindowImpl?.call() ?? 0;
    if (active != 0 && _isOwn(active)) {
      _cachedHwnd = active;
      return active;
    }
    final own = _scanOwnWindow();
    if (own != 0) {
      _cachedHwnd = own;
      return own;
    }
    // 兜底：实在找不到时用前台窗口（至少不崩）
    return _getForegroundWindowImpl?.call() ?? 0;
  }

  /// 切换全屏（= 最大化 / 还原）。返回切换后的全屏状态。
  static bool toggleFullscreen() {
    _bind();
    _fullscreen = !_fullscreen;
    if (!_supported) return _fullscreen;
    final hwnd = windowHandle;
    if (hwnd == 0) return _fullscreen;
    _showWindowImpl?.call(hwnd, _fullscreen ? _swMaximize : _swRestore);
    return _fullscreen;
  }

  /// 退出全屏
  static void exitFullscreen() {
    if (!_fullscreen) return;
    _fullscreen = false;
    _bind();
    if (!_supported) return;
    final hwnd = windowHandle;
    if (hwnd != 0) _showWindowImpl?.call(hwnd, _swRestore);
  }
}
