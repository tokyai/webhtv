import 'dart:ffi';
import 'dart:io';

/// 桌面端窗口控制（Windows）。
///
/// 项目没有引入 `window_manager` 插件，这里用已有的 `ffi` 依赖直接调
/// `user32.dll` / `kernel32.dll`，避免新增平台插件与构建配置。
///
/// 全屏语义与窗口最大化一致（`SW_MAXIMIZE`），切回时用 `SW_RESTORE`
/// 恢复成切换前的窗口状态。
class DesktopWindow {
  DesktopWindow._();

  static const int _swMaximize = 3;
  static const int _swRestore = 9;

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
      final show = user32.lookupFunction<
          Int32 Function(IntPtr, Int32),
          int Function(int, int)>('ShowWindow');
      final fg =
          user32.lookupFunction<IntPtr Function(), int Function()>(
              'GetForegroundWindow');

      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final pid =
          kernel32.lookupFunction<Uint32 Function(), int Function()>(
              'GetCurrentProcessId');

      _showWindowImpl = show;
      _getForegroundWindowImpl = fg;
      _getCurrentProcessIdImpl = pid;
      _supported = true;
    } catch (_) {
      _supported = false;
    }
  }

  static int Function(int, int)? _showWindowImpl;
  static int Function()? _getForegroundWindowImpl;
  static int Function()? _getCurrentProcessIdImpl;

  /// 本进程 id
  static int get processId {
    _bind();
    if (!_supported) return 0;
    return _getCurrentProcessIdImpl?.call() ?? 0;
  }

  /// 切换全屏（= 最大化 / 还原）。返回切换后的全屏状态。
  static bool toggleFullscreen() {
    _bind();
    _fullscreen = !_fullscreen;
    if (!_supported) return _fullscreen;
    final hwnd = _getForegroundWindowImpl?.call() ?? 0;
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
    final hwnd = _getForegroundWindowImpl?.call() ?? 0;
    if (hwnd != 0) _showWindowImpl?.call(hwnd, _swRestore);
  }
}
