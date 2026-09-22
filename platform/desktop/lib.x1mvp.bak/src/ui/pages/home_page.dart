/// 首页 —— 移植并改造自 PeekPili `lib/pages/home/home_page.dart`，
/// 数据源换成 WebHTV 源服务（CatVodSpiderios）。
///
/// ## 原版实测几何（1920x1080 @280dpi = 1.75）
/// - 顶栏内容中心 y=88px → 59dp（Logo 36dp + 「源名|分类名」，右侧 4 个图标间距 92px → 61dp）
/// - 分类条 y=152..214px → 101..143dp（药丸高 41dp，间距 23dp，右侧 筛选 + 网格/列表切换）
/// - 海报墙自 y=242px → 161dp 起（6 列，列间距 14dp，内容区左右内边距 18dp）
///
/// ## 与安卓版 WebHTV 的对应关系
/// 安卓首页是 `VodFragment`：MaterialToolbar（logo+title+菜单）+
/// 分类 RecyclerView（`type`）+ CustomViewPager（`pager`）+ 3 个 FAB
/// （筛选 `filter` / 链接 `link` / 置顶 `top`）。
/// 这里按桌面习惯映射为：
///   顶栏 = logo + 「源名|分类名」 + 搜索/换源/换站点/收藏/刷新
///   分类条 = 分类药丸 + 筛选按钮 + 视图切换 + 全部分类
///   网格 = 海报墙（对齐 PeekPili 的 6 列公式）
///   上滑加载 = 替代 pager 的翻页（桌面无左右滑手势）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/source_models.dart';
import '../../state/app_state.dart';
import '../theme/peek_nav.dart';
import '../theme/peek_theme.dart';
import '../widgets/peek_common.dart';
import '../widgets/peek_filter_dialog.dart';
import '../widgets/peek_poster_card.dart';
import '../widgets/peek_site_picker.dart';
import 'detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.onOpenSearch});

  /// shell 注入的「打开搜索」入口。
  final VoidCallback? onOpenSearch;

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  int _classIndex = 0; // 0 = 精选（源返回的 list）
  final List<VideoItem> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  final _scroll = ScrollController();
  bool _showFilters = false;
  Map<String, String> _extend = {};

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 数据
  // ---------------------------------------------------------------------------

  AppState get _app => context.read<AppState>();

  bool get _isFeatured => _classIndex == 0;

  List<CategoryClass> get _classes => _app.home.classes;

  CategoryClass? get _currentClass =>
      (_classIndex >= 1 && _classIndex <= _classes.length)
          ? _classes[_classIndex - 1]
          : null;

  /// 顶栏标题。源站名本身常含「源|页」写法，取分隔符前一段再拼分类名。
  String get _title {
    final raw = _app.currentSite?.name ?? 'WebHTV';
    final prefix = raw.split(RegExp(r'[|｜┃丨]')).first.trim();
    final cls = _currentClass?.typeName;
    if (_isFeatured || cls == null || cls.isEmpty) return prefix;
    return '$prefix|$cls';
  }

  List<FilterGroup> get _filtersOfCurrent {
    final cls = _currentClass;
    if (cls == null) return const [];
    return _app.home.filters[cls.typeId] ?? const [];
  }

  /// 重按左栏「首页」→ 回顶并刷新。
  Future<void> reload() async {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final app = _app;
    await app.loadHome();
    if (!mounted) return;
    setState(() {
      _classIndex = 0;
      _items
        ..clear()
        ..addAll(app.home.list);
      _hasMore = app.home.list.isNotEmpty;
      _loading = false;
      _error = app.lastError;
    });
  }

  Future<void> _selectClass(int index) async {
    setState(() {
      _classIndex = index;
      _items.clear();
      _hasMore = true;
      _error = null;
      _loading = true;
      _extend = {};
    });

    if (index == 0) {
      setState(() {
        _items.addAll(_app.home.list);
        _loading = false;
        _showFilters = false;
      });
      return;
    }

    final cls = _classes[index - 1];
    final groups = _app.home.filters[cls.typeId] ?? const <FilterGroup>[];
    setState(() => _showFilters = groups.isNotEmpty);

    final app = _app;
    await app.loadCategory(cls.typeId, page: 1, filters: _extend);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(app.page.list);
      _hasMore = app.page.page < app.page.pageCount && app.page.list.isNotEmpty;
      _loading = false;
      _error = app.lastError;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _isFeatured) return;
    setState(() => _loading = true);
    final app = _app;
    final before = app.page.list.length;
    await app.loadMore();
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(app.page.list);
      _hasMore = app.page.list.length > before;
      _loading = false;
      _error = app.lastError;
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) _loadMore();
  }

  // ---------------------------------------------------------------------------
  // 动作
  // ---------------------------------------------------------------------------

  Future<void> _openFilter() async {
    final cls = _currentClass;
    if (cls == null) return;
    final result = await showCategoryFilter(
      context,
      cls.typeName,
      _filtersOfCurrent,
      _extend,
    );
    if (result == null || !mounted) return;
    setState(() {
      _extend = result;
      _items.clear();
      _hasMore = true;
      _loading = true;
    });
    final app = _app;
    await app.loadCategory(cls.typeId, page: 1, filters: _extend);
    if (!mounted) return;
    setState(() {
      _items
        ..clear()
        ..addAll(app.page.list);
      _hasMore = app.page.list.isNotEmpty && app.page.page < app.page.pageCount;
      _loading = false;
      _error = app.lastError;
    });
  }

  Future<void> _openSitePicker() async {
    final app = _app;
    if (app.sites.isEmpty) {
      peekToast(context, '源未返回任何站点');
      return;
    }
    final picked = await showSitePicker(
      context,
      sites: app.sites,
      currentKey: app.currentSite?.key,
    );
    if (picked == null || !mounted) return;
    await app.selectSite(picked);
    if (!mounted) return;
    await _refresh();
  }

  void _openClassSheet() {
    showModalBottomSheet<int>(
      context: context,
      backgroundColor: PeekColors.surfaceContainer,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ClassSheet(
        names: ['精选', ..._classes.map((c) => c.typeName)],
        index: _classIndex,
      ),
    ).then((i) {
      if (i != null && mounted) _selectClass(i);
    });
  }

  void _openDetail(VideoItem vod) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailPage(
          vodId: vod.vodId,
          preview: vod,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 视图
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    if (!app.serviceReady && app.sites.isEmpty) {
      return _NotReadyState(
        phase: app.phase,
        message: app.phaseMessage,
        onRetry: () => _app.startActive(),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 内容区自带的顶部留白（左栏没有 SafeArea，别用全局 SafeArea 顶掉）
        const SizedBox(height: 20),
        _TopBar(
          title: _title,
          onSearch: widget.onOpenSearch,
          onSite: _openSitePicker,
          onFavorite: () => _goFavorite(),
          onRefresh: _refresh,
        ),
        _CategoryBar(
          names: ['精选', ..._classes.map((c) => c.typeName)],
          index: _classIndex,
          onSelect: _selectClass,
          onClassSheet: _openClassSheet,
          hasFilters: _filtersOfCurrent.isNotEmpty,
          onFilter: _openFilter,
          filterActive: _extend.values.any((v) => v.isNotEmpty),
        ),
        if (_showFilters && _filtersOfCurrent.isNotEmpty)
          _InlineFilterPanel(
            groups: _filtersOfCurrent,
            selected: _extend,
            onChanged: (k, v) {
              setState(() => _extend[k] = v);
              _openFilter();
            },
          ),
        Expanded(child: _buildBody(app)),
      ],
    );
  }

  void _goFavorite() {
    peekToast(context, '收藏页在左栏「收藏」');
  }

  Widget _buildBody(AppState app) {
    final items = _items;

    if (_loading && items.isEmpty) {
      return const PeekLoading(text: '正在获取首页内容…');
    }
    if (_error != null && items.isEmpty) {
      return PeekEmpty(
        icon: Icons.cloud_off_outlined,
        text: '内容加载失败\n$_error',
        selectable: true,
        actionText: '重试',
        onAction: _refresh,
      );
    }
    if (items.isEmpty) {
      final cls = _currentClass;
      return PeekEmpty(
        icon: Icons.inbox_outlined,
        text: _isFeatured
            ? '该站点首页没有返回内容\n可试试切换分类或换一个站点'
            : '「${cls?.typeName ?? ''}」暂无内容\n可调整筛选条件或换一个站点',
        actionText: '重试',
        onAction: _refresh,
      );
    }

    return RefreshIndicator(
      color: PeekColors.primary,
      backgroundColor: PeekColors.surfaceContainerHigh,
      onRefresh: _refresh,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth - PeekColors.contentPadding * 2;
          const gap = PeekColors.gridGap;
          const target = PeekColors.gridTargetWidth;
          final cols = ((w + gap) / (target + gap)).round().clamp(2, 8);
          final itemW = (w - gap * (cols - 1)) / cols;
          // 文字区（标题 + 备注）固定高度，避免不同标题长度导致行高抖动
          const textH = 41.0;
          final ratio = itemW / (itemW / PeekColors.posterAspect + textH);

          return GridView.builder(
            controller: _scroll,
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
            itemCount: items.length + 1,
            itemBuilder: (_, i) {
              if (i == items.length) return _buildFooter(asGridCell: true);
              final v = items[i];
              return PosterCard(vod: v, onTap: () => _openDetail(v));
            },
          );
        },
      ),
    );
  }

  Widget _buildFooter({bool asGridCell = false}) {
    Widget child;
    if (_error != null) {
      child = Center(
        child: TextButton(
          onPressed: _loadMore,
          child: const Text('加载失败，点击重试', style: TextStyle(fontSize: 12.5)),
        ),
      );
    } else if (_loading) {
      child = const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (!_hasMore || _isFeatured) {
      child = Center(
        child: Text(
          _isFeatured ? '' : '没有更多了',
          style: TextStyle(fontSize: 12, color: PeekColors.hint),
        ),
      );
    } else {
      child = const SizedBox(height: 8);
    }
    return asGridCell
        ? child
        : SizedBox(height: 46, child: child);
  }
}

