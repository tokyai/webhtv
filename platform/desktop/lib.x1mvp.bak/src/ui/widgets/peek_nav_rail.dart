/// 左侧导航栏 —— 移植自 PeekPili `lib/widgets/nav_rail.dart`。
///
/// ## 几何依据（1920x1080 @280dpi = 1.75）
/// - 栏总宽 131px → 75dp 内容盒 + 1px 分割线 `#242425`（整条纵向拉满，**不做 SafeArea**）
/// - Logo 顶部 77px → 44dp；Logo 69x69px → 39.5dp，圆角 12dp
/// - Logo 底 → 第一个条目顶 49px → 28dp
/// - 条目槽 112px → 64dp
/// - 选中块 103x104px → 59x59.5dp，填充 `#123755`，图标 `#9FCAFF`，文字 `#D1E4FF`
/// - 未选中图标/文字 `#808287`
library;

import 'package:flutter/material.dart';

import '../theme/peek_theme.dart';

/// 一个导航项。
class NavItem {
  final String id;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const NavItem(this.id, this.icon, this.activeIcon, this.label);
}

/// 左栏条目。顺序即 WebHTV 安卓版的底部导航顺序：
/// 首页（vod） / 直播（live） / 设置（setting)。
///
/// 与安卓版 `menu_nav.xml` 的三项一一对应（`labelVisibilityMode="unlabeled"`）。
const kNavItems = <NavItem>[
  NavItem('home', Icons.home_outlined, Icons.home_rounded, '首页'),
  NavItem('live', Icons.live_tv_outlined, Icons.live_tv_rounded, '直播'),
  NavItem('history', Icons.history_outlined, Icons.history_rounded, '历史'),
  NavItem('star', Icons.star_outline_rounded, Icons.star_rounded, '收藏'),
  NavItem('site', Icons.dns_outlined, Icons.dns_rounded, '站点'),
  NavItem('setting', Icons.settings_outlined, Icons.settings_rounded, '设置'),
];

class NavRail extends StatelessWidget {
  const NavRail({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: PeekColors.railWidth,
      decoration: BoxDecoration(
        color: PeekColors.surface,
        border: Border(
          right: BorderSide(color: PeekColors.railDivider, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 44),
          const _RailLogo(),
          const SizedBox(height: 28),
          for (var i = 0; i < items.length; i++)
            _RailItem(
              item: items[i],
              selected: i == index,
              onTap: () => onChanged(i),
            ),
        ],
      ),
    );
  }
}

class _RailLogo extends StatelessWidget {
  const _RailLogo();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/logo.png',
        width: 39.5,
        height: 39.5,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          width: 39.5,
          height: 39.5,
          decoration: BoxDecoration(
            color: PeekColors.iconTile,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.play_arrow_rounded,
              size: 22, color: PeekColors.primary),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? PeekColors.primary : PeekColors.railIdle;

    return SizedBox(
      height: PeekColors.railItemHeight,
      child: Center(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: PeekColors.railChipWidth,
            height: PeekColors.railChipHeight,
            decoration: BoxDecoration(
              color: selected ? PeekColors.railSelected : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(selected ? item.activeIcon : item.icon, size: 19, color: color),
                const SizedBox(height: 4),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.1,
                    color: selected ? PeekColors.onPrimaryContainer : color,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
