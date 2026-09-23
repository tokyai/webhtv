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

/// 导航栏样式（原版「导航栏设置」里的 6 种）。
///
/// 原版文案：横屏模式下显示侧边导航栏，竖屏模式下显示底部导航栏；
/// 样式对两种形态同时生效。
enum NavStyle {
  /// 经典风格：选中项整块填充
  classic('经典风格'),

  /// 指示条：仅左侧一条竖指示条
  indicator('指示条'),

  /// 紧凑图标：不显示文字
  compact('紧凑图标'),

  /// 胶囊高亮：选中项用圆角胶囊
  pill('胶囊高亮'),

  /// 底部指示：选中项下方一条横线
  underline('底部指示'),

  /// 可隐藏：滚动时自动收起
  hideable('可隐藏');

  final String label;
  const NavStyle(this.label);

  static NavStyle fromName(String? n) {
    for (final s in NavStyle.values) {
      if (s.name == n) return s;
    }
    return NavStyle.classic;
  }
}

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

  /// 导航栏样式（原版 6 选 1）
  final NavStyle style;

  const NavRail({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.style = NavStyle.classic,
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
              style: style,
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
  final NavStyle style;
  final VoidCallback onTap;

  const _RailItem({
    required this.item,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? PeekColors.primary : PeekColors.railIdle;

    // 紧凑图标：不显示文字，槽位压扁
    if (style == NavStyle.compact) {
      return SizedBox(
        height: 44,
        child: Center(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 40,
              height: 36,
              decoration: BoxDecoration(
                color: selected
                    ? PeekColors.railSelected
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(selected ? item.activeIcon : item.icon,
                  size: 20, color: color),
            ),
          ),
        ),
      );
    }

    // 指示条：选中项左侧一条竖条
    if (style == NavStyle.indicator) {
      return _slot(
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 3,
              height: selected ? 26 : 0,
              decoration: BoxDecoration(
                color: PeekColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(child: _label(color, showText: true)),
          ],
        ),
      );
    }

    // 底部指示：选中项下方一条横线
    if (style == NavStyle.underline) {
      return _slot(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _label(color, showText: true),
            const SizedBox(height: 3),
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: selected ? 22 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: PeekColors.primary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      );
    }

    // 胶囊高亮 / 可隐藏：都用圆角胶囊，可隐藏额外用更窄的胶囊
    final pill = style == NavStyle.pill || style == NavStyle.hideable;
    return SizedBox(
      height: PeekColors.railItemHeight,
      child: Center(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(pill ? 18 : 14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: pill ? PeekColors.railChipWidth : PeekColors.railChipWidth,
            height: pill ? 44 : PeekColors.railChipHeight,
            decoration: BoxDecoration(
              color: selected ? PeekColors.railSelected : Colors.transparent,
              borderRadius: BorderRadius.circular(pill ? 18 : 14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(selected ? item.activeIcon : item.icon,
                    size: 19, color: color),
                if (pill) ...[
                  const SizedBox(width: 7),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: selected
                          ? PeekColors.onPrimaryContainer
                          : color,
                      fontWeight:
                          selected ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 4),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.1,
                      color: selected
                          ? PeekColors.onPrimaryContainer
                          : color,
                      fontWeight:
                          selected ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 经典风格/指示条/底部指示共用的「图标 + 文字」竖排单元
  Widget _slot({required Widget child}) {
    return SizedBox(
      height: PeekColors.railItemHeight,
      child: Center(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: child,
        ),
      ),
    );
  }

  Widget _label(Color color, {required bool showText}) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(selected ? item.activeIcon : item.icon,
            size: 19, color: color),
        if (showText) ...[
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
      ],
    );
  }
}
