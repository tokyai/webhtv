/// 收藏页。
///
/// ## 与安卓版的差异（写清楚，避免误解）
/// 安卓 WebHTV 的收藏走 `CollectFragment` + Room 本地库，数据在**客户端**。
/// 桌面端的源服务（CatVodSpiderios）**没有暴露收藏接口** —— 实测
/// `/spider/<key>/<type>/support` 只声明 home/category/detail/search/play。
/// 因此这里的收藏落在本机 JSON 文件，由 [AppState] 管理，且按源隔离。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../theme/peek_nav.dart';
import '../theme/peek_theme.dart';
import '../widgets/peek_common.dart';
import '../widgets/peek_poster_card.dart';
import 'detail_page.dart';

class FavoritePage extends StatelessWidget {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = app.favorites;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        _Header(count: items.length),
        const SizedBox(height: 8),
        Expanded(
          child: items.isEmpty
              ? const PeekEmpty(
                  icon: Icons.star_outline_rounded,
                  text: '还没有收藏的影片\n在详情页点右上角的星标即可加入收藏',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final v = items[i];
                    return Dismissible(
                      key: ValueKey('${v.vodId}-$i'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        color: PeekColors.error.withValues(alpha: 0.18),
                        child: Icon(Icons.delete_outline,
                            size: 20, color: PeekColors.error),
                      ),
                      onDismissed: (_) {
                        context.read<AppState>().toggleFavorite(v);
                        peekToast(context, '已从收藏移除「${v.vodName}」');
                      },
                      child: PosterRowTile(
                        vod: v,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                DetailPage(vodId: v.vodId, preview: v),
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

class _Header extends StatelessWidget {
  const _Header({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '收藏',
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
              count == 0 ? '本机保存，按源隔离' : '共 $count 部',
              style: TextStyle(fontSize: 12, color: PeekColors.hint),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              '左滑可移除',
              style: TextStyle(fontSize: 11.5, color: PeekColors.hint),
            ),
          ),
        ],
      ),
    );
  }
}
