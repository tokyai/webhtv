import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../tvbox/models.dart';
import '../../widgets/common.dart';
import '../../widgets/poster_card.dart';
import '../detail/detail_page.dart';

/// 多元搜索页 —— 对齐原版 `T4SearchPage`。
///
/// 两种进入方式（由 [autoChange] 区分，对应原版 `t4AutoChangeSource`
/// 与 `_isAutoChangeSourceMode`）：
///
///   * **普通搜索**：从搜索入口进入，纯浏览。
///   * **换源模式**（`autoChange = true`）：从详情页/播放页点「换源」进入。
///     左上角显示当前片名，点任意结果会**替换当前播放源**继续播，
///     而不是单纯打开详情页。
///
/// 布局：左侧固定站源栏（`t4_landscape_side_by_side` 对应横屏并排），
/// 右侧按站源**分组**依次排列各源的搜索结果，每张卡片带源名角标。
class MultiSearchPage extends StatefulWidget {
  /// 初始关键词（换源模式下就是片名）
  final String keyword;

  /// 换源模式
  final bool autoChange;

  /// 换源模式下：当前所在的片（用于提示与回退）
  final String? originName;
  final String? originSite;

  const MultiSearchPage({
    super.key,
    required this.keyword,
    this.autoChange = false,
    this.originName,
    this.originSite,
  });

  @override
  State<MultiSearchPage> createState() => _MultiSearchPageState();
}

