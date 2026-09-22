import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'danmaku_item.dart';

/// 弹幕外观与行为参数（对应设置页「弹幕设置」里的各项开关）。
///
/// 键名与原版一致，便于和原版设置逐项对照：
/// `danmakuFontSize` / `danmakuOpacity` / `danmakuScroll` /
/// `danmakuArea` / `danmakuSpeed` / `danmakuFixedSeconds` / `danmakuBold`。
class DanmakuStyle {
  /// 基准字号：对应 B 站 25 档
  final double fontSize;
  final double opacity;

  /// 是否显示滚动弹幕（关闭后只留顶部/底部固定弹幕）
  final bool scrollEnabled;

  /// 弹幕显示区域占比（0.25 ~ 1.0），原版「显示区域」
  final double areaRatio;

  /// 滚动弹幕穿屏基准时长（秒），越小越快。原版「弹幕速度」
  final double scrollSeconds;

  /// 静止弹幕（顶/底固定）停留时长（秒）。原版「静止弹幕时长」
  final double fixedSeconds;

  /// 是否加粗（原版「弹幕字体粗细」的粗体档）
  final bool bold;

  const DanmakuStyle({
    this.fontSize = 16,
    this.opacity = 1.0,
    this.scrollEnabled = true,
    this.areaRatio = 0.6,
    this.scrollSeconds = 8.0,
    this.fixedSeconds = 4.0,
    this.bold = true,
  });

  static const DanmakuStyle fallback = DanmakuStyle();

  /// 行高：字号 × 1.35（含描边余量）
  double get laneHeight => fontSize * 1.35;

  /// 按 B 站档位换算实际字号（18 小 / 25 标准 / 36 大）
  double sizeFor(DanmakuItem item) {
    final r = item.size / 25.0;
    return (fontSize * r.clamp(0.65, 1.6)).roundToDouble();
  }

  Color colorFor(DanmakuItem item) {
    final rgb = item.color == 0 ? 0xFFFFFF : item.color;
    return Color(0xFF000000 | (rgb & 0xFFFFFF));
  }

  @override
  bool operator ==(Object other) =>
      other is DanmakuStyle &&
      other.fontSize == fontSize &&
      other.opacity == opacity &&
      other.scrollEnabled == scrollEnabled &&
      other.areaRatio == areaRatio &&
      other.scrollSeconds == scrollSeconds &&
      other.fixedSeconds == fixedSeconds &&
      other.bold == bold;

  @override
  int get hashCode => Object.hash(fontSize, opacity, scrollEnabled, areaRatio,
      scrollSeconds, fixedSeconds, bold);
}

/// 一条「正在屏上」的弹幕（已分配轨道、已排版）。
class LiveDanmaku {
  /// 在 `DanmakuController` 的 `_items` 里的下标（取缓存的 Paragraph 用）
  final int index;
  final DanmakuItem item;
  final int lane;
  final double width;

  /// 出现时刻（= item.time）
  final double bornAt;

  /// 滚动：穿屏总时长；固定：停留时长
  final double duration;

  const LiveDanmaku({
    required this.index,
    required this.item,
    required this.lane,
    required this.width,
    required this.bornAt,
    required this.duration,
  });

  double progress(double t) {
    final p = (t - bornAt) / duration;
    return p < 0 ? 0 : (p > 1 ? 1 : p);
  }

  bool expired(double t) => t - bornAt > duration;
}

/// 弹幕时间轴控制器：轨道分配 + 滑动窗口调度。
///
/// 它同时是 [CustomPainter] 的 `repaint` 源 —— 每帧 `tick()` 结束会
/// `notifyListeners()`，从而**只重绘、不重建 widget 树**。
///
/// ## 轨道分配规则（与主流播放器一致）
///
/// * 滚动弹幕：某轨道「上一条的尾巴完全进入屏幕」之后才能放下一条。
///   记录 `freeAt = bornAt + width / speed`；新弹幕要求 `t >= freeAt`。
/// * 顶部 / 底部固定弹幕：占用轨道 [fixedSeconds] 秒。
/// * 无可用轨道时**丢弃**该条（不排队），避免积压后一次性喷出。
///
/// ## 性能
///
/// 文本排版（`ui.Paragraph`）按弹幕下标**缓存**，只在样式变化时失效。
/// 4 MB / 2 万条的窗口调度是 O(可见条数)，与总量无关。
class DanmakuController extends ChangeNotifier {
  /// 滚动弹幕头部从右边缘走到左边缘的基准时长（秒）
  static const double scrollSpanSeconds = 8.0;

