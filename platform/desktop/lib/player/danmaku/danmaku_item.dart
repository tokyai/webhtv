/// 单条弹幕。
///
/// 字段与 Bilibili / fongmi 弹幕 XML 的 `<d p="...">` 八元组一一对应：
/// `时间(秒), 模式, 字号, 颜色(十进制RGB), 时间戳, 弹幕池, 用户hash, 行ID`
class DanmakuItem {
  /// 出现时间（秒，相对视频起点）
  final double time;

  /// 显示模式：1/2/3 = 滚动，4 = 底部固定，5 = 顶部固定，
  /// 6 = 逆向滚动，7 = 精准定位，8 = 高级弹幕
  final int mode;

  /// 字号档位（B 站约定 25 = 标准，18 = 小）
  final int size;

  /// 颜色，十进制 RGB（16777215 = 白）
  final int color;

  final String text;

  const DanmakuItem({
    required this.time,
    required this.mode,
    required this.size,
    required this.color,
    required this.text,
  });

  bool get isScroll => mode != 4 && mode != 5;
  bool get isTop => mode == 5;
  bool get isBottom => mode == 4;

  @override
  String toString() =>
      'DanmakuItem(${time.toStringAsFixed(2)}s mode=$mode size=$size '
      'color=$color "$text")';
}

/// 解析失败的占位（不参与渲染）。
const DanmakuItem kNoDanmaku =
    DanmakuItem(time: 0, mode: 1, size: 25, color: 0xFFFFFF, text: '');
