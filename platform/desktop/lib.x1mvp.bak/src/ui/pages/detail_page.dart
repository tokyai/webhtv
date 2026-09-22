/// 影片详情页 —— 移植并改造自 PeekPili `lib/pages/detail/detail_page.dart`。
///
/// 关键行为：`play` 返回的 500 是**业务提示**（如网盘未登录），
/// 需要把 `message` 原样展示，而不是显示"加载失败"。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/source_models.dart';
import '../../state/app_state.dart';
import '../theme/peek_nav.dart';
import '../theme/peek_theme.dart';
import '../widgets/peek_common.dart';
import '../widgets/player_sheet.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.vodId, this.preview});

  final String vodId;

  /// 列表页带过来的预览数据，用于首屏立即显示标题/封面。
  final VideoItem? preview;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  VideoDetail? _vod;
  bool _loading = true;
  String? _error;
  int _lineIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final d = await context.read<AppState>().loadDetail(widget.vodId);
    if (!mounted) return;
    setState(() {
      _vod = d;
      _loading = false;
      _error = d == null ? '该站点未返回详情（部分榜单类站点只提供推荐信息）' : null;
      _lineIndex = 0;
    });
  }

  Future<void> _toggleFavorite() async {
    final vod = _vod;
    final preview = widget.preview;
    final item = vod == null
        ? preview
        : VideoItem(
            vodId: vod.vodId,
            vodName: vod.vodName,
            vodPic: vod.vodPic,
            vodRemarks: vod.vodRemarks,
          );
    if (item == null) return;
    final app = context.read<AppState>();
    final wasFav = app.isFavorite(item.vodId);
    await app.toggleFavorite(item);
    if (!mounted) return;
    peekToast(context, wasFav ? '已取消收藏' : '已加入收藏「${item.vodName}」');
  }

  void _play(int episodeIndex) {
    final vod = _vod;
    if (vod == null) return;
    final lines = vod.sources;
    if (lines.isEmpty || _lineIndex >= lines.length) {
      peekToast(context, '该影片没有可播放的线路');
      return;
    }
    final line = lines[_lineIndex];
    if (episodeIndex < 0 || episodeIndex >= line.episodes.length) return;

    // 记一条观看历史（同 id 去重置顶）
    context.read<AppState>().addHistory(
          VideoItem(
            vodId: vod.vodId,
            vodName: vod.vodName.isEmpty
                ? (widget.preview?.vodName ?? '')
                : vod.vodName,
            vodPic: vod.vodPic.isEmpty
                ? (widget.preview?.vodPic ?? '')
                : vod.vodPic,
            vodRemarks: vod.vodRemarks,
          ),
          line.episodes[episodeIndex].name,
        );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerSheet(
          flag: line.name,
          episodeId: line.episodes[episodeIndex].id,
          episodeName: line.episodes[episodeIndex].name,
          title: vod.vodName.isEmpty
              ? (widget.preview?.vodName ?? '播放')
              : vod.vodName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vod = _vod;

    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _header(vod?.vodName ?? widget.preview?.vodName ?? '详情'),
            Expanded(
              child: _loading
                  ? const PeekLoading(text: '正在获取影片详情…')
                  : _error != null || vod == null
                      ? PeekEmpty(
                          icon: Icons.info_outline,
                          text: _error ?? '详情为空',
                          selectable: true,
                          actionText: '重试',
                          onAction: _load,
                        )
                      : _content(vod),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(String title) {
    final fav = _vod != null
        ? context.watch<AppState>().isFavorite(_vod!.vodId)
        : (widget.preview != null &&
            context.watch<AppState>().isFavorite(widget.preview!.vodId));
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: '返回',
            onPressed: () => Navigator.maybePop(context),
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
          PeekIconButton(
            icon: fav ? Icons.star_rounded : Icons.star_outline_rounded,
            tooltip: fav ? '取消收藏' : '加入收藏',
            color: fav ? PeekColors.primary : null,
            onTap: _toggleFavorite,
          ),
          PeekIconButton(icon: Icons.refresh, tooltip: '重新加载', onTap: _load),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _content(VideoDetail vod) {
    final lines = vod.sources;
    final episodes = lines.isEmpty
        ? const <PlayEpisode>[]
        : lines[_lineIndex.clamp(0, lines.length - 1)].episodes;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _head(vod),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 14),
          _lineSelector(lines),
        ],
        if (episodes.isNotEmpty) _episodes(episodes),
        if (lines.isEmpty) ...[
          const SizedBox(height: 20),
          PeekEmpty(
            icon: Icons.movie_filter_outlined,
            text: '该条目没有可播放的剧集。\n'
                '如果这是"豆瓣"等榜单类站点，它只提供推荐信息，\n'
                '请在左栏「站点」切换到可播放的源。',
          ),
        ],
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _head(VideoDetail vod) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 140,
              height: 192,
              child: (vod.vodPic.isEmpty ? widget.preview?.vodPic ?? '' : vod.vodPic)
                      .isEmpty
                  ? Container(
                      color: PeekColors.card,
                      alignment: Alignment.center,
                      child: Icon(Icons.movie_outlined,
                          size: 30, color: PeekColors.railIdle),
                    )
                  : Image.network(
                      vod.vodPic.isEmpty ? widget.preview!.vodPic : vod.vodPic,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: PeekColors.card,
                        alignment: Alignment.center,
                        child: Icon(Icons.movie_outlined,
                            size: 30, color: PeekColors.railIdle),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  vod.vodName.isEmpty ? '未知影片' : vod.vodName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: PeekColors.onSurface,
                    height: 1.25,
                  ),
                ),
                if (vod.vodRemarks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    vod.vodRemarks,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: PeekColors.primary),
                  ),
                ],
                if (vod.vodContent.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    _stripHtml(vod.vodContent),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: PeekColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _lineSelector(List<PlaySource> lines) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Row(
        children: [
          Text(
            '播放线路',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: PeekColors.onSurface,
            ),
          ),
          const SizedBox(width: 14),
          PopupMenuButton<int>(
            initialValue: _lineIndex,
            color: PeekColors.surfaceContainerHigh,
            tooltip: '切换线路',
            onSelected: (i) => setState(() => _lineIndex = i),
            itemBuilder: (_) => [
              for (var i = 0; i < lines.length; i++)
                PopupMenuItem<int>(
                  value: i,
                  child: Text(
                    '${lines[i].name}  (${lines[i].episodes.length} 集)',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: PeekColors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '《${lines[_lineIndex.clamp(0, lines.length - 1)].name}》',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: PeekColors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down,
                      size: 18, color: PeekColors.onPrimaryContainer),
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(
            '共 ${lines[_lineIndex.clamp(0, lines.length - 1)].episodes.length} 集',
            style: TextStyle(fontSize: 12, color: PeekColors.hint),
          ),
        ],
      ),
    );
  }

  Widget _episodes(List<PlayEpisode> episodes) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '剧集',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: PeekColors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < episodes.length; i++)
                InkWell(
                  onTap: () => _play(i),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 62),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: PeekColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      episodes[i].name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: PeekColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _stripHtml(String s) => s
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .trim();
}