  /// 顶部 / 底部固定弹幕停留时长（秒）
  static const double fixedSeconds = 4.0;

  /// 滚动弹幕可占用的屏幕高度占比
  static const double scrollAreaRatio = 0.6;

  /// 顶部 / 底部固定弹幕各自可占用的屏幕高度占比
  static const double fixedAreaRatio = 0.4;

  /// seek 后需要「预演」重建轨道状态的回溯窗口（秒）
  static const double replayWindow = 14.0;

  /// 弹幕区上下留白（逻辑像素）。
  ///
  /// 播放页是全屏沉浸式，首行弹幕若从 y=0 起排会压住状态栏图标，
  /// 末行也会贴住底部手势条。留 8 px 后实测观感与原版一致。
  static const double topInset = 8.0;
  static const double bottomInset = 8.0;

  // ---------------------------------------------------------------- 数据整理

  /// 合并一段时间内获取到的相同弹幕（原版「合并弹幕」）。
  ///
  /// 同一文本在 [window] 秒内重复出现只保留最早的一条 —— B 站刷屏场景下
  /// 能显著降低密度。返回新列表，不修改入参。
  static List<DanmakuItem> mergeDuplicates(
    List<DanmakuItem> items, {
    double window = 5.0,
  }) {
    if (items.length < 2 || window <= 0) return items;
    final last = <String, double>{};
    final out = <DanmakuItem>[];
    for (final it in items) {
      final prev = last[it.text];
      if (prev != null && it.time - prev < window) continue;
      last[it.text] = it.time;
      out.add(it);
    }
    return out;
  }

