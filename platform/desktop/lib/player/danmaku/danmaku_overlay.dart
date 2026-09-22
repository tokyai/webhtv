import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:media_kit/media_kit.dart';

import 'danmaku_controller.dart';

/// 弹幕渲染层：叠在视频之上，自带平滑时钟。
///
/// ## 为什么自己维护时钟
///
/// `player.stream.position` 的推送频率取决于后端（实测 200 ms ~ 1 s），
/// 直接用它绘制会明显卡顿。这里以推流值为**锚点**，用 [Ticker] 在帧间线性外推：
///
/// ```
/// t = playing ? base + (tickerElapsed - baseAt) : base
/// ```
///
/// 推流值到达时重置锚点；若与上一次差距 > 1.5 s，判定为 seek 并重建轨道。
///
/// ## 为什么用 [CustomPainter] + `repaint`
///
/// `DanmakuController` 同时是 `ChangeNotifier`。把它交给 `super(repaint:)`
/// 后，每帧只触发 `markNeedsPaint`，**不重建 widget 树**。
/// 文本排版（`ui.Paragraph`）在控制器里按条缓存，绘制阶段只做
/// `canvas.drawParagraph`，因此 2 万条弹幕的数据量不影响帧率。
class DanmakuOverlay extends StatefulWidget {
  final Player player;
  final DanmakuController controller;
  final DanmakuStyle style;

  /// 关闭时整层不绘制（但仍保留时钟，重新打开时无需重建数据）
  final bool enabled;

  const DanmakuOverlay({
    super.key,
    required this.player,
    required this.controller,
    required this.style,
    this.enabled = true,
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<StreamSubscription<dynamic>> _subs = <StreamSubscription<dynamic>>[];

  Duration _elapsed = Duration.zero;
  Duration _baseAt = Duration.zero;
  double _base = 0;
  double _lastStreamT = 0;
  bool _playing = false;
  Size _size = Size.zero;

  /// 状态栏 / 刘海高度，绘制时整体下移
  double _safeTop = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _subs.add(widget.player.stream.position.listen(_onPosition));
    _subs.add(widget.player.stream.playing.listen((v) {
      // 暂停时把锚点定在当前推流位置，恢复时从那里继续
      if (!v) _base = _lastStreamT;
      _playing = v;
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _ticker.dispose();
    super.dispose();
  }

  void _onPosition(Duration p) {
    final t = p.inMicroseconds / 1e6;
    // 与上一次推流值差距过大 → 用户 seek / 换集
    if ((t - _lastStreamT).abs() > 1.5) {
      widget.controller.seek(t);
    }
    _lastStreamT = t;
    _base = t;
    _baseAt = _elapsed;
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    if (_size.isEmpty) return;
    final t = _playing
        ? _base + (elapsed - _baseAt).inMicroseconds / 1e6
        : _base;
    widget.controller.tick(t, _size, widget.style);
  }

  @override
  Widget build(BuildContext context) {
    // 播放页是 edgeToEdge：状态栏可见时 `padding.top` 非 0，
    // 进入 immersiveSticky 后自动变 0。弹幕区域跟随安全区收缩，
    // 绘制时整体下移，两种状态下首行都不会被系统栏盖住。
    final pad = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        _safeTop = pad.top;
        _size = Size(c.maxWidth, c.maxHeight - pad.top - pad.bottom);
        if (!widget.enabled || widget.controller.isEmpty || _size.isEmpty) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size(c.maxWidth, c.maxHeight),
              painter: _DanmakuPainter(widget.controller, _safeTop),
            ),
          ),
        );
      },
    );
  }
}

class _DanmakuPainter extends CustomPainter {
  final DanmakuController c;

  /// 安全区顶部内边距：绘制前整体下移，避开状态栏 / 刘海
  final double safeTop;

  _DanmakuPainter(this.c, this.safeTop) : super(repaint: c);

  @override
  void paint(Canvas canvas, Size size) {
    final t = c.currentTime;
    if (t.isNaN || c.live.isEmpty) return;

    if (safeTop > 0) canvas.translate(0, safeTop);

    final opacity = c.style.opacity.clamp(0.0, 1.0);
    final layered = opacity < 0.999;
    if (layered) {
      canvas.saveLayer(
        ui.Offset.zero & size,
        Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
      );
    }

    // 滚动的先画，固定的后画（固定弹幕压在上面，与主流播放器一致）
    for (final l in c.live) {
      if (!l.item.isScroll) continue;
      canvas.drawParagraph(c.paragraphFor(l.index), c.positionOf(l, t));
    }
    for (final l in c.live) {
      if (l.item.isScroll) continue;
      canvas.drawParagraph(c.paragraphFor(l.index), c.positionOf(l, t));
    }

    if (layered) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter old) =>
      old.safeTop != safeTop || old.c != c;
}
