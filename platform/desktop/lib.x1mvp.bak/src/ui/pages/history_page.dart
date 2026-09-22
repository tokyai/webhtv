/// 观看历史页。
///
/// 安卓版对应 `HistoryActivity` + `FragmentHistory`（`menu_history.xml` 的
/// `sync` / `delete`）。桌面端保留「清空」，同步功能依赖源服务的观看记录
/// 接口，该源未提供，因此不呈现该按钮。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../theme/peek_nav.dart';
import '../theme/peek_theme.dart';
import '../widgets/peek_common.dart';
import '../widgets/peek_poster_card.dart';
import 'detail_page.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = app.history;

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
                '观看历史',
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
                  items.isEmpty ? '最近播放记录' : '共 ${items.length} 条',
                  style: TextStyle(fontSize: 12, color: PeekColors.hint),
                ),
              ),
              const Spacer(),
              if (items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: TextButton.icon(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('清空观看历史'),
                          content: const Text('确定清空本机全部观看记录？此操作不可撤销。'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: PeekColors.error,
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('清空'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true && context.mounted) {
                        await context.read<AppState>().clearHistory();
                        if (context.mounted) peekToast(context, '已清空观看历史');
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('清空', style: TextStyle(fontSize: 12.5)),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: items.isEmpty
              ? const PeekEmpty(
                  icon: Icons.history_toggle_off_rounded,
                  text: '还没有观看记录\n播放任意影片后会自动记录到本机',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final h = items[i];
                    return _HistoryTile(
                      entry: h,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DetailPage(
                            vodId: h.vod.vodId,
                            preview: h.vod,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.onTap});

  final WatchRecord entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ep = entry.episodeName;
    return Stack(
      children: [
        PosterRowTile(
          vod: entry.vod,
          subtitle: ep.isEmpty ? null : '看到 $ep',
          onTap: onTap,
        ),
        Positioned(
          right: 20,
          top: 14,
          child: Text(
            _fmt(entry.watchedAt),
            style: TextStyle(fontSize: 11, color: PeekColors.hint),
          ),
        ),
      ],
    );
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    if (sameDay) return '${two(d.hour)}:${two(d.minute)}';
    return '${two(d.month)}-${two(d.day)}';
  }
}
