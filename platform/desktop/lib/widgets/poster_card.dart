import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../tvbox/models.dart';

/// 海报卡片（网格模式）。
///
/// 原版实测：海报 181x248dp（比例 0.73），圆角约 8dp，
/// 下方一行标题（13sp #E2E2E6）+ 一行副标题（11sp #8A8B91）。
class PosterCard extends StatelessWidget {
  final Vod vod;
  final VoidCallback? onTap;
  final bool showTitle;
  final bool compact;
  final String? badge;

  const PosterCard({
    super.key,
    required this.vod,
    this.onTap,
    this.showTitle = true,
    this.compact = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PosterImage(url: vod.pic, headers: vod.picHeaders),
                  if (badge != null && badge!.isNotEmpty)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.66),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(
                              fontSize: 10, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (showTitle) ...[
            SizedBox(height: compact ? 4 : 6),
            Text(
              vod.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11.5 : 13,
                color: PeekColors.onSurface,
              ),
            ),
            if (!compact && vod.remarks.isNotEmpty) ...[
              SizedBox(height: 2),
              Text(
                vod.remarks,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: PeekColors.hint),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// 列表模式的横排卡片
class PosterRowTile extends StatelessWidget {
  final Vod vod;
  final VoidCallback? onTap;
  final String? sourceName;

  const PosterRowTile({
    super.key,
    required this.vod,
    this.onTap,
    this.sourceName,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 92,
                height: 126,
                child: _PosterImage(url: vod.pic, headers: vod.picHeaders),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  Text(
                    vod.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        color: PeekColors.onSurface,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),
                  if (vod.remarks.isNotEmpty)
                    Text(
                      vod.remarks,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: PeekColors.primary),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (vod.typeName.isNotEmpty) vod.typeName,
                      if (vod.year.isNotEmpty) vod.year,
                      if (vod.area.isNotEmpty) vod.area,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: PeekColors.hint),
                  ),
                  if (sourceName != null && sourceName!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: PeekColors.iconTile,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        sourceName!,
                        style: TextStyle(
                            fontSize: 10, color: PeekColors.primary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PosterImage extends StatelessWidget {
  final String url;
  final Map<String, String> headers;
  const _PosterImage({required this.url, this.headers = const {}});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const _PosterPlaceholder();
    return CachedNetworkImage(
      imageUrl: url,
      // 豆瓣系源的海报带 `@Referer=...` 防盗链，必须带上请求头
      httpHeaders: headers,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (_, __) => Container(color: PeekColors.card),
      errorWidget: (_, __, ___) => const _PosterPlaceholder(),
    );
  }
}

class _PosterPlaceholder extends StatelessWidget {
  const _PosterPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PeekColors.card,
      alignment: Alignment.center,
      child: Icon(Icons.movie_outlined,
          size: 26, color: PeekColors.railIdle),
    );
  }
}
