/// PeekPili 风格通用组件 —— 移植自 `lib/widgets/common.dart`。
library;

import 'package:flutter/material.dart';

import '../theme/peek_theme.dart';

/// 居中加载态。
class PeekLoading extends StatelessWidget {
  const PeekLoading({super.key, this.text = '正在加载…'});

  final String text;

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
          const SizedBox(height: 14),
          Text(text, style: TextStyle(fontSize: 13, color: PeekColors.hint)),
        ],
      ),
    );
  }
}

/// 空态 / 错误态（可选一个操作按钮）。
class PeekEmpty extends StatelessWidget {
  const PeekEmpty({
    super.key,
    required this.text,
    this.icon = Icons.inbox_outlined,
    this.actionText,
    this.onAction,
    this.selectable = false,
  });

  final String text;
  final IconData icon;
  final String? actionText;
  final VoidCallback? onAction;

  /// 错误信息需要可选中复制。
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: PeekColors.railIdle),
            const SizedBox(height: 12),
            if (selectable)
              SelectableText(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: PeekColors.hint, height: 1.6),
              )
            else
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: PeekColors.hint, height: 1.6),
              ),
            if (actionText != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 13),
                ),
                child: Text(actionText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分组小标题。
class PeekSectionTitle extends StatelessWidget {
  const PeekSectionTitle(this.text, {super.key});

  final String text;

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

/// 设置项行：图标磁贴 + 标题 + 副标题 + 尾部控件。
class PeekTile extends StatelessWidget {
  const PeekTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
                    mainAxisSize: MainAxisSize.min,
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
                    Icon(Icons.chevron_right, size: 20, color: PeekColors.railIdle),
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

/// 页面级顶栏（返回 + 标题 + 若干操作）。
class PeekPageHeader extends StatelessWidget {
  const PeekPageHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.onBack,
  });

  final String title;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: '返回',
            onPressed: onBack ?? () => Navigator.maybePop(context),
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

/// 顶栏图标按钮（统一 22 号字重与 splash 半径）。
class PeekIconButton extends StatelessWidget {
  const PeekIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.color,
    this.size = 22,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: size),
      tooltip: tooltip,
      color: color ?? PeekColors.onSurface,
      splashRadius: 20,
      onPressed: onTap,
    );
  }
}
