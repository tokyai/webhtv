/// 站点页 —— 展示源返回的全部站点，可切换当前站点与启停服务。
///
/// 布局沿用 PeekPili 的 `PeekTile` 行风格，与「设置」页视觉一致。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../theme/peek_nav.dart';
import '../theme/peek_theme.dart';
import '../widgets/peek_common.dart';

class SitePage extends StatelessWidget {
  const SitePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (!state.serviceReady) {
      final failed = state.phase == SourcePhase.error;
      if (!failed) {
        return PeekLoading(
          text: state.phaseMessage.isEmpty ? '正在启动源服务…' : state.phaseMessage,
        );
      }
      return PeekEmpty(
        icon: Icons.error_outline,
        text: '源服务未就绪\n${state.phaseMessage}',
        selectable: true,
        actionText: '重启源服务',
        onAction: () => context.read<AppState>().startActive(),
      );
    }

    final sites = state.sites;
    final currentKey = state.currentSite?.key;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '站点',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: PeekColors.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${sites.length} 个 · 可搜索 ${sites.where((s) => s.searchable).length} 个',
                  style: TextStyle(fontSize: 12, color: PeekColors.hint),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: TextButton.icon(
                  onPressed: () async {
                    await context.read<AppState>().stopActive();
                    if (context.mounted) peekToast(context, '源服务已停止');
                  },
                  icon: const Icon(Icons.stop_circle_outlined, size: 16),
                  label: const Text('停止服务', style: TextStyle(fontSize: 12.5)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: sites.isEmpty
              ? const PeekEmpty(
                  icon: Icons.dns_outlined,
                  text: '源未返回任何站点',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: sites.length,
                  itemBuilder: (_, i) {
                    final s = sites[i];
                    final active = s.key == currentKey;
                    return PeekTile(
                      icon: active
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      title: s.shortName,
                      subtitle: _subtitleOf(s),
                      showDivider: i != sites.length - 1,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (s.searchable)
                            _Badge(label: '可搜索', color: PeekColors.primary),
                          if (s.filterable) ...[
                            const SizedBox(width: 5),
                            _Badge(label: '可筛选', color: PeekColors.ok),
                          ],
                          if (active) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check, size: 18, color: PeekColors.primary),
                          ],
                        ],
                      ),
                      onTap: () async {
                        if (active) return;
                        await context.read<AppState>().selectSite(s);
                        if (context.mounted) {
                          peekToast(context, '已切换到「${s.shortName}」');
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  static String _subtitleOf(dynamic s) {
    final parts = <String>[];
    final sub = '${s.subtitle}';
    if (sub.isNotEmpty) parts.add(sub);
    parts.add('${s.key}');
    if (!(s.enable as bool)) parts.add('已禁用');
    return parts.join('  ·  ');
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}