class _MultiSearchPageState extends State<MultiSearchPage> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _searching = false;
  bool _searched = false;
  int _done = 0;
  int _total = 0;

  /// 按源分组的结果：key = site.key（原版侧边栏顺序）
  final List<Site> _order = <Site>[];
  final Map<String, List<Vod>> _bySource = <String, List<Vod>>{};

  /// 侧边栏选中项；null = 全部源
  String? _focus;

  int _totalHits = 0;

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.keyword;
    if (widget.keyword.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _doSearch(widget.keyword));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _doSearch(String kw) async {
    final keyword = kw.trim();
    if (keyword.isEmpty) return;
    if (_searching) return;
    _ctrl.text = keyword;
    FocusScope.of(context).unfocus();
    if (!widget.autoChange) await Store.addSearchHistory(keyword);
    if (!mounted) return;
    setState(() {
      _searching = true;
      _searched = true;
      _done = 0;
      _total = 0;
      _totalHits = 0;
      _order.clear();
      _bySource.clear();
      _focus = null;
    });
    final app = context.read<AppState>();
    await app.searchBySource(
      keyword,
      onlyDefault: app.searchOnlyDefaultSource,
      onResult: (site, items, done, total) {
        if (!mounted) return;
        setState(() {
          if (items.isNotEmpty) {
            _order.add(site);
            _bySource[site.key] = items;
            _totalHits += items.length;
          } else {
            // 空结果的源也记进侧边栏，显示为「无结果」（原版行为）
            if (!_order.any((s) => s.key == site.key)) _order.add(site);
            _bySource[site.key] = const <Vod>[];
          }
          _done = done;
          _total = total;
        });
      },
    );
    if (mounted) setState(() => _searching = false);
  }

  /// 打开某个结果。
  ///
  /// 换源模式：直接把结果作为新的播放源回传给上游（pop 出结果），
  /// 普通模式：进入详情页。
  void _open(Site site, Vod vod) {
    if (widget.autoChange) {
      Navigator.of(context).pop<AutoChangePick>(AutoChangePick(site, vod));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(site: site, vodId: vod.id, preview: vod),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Row(
          children: [
            // 左侧站源栏 —— 原版侧边显示分源结果
            _SourceRail(
              width: wide ? 188 : 132,
              order: _order,
              bySource: _bySource,
              focus: _focus,
              searching: _searching,
              done: _done,
              total: _total,
              onPick: (k) => setState(() => _focus = k),
            ),
            Expanded(
              child: Column(
                children: [
                  _header(),
                  Expanded(child: _body()),
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
          if (widget.autoChange) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: PeekColors.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('换源',
                  style: TextStyle(fontSize: 11.5, color: PeekColors.onPrimaryContainer)),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.search,
              onSubmitted: _doSearch,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: widget.autoChange ? '搜索要换到的片名…' : '搜索影片、剧集、综艺…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                suffixIcon: _ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _ctrl.clear()),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _searching ? null : () => _doSearch(_ctrl.text),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('搜索', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 10),
          _menu(),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  Widget _menu() {
    final app = context.watch<AppState>();
    return PopupMenuButton<String>(
      tooltip: '搜索设置',
      icon: const Icon(Icons.more_vert, size: 20),
      color: PeekColors.surfaceContainerHigh,
      onSelected: (v) {
        if (v == 'onlyDefault') {
          app.setSearchOnlyDefaultSource(!app.searchOnlyDefaultSource);
        } else if (v == 'blocked') {
          _showBlockSheet(app);
        } else if (v == 'auto') {
          _showAutoSheet();
        }
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: 'onlyDefault',
          checked: app.searchOnlyDefaultSource,
          height: 40,
          child: Text('只搜首页选择的源', style: TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          value: 'auto',
          height: 40,
          child: Row(
            children: [
              Expanded(
                  child: Text('自动换源配置',
                      style: TextStyle(
                          fontSize: 13,
                          color: AutoChangeSourceConfig.load().enabled
                              ? PeekColors.primary
                              : PeekColors.onSurface))),
              if (AutoChangeSourceConfig.load().enabled)
                Icon(Icons.check, size: 15, color: PeekColors.primary),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'blocked',
          height: 40,
          child: Text('参与搜索的源', style: TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ 弹层

  /// 逐源勾选是否参与搜索（原版 `t4_blocked_search_sources`）
  Future<void> _showBlockSheet(AppState app) async {
    final all = app.quickSearchSites;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PeekColors.surfaceContainer,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 8, 6),
                child: Row(
                  children: [
                    Text('参与搜索的源',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: PeekColors.onSurface)),
                    const SizedBox(width: 10),
                    Text('共 ${all.length} 个',
                        style: TextStyle(
                            fontSize: 12, color: PeekColors.hint)),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await BlockedSearchSources.setAll(
                            all.map((s) => s.key).toList(),
                            blocked: false);
                        setSheet(() {});
                      },
                      child: const Text('全部启用', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () async {
                        await BlockedSearchSources.setAll(
                            all.map((s) => s.key).toList(),
                            blocked: true);
                        setSheet(() {});
                      },
                      child: const Text('全部禁用', style: TextStyle(fontSize: 12)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: all.length,
                  itemBuilder: (_, i) {
                    final s = all[i];
                    final blocked = BlockedSearchSources.isBlocked(s.key);
                    return ListTile(
                      dense: true,
                      title: Text(s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              color: blocked
                                  ? PeekColors.hint
                                  : PeekColors.onSurface)),
                      trailing: Switch(
                        value: !blocked,
                        onChanged: (v) async {
                          await BlockedSearchSources.setBlocked(s.key, !v);
                          setSheet(() {});
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 自动换源配置（原版 `t4_auto_change_source_config`）
  Future<void> _showAutoSheet() async {
    var c = AutoChangeSourceConfig.load();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PeekColors.surfaceContainer,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 8, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('自动换源',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: PeekColors.onSurface)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                dense: true,
                value: c.enabled,
                onChanged: (v) async {
                  c = c.copyWith(enabled: v);
                  await AutoChangeSourceConfig.save(c);
                  setSheet(() {});
                },
                title: const Text('播放失败时自动换源',
                    style: TextStyle(fontSize: 13.5)),
                subtitle: Text('播放器报错后用片名搜索其他源并跳转继续播放',
                    style: TextStyle(fontSize: 11.5, color: PeekColors.hint)),
              ),
              SwitchListTile(
                dense: true,
                value: c.quickOnly,
                onChanged: c.enabled
                    ? (v) async {
                        c = c.copyWith(quickOnly: v);
                        await AutoChangeSourceConfig.save(c);
                        setSheet(() {});
                      }
                    : null,
                title: const Text('仅使用快搜源', style: TextStyle(fontSize: 13.5)),
                subtitle: Text('只从标记了快搜的源里找，速度更快',
                    style: TextStyle(fontSize: 11.5, color: PeekColors.hint)),
              ),
              ListTile(
                dense: true,
                title: const Text('最多换源次数', style: TextStyle(fontSize: 13.5)),
                subtitle: Text('当前 ${c.maxAttempts} 次',
                    style: TextStyle(
                        fontSize: 11.5, color: PeekColors.hint)),
                trailing: SizedBox(
                  width: 160,
                  child: Slider(
                    value: c.maxAttempts.toDouble(),
                    min: 1,
                    max: 8,
                    divisions: 7,
                    label: '${c.maxAttempts}',
                    onChanged: c.enabled
                        ? (v) async {
                            c = c.copyWith(maxAttempts: v.round());
                            await AutoChangeSourceConfig.save(c);
                            setSheet(() {});
                          }
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ 内容区

  Widget _body() {
    if (_searching && _totalHits == 0) {
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
            Text('正在聚合搜索 $_done/$_total 个站源…',
                style: TextStyle(fontSize: 13, color: PeekColors.hint)),
          ],
        ),
      );
    }
    if (!_searched) {
      return PeekEmpty(
        icon: Icons.travel_explore_outlined,
        text: widget.autoChange
            ? '输入片名后搜索，点结果即可换到该源播放'
            : '输入关键词开始多元搜索',
      );
    }
    if (_totalHits == 0 && !_searching) {
      return PeekEmpty(
        icon: Icons.search_off_outlined,
        text: '没有搜索到「${_ctrl.text}」相关内容\n已搜索 ${_order.length} 个站源',
      );
    }
    return _groupedList();
  }

  /// 按源分组渲染（原版核心观感：分源显示搜索结果）
  Widget _groupedList() {
    final keys = _focus != null
        ? <Site>[_order.firstWhere((s) => s.key == _focus)]
        : _order;
    final app = context.watch<AppState>();

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
          PeekColors.contentPadding, 6, PeekColors.contentPadding, 28),
      itemCount: keys.length + (_searching ? 1 : 0),
      itemBuilder: (_, gi) {
        if (gi == keys.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('正在搜索剩余站源 $_done/$_total…',
                    style: TextStyle(fontSize: 12, color: PeekColors.hint)),
              ],
            ),
          );
        }
        final site = keys[gi];
        final items = _bySource[site.key] ?? const <Vod>[];
        return _group(site, items, app);
      },
    );
  }

  Widget _group(Site site, List<Vod> items, AppState app) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: PeekColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  site.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: PeekColors.onSurface),
                ),
              ),
              SizedBox(width: 8),
              Text('${items.length} 个结果',
                  style: TextStyle(fontSize: 11.5, color: PeekColors.hint)),
              const Spacer(),
              if (site.key == app.currentSite?.key)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: PeekColors.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('当前源',
                      style:
                          TextStyle(fontSize: 10.5, color: PeekColors.hint)),
                ),
            ],
          ),
        ),
        if (items.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(2, 2, 2, 10),
            child: Text('该源没有匹配结果',
                style: TextStyle(fontSize: 12, color: PeekColors.hint)),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth - PeekColors.contentPadding;
              const gap = PeekColors.gridGap;
              final cols = ((w + gap) / (181 + gap)).round().clamp(2, 8);
              final itemW = (w - gap * (cols - 1)) / cols;
              final ratio = itemW / (itemW / PeekColors.posterAspect + 41);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: gap,
                  childAspectRatio: ratio,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) => PosterCard(
                  vod: items[i],
                  showTitle: app.showPosterTitle,
                  compact: app.compactTitle,
                  onTap: () => _open(site, items[i]),
                ),
              );
            },
          ),
        SizedBox(height: 4),
        Divider(height: 1, color: PeekColors.railDivider),
      ],
    );
  }
}

