import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../state/app_state.dart';
import '../tvbox/models.dart';
import '../widgets/common.dart';
import '../widgets/poster_card.dart';
import 'detail/detail_page.dart';

/// 收藏夹（原版顶栏「收藏」图标）。
class FavoritePage extends StatefulWidget {
  const FavoritePage({super.key});

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> {
  late List<Map<String, dynamic>> _list;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _list = Store.allFavorites()
      ..sort((a, b) => (int.tryParse('${b['time'] ?? 0}') ?? 0)
          .compareTo(int.tryParse('${a['time'] ?? 0}') ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            PeekPageHeader(
              title: '我的收藏',
              actions: [
                if (_list.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text('${_list.length} 部',
                        style: TextStyle(
                            fontSize: 12, color: PeekColors.hint)),
                  ),
              ],
            ),
            Expanded(
              child: _list.isEmpty
                  ? const PeekEmpty(
                      icon: Icons.favorite_border,
                      text: '还没有收藏任何影片',
                    )
                  : LayoutBuilder(
                      builder: (context, c) {
                        final w = c.maxWidth - PeekColors.contentPadding * 2;
                        const gap = PeekColors.gridGap;
                        final cols = ((w + gap) / (181 + gap)).round().clamp(2, 8);
                        final itemW = (w - gap * (cols - 1)) / cols;
                        final ratio =
                            itemW / (itemW / PeekColors.posterAspect + 41);
                        return GridView.builder(
                          padding: const EdgeInsets.fromLTRB(
                            PeekColors.contentPadding,
                            12,
                            PeekColors.contentPadding,
                            24,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: cols,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: gap,
                            childAspectRatio: ratio,
                          ),
                          itemCount: _list.length,
                          itemBuilder: (_, i) {
                            final e = _list[i];
                            final vod = Vod(
                              id: e['vod_id']?.toString() ?? '',
                              name: e['vod_name']?.toString() ?? '',
                              pic: e['vod_pic']?.toString() ?? '',
                              remarks: e['vod_remarks']?.toString() ?? '',
                            );
                            return GestureDetector(
                              onSecondaryTap: () => _remove(i),
                              child: PosterCard(
                                vod: vod,
                                badge: e['source_name']?.toString(),
                                showTitle: app.showPosterTitle,
                                compact: app.compactTitle,
                                onTap: () {
                                  final site = _resolveSite(e);
                                  if (site == null) {
                                    peekToast(context,
                                        '找不到该收藏对应的站源，请先加载接口');
                                    return;
                                  }
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => DetailPage(
                                        site: site,
                                        vodId: vod.id,
                                        preview: vod,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _remove(int index) async {
    final e = _list[index];
    final site = _resolveSite(e);
    final key = e['_key']?.toString() ?? '';
    if (site == null || key.isEmpty) return;
    final ok = await peekConfirm(
        context, '取消收藏', '确定取消收藏《${e['vod_name']}》吗？');
    if (!ok) return;
    await Store.toggleFavorite(key, {});
    if (mounted) setState(_reload);
  }

  Site? _resolveSite(Map<String, dynamic> e) {
    final app = context.read<AppState>();
    final key = e['source_key']?.toString() ?? '';
    for (final s in app.sites) {
      if (s.displayKey == key || s.key == key) return s;
    }
    final api = e['source_api']?.toString() ?? '';
    if (api.isEmpty) return null;
    return Site(
      key: key,
      name: e['source_name']?.toString() ?? key,
      type: int.tryParse('${e['source_type'] ?? 3}') ?? 3,
      api: api,
      raw: const {},
    );
  }
}
