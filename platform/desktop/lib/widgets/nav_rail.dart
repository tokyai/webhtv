import 'package:flutter/material.dart';

import '../core/theme.dart';

class NavItem {
  /// 稳定标识：开关切换后条目位置会变，靠它而不是下标来定位页面。
  final String id;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const NavItem(this.id, this.icon, this.activeIcon, this.label);
}

/// 左侧导航条目全集。
///
/// 原版左栏是**可配置**的 —— 设置里有「显示短剧」「显示音乐」
/// （「关闭后将隐藏底部/侧边的短剧入口」），阅读同理。
/// 实际显示哪些由 [MainShell] 按开关过滤，顺序保持不变。
///
/// 图标取自**原版 APK 的 tree-shaken `MaterialIcons-Regular.otf`**：
/// `flutter build` 会把该字体裁剪成「只含实际用到的字形」，所以字体里的
/// 码点集合 = 原版用到的图标集合。实测（`.peekpili-analysis/g8/identify_icons.py`）：
///   未选中 = `*_outlined`，选中 = `*_rounded`
///   首页 home_outlined/home_rounded、短剧 movie_filter_outlined/movie_filter_rounded、
///   音乐 music_note_outlined/music_note_rounded、
///   阅读 menu_book_outlined/menu_book_rounded、
///   实验室 science_outlined/science_rounded、设置 settings_outlined/settings_rounded
///
/// 图标取自**原版 APK 的 tree-shaken `MaterialIcons-Regular.otf`**：
/// `flutter build` 会把该字体裁剪成「只含实际用到的字形」，所以字体里的
/// 码点集合 = 原版用到的图标集合。实测（`.peekpili-analysis/g8/identify_icons.py`）：
///   未选中 = `*_outlined`，选中 = `*_rounded`
///   首页 home_outlined/home_rounded、设置 settings_outlined/settings_rounded
///
/// 本工程的条目集合按 **WebHTV 安卓版**取：安卓底部导航是
/// 「点播(vod) / 直播(live) / 设置(setting)」三项，桌面端屏幕宽，
/// 因此把「历史」「收藏」这两个安卓端藏在顶栏的入口一并放进左栏。
const kNavItems = <NavItem>[
  NavItem('home', Icons.home_outlined, Icons.home_rounded, '首页'),
  NavItem('star', Icons.star_outline_rounded, Icons.star_rounded, '收藏'),
  NavItem('history', Icons.history_outlined, Icons.history_rounded, '历史'),
  NavItem('setting', Icons.settings_outlined, Icons.settings_rounded, '设置'),
];

/// 左侧竖向导航栏。
///
/// 几何参数来自原版 1.2.5+2 **实机像素复测**（1920x1080 @280dpi = 1.75）：
///   栏宽 131px -> 75dp，右侧 1px 分割线 #242425（贯穿全高，原版**没有** SafeArea）
///   头像顶 77px -> 44dp（= 左栏自身留白，不是系统状态栏 inset）
///   头像 69x69px -> 39.5dp，圆角 12dp
///   头像底 146px → 首项槽顶 195px，即间隔 49px -> 28dp
///   条目槽高 112px -> 64dp
///   选中块 103x104px -> 59x59.5dp，填充 #123755，图标 #9FCAFF，文字 #D1E4FF
///   未选中图标/文字 #808287
class NavRail extends StatelessWidget {
  /// 当前实际显示的条目（已按设置开关过滤），顺序与 [kNavItems] 一致。
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  const NavRail({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

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
        'assets/images/logo/logo.png',
        width: 39.5,
        height: 39.5,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 39.5,
          height: 39.5,
          decoration: BoxDecoration(
            color: PeekColors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.play_arrow_rounded,
              color: PeekColors.primary, size: 22),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _RailItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

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
                // 图标 33px = 18.9dp、文字墨高 ~22px（原版像素复测）
                Icon(selected ? item.activeIcon : item.icon,
                    size: 19, color: color),
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
