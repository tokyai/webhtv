import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/poster_card.dart';
import '../detail/detail_page.dart';

/// 搜索页。
///
/// 原版结构：
///   顶部搜索框 + 右侧「搜索」按钮
///   未输入时：搜索历史 + 热搜榜（含排名与热度值，Top30）
///   结果区：跨站源聚合，支持「视图模式」网格/列表 与「标题」紧凑/完整 两组开关
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _searched = false;
  bool _searching = false;
  int _done = 0;
  int _total = 0;
  List<SiteVod> _results = <SiteVod>[];
  List<String> _history = <String>[];

  @override
  void initState() {
    super.initState();
    _history = Store.searchHistory;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadHotWords();
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _doSearch(String kw) async {
    final keyword = kw.trim();
    if (keyword.isEmpty) return;
    _ctrl.text = keyword;
    _focus.unfocus();
    await Store.addSearchHistory(keyword);
    if (!mounted) return;
    setState(() {
      _history = Store.searchHistory;
      _searched = true;
      _searching = true;
      _done = 0;
      _total = 0;
      _results = <SiteVod>[];
    });
    try {
      final r = await context.read<AppState>().searchAll(
        keyword,
        onProgress: (d, t) {
          if (!mounted) return;
          setState(() {
            _done = d;
            _total = t;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _results = r;
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _searching = false);
      peekToast(context, '搜索失败：${friendlyError(e)}');
    }
  }

  void _open(SiteVod sv) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(site: sv.site, vodId: sv.vod.id, preview: sv.vod),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Row(
          children: [
            if (MediaQuery.of(context).size.width >= 900)
              _ViewModePanel(
                viewMode: app.viewMode,
                compact: app.compactTitle,
                showTitle: app.showPosterTitle,
                onViewMode: app.setViewMode,
                onCompact: app.setCompactTitle,
                onShowTitle: app.setShowPosterTitle,
              ),
            Expanded(
              child: Column(
                children: [
                  _header(),
                  Expanded(child: _body(app)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: _doSearch,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: '搜索影片、剧集、综艺…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() {
                          _ctrl.clear();
                          _searched = false;
                          _results = <SiteVod>[];
                        }),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: () => _doSearch(_ctrl.text),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('搜索', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 18),
        ],
      ),
    );
  }

  Widget _body(AppState app) {
    if (_searching) {
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
            Text(
              '正在聚合搜索 $_done/$_total 个站源…',
              style: TextStyle(fontSize: 13, color: PeekColors.hint),
            ),
          ],
        ),
      );
    }

    if (!_searched) return _discover(app);

    if (_results.isEmpty) {
      return PeekEmpty(
        icon: Icons.search_off_outlined,
        text: '没有搜索到「${_ctrl.text}」相关内容\n可尝试更换站源或更换关键词',
      );
    }

    if (app.viewMode == ViewMode.list) {
      return ListView.builder(
        padding: const EdgeInsets.only(top: 6, bottom: 24),
        itemCount: _results.length,
        itemBuilder: (_, i) => PosterRowTile(
          vod: _results[i].vod,
          sourceName: _results[i].site.name,
          onTap: () => _open(_results[i]),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth - PeekColors.contentPadding * 2;
        const gap = PeekColors.gridGap;
        final cols = ((w + gap) / (181 + gap)).round().clamp(2, 8);
        final itemW = (w - gap * (cols - 1)) / cols;
        final ratio = itemW / (itemW / PeekColors.posterAspect + 41);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            PeekColors.contentPadding,
            12,
            PeekColors.contentPadding,
            24,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 16,
            crossAxisSpacing: gap,
            childAspectRatio: ratio,
          ),
          itemCount: _results.length,
          itemBuilder: (_, i) => PosterCard(
            vod: _results[i].vod,
            badge: _results[i].site.name,
            showTitle: app.showPosterTitle,
            compact: app.compactTitle,
            onTap: () => _open(_results[i]),
          ),
        );
      },
    );
  }

  /// 未搜索时：搜索历史 + 热搜榜
  Widget _discover(AppState app) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        if (_history.isNotEmpty) ...[
          Row(
            children: [
              Text('搜索历史',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: PeekColors.onSurface)),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  await Store.clearSearchHistory();
                  setState(() => _history = Store.searchHistory);
                },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('清空', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final h in _history)
                InkWell(
                  onTap: () => _doSearch(h),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: PeekColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(h,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: PeekColors.onSurfaceVariant)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
        Text('热搜榜',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: PeekColors.onSurface)),
        const SizedBox(height: 8),
        if (app.loadingHot && app.hotWords.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: PeekLoading(text: '正在获取热搜…'),
          )
        else
          for (var i = 0; i < app.hotWords.length; i++)
            InkWell(
              onTap: () => _doSearch(app.hotWords[i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: i < 3
                              ? PeekColors.primary
                              : PeekColors.railIdle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        app.hotWords[i],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5, color: PeekColors.onSurface),
                      ),
                    ),
                    if (i < 3)
                      Icon(Icons.local_fire_department,
                          size: 15, color: PeekColors.primary),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// 左侧「视图模式」面板
class _ViewModePanel extends StatelessWidget {
  final ViewMode viewMode;
  final bool compact;
  final bool showTitle;
  final ValueChanged<ViewMode> onViewMode;
  final ValueChanged<bool> onCompact;
  final ValueChanged<bool> onShowTitle;

  const _ViewModePanel({
    required this.viewMode,
    required this.compact,
    required this.showTitle,
    required this.onViewMode,
    required this.onCompact,
    required this.onShowTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: PeekColors.railDivider, width: 1),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        children: [
          Text('视图模式',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: PeekColors.primary)),
          const SizedBox(height: 10),
          _opt('网格', viewMode == ViewMode.grid,
              () => onViewMode(ViewMode.grid)),
          _opt('列表', viewMode == ViewMode.list,
              () => onViewMode(ViewMode.list)),
          const SizedBox(height: 22),
          Text('标题模式',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: PeekColors.primary)),
          const SizedBox(height: 10),
          _opt('完整标题', showTitle, () => onShowTitle(true)),
          _opt('紧凑', compact, () => onCompact(!compact)),
        ],
      ),
    );
  }

  Widget _opt(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 9, horizontal: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? PeekColors.primary
                      : PeekColors.onSurfaceVariant,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check, size: 15, color: PeekColors.primary),
          ],
        ),
      ),
    );
  }
}
