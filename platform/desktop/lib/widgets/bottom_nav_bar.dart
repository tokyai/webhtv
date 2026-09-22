import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'nav_rail.dart';

/// 竖屏底部标签栏（自适应导航的第二形态）。
///
/// ## 为什么要两套导航
///
/// 用户要求「iOS 用竖屏结构，风格与 Windows 一致，元素符合竖屏配置」。
/// 竖屏时设备宽度通常只有 320–430dp：
///   - 侧栏（[NavRail]，76dp 宽）会吃掉 **约 20%** 的可用宽度，
///     内容区被压缩到难以浏览海报栅格；
///   - 底部标签栏高度仅 56–64dp，只损耗纵向 —— 而竖屏本来就是要滚动的，
///     纵向空间比横向廉价得多。
///
/// 横屏（iPad、iPhone 横置、播放器全屏）时反过来：宽度充裕、纵向紧张，
/// 侧栏才是对的。因此 [AdaptiveNav] 按 `LayoutBuilder` 的宽度自动切换。
///
/// ## 视觉与 Windows 版保持一致
///
/// 「风格一致」不是「长得一样」，而是同一套设计语言：
///   - 选中项用 [PeekColors.railSelected] 底 + [PeekColors.primary] 图标
///   - 未选中用 [PeekColors.railIdle]
///   - 图标沿用 `*_outlined`（未选）/ `*_rounded`（选中）的成对规律
///   - 圆角、间距、字重从 [PeekColors] 取同一组常量
///
/// 差异只在**几何**：侧栏是 59×59.5dp 的方块 + 12px 文字（纵向堆叠），
/// 底栏是图标在上、10–11px 文字在下的窄条（横向均分）。
class BottomNavBar extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  const BottomNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: PeekColors.surface,
        border: Border(
          top: BorderSide(color: PeekColors.railDivider, width: 1),
        ),
      ),
      // 底栏要给 Home Indicator 让位，因此 SafeArea 只取底部。
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _BottomNavItem(
                    item: items[i],
                    selected: i == index,
                    onTap: () => onChanged(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? PeekColors.primary : PeekColors.railIdle;
    return InkWell(
      onTap: onTap,
      // 底栏不满高点击：把触摸区压到视觉块上，避免误触相邻项
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          decoration: BoxDecoration(
            // 与侧栏同款选中底 —— 这是「风格一致」的关键锚点
            color: selected ? PeekColors.railSelected : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? item.activeIcon : item.icon,
                  size: 21, color: color),
              const SizedBox(height: 2),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  color: selected ? PeekColors.onPrimaryContainer : color,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 自适应导航包装：**宽屏出侧栏，窄屏出底栏**。
///
/// 断点取 600dp —— Material 3 的 `compact`/`medium` 分界，也是「手机竖屏」
/// 与「平板/横屏」的通常分野。iPhone 竖屏最宽约 430dp（Pro Max），
/// 平板竖屏最小约 744dp（iPad mini），600 落在两者之间的空档，不会误判。
///
/// 交给调用方的是 [builder]：它收到「内容区该不该为侧栏让位」的信息，
/// 自行决定如何摆放。这样页面层不用关心导航形态。
class AdaptiveNav extends StatelessWidget {
  /// 侧栏/底栏共用的条目（已按设置开关过滤）。
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  /// 内容区构建器。[showRail] 为 true 表示侧栏占用了左侧空间，
  /// 内容区已在其右；false 表示导航在底部（或未显示）。
  final Widget Function(BuildContext context, bool showRail) builder;

  /// 切换断点（dp）。小于此宽度用底栏。
  final double breakpoint;

  const AdaptiveNav({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    required this.builder,
    this.breakpoint = 600,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= breakpoint;

        if (wide) {
          return Row(
            children: [
              NavRail(items: items, index: index, onChanged: onChanged),
              Expanded(child: builder(context, true)),
            ],
          );
        }

        return Column(
          children: [
            Expanded(child: builder(context, false)),
            BottomNavBar(items: items, index: index, onChanged: onChanged),
          ],
        );
      },
    );
  }
}
