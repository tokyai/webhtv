import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 通用加载态
class PeekLoading extends StatelessWidget {
  final String text;
  const PeekLoading({super.key, this.text = '正在加载…'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          SizedBox(height: 14),
          Text(text, style: TextStyle(fontSize: 13, color: PeekColors.hint)),
        ],
      ),
    );
  }
}

/// 通用空/错误态
class PeekEmpty extends StatelessWidget {
  final String text;
  final IconData icon;
  final String? actionText;
  final VoidCallback? onAction;

  const PeekEmpty({
    super.key,
    required this.text,
    this.icon = Icons.inbox_outlined,
    this.actionText,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: PeekColors.railIdle),
          const SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: PeekColors.hint),
            ),
          ),
          if (actionText != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onAction,
              child: Text(actionText!, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}

/// 设置/实验室页的圆角分组标题
class PeekSectionTitle extends StatelessWidget {
  final String text;
  const PeekSectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: PeekColors.primary,
        ),
      ),
    );
  }
}

/// 原版设置/实验室条目：左侧圆角图标底板 + 标题 + 副标题 + 右侧箭头
class PeekTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  const PeekTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: PeekColors.iconTile,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 21, color: PeekColors.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: PeekText.tileTitle),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PeekText.tileSubtitle,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                trailing ??
                    Icon(Icons.chevron_right,
                        size: 20, color: PeekColors.railIdle),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: 74,
            color: PeekColors.cardBorder,
          ),
      ],
    );
  }
}

/// 二级页通用头部（返回 + 标题 + 右侧操作）
class PeekPageHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final VoidCallback? onBack;

  const PeekPageHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          const SizedBox(width: 6),
          IconButton(
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: '返回',
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: PeekColors.onSurface,
              ),
            ),
          ),
          ...actions,
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// 顶栏图标按钮（原版 4 个操作图标尺寸一致）
class PeekIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const PeekIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      iconSize: 22,
      color: PeekColors.onSurface,
      splashRadius: 20,
      icon: Icon(icon),
    );
  }
}
