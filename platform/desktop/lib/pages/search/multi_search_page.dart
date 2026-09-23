import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/debug_log.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../tvbox/models.dart';
import '../../widgets/poster_card.dart';
import '../detail/detail_page.dart';
import '../setting/auto_change_source_page.dart';

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

  /// 搜索历史（新→旧）。进入页面时从本地读，搜索成功后刷新。
  ///
  /// ⚠️ 历史以前**只写不读** —— `Store.addSearchHistory` 一直在正常落盘
  /// （Hive `historyword.hive` 里能查到用户搜过的词），但没有任何 UI 组件
  /// 读取 `Store.searchHistory`，所以用户进搜索页永远看不到历史记录。
  List<String> _history = const [];

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.keyword;
    // 输入框内容变化要触发重建，否则清空按钮（suffixIcon）不会出现/消失。
    _ctrl.addListener(_onCtrlChanged);
    _loadHistory();
    if (widget.keyword.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _doSearch(widget.keyword));
    }
  }

  void _onCtrlChanged() {
    if (mounted) setState(() {});
  }

  void _loadHistory() {
    final h = Store.searchHistory;
    if (!mounted) return;
    setState(() => _history = h);
  }

  /// 等源服务把站点清单拉回来。返回 true = 可用了。
  ///
  /// 为什么要等：见 [_doSearch] 里对「开 App 后立刻搜索」窗口期的说明。
  /// 源服务是独立 node 进程，冷启动 + 拉 94 个站点清单通常 10~30 秒。
  /// 这里最多等 45 秒，并且**在等待期间持续上报进度**，让用户看到界面在动，
  /// 而不是停在一个看起来已经失败的「没有搜索到相关内容」上。
  Future<bool> _waitForSources(AppState app) async {
    const maxWait = Duration(seconds: 45);
    const step = Duration(milliseconds: 400);
    var waited = Duration.zero;
    while (waited < maxWait) {
      if (!mounted) return false;
      if (app.searchSources(onlyDefault: app.searchOnlyDefaultSource).isNotEmpty) {
        return true;
      }
      // 明确失败（拿到了错误）就别再等了。
      if (!app.loadingConfig && !app.serviceReady && app.configError != null) {
        DebugLog.add('SEARCH', '源服务启动失败：${app.configError}');
        return false;
      }
      setState(() => _total = -1); // -1 表示「正在等待源服务」
      await Future<void>.delayed(step);
      waited += step;
    }
    DebugLog.add('SEARCH', '等待源服务超时（${maxWait.inSeconds}s）');
    return false;
  }

  Future<void> _clearHistory() async {
    await Store.clearSearchHistory();
    if (!mounted) return;
    setState(() => _history = const []);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrlChanged);
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _doSearch(String kw) async {
    final keyword = kw.trim();
    // 空关键词：以前是静默 return，用户点了「搜索」却什么都没发生，
    // 很容易被当成「点击无效 / 搜不到」。现在给一句明确提示。
    if (keyword.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请输入关键词'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    // 搜索进行中重复点击：以前也是静默 return。改成提示，否则用户会以为
    // 按钮坏了（93 源并发 + 慢源，一轮最长要 20 秒）。
    if (_searching) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('正在搜索中 $_done/$_total，请稍候…'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _ctrl.text = keyword;
    FocusScope.of(context).unfocus();
    DebugLog.add('SEARCH', '--- 开始搜索「$keyword」---');
    if (!widget.autoChange) {
      await Store.addSearchHistory(keyword);
      _loadHistory();
    }
    if (!mounted) return;

    final app = context.read<AppState>();

    // ⚠️⚠️ 真因修复：等待源服务就绪。
    //
    // `AppState.init()` 里是 `unawaited(_startActive(silent: true))` —— 源服务
    // （独立 node 子进程 + 拉 94 个站点清单）**不阻塞启动**，要跑十几到几十秒。
    // 在这个窗口期内 `_svc.sites` 还是空数组，于是：
    //     searchSources() → 空列表
    //     → searchBySource 一个源都没发
    //     → _totalHits 恒为 0
    //     → 界面显示「没有搜索到相关内容」
    // 这正是用户反馈的「搜不到东西，如凡人修仙传」：**开 App 后马上搜索**
    // 就会命中这个窗口，而数据层其实一切正常（实测同关键词 47 源 887 条）。
    //
    // 处理：若此刻没有可用源而源仍在加载，先等它；等待期间给出进度提示。
    if (app.searchSources(onlyDefault: app.searchOnlyDefaultSource).isEmpty &&
        !app.serviceReady) {
      DebugLog.add('SEARCH', '源服务尚未就绪，等待中…');
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
      final ok = await _waitForSources(app);
      if (!mounted) return;
      if (!ok) {
        setState(() => _searching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('源服务启动失败或超时，请到「设置 → 运行状态」查看'),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }
      DebugLog.add('SEARCH', '源服务已就绪，开始搜索');
    }

    // 站点原序：并发回调的到达顺序是「谁先返回谁先到」，直接 `_order.add`
    // 会让侧栏顺序每次搜索都不一样（实测完成时间从 0.6s 到 20s 跨度极大）。
    // 这里先取一份权威顺序，回调里只写 `_bySource`，结束后按原序重建 `_order`。
    final ordered = app.searchSources(onlyDefault: app.searchOnlyDefaultSource);
    DebugLog.add('SEARCH', '参与搜索的源 ${ordered.length} 个');
    if (ordered.isEmpty) {
      // 源清单为空（源服务未就绪 / 全被屏蔽）—— 直接给出可执行的原因，
      // 而不是让界面停在「没有搜索到相关内容」上误导用户。
      setState(() {
        _searching = false;
        _searched = true;
        _done = 0;
        _total = 0;
        _totalHits = 0;
        _order.clear();
        _bySource.clear();
        _focus = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('没有可用的搜索源，请检查源是否已加载'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    final pending = <String, Site>{for (final s in ordered) s.key: s};

    setState(() {
      _searching = true;
      _searched = true;
      _done = 0;
      // 一开始就把 total 设为真实源数，避免界面显示「正在聚合搜索 0/0」
      // 被误读为「没有任何源 / 卡住了」。
      _total = ordered.length;
      _totalHits = 0;
      _order.clear();
      _bySource.clear();
      _focus = null;
    });

    try {
      await app.searchBySource(
        keyword,
        onlyDefault: app.searchOnlyDefaultSource,
        onResult: (site, items, done, total) {
          if (!mounted) return;
          DebugLog.add('SEARCH', '${site.name} -> ${items.length} 条 ($done/$total)');
          setState(() {
            // 搜索过程中：有结果的源**实时上屏**，让用户尽快看到东西。
            _bySource[site.key] = items;
            if (items.isNotEmpty) {
              if (!_order.any((s) => s.key == site.key)) _order.add(site);
              _totalHits += items.length;
            }
            _done = done;
            _total = total;
          });
        },
      );
    } catch (e, st) {
      // 以前这里没有 try/catch：一旦抛出，`_searching` 永远停在 true，
      // 界面就永久卡在「正在聚合搜索…」，用户看到的就是「搜不到东西」。
      DebugLog.add('SEARCH', '搜索整体失败：$e');
      debugPrint('searchBySource failed: $e\n$st');
    }
    if (!mounted) return;
    setState(() {
      _searching = false;
      // 搜索结束：按**站点原序**重建，且**只保留有结果的源**。
      //
      // 用户要求「把没有结果的站点从两侧分栏中剔除，只保留有条数结果的标签
      // 和结果列表」。搜索过程中不剔除（否则侧栏会不断跳动、也看不出进度），
      // 结束后一次性收拢。这样侧栏的条目数 = 真正能用的源数，不再被
      // 「站名 0」刷屏。
      _order
        ..clear()
        ..addAll([
          for (final s in ordered)
            if ((_bySource[s.key] ?? const <Vod>[]).isNotEmpty) s,
        ]);
      // `_focus` 指向的源可能已被剔除。
      if (_focus != null && !_order.any((s) => s.key == _focus)) {
        _focus = null;
      }
      // 清理没有结果的源，避免 `_bySource` 里留一堆空列表。
      _bySource.removeWhere((k, v) => v.isEmpty);
      // pending 仅为可读性保留（原序已在 `ordered` 中体现）。
      pending.clear();
    });
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
    // 统一为**左侧站源栏 + 右侧结果区**，不再区分「上下布局 / 网格视图」。
    //
    // ⚠️ 历史包袱：这里曾有两套并行 UI —— `multiSearchStacked=false` 走左侧
    // `_SourceRail`，`true` 走顶部 `_chipBar`。默认值是 `true`，于是**绝大多数
    // 用户看到的都是顶部 chips 条，左侧站源栏根本不渲染**。用户反馈「点击搜索
    // 图标进行搜索，结果怎么没有左侧站点的导航标签」，根因就在这里。
    //
    // 而且 44 个空结果源会全被塞进 chips 条，稠密的「站名 0」让用户误以为
    // 「没搜到结果」。现统一成单一实现：任何尺寸都用左侧栏，窄屏自动收窄。
    final w = MediaQuery.of(context).size.width;
    // 三档宽度：宽屏 188 / 中屏 152 / 窄屏 118（竖屏手机）。
    final railW = w >= 900 ? 188.0 : (w >= 600 ? 152.0 : 118.0);
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Row(
          children: [
            _SourceRail(
              width: railW,
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
          // 布局切换按钮已移除 —— 现在统一使用左侧站源栏，
          // 不再有「上下布局 / 网格视图」两套 UI（见 build 里的说明）。
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
        } else if (v == 'timeout') {
          _showTimeoutSheet(app);
        } else if (v == 'auto') {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AutoChangeSourcePage(),
            ),
          );
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
        ),        const PopupMenuItem(
          value: 'blocked',
          height: 40,
          child: Text('参与搜索的源', style: TextStyle(fontSize: 13)),
        ),
        PopupMenuItem(
          value: 'timeout',
          height: 40,
          child: Row(
            children: [
              const Expanded(
                  child: Text('单源搜索超时', style: TextStyle(fontSize: 13))),
              Text('${app.searchTimeoutSeconds}s',
                  style: TextStyle(fontSize: 12, color: PeekColors.primary)),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ 弹层

  /// 调节单源搜索超时。
  ///
  /// 为什么要给用户这个开关：93 个站源并发时，慢源可能在默认超时之后才
  /// 返回。调大能捞回这些结果，代价是「搜索中」更久；调小则更快出结果。
  Future<void> _showTimeoutSheet(AppState app) async {
    int cur = app.searchTimeoutSeconds;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PeekColors.surfaceContainer,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('单源搜索超时',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: PeekColors.onSurface)),
                  const Spacer(),
                  Text('$cur 秒',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: PeekColors.primary)),
                ],
              ),
              const SizedBox(height: 4),
              Text('超时更短出结果更快，更长能捞回慢源',
                  style: TextStyle(fontSize: 12, color: PeekColors.hint)),
              Slider(
                value: cur.toDouble(),
                min: 5,
                max: 60,
                divisions: 11,
                label: '$cur 秒',
                onChanged: (v) {
                  setSheet(() => cur = v.round());
                },
                onChangeEnd: (v) async {
                  await app.setSearchTimeoutSeconds(v.round());
                },
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('5 秒（最快）',
                      style: TextStyle(fontSize: 11, color: PeekColors.hint)),
                  Text('60 秒（最全）',
                      style: TextStyle(fontSize: 11, color: PeekColors.hint)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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


  // ------------------------------------------------------------ 内容区

  Widget _body() {
    if (_searching && _totalHits == 0) {
      final waiting = _total < 0;
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
              // `_total == -1`：源服务还在冷启动，一个源都还没有。
              // 这时如果仍显示「0/0 个站源」，用户会以为搜索坏了。
              waiting
                  ? '正在启动源服务…'
                  : (_total > 0
                      ? '正在聚合搜索 $_done/$_total 个站源…'
                      : '正在准备搜索…'),
              style: TextStyle(fontSize: 13, color: PeekColors.hint),
            ),
            if (waiting) ...[
              const SizedBox(height: 8),
              Text('首次启动需要加载站源清单，请稍候',
                  style: TextStyle(fontSize: 11.5, color: PeekColors.railIdle)),
            ],
          ],
        ),
      );
    }
    if (!_searched) {
      // 首次进入（未搜索过）：展示**搜索历史**。
      //
      // 用户报告「搜索栏进去没有搜索历史」——根因是 `Store.searchHistory`
      // 只被写、从来没被读过。历史数据其实一直在 `historyword.hive` 里。
      return _historyPanel();
    }
    if (_totalHits == 0 && !_searching) {
      // ⚠️ 这里以前用 `_order.length` 报「已搜索 N 个站源」。现在 `_order`
      // 在搜索结束后只保留**有结果**的源（空结果源已被剔除），那样会报
      // 「已搜索 0 个站源」，与实际搜了几十个源完全不符。改用 `_total`
      // （本轮参与搜索的源总数），才是用户想知道的数字。
      final scanned = _total > 0 ? _total : _order.length;
      return _noResultPanel(scanned);
    }
    return _groupedList();
  }

  /// 无结果面板：给出「已搜索 N 个源」的明确数字，并**回退到搜索历史**，
  /// 让用户能一键换个词重试（而不是面对一个死胡同）。
  Widget _noResultPanel(int scanned) {
    final kw = _ctrl.text.trim();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          PeekColors.contentPadding, 40, PeekColors.contentPadding, 24),
      children: [
        Icon(Icons.search_off_outlined, size: 46, color: PeekColors.hint),
        const SizedBox(height: 14),
        Text(
          '没有搜索到「$kw」相关内容',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: PeekColors.onSurface),
        ),
        const SizedBox(height: 6),
        Text(
          '已搜索 $scanned 个站源，均未返回结果\n可换个关键词，或调大「单源搜索超时」再试',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: PeekColors.hint, height: 1.6),
        ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 28),
          _historyHeader(),
          const SizedBox(height: 10),
          _historyChips(),
        ],
      ],
    );
  }

  /// 搜索历史面板（首次进入搜索页 / 换源模式初筛时展示）。
  Widget _historyPanel() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          PeekColors.contentPadding, 28, PeekColors.contentPadding, 24),
      children: [
        Row(
          children: [
            Icon(Icons.travel_explore_outlined,
                size: 20, color: PeekColors.primary),
            const SizedBox(width: 8),
            Text(
              widget.autoChange ? '换源搜索' : '多元搜索',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: PeekColors.onSurface),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          widget.autoChange
              ? '输入片名后搜索，点结果即可换到该源播放'
              : '一次搜索全部站源，按源分组展示结果',
          style: TextStyle(fontSize: 12.5, color: PeekColors.hint),
        ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 26),
          _historyHeader(),
          const SizedBox(height: 12),
          _historyChips(),
        ] else ...[
          const SizedBox(height: 40),
          Center(
            child: Text('还没有搜索记录',
                style: TextStyle(fontSize: 12.5, color: PeekColors.railIdle)),
          ),
        ],
      ],
    );
  }

  Widget _historyHeader() {
    return Row(
      children: [
        Icon(Icons.history, size: 16, color: PeekColors.onSurfaceVariant),
        const SizedBox(width: 6),
        Text('搜索历史',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: PeekColors.onSurfaceVariant)),
        const Spacer(),
        InkWell(
          onTap: _clearHistory,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 14, color: PeekColors.hint),
                const SizedBox(width: 3),
                Text('清空',
                    style: TextStyle(fontSize: 12, color: PeekColors.hint)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _historyChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final kw in _history)
          InkWell(
            onTap: () => _doSearch(kw),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: PeekColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                kw,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: PeekColors.onSurface),
              ),
            ),
          ),
      ],
    );
  }

  /// 按源分组渲染（原版核心观感：分源显示搜索结果）
  Widget _groupedList() {
    // ⚠️ `_focus` 可能指向一个**本轮已不在 `_order` 里**的站点（例如上一轮选中的
    // 源这一轮超时、被屏蔽，或用户在搜索中途切了源）。原先这里直接
    // `_order.firstWhere(...)` 且**没有 `orElse`** —— 找不到就抛 `StateError`，
    // 整个结果区变成红色报错页。现在退回「全部」，语义上也更合理。
    Site? focused;
    if (_focus != null) {
      for (final s in _order) {
        if (s.key == _focus) {
          focused = s;
          break;
        }
      }
    }
    final keys = focused != null ? <Site>[focused] : _order;
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
              // 竖屏窄屏：原版用「海报 + 标题 + 源角标 + 题材标签」的横排列表卡
              if (c.maxWidth < 620) {
                return Column(
                  children: [
                    for (final v in items)
                      _resultRow(site, v, app),
                  ],
                );
              }
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

  /// 竖屏横排结果卡（原版竖屏列表观感）：
  /// 左海报 + 右标题 / 源角标 / 题材标签。
  Widget _resultRow(Site site, Vod vod, AppState app) {
    final tags = <String>[
      if (vod.typeName.isNotEmpty) vod.typeName,
      if (vod.year.isNotEmpty) vod.year,
      if (vod.area.isNotEmpty) vod.area,
      if (vod.remarks.isNotEmpty) vod.remarks,
    ];
    return InkWell(
      onTap: () => _open(site, vod),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 74,
                height: 100,
                child: vod.pic.isEmpty
                    ? Container(color: PeekColors.surfaceContainerHigh)
                    : CachedNetworkImage(
                        imageUrl: vod.pic,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                            color: PeekColors.surfaceContainerHigh),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vod.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: PeekColors.onSurface),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Icon(Icons.folder_outlined,
                          size: 13, color: PeekColors.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          site.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: PeekColors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  if (tags.isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        for (final t in tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: PeekColors.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(t,
                                style: TextStyle(
                                    fontSize: 11, color: PeekColors.hint)),
                          ),
                      ],
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
                  // 搜索中：显示进度（已回/总数），此时侧栏在**实时增长**
                  // （有结果的源随到随上屏）；结束后：显示最终统计。
                  searching
                      ? '$done/$total'
                      : '${order.length} 源 · $hits 结果',
                  style:
                      TextStyle(fontSize: 11, color: PeekColors.hint),
                ),
                if (searching) ...[
                  const SizedBox(height: 8),
                  const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 6),
                  // 空结果源在搜索结束后才被剔除，这里提示一下，避免用户
                  // 以为「侧栏只有这几个源」。
                  Text('搜索中，空结果的源稍后自动隐藏',
                      style: TextStyle(fontSize: 10.5, color: PeekColors.railIdle)),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              children: [
                if (width < 150)
                  _RailItemNarrow(
                    label: '全部',
                    count: hits,
                    selected: focus == null,
                    empty: hits == 0,
                    onTap: () => onPick(null),
                  )
                else
                  _item(null, '全部源', hits),
                for (final s in order)
                  if (width < 150)
                    _RailItemNarrow(
                      label: s.name,
                      count: (bySource[s.key] ?? const []).length,
                      selected: focus == s.key,
                      empty: (bySource[s.key] ?? const []).isEmpty,
                      onTap: () => onPick(s.key),
                    )
                  else
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

/// 竖屏窄栏下的站源项：三行布局，对齐原版竖屏观感
/// (`站名` / 源等级 `4K` / `N 个结果`)。
class _RailItemNarrow extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final bool empty;
  final VoidCallback onTap;

  const _RailItemNarrow({
    required this.label,
    required this.count,
    required this.selected,
    required this.empty,
    required this.onTap,
  });

  /// 从站名里抽源等级标签（原版站名常形如 `💗花卷┃4K💗`）。
  String get _tier {
    for (final t in const ['4K', '秒播', 'T3', 'T4']) {
      if (label.contains(t)) return t;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final tier = _tier;
    final name = label
        .replaceAll('┃4K', '')
        .replaceAll('|4K', '')
        .replaceAll('┃秒播', '')
        .replaceAll('|秒播', '');
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? PeekColors.surfaceContainerHigh : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected
                    ? PeekColors.primary
                    : empty
                        ? PeekColors.railIdle
                        : PeekColors.onSurfaceVariant,
              ),
            ),
            if (tier.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(tier,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: selected ? PeekColors.primary : PeekColors.hint)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('$count 个结果',
                  style:
                      TextStyle(fontSize: 10.5, color: PeekColors.hint)),
            ),
          ],
        ),
      ),
    );
  }
}
