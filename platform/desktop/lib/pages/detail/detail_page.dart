import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_state.dart';
import '../../tvbox/models.dart';
import '../../tvbox/playlist_merge.dart';
import '../../widgets/common.dart';
import '../../widgets/poster_card.dart';
import '../player/player_page.dart';
import '../search/multi_search_page.dart';

/// 详情页。
///
/// 原版结构：
///   顶栏：返回 / 标题 / 收藏 / 更多
///   头部：海报 + 片名 + 评分 + 类型地区年份 + 演员导演
///   页签：简介 / 推荐 / 快搜
///   播放源：《线路名》下拉切换
///   合集：查看全部
///   剧集：网格（带播放进度高亮）
///   底部：官方下载提示浮层
class DetailPage extends StatefulWidget {
  final Site site;
  final String vodId;
  final Vod? preview;

  /// 叠加层模式：作为播放页侧边栏使用。
  ///
  /// 原版的详情页并不是独立页面，而是**播放器之上的一层侧边面板**：
  /// 播放器占主区，详情固定贴在一侧，关闭面板播放不中断。置为 `true` 时
  /// 本页不再渲染自己的顶栏与背景，只输出可嵌入的内容区，由宿主
  /// （[PlayerPage]）提供容器与关闭按钮。
  final bool embedded;

  /// 叠加层里点某一集时的回调；为空则走默认导航（push 播放页）。
  final void Function(Vod vod, int lineIndex, int episodeIndex)? onPickEpisode;

