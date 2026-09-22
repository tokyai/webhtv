/// 海报卡 —— 移植自 PeekPili `lib/widgets/poster_card.dart`。
///
/// 说明：PeekPili 用 `cached_network_image`，这里为减少依赖直接用
/// `Image.network` + `loadingBuilder`；豆瓣系源的海报带防盗链请求头，
/// 通过 [headers] 透传（源服务返回的图片地址通常已带 `@Referer=`，
/// 需要额外请求头时由调用方传入）。
library;

import 'package:flutter/material.dart';

import '../../models/source_models.dart';
import '../theme/peek_theme.dart';

/// 竖版海报卡（网格用）。
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.vod,
    this.onTap,
    this.showTitle = true,
    this.compact = false,
    this.badge,
  });

  final VideoItem vod;
  final VoidCallback? onTap;
  final bool showTitle;
  final bool compact;

  /// 右上角角标（多源搜索时显示来源站名）。
  final String? badge;

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
                  _PosterImage(url: vod.vodPic),
                  if (badge != null && badge!.isNotEmpty)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.66),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(fontSize: 10, color: Colors.white),
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
              vod.vodName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11.5 : 13,
                color: PeekColors.onSurface,
              ),
            ),
            if (!compact && vod.vodRemarks.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                vod.vodRemarks,
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

/// 横版列表行（列表模式 / 搜索结果用）。
class PosterRowTile extends StatelessWidget {
  const PosterRowTile({
    super.key,
    required this.vod,
    this.onTap,
    this.sourceName,
    this.subtitle,
  });

  final VideoItem vod;
  final VoidCallback? onTap;

  /// 来源站名（多源搜索）。
  final String? sourceName;

  /// 额外的第二行信息（如类型/年份/地区）。
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 92,
                height: 126,
                child: _PosterImage(url: vod.vodPic),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    vod.vodName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: PeekColors.onSurface,
                    ),
                  ),
                  if (vod.vodRemarks.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      vod.vodRemarks,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: PeekColors.primary),
                    ),
                  ],
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: PeekColors.hint),
                    ),
                  ],
                  if (sourceName != null && sourceName!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: PeekColors.iconTile,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        sourceName!,
                        style: TextStyle(fontSize: 10, color: PeekColors.primary),
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
  const _PosterImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const _PosterPlaceholder();
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const _PosterPlaceholder(),
      loadingBuilder: (_, child, progress) => progress == null
          ? child
          : Container(
              color: PeekColors.card,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              ),
            ),
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
      child: Icon(Icons.movie_outlined, size: 26, color: PeekColors.railIdle),
    );
  }
}