// -----------------------------------------------------------------------------
// 顶栏
// -----------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onSearch,
    required this.onSite,
    required this.onFavorite,
    required this.onRefresh,
  });

  final String title;
  final VoidCallback? onSearch;
  final VoidCallback onSite;
  final VoidCallback onFavorite;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          const SizedBox(width: 10),
          // Logo + 「源名|分类名」整体可点（对齐原版点标题区换源的交互）
          InkWell(
            onTap: onSite,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: PeekColors.iconTile,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(Icons.play_arrow_rounded,
                            size: 19, color: PeekColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: PeekColors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          PeekIconButton(
            icon: Icons.search,
            tooltip: '搜索',
            onTap: onSearch,
          ),
          PeekIconButton(
            icon: Icons.add_link,
            tooltip: '切换站点',
            onTap: onSite,
          ),
          PeekIconButton(
            icon: Icons.favorite_border,
            tooltip: '收藏',
            onTap: onFavorite,
          ),
          PeekIconButton(
            icon: Icons.refresh,
            tooltip: '刷新首页',
            onTap: onRefresh,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 分类条
// -----------------------------------------------------------------------------

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({
    required this.names,
    required this.index,
    required this.onSelect,
    required this.onClassSheet,
    required this.hasFilters,
    required this.onFilter,
    required this.filterActive,
  });

  final List<String> names;
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onClassSheet;
  final bool hasFilters;
  final VoidCallback onFilter;
  final bool filterActive;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: names.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final selected = i == index;
                return InkWell(
                  onTap: () => onSelect(i),
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    height: PeekColors.chipHeight,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: PeekColors.chipPaddingH,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? PeekColors.chipSelectedFill
                          : PeekColors.chipFill,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: selected
                            ? PeekColors.chipSelectedBorder
                            : PeekColors.chipBorder,
                        width: PeekColors.chipBorderWidth,
                      ),
                    ),
                    child: Text(
                      names[i],
                      style: TextStyle(
                        fontSize: 14.5,
                        color: selected
                            ? PeekColors.chipSelectedText
                            : PeekColors.chipText,
                        fontWeight:
                            selected ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (hasFilters)
            _barIcon(
              filterActive ? Icons.filter_alt : Icons.filter_alt_outlined,
              tooltip: filterActive ? '筛选（已生效）' : '筛选',
              onTap: onFilter,
              active: filterActive,
            ),
          _barIcon(Icons.keyboard_arrow_down, tooltip: '全部分类', onTap: onClassSheet),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _barIcon(
    IconData icon, {
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    // ⚠️ tapTargetSize 不是 IconButton 的直接参数，要用 styleFrom
    return Tooltip(
      message: tooltip,
      child: IconButton(
        style: IconButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(32, 40),
          maximumSize: const Size(32, 40),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(icon, size: 21),
        color: active ? PeekColors.primary : PeekColors.onSurfaceVariant,
        onPressed: onTap,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 内联筛选条
// -----------------------------------------------------------------------------

class _InlineFilterPanel extends StatelessWidget {
  const _InlineFilterPanel({
    required this.groups,
    required this.selected,
    required this.onChanged,
  });

  final List<FilterGroup> groups;
  final Map<String, String> selected;
  final void Function(String key, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final g in groups)
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                itemCount: g.values.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final v = g.values[i];
                  final isSel = (selected[g.key] ?? '') == v.value;
                  return Center(
                    child: InkWell(
                      onTap: () => onChanged(g.key, v.value),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSel
                              ? PeekColors.primaryContainer
                              : PeekColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          // 源本身就把「全部类型/全部地区/全部年代」作为首值返回，不再补「全部」
                          v.name.isEmpty ? '全部' : v.name,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isSel
                                ? PeekColors.onPrimaryContainer
                                : PeekColors.onSurfaceVariant,
                          ),
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
}

// -----------------------------------------------------------------------------
// 全部分类底部弹层
// -----------------------------------------------------------------------------

class _ClassSheet extends StatelessWidget {
  const _ClassSheet({required this.names, required this.index});

  final List<String> names;
  final int index;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '全部分类',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: PeekColors.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 14,
                  children: [
                    for (var i = 0; i < names.length; i++)
                      SizedBox(
                        width: 260,
                        child: _sheetChip(
                          context,
                          names[i],
                          i == index,
                          () => Navigator.pop(context, i),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetChip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? PeekColors.primaryContainer
              : PeekColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            color: selected
                ? PeekColors.onPrimaryContainer
                : PeekColors.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 源未就绪
// -----------------------------------------------------------------------------

class _NotReadyState extends StatelessWidget {
  const _NotReadyState({
    required this.phase,
    required this.message,
    required this.onRetry,
  });

  final SourcePhase phase;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final failed = phase == SourcePhase.error;
    if (!failed) {
      return PeekLoading(text: message.isEmpty ? '正在准备源服务…' : message);
    }
    return PeekEmpty(
      icon: Icons.error_outline,
      text: '源服务未就绪\n$message',
      selectable: true,
      actionText: '重启源服务',
      onAction: onRetry,
    );
  }
}
