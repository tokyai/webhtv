import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_state.dart';
import '../../tvbox/models.dart';
import '../../widgets/common.dart';
import '../../widgets/poster_card.dart';
import '../detail/detail_page.dart';
import '../favorite_page.dart';
import '../history_page.dart';
import '../search/search_page.dart';
import 'source_picker.dart';

/// 首页。
///
/// 原版布局（1920x1080 @density1.5 实测）：
///   顶栏 内容中心 y=88px -> 59dp：左侧 logo 36dp + 「源名|分类名」，右侧 4 个图标
///         （搜索 / 换源 / 历史 / 收藏），图标中心间距 92px -> 61dp
///   分类条 y=152..214px -> 101..143dp：chip 高 41dp、间距 23dp，
///         右侧为「筛选」与「网格/列表」切换
///   海报网格 y=242px -> 161dp 起：6 列、列间距 14dp、内容左右内边距 18dp
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  int _classIndex = 0;
  final List<Vod> _items = <Vod>[];
  final Map<String, String> _extend = <String, String>{};
  int _page = 1;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  final ScrollController _scroll = ScrollController();

  /// 内联筛选面板是否展开（原版：选中带筛选的分类后自动展开多行条件）
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncHome());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  AppState get _app => context.read<AppState>();

  /// 供主框架调用（再次点击「首页」时回到顶部并刷新）
  Future<void> reload() async {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _refresh();
  }

  /// 精选：直接使用 homeContent 的推荐列表
  bool get _isFeatured => _classIndex == 0;

  List<VodClass> get _classes {
    final home = _app.home;
    if (home == null) return const [];
    return home.classes;
  }

  VodClass? get _currentClass {
    if (_isFeatured || _classes.isEmpty) return null;
    final i = _classIndex - 1;
    return i < _classes.length ? _classes[i] : null;
  }

  /// 顶栏显示的「分类」部分：精选页显示「首页」，其余显示分类名
  String get _currentClassName =>
      _isFeatured ? '首页' : (_currentClass?.typeName ?? '首页');

  /// 顶栏标题。
  ///
  /// 原版实测为「豆瓣|首页」—— 而该源的自注册名恰好也是「豆瓣|首页」
  /// （Node `/full-config` 首项 `nodejs_douban`）。
  /// 即源名已自带「源|页」结构，不能再直接拼一次，否则会得到「豆瓣|首页|首页」。
  /// 规则：取源名首个分隔符之前的部分作为源前缀，再与当前页名拼接。
  String get _title {
    final name = _app.currentSiteName;
    final i = name.indexOf(RegExp(r'[|｜┃丨]'));
    final prefix = i > 0 ? name.substring(0, i) : name;
    return '$prefix|$_currentClassName';
  }

  void _syncHome() {
    final app = _app;
    if (app.home != null) {
      setState(() {
        _items
          ..clear()
          ..addAll(app.home!.list);
        _error = null;
      });
    }
  }

  Future<void> _selectClass(int index) async {
    if (_classIndex == index) return;
    final cls = index == 0 ? null : (index - 1 < _classes.length ? _classes[index - 1] : null);
    setState(() {
      _classIndex = index;
      _items.clear();
      _error = null;
      _hasMore = true;
      _page = 1;
      _extend.clear();
      // 原版行为：切到带筛选条件的分类时，条件行自动展开
      _showFilters = (cls?.filters.isNotEmpty ?? false);
    });
    if (index == 0) {
      await _app.loadHome(force: true);
      if (mounted) _syncHome();
    } else {
      await _loadMore();
    }
  }

  /// 应用筛选条件（内联面板点选后立即重查）
  Future<void> _applyExtend(String key, String value) async {
    setState(() {
      if (value.isEmpty) {
        _extend.remove(key);
      } else {
        _extend[key] = value;
      }
      _items.clear();
      _page = 1;
      _hasMore = true;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_isFeatured || _loading || !_hasMore) return;
    final cls = _currentClass;
    if (cls == null) return;
    setState(() => _loading = true);
    try {
      final res = await _app.category(
        typeId: cls.typeId,
        page: _page,
        extend: _extend,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(res.list);
        _hasMore = res.hasMore && res.list.isNotEmpty;
        _page++;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasMore = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _refresh() async {
    if (_isFeatured) {
      await _app.loadHome(force: true);
      if (mounted) _syncHome();
      return;
    }
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
    });
    await _loadMore();
  }

  void _openVod(Vod vod) {
    final site = _app.currentSite;
    if (site == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(site: site, vodId: vod.id, preview: vod),
      ),
    );
  }

  /// 原版「全部分类」弹层：chips 行最右 ∨ 触发，2 列网格列出所有分类。
  Future<void> _openClassSheet() async {
    final names = <String>['精选', ..._classes.map((e) => e.typeName)];
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: PeekColors.surfaceContainer,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _ClassSheet(names: names, index: _classIndex),
    );
    if (picked != null && picked != _classIndex) {
      await _selectClass(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cls = _currentClass;
    final hasFilters = cls != null && cls.filters.isNotEmpty;
    return Column(
      children: [
        // 原版实测：内容区顶栏图标中心在 y=91px（@1.75 → 52dp）。
        // 顶栏本身是 64dp（和我们一样，中心 32dp），差出来的 20dp 是
        // **内容区自己的顶部留白**。左栏没有这层留白（它的分割线从 y=0 贯穿），
        // 所以不能用一个全局 SafeArea 来凑。
        const SizedBox(height: 20),
        _TopBar(
          title: _title,
          onSearch: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SearchPage()),
          ),
          onSwitchSource: () => showSourcePicker(context),
          onHistory: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HistoryPage()),
          ),
          onFavorite: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FavoritePage()),
          ),
        ),
        _CategoryBar(
          classes: _classes,
          index: _classIndex,
          onSelect: _selectClass,
          viewMode: app.viewMode,
          onToggleView: () {
            app.setViewMode(app.viewMode == ViewMode.grid
                ? ViewMode.list
                : ViewMode.grid);
          },
          filterOpen: _showFilters,
          onFilterToggle: hasFilters
              ? () => setState(() => _showFilters = !_showFilters)
              : null,
          onAllClasses: _openClassSheet,
          mergePlaylist: app.mergePlaylist,
          onToggleMerge: () => app.setMergePlaylist(!app.mergePlaylist),
        ),
        if (_showFilters && hasFilters)
          _InlineFilterPanel(
            cls: cls,
            selected: _extend,
            onChanged: _applyExtend,
          ),
        Expanded(child: _buildBody(app)),
      ],
    );
  }

  Widget _buildBody(AppState app) {
    // 「精选」直接以 AppState.home 为准（配置可能在首帧之后才加载完成，
    // 因此不能只依赖本地缓存的 _items）；其余分类用分页累积的 _items。
    final items = _isFeatured
        ? (app.home?.list ?? const <Vod>[])
        : _items;

    if (items.isEmpty) {
      if (app.loadingHome || _loading) {
        return const PeekLoading(text: '正在加载首页内容…');
      }
      final err = _isFeatured ? app.homeError : _error;
      if (err != null) {
        return PeekEmpty(
          icon: Icons.cloud_off_outlined,
          text: '首页加载失败\n$err',
          actionText: '重试',
          onAction: _isFeatured
              ? () => app.loadHome(force: true)
              : () {
                  setState(() {
                    _error = null;
                    _hasMore = true;
                  });
                  _loadMore();
                },
        );
      }
      return PeekEmpty(
        icon: Icons.movie_filter_outlined,
        text: _isFeatured ? '当前接口暂无推荐内容' : '该分类暂无内容',
        actionText: '刷新',
        onAction: _refresh,
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: PeekColors.primary,
      backgroundColor: PeekColors.surfaceContainerHigh,
      child: LayoutBuilder(
        builder: (context, c) {
          if (app.viewMode == ViewMode.list) {
            return ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              itemCount: items.length + 1,
              itemBuilder: (_, i) {
                if (i == items.length) return _buildFooter();
                return PosterRowTile(
                  vod: items[i],
                  onTap: () => _openVod(items[i]),
                );
              },
            );
          }

          final w = c.maxWidth - PeekColors.contentPadding * 2;
          const gap = PeekColors.gridGap;
          const target = PeekColors.gridTargetWidth;
          final cols = ((w + gap) / (target + gap)).round().clamp(2, 8);
          final itemW = (w - gap * (cols - 1)) / cols;
          const textH = 41.0;
          final ratio = itemW / (itemW / PeekColors.posterAspect + textH);

          return GridView.builder(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
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
              if (i == items.length) {
                return _buildFooter(asGridCell: true);
              }
              return PosterCard(
                vod: items[i],
                onTap: () => _openVod(items[i]),
                showTitle: app.showPosterTitle,
                compact: app.compactTitle,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFooter({bool asGridCell = false}) {
    if (_error != null) {
      final child = Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: TextButton(
            onPressed: () {
              setState(() {
                _error = null;
                _hasMore = true;
              });
              _loadMore();
            },
            child: const Text('加载失败，点击重试', style: TextStyle(fontSize: 12)),
          ),
        ),
      );
      return asGridCell
          ? GridView.count(
              crossAxisCount: 1,
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              childAspectRatio: 6,
              children: [child],
            )
          : child;
    }
    if (_isFeatured) return const SizedBox(height: 8);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: Text('没有更多了',
              style: TextStyle(fontSize: 12, color: PeekColors.hint)),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

/// 顶栏
class _TopBar extends StatelessWidget {
  final String title;
  final VoidCallback onSearch;
  final VoidCallback onSwitchSource;
  final VoidCallback onHistory;
  final VoidCallback onFavorite;

  const _TopBar({
    required this.title,
    required this.onSearch,
    required this.onSwitchSource,
    required this.onHistory,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: Row(
        children: [
          // 原版实测：顶栏 logo 可见左边缘就在 x=161px —— 与内容区左边缘
          // （海报墙第 1 列、chips 首个药丸）**完全对齐**，即统一的 16dp 内边距。
          // 这 10dp 加上下面 InkWell 自带的 6dp 横向 padding 正好 16dp。
          const SizedBox(width: 10),
          InkWell(
            onTap: onSwitchSource,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.asset(
                      'assets/images/logo/logo.png',
                      // 原版实测 logo 可见块 x=161..216 = 56px = 32dp
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 32,
                        height: 32,
                        color: PeekColors.iconTile,
                        child: Icon(Icons.movie_filter_outlined,
                            size: 18, color: PeekColors.primary),
                      ),
                    ),
                  ),
                  // 原版实测：logo 右边缘 216px → 标题首个字形 232px，即约 8dp
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
            tooltip: '换源',
            onTap: onSwitchSource,
          ),
          PeekIconButton(
            icon: Icons.history,
            tooltip: '历史',
            onTap: onHistory,
          ),
          PeekIconButton(
            icon: Icons.favorite_border,
            tooltip: '收藏',
            onTap: onFavorite,
          ),
          // 原版实测：4 个图标中心 x = 1611 / 1695 / 1779 / 1863，间距 84px = 48dp
          // （= IconButton 在 `MaterialTapTargetSize.padded` 下的默认盒宽）。
          // 最后一个中心 1863px 反推右留白 = 1920 - 1863 - 42 = 15px ≈ 8dp。
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// 分类 chips 条。
///
/// 原版实测（1920×1080 @1.75，`uiautomator dump` 原版语义树）右侧控制图标组：
///   精选（无筛选条件）→ `☰▸ 合并播放列表` / `⊞ 视图` / `∨ 全部分类`（3 个）
///   电影筛选（有筛选条件）→ `☰▸` / `▽ 筛选` / `⊞` / `∨`（4 个）
///
/// ⚠️ **原版没有「排序」按钮**。早期版本我们按截图目测把第 1 个图标认成了
/// `Icons.sort`，实际语义树的 `content-desc` 是 `合并播放列表（已关闭）`，
/// 图标模板匹配 `playlist_play_rounded` 0.8553、`sort` 仅 0.0191。
class _CategoryBar extends StatelessWidget {
  final List<VodClass> classes;
  final int index;
  final ValueChanged<int> onSelect;
  final ViewMode viewMode;
  final VoidCallback onToggleView;
  final VoidCallback? onFilterToggle;
  final bool filterOpen;
  final VoidCallback onAllClasses;

  /// 「合并播放列表」开关状态（原版 chips 行第 1 个 Button）。
  final bool mergePlaylist;
  final VoidCallback onToggleMerge;

  const _CategoryBar({
    required this.classes,
    required this.index,
    required this.onSelect,
    required this.viewMode,
    required this.onToggleView,
    required this.onFilterToggle,
    required this.filterOpen,
    required this.onAllClasses,
    required this.mergePlaylist,
    required this.onToggleMerge,
  });

  @override
  Widget build(BuildContext context) {
    final names = <String>['精选', ...classes.map((e) => e.typeName)];
    return SizedBox(
      // 原版实测：chips 药丸 y=152..214（高 63px = 36dp），中心 183px = 104.6dp。
      // 顶栏底 = 20(留白) + 64 = 84dp，所以药丸中心落在本条第 20.6dp 处；
      // 药丸高约 34dp，居中即上下各 4dp → 条高 42dp。
      height: 42,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // 原版实测：chips 首个药丸左边缘 161px = 内容区左边缘，
              // 即与海报墙、顶栏 logo 共用同一个 16dp 内容内边距。
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: names.length,
              // 原版实测：药丸左边缘 161 / 275 / 440 / 606 …，间距 14px = 8dp。
              // 曾写 23dp（=40px），于是整行比原版宽出约 20%，右侧图标被顶出去。
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final selected = i == index;
                return Center(
                  child: InkWell(
                    onTap: () => onSelect(i),
                    borderRadius: BorderRadius.circular(18),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      // 原版实测（逐像素，见 .peekpili-analysis/g8/cmp_pill1_orig.png）：
                      //   * **描边胶囊**：全圆角（半径 = 高/2 = 18dp）+ 1dp 描边，
                      //     不是我们原来的实心圆角矩形（radius 8）
                      //   * 选中态是**深蓝文字 (#00325B) 配浅蓝灰底 (#545E6B)** +
                      //     浅蓝描边 (#8DAED9) —— 我们原来写反了（浅字配深底）
                      //   * 高度 63px = 36dp 写死，避免依赖字体行高导致 ±2px 漂移
                      //     （文字靠 `alignment: center` 竖直居中）
                      //   * 横向内边距由「精选」100px / 「热门电影」152px 联立反推 12.5dp
                      height: PeekColors.chipHeight,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                          horizontal: PeekColors.chipPaddingH),
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
                          // 由「精选」100px 与「热门电影」152px 两个宽度联立：
                          // 每字步进 (152-100)/2 = 26px = 14.86dp。实测本工程字体
                          // 步进 ≈ 1.029em，故 fontSize = 14.86/1.029 ≈ 14.5dp。
                          // （写 15 时 4 字药丸会宽 3px）
                          fontSize: 14.5,
                          color: selected
                              ? PeekColors.chipSelectedText
                              : PeekColors.chipText,
                          fontWeight:
                              selected ? FontWeight.w500 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 原版第 1 个 Button：合并播放列表（`playlist_play_rounded`）。
          // 语义树：`Button [1724,149][1780,219] desc="合并播放列表（已关闭）"`
          // 原版字符串：`合并播放列表（已开启）` / `合并播放列表（已关闭）`。
          _barIcon(
            icon: Icons.playlist_play_rounded,
            tooltip: mergePlaylist ? '合并播放列表（已开启）' : '合并播放列表（已关闭）',
            active: mergePlaylist,
            onTap: onToggleMerge,
          ),
          // 原版第 2 个图标：筛选（▽）—— 仅当分类带筛选条件时出现
          if (onFilterToggle != null)
            _barIcon(
              icon: filterOpen ? Icons.filter_alt : Icons.filter_alt_outlined,
              tooltip: filterOpen ? '收起筛选条件' : '展开筛选条件',
              active: filterOpen,
              onTap: onFilterToggle!,
            ),
          // 原版第 2 个图标：视图模式（⊞ / ☰）—— 无筛选条件时的第 2 个
          _barIcon(
            icon: viewMode == ViewMode.grid
                ? Icons.grid_view
                : Icons.view_list,
            tooltip: viewMode == ViewMode.grid ? '切换到列表视图' : '切换到网格视图',
            onTap: onToggleView,
          ),
          // 原版第 3 个图标：全部分类（∨）—— 无筛选条件时的第 3 个（最右）
          _barIcon(
            icon: Icons.keyboard_arrow_down,
            tooltip: '全部分类',
            onTap: onAllClasses,
          ),
          // 原版实测：chips 行 3 个图标中心 x = 1750 / 1807 / 1863，间距 56px = 32dp，
          // 最后一个中心 1863px 反推右留白 16dp（= 内容内边距，与左端对称）。
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _barIcon({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      iconSize: 20,
      color: active ? PeekColors.primary : PeekColors.onSurfaceVariant,
      icon: Icon(icon),
      // 主题是 `VisualDensity.compact`（-8dp），但 `MaterialTapTargetSize.padded`
      // 会把布局盒撑到 48dp —— 于是 chips 行的图标间距变成 84px，而原版是 56px。
      // 显式 shrinkWrap + 32dp 宽盒后间距正好 56px = 32dp，命中原版。
      //
      // 高度原版是 **70px = 40dp**（`uiautomator dump`：`[1724,149][1780,219]`），
      // 即 48dp 默认盒在 `VisualDensity.compact` 下 -8dp 的结果；宽度则被收成
      // 32dp。所以是 **32dp × 40dp** 而不是正方形 —— 顶栏那 4 个才是 48×48
      // （原版 `[1570,49][1654,133]` = 84×84px）。两者别混。
      //
      // 注意：`tapTargetSize` **不是** IconButton 的直接参数（它在 ButtonStyle 里），
      // 只能通过 `style:` 传 —— 直接写 `tapTargetSize:` 会报
      // `The named parameter 'tapTargetSize' isn't defined`。
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 40),
        maximumSize: const Size(32, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// 「全部分类」弹层（原版 chips 行最右 ∨）。
/// 2 列网格列出所有分类，右上角关闭按钮；返回选中的下标。
class _ClassSheet extends StatelessWidget {
  final List<String> names;
  final int index;
  const _ClassSheet({required this.names, required this.index});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('全部分类',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: PeekColors.onSurface)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  iconSize: 20,
                  color: PeekColors.onSurfaceVariant,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                          label: names[i],
                          selected: i == index,
                          onTap: () => Navigator.of(context).pop(i),
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
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
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

/// 内联筛选条件面板（原版：分类 chips 下方直接铺开多行条件，不是弹窗）。
///
/// 每组条件一行横向滚动；「全部」为清空该组。
class _InlineFilterPanel extends StatelessWidget {
  final VodClass cls;
  final Map<String, String> selected;
  final void Function(String key, String value) onChanged;

  const _InlineFilterPanel({
    required this.cls,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final g in cls.filters) _row(g),
        ],
      ),
    );
  }

  Widget _row(FilterGroup g) {
    // 源返回的第一项本身就是「全部类型 / 全部地区 / 全部年代」，
    // 原版直接铺开这组值、不再额外补一个「全部」（实测原版筛选行逐字如此）。
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: g.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final v = g.values[i];
          final cur = selected[g.key] ?? '';
          final isSel = cur == v.v;
          return Center(
            child: InkWell(
              onTap: () => onChanged(g.key, v.v),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: isSel
                      ? PeekColors.primaryContainer
                      : PeekColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  v.n.isEmpty ? '全部' : v.n,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isSel
                        ? PeekColors.onPrimaryContainer
                        : PeekColors.onSurfaceVariant,
                    fontWeight: isSel ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