  const DetailPage({
    super.key,
    required this.site,
    required this.vodId,
    this.preview,
    this.embedded = false,
    this.onPickEpisode,
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Vod? _vod;
  bool _loading = true;
  String? _error;

  int _tab = 0;
  int _lineIndex = 0;

  List<Vod> _recommend = <Vod>[];
  bool _loadingRec = false;

  List<SiteVod> _quick = <SiteVod>[];
  bool _loadingQuick = false;

  int _progressIndex = -1;
  bool _showDownloadTip = true;

  @override
  void initState() {
    super.initState();
    _vod = widget.preview;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final v = await context.read<AppState>().detail(widget.site, widget.vodId);
      if (!mounted) return;
      setState(() {
        _vod = v ?? _vod;
        _loading = false;
      });
      _restoreProgress();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _restoreProgress() {
    final p = Store.progressOf(widget.site.displayKey, widget.vodId);
    if (p == null) return;
    final idx = int.tryParse('${p['episode_index'] ?? ''}') ?? -1;
    if (idx >= 0) setState(() => _progressIndex = idx);
  }

  Future<void> _loadRecommend() async {
    if (_recommend.isNotEmpty || _loadingRec) return;
    setState(() => _loadingRec = true);
    try {
      final name = _vod?.name ?? '';
      final r = await context.read<AppState>().search(name);
      if (!mounted) return;
      setState(() {
        _recommend = r.where((e) => e.id != widget.vodId).take(18).toList();
        _loadingRec = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingRec = false);
    }
  }

  Future<void> _loadQuick() async {
    if (_quick.isNotEmpty || _loadingQuick) return;
    setState(() => _loadingQuick = true);
    try {
      final name = _vod?.name ?? '';
      final r = await context.read<AppState>().searchAll(name);
      if (!mounted) return;
      setState(() {
        _quick = r.take(60).toList();
        _loadingQuick = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingQuick = false);
    }
  }

  /// 详情页「快搜」tab → 进入多元搜索页（原版 `T4SearchPage`）。
  /// 用户点剧集时若当前源不可播，也会走这里。
  Future<void> _openMultiSearch() async {
    final vod = _vod;
    if (vod == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MultiSearchPage(
          keyword: vod.name,
          autoChange: true,
          originName: vod.name,
          originSite: widget.site.name,
        ),
      ),
    );
  }

  void _play(int episodeIndex) {
    final vod = _vod;
    if (vod == null) return;
    final lines = _displayLines(vod);
    if (lines.isEmpty || _lineIndex >= lines.length) {
      peekToast(context, '该影片没有可播放的线路');
      return;
    }
    // 叠加层模式：交给宿主（播放页）在同一处播放器里切集，不新开页面
    if (widget.embedded) {
      widget.onPickEpisode?.call(vod, _lineIndex, episodeIndex);
      return;
    }
    final merged = context.read<AppState>().mergePlaylist;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerPage(
          site: widget.site,
          vod: vod,
          lineIndex: _lineIndex,
          episodeIndex: episodeIndex,
          // 合并后 `vod.lines` 的原始下标已经和「合集」里的剧集下标对不上，
          // 必须把合并好的列表直接交给播放页。
          linesOverride: merged ? lines : null,
        ),
      ),
    );
  }

  /// 详情页实际展示的线路列表。
  ///
  /// 原版首页 chips 行第 1 个 Button 是「合并播放列表」开关；开启后
  /// 多条线路合并成一条「合集」（原版播放页语义树里的「合集」节点）。
  List<PlayLine> _displayLines(Vod vod, [bool? merge]) => resolvePlayLines(
      vod.lines, merge ?? context.read<AppState>().mergePlaylist);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final vod = _vod;
    final fav = app.isFavorite(widget.site, widget.vodId);

    final body = Column(
      children: [
        if (widget.embedded)
          _panelHeader(vod?.name ?? '详情', fav)
        else
          _header(vod?.name ?? '详情', fav),
        Expanded(
          child: _loading && vod == null
              ? const PeekLoading(text: '正在获取影片详情…')
              : _error != null && vod == null
                  ? PeekEmpty(
                      icon: Icons.error_outline,
                      text: '详情加载失败\n$_error',
                      actionText: '重试',
                      onAction: _load,
                    )
                  : _content(vod!, app),
        ),
        if (_showDownloadTip && vod != null) _downloadTip(),
      ],
    );

    // 叠加层模式：不套自己的 Scaffold / SafeArea，由播放页提供容器
    if (widget.embedded) {
      return Material(
        color: Colors.transparent,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(child: body),
    );
  }

  /// 叠加层模式下的紧凑头：返回 / 片名 / 收藏 / 返回主页。
  /// 对应原版侧边面板顶部那一行。
  Widget _panelHeader(String title, bool fav) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          IconButton(
            tooltip: '返回',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, size: 19),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: PeekColors.onSurface),
            ),
          ),
          IconButton(
            tooltip: fav ? '取消收藏' : '收藏',
            onPressed: () async {
              final vod = _vod;
              if (vod == null) return;
              await context.read<AppState>().toggleFavorite(widget.site, vod);
              if (mounted) {
                peekToast(context, fav ? '已取消收藏' : '已加入收藏');
              }
            },
            icon: Icon(
              fav ? Icons.favorite : Icons.favorite_border,
              size: 19,
              color: fav ? PeekColors.primary : PeekColors.onSurface,
            ),
          ),
          IconButton(
            tooltip: '返回主页',
            onPressed: () =>
                Navigator.of(context).popUntil((r) => r.isFirst),
            icon: const Icon(Icons.home_outlined, size: 19),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _header(String title, bool fav) {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          const SizedBox(width: 6),
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: PeekColors.onSurface),
            ),
          ),
          IconButton(
            tooltip: fav ? '取消收藏' : '收藏',
            onPressed: () async {
              final vod = _vod;
              if (vod == null) return;
              await context.read<AppState>().toggleFavorite(widget.site, vod);
              if (mounted) {
                peekToast(context, fav ? '已取消收藏' : '已加入收藏');
              }
            },
            icon: Icon(
              fav ? Icons.favorite : Icons.favorite_border,
              size: 20,
              color: fav ? PeekColors.primary : PeekColors.onSurface,
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 20),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _content(Vod vod, AppState app) {
    final lines = _displayLines(vod, app.mergePlaylist);
    if (_lineIndex >= lines.length) _lineIndex = 0;
    final episodes = lines.isEmpty ? <Episode>[] : lines[_lineIndex].episodes;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _head(vod),
        _tabs(),
        _tabBody(vod),
        const SizedBox(height: 18),
        if (lines.isNotEmpty) _lineSelector(lines),
        if (episodes.isNotEmpty) _episodes(episodes),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _head(Vod vod) {
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
              child: vod.pic.isEmpty
                  ? Container(color: PeekColors.card)
                  : CachedNetworkImage(
                      imageUrl: vod.pic,
                      httpHeaders: vod.picHeaders,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: PeekColors.card),
                      errorWidget: (_, __, ___) => Container(
                        color: PeekColors.card,
                        child: Icon(Icons.movie_outlined,
                            color: PeekColors.railIdle),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vod.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: PeekColors.onSurface),
                ),
                const SizedBox(height: 10),
                if (vod.score > 0)
                  Row(
                    children: [
                      Icon(Icons.star_rounded,
                          size: 18, color: PeekColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        vod.score.toStringAsFixed(1),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: PeekColors.primary),
                      ),
                    ],
                  ),
                if (vod.remarks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(vod.remarks,
                      style: TextStyle(
                          fontSize: 12.5, color: PeekColors.onSurfaceVariant)),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final t in [
                      vod.typeName,
                      vod.year,
                      vod.area,
                    ])
                      if (t.isNotEmpty) _pill(t),
                  ],
                ),
                const SizedBox(height: 12),
                if (vod.director.isNotEmpty)
                  _kv('导演', vod.director),
                if (vod.actor.isNotEmpty) _kv('主演', vod.actor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: PeekColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 11.5, color: PeekColors.onSurfaceVariant)),
      );

  Widget _kv(String k, String v) {
    return Padding(
      padding: EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(k,
                style: TextStyle(fontSize: 12, color: PeekColors.hint)),
          ),
          Expanded(
            child: Text(
              v,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, color: PeekColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs() {
    const labels = ['简介', '推荐', '快搜'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 26),
              child: InkWell(
                onTap: () {
                  setState(() => _tab = i);
                  if (i == 1) _loadRecommend();
                  if (i == 2) _loadQuick();
                },
                child: Column(
                  children: [
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            _tab == i ? FontWeight.w600 : FontWeight.w400,
                        color: _tab == i
                            ? PeekColors.primary
                            : PeekColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      height: 2,
                      width: 22,
                      decoration: BoxDecoration(
                        color: _tab == i
                            ? PeekColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabBody(Vod vod) {
    switch (_tab) {
      case 1:
        if (_loadingRec) {
          return const SizedBox(
              height: 120, child: PeekLoading(text: '正在获取推荐…'));
        }
        if (_recommend.isEmpty) {
          return const SizedBox(
            height: 100,
            child: PeekEmpty(text: '暂无推荐内容', icon: Icons.recommend_outlined),
          );
        }
        return SizedBox(
          height: 230,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            itemCount: _recommend.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(right: 14),
              child: SizedBox(
                width: 120,
                child: PosterCard(
                  vod: _recommend[i],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DetailPage(
                        site: widget.site,
                        vodId: _recommend[i].id,
                        preview: _recommend[i],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      case 2:
        if (_loadingQuick) {
          return const SizedBox(
              height: 120, child: PeekLoading(text: '正在全网快搜…'));
        }
        if (_quick.isEmpty) {
          return const SizedBox(
            height: 100,
            child: PeekEmpty(text: '其他站源暂无该影片', icon: Icons.travel_explore),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
          child: Column(
            children: [
              // 「进入多元搜索页」—— 原版快搜 tab 的完整形态
              // （侧边栏 + 分源分组），这里给一个直达入口
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _openMultiSearch,
                  icon: const Icon(Icons.travel_explore, size: 16),
                  label: const Text('打开多元搜索页',
                      style: TextStyle(fontSize: 12.5)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 30),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              for (final q in _quick.take(12))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: SizedBox(
                      width: 42,
                      height: 58,
                      child: q.vod.pic.isEmpty
                          ? Container(color: PeekColors.card)
                          : CachedNetworkImage(
                              imageUrl: q.vod.pic,
                              httpHeaders: q.vod.picHeaders,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  Container(color: PeekColors.card),
                            ),
                    ),
                  ),
                  title: Text(q.vod.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    '${q.site.name}${q.vod.remarks.isEmpty ? '' : ' · ${q.vod.remarks}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: PeekColors.hint),
                  ),
                  trailing: Icon(Icons.chevron_right,
                      size: 18, color: PeekColors.railIdle),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DetailPage(
                        site: q.site,
                        vodId: q.vod.id,
                        preview: q.vod,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      default:
        // 说明：PeekPili 这里还挂了 `<TmdbSection>`（原版「开启后视频详情页将
        // 显示 TMDB 剧情等信息」）。TMDB 属于 WebHTV 安卓版没有的模块，
        // 按本轮要求（「去除之前 webhtv 没有的…模块」）已整体裁掉。
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Text(
                vod.content.isEmpty ? '暂无简介' : _stripHtml(vod.content),
                style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: PeekColors.onSurfaceVariant),
              ),
            ),
          ],
        );
    }
  }

  Widget _lineSelector(List<PlayLine> lines) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('播放源',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: PeekColors.onSurface)),
              const SizedBox(width: 10),
              Text(
                '合集 · 正在播放：${_lineIndex + 1}',
                style: TextStyle(fontSize: 11.5, color: PeekColors.hint),
              ),
              const Spacer(),
              // 原版 `changeable` 为真时才有「换源」入口
              if (widget.site.changeable)
                TextButton.icon(
                  onPressed: _openMultiSearch,
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('换源', style: TextStyle(fontSize: 12.5)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              TextButton(
                onPressed: () => _openAllEpisodes(lines),
                child: const Text('查看全部',
                    style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 线路 tabs：原版详情页底部横排线路按钮
          // （如 `夸克原画#01 / 夸克极速#01 / 夸克原画#02`）
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: lines.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final sel = i == _lineIndex;
                return InkWell(
                  onTap: () => setState(() {
                    _lineIndex = i;
                    // 原版：切换线路后左下角提示「正在切换线路至「XXX」」
                    peekToast(context, '正在切换线路至「${lines[i].name}」');
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel
                          ? PeekColors.primaryContainer
                          : PeekColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color:
                            sel ? PeekColors.primary : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      lines[i].name,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight:
                            sel ? FontWeight.w600 : FontWeight.w400,
                        color: sel
                            ? PeekColors.onPrimaryContainer
                            : PeekColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 「查看全部」面板 —— 原版：`合集` 标题 + 五图标工具条
  /// （排序 / 字号 / 顺序 / 定位 / 关闭）+ 分段页码 + 剧集网格。
  Future<void> _openAllEpisodes(List<PlayLine> lines) async {
    final episodes = lines.isEmpty ? <Episode>[] : lines[_lineIndex].episodes;
    if (episodes.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PeekColors.surfaceContainer,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _AllEpisodesSheet(
        title: '合集',
        episodes: episodes,
        progressIndex: _progressIndex,
        onPick: (i) {
          Navigator.of(ctx).pop();
          _play(i);
        },
      ),
    );
  }

  Widget _episodes(List<Episode> episodes) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('剧集',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: PeekColors.onSurface)),
          ),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: i == _progressIndex
                          ? PeekColors.primaryContainer
                          : PeekColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      episodes[i].name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: i == _progressIndex
                            ? PeekColors.onPrimaryContainer
                            : PeekColors.onSurfaceVariant,
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

  Widget _downloadTip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: PeekColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: PeekColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '本内容由第三方接口提供，请通过官方渠道下载安装使用',
              style: TextStyle(fontSize: 11.5, color: PeekColors.hint),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _showDownloadTip = false),
            child: Padding(
              padding: EdgeInsets.all(2),
              child: Icon(Icons.close, size: 15, color: PeekColors.hint),
            ),
          ),
        ],
      ),
    );
  }

  String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]+>'), '').replaceAll('&nbsp;', ' ').trim();
}

/// 「查看全部」剧集面板。
///
/// 原版形态：`合集` 标题 + 一条五图标工具条
/// （↓排序 / T字号 / ⇅顺序 / ⊙定位 / ✕关闭）
/// + 分段页码（`1-50 / 51-100 / 101-150 / …`）+ 剧集网格。
class _AllEpisodesSheet extends StatefulWidget {
  final String title;
  final List<Episode> episodes;
  final int progressIndex;
  final ValueChanged<int> onPick;

  const _AllEpisodesSheet({
    required this.title,
    required this.episodes,
    required this.progressIndex,
    required this.onPick,
  });

  @override
  State<_AllEpisodesSheet> createState() => _AllEpisodesSheetState();
}

class _AllEpisodesSheetState extends State<_AllEpisodesSheet> {
  /// 每段的集数（原版按 50 一段分页）
  static const int _segSize = 50;

  /// 倒序显示（原版工具条第 3 个图标的语义）
  bool _reversed = false;

  /// 每行集数（原版工具条第 2 个图标调整字号/密度）
  int _perRow = 5;

  late int _segment = 0;

  int get _segmentCount =>
      (widget.episodes.length / _segSize).ceil().clamp(1, 999);

  List<int> get _indexes {
    final start = _segment * _segSize;
    final end =
        (start + _segSize).clamp(0, widget.episodes.length).toInt();
    final list = [for (var i = start; i < end; i++) i];
    return _reversed ? list.reversed.toList() : list;
  }

  @override
  void initState() {
    super.initState();
    // 默认定位到当前播放集所在分段
    if (widget.progressIndex >= 0) {
      _segment = (widget.progressIndex ~/ _segSize).clamp(0, _segmentCount - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final idx = _indexes;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.66,
        child: Column(
          children: [
            // 标题 + 五图标工具条
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
              child: Row(
                children: [
                  Text(widget.title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: PeekColors.onSurface)),
                  const Spacer(),
                  IconButton(
                    tooltip: _reversed ? '恢复顺序' : '倒序',
                    onPressed: () => setState(() => _reversed = !_reversed),
                    icon: Icon(
                        _reversed
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 18),
                  ),
                  IconButton(
                    tooltip: '每行集数',
                    onPressed: () => setState(
                        () => _perRow = _perRow == 5 ? 8 : (_perRow == 8 ? 4 : 5)),
                    icon: const Icon(Icons.text_fields, size: 18),
                  ),
                  IconButton(
                    tooltip: '顺序',
                    onPressed: () => setState(() => _reversed = !_reversed),
                    icon: const Icon(Icons.swap_vert, size: 18),
                  ),
                  IconButton(
                    tooltip: '定位到当前集',
                    onPressed: widget.progressIndex >= 0
                        ? () => setState(() {
                              _segment = (widget.progressIndex ~/ _segSize)
                                  .clamp(0, _segmentCount - 1);
                            })
                        : null,
                    icon: const Icon(Icons.my_location, size: 18),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            // 分段页码
            if (_segmentCount > 1)
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  itemCount: _segmentCount,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, s) {
                    final sel = s == _segment;
                    final a = s * _segSize + 1;
                    final b = ((s + 1) * _segSize)
                        .clamp(0, widget.episodes.length)
                        .toInt();
                    return InkWell(
                      onTap: () => setState(() => _segment = s),
                      borderRadius: BorderRadius.circular(7),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel
                              ? PeekColors.primaryContainer
                              : PeekColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '$a-$b',
                          style: TextStyle(
                            fontSize: 12,
                            color: sel
                                ? PeekColors.onPrimaryContainer
                                : PeekColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 6),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _perRow,
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  childAspectRatio: 1.85,
                ),
                itemCount: idx.length,
                itemBuilder: (_, i) {
                  final real = idx[i];
                  final sel = real == widget.progressIndex;
                  return InkWell(
                    onTap: () => widget.onPick(real),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel
                            ? PeekColors.primaryContainer
                            : PeekColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              sel ? PeekColors.primary : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        widget.episodes[real].name,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: sel
                              ? PeekColors.onPrimaryContainer
                              : PeekColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
