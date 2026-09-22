import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/debug_log.dart';
import '../../core/storage.dart';
import '../../tvbox/models.dart';

/// 悬浮球（小窗播放）。
///
/// 对齐原版日志族：
///   * `[T4] _restoreFromFloatingBall` —— 从悬浮球恢复回全屏播放页
///   * `[T4] dispose: 悬浮球模式` —— 播放页被销毁但不释放播放器
///
/// 原版在 Android 上走**系统级悬浮窗**（`WindowManager` +
/// `TYPE_APPLICATION_OVERLAY`）。复刻版三端统一，做法是：
///   * 播放器实例（[Player]）与 [VideoController] **不随播放页销毁**，
///     由本单例持有，因此恢复时不用重新 open，**进度不丢、秒回**；
///   * 悬浮球是一个 `OverlayEntry`，挂在根 `Navigator` 之上，
///     与当前页面栈无关；
///   * 点小窗回全屏 = 把同一个 [Player] 交还给新建的播放页。
class FloatingBall {
  FloatingBall._();

  /// 当前是否处于悬浮球模式
  static bool get active => _entry != null;

  /// 被接管的播放器与渲染控制器（播放页交出所有权后由这里持有）
  static Player? player;
  static VideoController? controller;

  /// 被最小化的播放上下文，恢复时用来重建播放页
  static FloatingSession? session;

  static OverlayEntry? _entry;

  /// 点小窗「回全屏」的回调。
  ///
  /// 由 `main.dart` 在启动时注册一次（用根 `navigatorKey` push 播放页），
  /// 这样悬浮球不依赖任何页面 `BuildContext` 还活着。
  static void Function()? onRestore;

  /// 位置按屏幕可用区比例持久化，换分辨率/旋转后不跑偏
  static double xRatio = 0.80;
  static double yRatio = 0.66;

  /// 进入悬浮球模式。
  ///
  /// [player] / [controller] 由播放页交出所有权 —— 播放页此后
  /// **不得**再 dispose 它们（见 [shouldKeepPlaying]）。
  static void enter({
    required Player player,
    required VideoController controller,
    required FloatingSession session,
    required OverlayState overlay,
  }) {
    if (_entry != null) {
      // 已在悬浮球模式：只更新上下文，别重复插条目
      FloatingBall.player = player;
      FloatingBall.controller = controller;
      FloatingBall.session = session;
      _entry!.markNeedsBuild();
      return;
    }
    FloatingBall.player = player;
    FloatingBall.controller = controller;
    FloatingBall.session = session;
    xRatio = Store.get<double>('floatingBallX', 0.80);
    yRatio = Store.get<double>('floatingBallY', 0.66);
    final e = OverlayEntry(builder: (_) => const FloatingBallWidget());
    _entry = e;
    overlay.insert(e);
    DebugLog.add('播放', '进入悬浮球模式');
  }

  /// 从悬浮球恢复回全屏。
  ///
  /// 原版日志：`[T4] _restoreFromFloatingBall`
  /// 返回被接管的 `(player, controller, session)`；调用方把它们交给
  /// 新建的播放页（通过 `externalPlayer`），避免重复创建播放器。
  static FloatingHandoff? restore() {
    final p = player;
    final c = controller;
    final s = session;
    if (p == null || c == null || s == null) return null;
    DebugLog.add('播放', '_restoreFromFloatingBall');
    final h = FloatingHandoff(p, c, s);
    // 所有权交还播放页：这里只移除 UI，不释放播放器
    _removeEntry();
    player = null;
    controller = null;
    session = null;
    return h;
  }

  /// 彻底关闭悬浮球（用户点了小窗的 ×）
  static void close() {
    _removeEntry();
    player?.dispose();
    player = null;
    controller = null;
    session = null;
  }

  static void _removeEntry() {
    _entry?.remove();
    _entry = null;
  }

  /// 播放页 dispose 时的判断：是真的「退出播放」，还是「转悬浮球」。
  ///
  /// 原版 `[T4] dispose: 悬浮球模式` 的语义就是这个分支 ——
  /// 为 true 时播放页**不能**释放播放器。
  static bool shouldKeepPlaying() => _entry != null;

  static void savePosition(double x, double y) {
    xRatio = x.clamp(0.0, 1.0);
    yRatio = y.clamp(0.0, 1.0);
    unawaited(Store.set('floatingBallX', xRatio));
    unawaited(Store.set('floatingBallY', yRatio));
  }

  /// 通知小窗重建（播放/暂停状态变化时）
  static void refresh() => _entry?.markNeedsBuild();
}

/// 播放器所有权交接包
class FloatingHandoff {
  final Player player;
  final VideoController controller;
  final FloatingSession session;
  const FloatingHandoff(this.player, this.controller, this.session);
}

/// 播放页转悬浮球时保留下来的上下文
class FloatingSession {
  final Site site;
  final Vod vod;
  final int lineIndex;
  final int episodeIndex;

  const FloatingSession({
    required this.site,
    required this.vod,
    required this.lineIndex,
    required this.episodeIndex,
  });
}

/// 悬浮球 UI：可拖拽的小窗 + 播放/暂停 + 回全屏 + 关闭。
class FloatingBallWidget extends StatefulWidget {
  const FloatingBallWidget({super.key});

  @override
  State<FloatingBallWidget> createState() => _FloatingBallWidgetState();
}

class _FloatingBallWidgetState extends State<FloatingBallWidget> {
  static const double _w = 156;
  static const double _h = 88;

  double? _x;
  double? _y;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final pad = MediaQuery.of(context).padding;
    final maxX = (size.width - _w).clamp(0.0, double.infinity);
    final maxY =
        (size.height - _h - pad.bottom).clamp(0.0, double.infinity);
    _x ??= (FloatingBall.xRatio * maxX).clamp(0.0, maxX);
    _y ??= (FloatingBall.yRatio * maxY).clamp(0.0, maxY);

    final p = FloatingBall.player;
    final c = FloatingBall.controller;

    return Positioned(
      left: _x!.clamp(0.0, maxX),
      top: _y!.clamp(0.0, maxY),
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _x = (_x! + d.delta.dx).clamp(0.0, maxX);
            _y = (_y! + d.delta.dy).clamp(0.0, maxY);
          });
          FloatingBall.savePosition(
            maxX == 0 ? 0 : _x! / maxX,
            maxY == 0 ? 0 : _y! / maxY,
          );
        },
        child: Material(
          color: Colors.black,
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: _w,
            height: _h,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (c != null)
                  Video(
                    controller: c,
                    controls: NoVideoControls,
                    fill: Colors.black,
                  ),
                // 点画面 = 回全屏（可点区域避开右下角按钮）
                Positioned.fill(
                  right: 34,
                  bottom: 26,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => FloatingBall.onRestore?.call(),
                  ),
                ),
                Positioned(
                  right: 3,
                  top: 3,
                  child: _miniBtn(Icons.close, () {
                    FloatingBall.close();
                  }),
                ),
                if (p != null)
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: StreamBuilder<bool>(
                      stream: p.stream.playing,
                      initialData: p.state.playing,
                      builder: (_, snap) => _miniBtn(
                        snap.data == true ? Icons.pause : Icons.play_arrow,
                        () => p.playOrPause(),
                      ),
                    ),
                  ),
                Positioned(
                  left: 3,
                  bottom: 3,
                  child: _miniBtn(
                    Icons.open_in_full,
                    () => FloatingBall.onRestore?.call(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniBtn(IconData icon, VoidCallback onTap) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Icon(icon, size: 13, color: Colors.white),
          ),
        ),
      );
}