  /// 按关键词 / 正则屏蔽弹幕（原版「弹幕屏蔽词」）。
  ///
  /// [keywords] 为纯文本包含匹配；[regexes] 为 `RegExp` 源码，编译失败的
  /// 条目会被忽略而不是抛异常（用户手输的规则经常写错）。
  static List<DanmakuItem> filterBlocked(
    List<DanmakuItem> items, {
    List<String> keywords = const <String>[],
    List<String> regexes = const <String>[],
  }) {
    if (items.isEmpty) return items;
    final words = keywords
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final regs = <RegExp>[];
    for (final r in regexes) {
      final s = r.trim();
      if (s.isEmpty) continue;
      try {
        regs.add(RegExp(s));
      } catch (_) {
        // 用户写错的正则直接跳过，不影响其它规则
      }
    }
    if (words.isEmpty && regs.isEmpty) return items;
    return items.where((it) {
      for (final w in words) {
        if (it.text.contains(w)) return false;
      }
      for (final r in regs) {
        if (r.hasMatch(it.text)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  /// 从多行文本解析屏蔽规则（每行一条）
  static List<String> splitRules(String raw) => raw
      .split(RegExp(r'[\r\n]+'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  List<DanmakuItem> _items = const <DanmakuItem>[];
  final List<ui.Paragraph?> _paras = <ui.Paragraph?>[];

  Size _size = Size.zero;
  double _t = double.nan;
  int _cursor = 0;
  int _scrollLanes = 1;
  int _topLanes = 1;
  int _bottomLanes = 1;

  final List<double> _scrollFree = <double>[];
  final List<double> _topFree = <double>[];
  final List<double> _bottomFree = <double>[];

  final List<LiveDanmaku> _live = <LiveDanmaku>[];

  DanmakuStyle _style = DanmakuStyle.fallback;

  /// 当前屏上弹幕（绘制用，勿修改）
  List<LiveDanmaku> get live => _live;

  /// 已加载的弹幕总条数
  int get total => _items.length;

  bool get isEmpty => _items.isEmpty;

  /// 当前生效的样式
  DanmakuStyle get style => _style;

  /// 滚动弹幕轨道数
  int get scrollLanes => _scrollLanes;

  /// 顶部固定弹幕轨道数
  int get topLanes => _topLanes;

  /// 底部固定弹幕轨道数
  int get bottomLanes => _bottomLanes;

  /// 视频区域尺寸
  Size get viewSize => _size;

  /// 当前时刻（秒）。未推进时为 NaN。
  double get currentTime => _t;

  /// 装载弹幕数据（已按时间升序）。会重置全部轨道状态。
  void setItems(List<DanmakuItem> items, {DanmakuStyle? style}) {
    _items = items;
    _paras
      ..clear()
      ..addAll(List<ui.Paragraph?>.filled(items.length, null));
    if (style != null) _style = style;
    _reset();
    notifyListeners();
  }

  /// 仅更新外观（设置变更时调用），会清排版缓存并重置轨道。
  void setStyle(DanmakuStyle style) {
    if (_style == style) return;
    _style = style;
    for (var i = 0; i < _paras.length; i++) {
      _paras[i] = null;
    }
    _reset();
    notifyListeners();
  }

  void clear() {
    _items = const <DanmakuItem>[];
    _paras.clear();
    _reset();
    notifyListeners();
  }

  /// 跳转：重建轨道状态，让 seek 之后立刻有弹幕而不是空白。
  void seek(double t) {
    _reset();
    _t = t;
    if (_items.isEmpty || _size.width <= 0) {
      notifyListeners();
      return;
    }
    final from = t - replayWindow;
    _cursor = _lowerBound(from < 0 ? 0 : from);
    // 预演：把 [from, t] 区间的弹幕按顺序分配轨道，把轨道状态推到「当前」。
    // 仍在屏上的保留进 _live —— 否则 seek 之后会出现一段空白。
    while (_cursor < _items.length && _items[_cursor].time <= t) {
      final born = _birth(_items[_cursor], _cursor, _size, _style);
      _cursor++;
      if (born != null && !born.expired(t)) _live.add(born);
    }
    notifyListeners();
  }

  /// 每帧推进到时刻 [t]（秒）。[size] 为视频区域像素尺寸。
  void tick(double t, Size size, DanmakuStyle style) {
    if (t.isNaN) return;

    if (size != _size || style != _style) {
      final styleChanged = style != _style;
      _size = size;
      if (styleChanged) {
        _style = style;
        for (var i = 0; i < _paras.length; i++) {
          _paras[i] = null;
        }
      }
      _scrollLanes = _laneCount(size, _style, _style.areaRatio);
      _topLanes = _laneCount(size, _style, fixedAreaRatio);
      _bottomLanes = _laneCount(size, _style, fixedAreaRatio);
      seek(t);
      return;
    }

    if (_t.isNaN || t < _t - 0.001 || t - _t > 2.0) {
      seek(t);
      return;
    }
    _t = t;

    if (_items.isEmpty) {
      if (_live.isNotEmpty) {
        _live.clear();
        notifyListeners();
      }
      return;
    }

    _live.removeWhere((l) => l.expired(t));
    while (_cursor < _items.length && _items[_cursor].time <= t) {
      final born = _birth(_items[_cursor], _cursor, size, style);
      _cursor++;
      if (born != null) _live.add(born);
    }
    notifyListeners();
  }

  /// 绘制用几何：返回该弹幕左上角坐标。
  /// 滚动弹幕返回的 x 可能为负（已部分滑出左侧），由绘制层裁剪。
  ui.Offset positionOf(LiveDanmaku l, double t) {
    final p = l.progress(t);
    if (l.item.isTop) {
      // 顶部固定：从屏幕顶边往下排，lane 0 在最上
      return ui.Offset(
        (_size.width - l.width) / 2,
        topInset + l.lane * _style.laneHeight,
      );
    }
    if (l.item.isBottom) {
      // 底部固定：从屏幕底边往上排，lane 0 在最下
      final y = _size.height - bottomInset - (l.lane + 1) * _style.laneHeight;
      return ui.Offset((_size.width - l.width) / 2, y);
    }
    return ui.Offset(
      _size.width - p * (_size.width + l.width),
      topInset + l.lane * _style.laneHeight,
    );
  }

  /// 取（或构建）该弹幕的排版对象。样式变化后自动重建。
  ui.Paragraph paragraphFor(int index) {
    final cached = _paras[index];
    if (cached != null) return cached;
    final item = _items[index];
    final size = _style.sizeFor(item);
    // 透明度作用在文字与描边上（原版「弹幕透明度」）
    final alpha = _style.opacity.clamp(0.05, 1.0);
    final fg = _style.colorFor(item).withValues(alpha: alpha);
    final edge = const Color(0xFF000000).withValues(alpha: 0.8 * alpha);
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontSize: size,
      fontWeight: _style.bold ? FontWeight.w700 : FontWeight.w400,
      maxLines: 1,
      textAlign: TextAlign.left,
    ))
      ..pushStyle(ui.TextStyle(
        color: fg,
        // 黑描边：四向硬阴影，等价于常见弹幕的描边效果且只需一次排版
        shadows: <ui.Shadow>[
          ui.Shadow(offset: const ui.Offset(-1, -1), blurRadius: 0, color: edge),
          ui.Shadow(offset: const ui.Offset(1, -1), blurRadius: 0, color: edge),
          ui.Shadow(offset: const ui.Offset(-1, 1), blurRadius: 0, color: edge),
          ui.Shadow(offset: const ui.Offset(1, 1), blurRadius: 0, color: edge),
        ],
      ))
      ..addText(item.text);
    final p = pb.build()..layout(const ui.ParagraphConstraints(width: 4096));
    _paras[index] = p;
    return p;
  }

  // ---------------------------------------------------------------- 内部

  void _reset() {
    _scrollFree.clear();
    _topFree.clear();
    _bottomFree.clear();
    _live.clear();
    _cursor = 0;
  }

  int _lowerBound(double t) {
    var lo = 0, hi = _items.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_items[mid].time < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  int _laneCount(Size size, DanmakuStyle style, double ratio) {
    if (size.height <= 0 || style.laneHeight <= 0) return 1;
    final usable = size.height - topInset - bottomInset;
    if (usable <= 0) return 1;
    final n = (usable * ratio / style.laneHeight).floor();
    return n < 1 ? 1 : (n > 60 ? 60 : n);
  }

  /// 文本宽度（取自缓存排版对象的 `longestLine`）
  double _widthOf(int index) {
    final p = paragraphFor(index);
    final w = p.longestLine;
    return w > 0 ? w : p.maxIntrinsicWidth;
  }

  /// 尝试让第 [index] 条弹幕「出生」。轨道占满则返回 null（丢弃）。
  LiveDanmaku? _birth(
    DanmakuItem item,
    int index,
    Size size,
    DanmakuStyle style,
  ) {
    if (size.width <= 0 || size.height <= 0) return null;
    final w = _widthOf(index);

    if (item.isScroll && style.scrollEnabled) {
      final lanes = _laneCount(size, style, style.areaRatio);
      final span = style.scrollSeconds > 0 ? style.scrollSeconds : scrollSpanSeconds;
      final speed = size.width / span; // px/s
      if (speed <= 0) return null;
      final duration = (size.width + w) / speed;
      final tailIn = w / speed; // 尾巴完全进入屏幕所需时间

      _ensure(_scrollFree, lanes, -1e9);
      for (var i = 0; i < lanes; i++) {
        if (_scrollFree[i] <= item.time) {
          _scrollFree[i] = item.time + tailIn;
          return LiveDanmaku(
            index: index,
            item: item,
            lane: i,
            width: w,
            bornAt: item.time,
            duration: duration,
          );
        }
      }
      return null;
    }

    final fixed = item.isTop ? _topFree : (item.isBottom ? _bottomFree : null);
    if (fixed == null) return null; // mode 6/7/8 暂不渲染
    final lanes = _laneCount(size, style, fixedAreaRatio);
    final stay = style.fixedSeconds > 0 ? style.fixedSeconds : fixedSeconds;
    _ensure(fixed, lanes, -1e9);
    for (var i = 0; i < lanes; i++) {
      if (fixed[i] <= item.time) {
        fixed[i] = item.time + stay;
        return LiveDanmaku(
          index: index,
          item: item,
          lane: i,
          width: w,
          bornAt: item.time,
          duration: stay,
        );
      }
    }
    return null;
  }

  static void _ensure(List<double> l, int n, double v) {
    while (l.length < n) {
      l.add(v);
    }
  }
}