/// 换源模式下选择的结果
class AutoChangePick {
  final Site site;
  final Vod vod;
  AutoChangePick(this.site, this.vod);
}

/// 左侧站源栏：列出各源及命中数，点击只看该源
class _SourceRail extends StatelessWidget {
  final double width;
  final List<Site> order;
  final Map<String, List<Vod>> bySource;
  final String? focus;
  final bool searching;
  final int done;
  final int total;
  final ValueChanged<String?> onPick;

  const _SourceRail({
    required this.width,
    required this.order,
    required this.bySource,
    required this.focus,
    required this.searching,
    required this.done,
    required this.total,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    var hits = 0;
    for (final l in bySource.values) {
      hits += l.length;
    }
    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: PeekColors.railDivider, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('搜索源',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: PeekColors.primary)),
                SizedBox(height: 4),
                Text(
                  searching ? '$done/$total' : '${order.length} 源 · $hits 结果',
                  style:
                      TextStyle(fontSize: 11, color: PeekColors.hint),
                ),
                if (searching) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              children: [
                _item(null, '全部源', hits),
                for (final s in order)
                  _item(s.key, s.name, (bySource[s.key] ?? const []).length),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(String? key, String label, int count) {
    final sel = focus == key;
    final empty = count == 0;
    return InkWell(
      onTap: () => onPick(key),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? PeekColors.surfaceContainerHigh : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                  color: sel
                      ? PeekColors.primary
                      : empty
                          ? PeekColors.railIdle
                          : PeekColors.onSurfaceVariant,
                ),
              ),
            ),
            if (count > 0)
              Text('$count',
                  style: TextStyle(
                      fontSize: 11,
                      color: sel ? PeekColors.primary : PeekColors.hint)),
          ],
        ),
      ),
    );
  }
}
