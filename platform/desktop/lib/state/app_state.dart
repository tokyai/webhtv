import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../backend/source_config.dart';
import '../core/http.dart';
import '../core/storage.dart';
import '../core/utils.dart';
import '../tvbox/backend_bridge.dart';
import '../tvbox/models.dart';
import '../tvbox/spider.dart';

/// 结果视图模式（原版搜索页「视图模式」两选项）。
enum ViewMode { grid, list }

/// 主题模式（原版「设置 → 外观与语言 → 主题模式」，3 个单选项）。
enum PeekThemeMode { light, dark, system }

/// 全局状态。
///
/// ## 这一层为什么是「重写」而不是「移植」
///
/// 界面层（`pages/**`、`widgets/**`）从 PeekPili **整建制移植**，它只依赖
/// 本类的这些成员：`config` / `currentSite` / `sites` / `home` / `category` /
/// `search` / `detail` / `player` / `toggleFavorite` / `viewMode` / 各类 setter。
///
/// 但 PeekPili 的实现是把 `TvBoxConfig` 与 spider 都放在**本进程内**，
/// 而本工程的后端是**独立 Node 子进程 + HTTP**（见 `tvbox/backend_bridge.dart`）。
/// 所以这里保留 **完全一致的对外形状**，把内部实现换成后端桥接 ——
/// 页面代码因此一行都不用改。
///
/// ## 与 PeekPili 的差异（诚实记录）
///
/// * **接口配置**：PeekPili 是「一个 config 装所有站点」；本工程是
///   「源列表 + 一个激活源」。所以 [config] 只反映**当前激活源**，
///   多源管理在「接口配置」页里另行呈现。
/// * **`sites`**：来源是 Node 服务的 `GET /config`，全部是 `nodejs_*`。
///   没有 DEX / T4 / JS 源（桌面端跑不了）。
/// * **[parseInterfaces]**：源不提供 `parses`，恒为空。
/// * **默认接口**：**不内置任何源**（这是既定约束），首次启动为空态。
class AppState extends ChangeNotifier {
  /// 全局单例（与 PeekPili 同名同形）。私有构造见文件末尾。
  static final AppState I = AppState._();

  AppState._();

  // ---------------------------------------------------------------------------
  // 持久化键
  // ---------------------------------------------------------------------------
  static const _kSources = 'sources_v1';
  static const _kActiveId = 'active_source_v1';
  static const _kThemeMode = 'peekThemeMode';

  final SourceService _svc = SourceService();

  List<SourceConfig> _sources = const [];
  String? _activeId;

  // ---------------- 接口配置（当前激活源） ----------------
  TvBoxConfig? config;
  bool loadingConfig = false;
  String? configError;
  String? activeConfigUrl;

  /// 源服务启动失败原因，供「接口配置」页提示。
  String? nodeSourceError;

  // ---------------- 站源 ----------------
  String? _siteKey;

  // ---------------- 视图 ----------------
  ViewMode viewMode = ViewMode.grid;
  bool compactTitle = false;
  bool showPosterTitle = true;

  /// 主题模式。**唯一事实来源** —— `MaterialApp.themeMode` 由它驱动。
  PeekThemeMode themeMode = PeekThemeMode.system;

  /// 首页「合并播放列表」开关（原版首页 chips 行第 1 个 Button）。
  bool mergePlaylist = false;

  // ---------------- 首页 ----------------
  HomeContent? home;
  bool loadingHome = false;
  String? homeError;
  int homeTab = 0;

  /// 每个分类的筛选默认值（源的 `filters[typeId][].init`）。
  final Map<String, Map<String, String>> _filterInit = {};

  // ---------------- 搜索 ----------------
  final List<String> hotWords = <String>[];
  bool loadingHot = false;

  // ---------------------------------------------------------------------------
  // 只读访问
  // ---------------------------------------------------------------------------

  List<SourceConfig> get sourceConfigs => List.unmodifiable(_sources);
  String? get activeId => _activeId;
  SourceConfig? get activeSource =>
      _sources.where((s) => s.id == _activeId).firstOrNull;
  bool get hasSources => _sources.isNotEmpty;
  bool get serviceReady => _svc.ready;
  String? get serviceBaseUrl => _svc.baseUrl;
  List<String> get runtimeLog => _svc.log;
  String? get activeWorkDir => _svc.workDir;
  String? get lastServiceError => _svc.lastError;

  List<Site> get sites => _svc.sites.where((s) => !s.hide).toList();

  List<Site> get searchableSites => sites.where((s) => s.searchable).toList();

  /// 详情页「快搜」可用的源。
  List<Site> get quickSearchSites =>
      searchableSites.where((s) => s.quickSearch).toList();

  /// 参与搜索的源集合（减去用户屏蔽列表）。
  List<Site> searchSources({bool onlyDefault = false}) {
    final blocked = BlockedSearchSources.all;
    var list = quickSearchSites.where((s) => !blocked.contains(s.key));
    if (onlyDefault) {
      final cur = currentSite;
      if (cur != null) list = list.where((s) => s.key == cur.key);
    }
    return list.toList();
  }

  bool get searchOnlyDefaultSource =>
      Store.get<bool>('searchOnlyDefaultSource', false);

  Future<void> setSearchOnlyDefaultSource(bool v) async {
    await Store.set('searchOnlyDefaultSource', v);
    notifyListeners();
  }

  /// 多元搜索页布局：`true` = 上下布局（顶部横排站点 chips），
  /// `false` = 网格视图（左侧纵向站源栏）。对应原版顶栏第 4 个切换按钮，
  /// 选择会持久化并跨会话保留（原版行为）。
  bool get multiSearchStacked =>
      Store.get<bool>('multiSearchStacked', true);

  Future<void> setMultiSearchStacked(bool v) async {
    await Store.set('multiSearchStacked', v);
    notifyListeners();
  }

  Site? get currentSite {
    final list = sites;
    if (list.isEmpty) return null;
    for (final s in list) {
      if (s.key == _siteKey) return s;
    }
    return list.first;
  }

  String get currentSiteName => currentSite?.name ?? '未选择';

  bool get hasConfig => sites.isNotEmpty;

  /// 源不提供解析接口列表，恒为空。
  List<Parse> get parseInterfaces => config?.parses ?? const <Parse>[];

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    await _svc.init();

    _sources = SourceConfig.decodeList(Store.get<String>(_kSources, ''));
    _activeId = Store.get<String>(_kActiveId, '').isEmpty
        ? null
        : Store.get<String>(_kActiveId, '');

    if (Store.get<String>('viewMode', 'grid') == 'list') {
      viewMode = ViewMode.list;
    }
    compactTitle = Store.get<bool>('compactTitle', false);
    showPosterTitle = Store.get<bool>('showPosterTitle', true);
    mergePlaylist = Store.get<bool>('mergePlaylist', false);
    _siteKey = Store.selectedSourceKey;
    themeMode = _decodeThemeMode(Store.get<String>(_kThemeMode, 'system'));

    notifyListeners();

    // 有源则自动启动（不内置任何源，首次启动停在空态）
    final cfg = activeSource;
    if (cfg != null) {
      unawaited(_startActive(silent: true));
    }
  }

  @override
  void dispose() {
    unawaited(_svc.dispose());
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 源管理
  // ---------------------------------------------------------------------------

  /// 添加一个源。返回 null 表示成功，否则为错误信息。
  Future<String?> addSource(String url, {String? displayName}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '请填写源地址';

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '源地址格式无效，需形如 http://user:pass@host/index.js.md5';
    }

    final id = sourceIdOf(trimmed);
    if (_sources.any((s) => s.id == id)) return '该源已存在';

    final name = (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim()
        : _defaultNameFrom(trimmed);

    var cfg = SourceConfig(id: id, url: trimmed, name: name);
    final err = await _svc.fetchAndInstall(cfg);
    cfg = err != null
        ? cfg.copyWith(lastError: err)
        : cfg.copyWith(updatedAt: DateTime.now(), clearError: true);
    _sources = [..._sources, cfg];

    if (err == null) {
      _activeId = id;
      await _persist();
      notifyListeners();
      await _startActive();
    } else {
      await _persist();
      notifyListeners();
    }
    return err;
  }

  Future<void> removeSource(String id) async {
    if (_activeId == id) {
      await _svc.stop();
      _resetBrowsing();
    }
    _sources = _sources.where((s) => s.id != id).toList();
    if (_activeId == id) {
      _activeId = _sources.isEmpty ? null : _sources.first.id;
    }
    await _persist();
    notifyListeners();
    if (_activeId != null) unawaited(_startActive());
  }

  Future<void> setActive(String id) async {
    if (_activeId == id) return;
    await _svc.stop();
    _activeId = id;
    _resetBrowsing();
    await _persist();
    notifyListeners();
    await _startActive();
  }

  Future<void> renameSource(String id, String name) async {
    _sources = _sources
        .map((s) => s.id == id ? s.copyWith(name: name.trim()) : s)
        .toList();
    await _persist();
    notifyListeners();
  }

  /// 重新拉取当前源并重启服务。
  Future<void> refreshConfig() async {
    final cfg = activeSource;
    if (cfg == null) return;
    await _svc.stop();
    final err = await _svc.fetchAndInstall(cfg);
    _sources = _sources
        .map((s) => s.id == cfg.id
            ? s.copyWith(
                updatedAt: err == null ? DateTime.now() : s.updatedAt,
                lastError: err,
                clearError: err == null,
              )
            : s)
        .toList();
    await _persist();
    if (err != null) {
      configError = err;
      nodeSourceError = err;
      notifyListeners();
      return;
    }
    await _startActive();
  }

  // ---------------------------------------------------------------------------
  // 服务生命周期
  // ---------------------------------------------------------------------------

  Future<void> _startActive({bool silent = false}) async {
    final cfg = activeSource;
    if (cfg == null) return;

    loadingConfig = true;
    configError = null;
    nodeSourceError = null;
    if (!silent) notifyListeners();

    final err = await _svc.start(cfg);
    loadingConfig = false;

    if (err != null) {
      configError = err;
      nodeSourceError = err;
      notifyListeners();
      return;
    }

    _sources = _sources
        .map((s) => s.id == cfg.id ? s.copyWith(clearError: true) : s)
        .toList();
    await _persist();

    activeConfigUrl = cfg.url;
    config = TvBoxConfig(
      sites: _svc.sites,
      parses: const [],
      lives: const [],
      raw: const {},
    );
    _siteKey ??= _svc.sites.isNotEmpty ? _svc.sites.first.key : null;
    notifyListeners();

    await loadHome();
  }

  Future<void> stopService() async {
    await _svc.stop();
    config = null;
    _resetBrowsing();
    notifyListeners();
  }

  void _resetBrowsing() {
    home = null;
    homeError = null;
    _filterInit.clear();
  }

  // ---------------------------------------------------------------------------
  // 站源切换
  // ---------------------------------------------------------------------------

  Future<void> selectSite(Site site) async {
    if (_siteKey == site.key) return;
    _siteKey = site.key;
    await Store.setSelectedSourceKey(site.key);
    _resetBrowsing();
    notifyListeners();
    await loadHome();
  }

  // ---------------------------------------------------------------------------
  // 视图设置
  // ---------------------------------------------------------------------------

  Future<void> setViewMode(ViewMode m) async {
    viewMode = m;
    await Store.set('viewMode', m == ViewMode.list ? 'list' : 'grid');
    notifyListeners();
  }

  Future<void> setCompactTitle(bool v) async {
    compactTitle = v;
    await Store.set('compactTitle', v);
    notifyListeners();
  }

  Future<void> setShowPosterTitle(bool v) async {
    showPosterTitle = v;
    await Store.set('showPosterTitle', v);
    notifyListeners();
  }

  Future<void> setMergePlaylist(bool v) async {
    mergePlaylist = v;
    await Store.set('mergePlaylist', v);
    notifyListeners();
  }

  Future<void> setThemeMode(PeekThemeMode m) async {
    themeMode = m;
    await Store.set(_kThemeMode, m.name);
    notifyListeners();
  }

  static PeekThemeMode _decodeThemeMode(String s) => switch (s) {
        'light' => PeekThemeMode.light,
        'dark' => PeekThemeMode.dark,
        _ => PeekThemeMode.system,
      };

  // ---------------------------------------------------------------------------
  // 首页 / 分类
  // ---------------------------------------------------------------------------

  Future<void> loadHome({bool force = false}) async {
    final site = currentSite;
    if (site == null) return;
    if (loadingHome) return;
    if (!force && home != null) return;

    loadingHome = true;
    homeError = null;
    notifyListeners();

    try {
      final h = await _svc.homeOf(site);
      home = h;
      // 源的筛选默认值要留下来，内联筛选面板靠它判选中态
      _filterInit.clear();
      for (final c in h.classes) {
        final d = <String, String>{};
        for (final g in c.filters) {
          if (g.init.isNotEmpty) d[g.key] = g.init;
        }
        if (d.isNotEmpty) _filterInit[c.typeId] = d;
      }
    } catch (e) {
      homeError = friendlyError(e);
    } finally {
      loadingHome = false;
      notifyListeners();
    }
  }

  Future<CategoryContent> category({
    required String typeId,
    required int page,
    Map<String, String> extend = const {},
  }) async {
    final site = currentSite;
    if (site == null) throw SpiderException('尚未选择站源');
    return _svc.categoryOf(site, typeId: typeId, page: page, extend: extend);
  }

  /// 某分类的筛选默认值。
  Map<String, String> filterInitOf(String typeId) =>
      Map<String, String>.from(_filterInit[typeId] ?? const {});

  // ---------------------------------------------------------------------------
  // 搜索
  // ---------------------------------------------------------------------------

  Future<List<Vod>> search(String keyword, {Site? site}) async {
    final target = site ?? currentSite;
    if (target == null) throw SpiderException('尚未选择站源');
    return _svc.searchOf(target, keyword);
  }

  /// 全站源聚合搜索。
  Future<List<SiteVod>> searchAll(
    String keyword, {
    void Function(int done, int total)? onProgress,
    bool onlyDefault = false,
  }) async {
    final list = searchSources(onlyDefault: onlyDefault);
    final out = <SiteVod>[];
    var done = 0;
    final futures = list.map((site) async {
      try {
        final r = await _svc
            .searchOf(site, keyword)
            .timeout(const Duration(seconds: 12));
        if (r.isNotEmpty) out.addAll(r.map((v) => SiteVod(site, v)));
      } catch (_) {
        // 单个站源失败不影响整体聚合
      } finally {
        done++;
        onProgress?.call(done, list.length);
      }
    }).toList();
    await Future.wait(futures);
    return out;
  }

  /// 分源搜索：谁先返回谁先上屏。
  Future<void> searchBySource(
    String keyword, {
    required void Function(Site site, List<Vod> items, int done, int total)
        onResult,
    bool onlyDefault = false,
  }) async {
    final list = searchSources(onlyDefault: onlyDefault);
    var done = 0;
    // 单源超时。
    //
    // 原为固定 12 秒，实测**偏短**：93 个站源同时并发时，源服务要现拉现解析，
    // 部分秒播源会排队到 12 秒之后才返回（实测瓜子单站就要 1.5s，并发下更久），
    // 一律被砍掉 → 用户看到「搜不到」。
    //
    // 折中方案：默认放宽到 20 秒。用户在「设置 → 搜索」里可调
    // （`searchTimeoutSeconds`，范围 5–60）。
    final timeout = Duration(seconds: searchTimeoutSeconds);
    final futures = list.map((site) async {
      List<Vod> items = const <Vod>[];
      try {
        items = await _svc.searchOf(site, keyword).timeout(timeout);
      } catch (_) {
        items = const <Vod>[];
      } finally {
        done++;
        onResult(site, items, done, list.length);
      }
    }).toList();
    await Future.wait(futures);
  }

  /// 单源搜索超时（秒）。默认 20。
  int get searchTimeoutSeconds {
    final v = Store.get<int>('searchTimeoutSeconds', 20);
    return v.clamp(5, 60);
  }

  Future<void> setSearchTimeoutSeconds(int v) async {
    await Store.set('searchTimeoutSeconds', v.clamp(5, 60));
    notifyListeners();
  }

  Future<void> loadHotWords() async {
    if (hotWords.isNotEmpty || loadingHot) return;
    loadingHot = true;
    notifyListeners();
    try {
      final text = await Http.getText(
        'https://api.bilibili.com/x/web-interface/search/square?limit=30',
      );
      final json = jsonDecode(text) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      final trending = data?['trending'] as Map<String, dynamic>?;
      final list = trending?['list'] as List? ?? const [];
      for (final item in list) {
        if (item is Map && item['keyword'] != null) {
          hotWords.add(item['keyword'].toString());
        }
      }
    } catch (_) {
      hotWords.addAll(_fallbackHot);
    }
    if (hotWords.isEmpty) hotWords.addAll(_fallbackHot);
    loadingHot = false;
    notifyListeners();
  }

  static const _fallbackHot = <String>[
    '庆余年',
    '与凤行',
    '繁花',
    '南来北往',
    '大唐狄公案',
    '在暴雪时分',
    '如果奔跑是我的人生',
    '狗剩快跑',
    '飞驰人生2',
    '热辣滚烫',
  ];

  // ---------------------------------------------------------------------------
  // 详情 / 播放
  // ---------------------------------------------------------------------------

  Future<Vod?> detail(Site site, String id) => _svc.detailOf(site, id);

  Future<PlayResult> player(Site site, String flag, String id) async {
    // 用户手动指定的解析接口（原版 `[T4] 用户手动选择解析接口:`）：
    // 只有当站源没自带解析名时才覆盖。本工程的源不提供 parses，
    // 因此这个开关只在源自己返回空 flag 时生效。
    final picked = Store.get<String>('parseName', '').trim();
    final useFlag = (flag.trim().isEmpty && picked.isNotEmpty) ? picked : flag;
    return _svc.playOf(site, useFlag, id);
  }

  Future<Map<String, dynamic>> providerStatus() => _svc.providerStatus();

  // ---------------------------------------------------------------------------
  // 收藏
  // ---------------------------------------------------------------------------

  static String favKey(Site site, String vodId) => '${site.displayKey}|$vodId';

  bool isFavorite(Site site, String vodId) =>
      Store.isFavorite(favKey(site, vodId));

  Future<void> toggleFavorite(Site site, Vod vod) async {
    await Store.toggleFavorite(favKey(site, vod.id), {
      'vod_id': vod.id,
      'vod_name': vod.name,
      'vod_pic': vod.pic,
      'vod_remarks': vod.remarks,
      'source_key': site.displayKey,
      'source_name': site.name,
      'source_api': site.api,
      'source_type': site.type,
      'time': DateTime.now().millisecondsSinceEpoch,
    });
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  Future<void> _persist() async {
    await Store.set(_kSources, SourceConfig.encodeList(_sources));
    if (_activeId != null) {
      await Store.set(_kActiveId, _activeId!);
    } else {
      await Store.set(_kActiveId, null);
    }
  }

  static String _defaultNameFrom(String url) {
    try {
      final u = Uri.parse(url);
      return u.host.isEmpty ? '我的源' : u.host;
    } catch (_) {
      return '我的源';
    }
  }
}

/// 聚合搜索结果条目（带来源站源）。
class SiteVod {
  final Site site;
  final Vod vod;
  SiteVod(this.site, this.vod);
}

/// 参与搜索的源屏蔽列表 —— 对应原版存储键 `t4_blocked_search_sources`。
class BlockedSearchSources {
  static const _key = 'blockedSearchSources';

  static Set<String> get all =>
      (Store.get<List>(_key, const <String>[])).map((e) => e.toString()).toSet();

  static bool isBlocked(String key) => all.contains(key);

  static Future<void> setBlocked(String key, bool blocked) async {
    final s = all;
    if (blocked) {
      s.add(key);
    } else {
      s.remove(key);
    }
    await Store.set(_key, s.toList());
  }

  static Future<void> setAll(List<String> keys, {required bool blocked}) async {
    final s = all;
    if (blocked) {
      s.addAll(keys);
    } else {
      s.removeAll(keys);
    }
    await Store.set(_key, s.toList());
  }

  static Future<void> clear() async => Store.set(_key, <String>[]);
}

/// 自动换源配置 —— 对应原版存储键 `t4_auto_change_source_config`。
class AutoChangeSourceConfig {
  final bool enabled;
  final int maxAttempts;
  final bool quickOnly;

  const AutoChangeSourceConfig({
    this.enabled = false,
    this.maxAttempts = 3,
    this.quickOnly = true,
  });

  static const _key = 'auto_change_source_config';

  static AutoChangeSourceConfig load() {
    final raw = Store.get<Map>(_key, const <String, dynamic>{});
    return AutoChangeSourceConfig(
      enabled: raw['enabled'] == true,
      maxAttempts: int.tryParse('${raw['maxAttempts'] ?? 3}') ?? 3,
      quickOnly: raw['quickOnly'] != false,
    );
  }

  static Future<void> save(AutoChangeSourceConfig c) async {
    await Store.set(_key, <String, dynamic>{
      'enabled': c.enabled,
      'maxAttempts': c.maxAttempts,
      'quickOnly': c.quickOnly,
    });
  }

  AutoChangeSourceConfig copyWith({
    bool? enabled,
    int? maxAttempts,
    bool? quickOnly,
  }) =>
      AutoChangeSourceConfig(
        enabled: enabled ?? this.enabled,
        maxAttempts: maxAttempts ?? this.maxAttempts,
        quickOnly: quickOnly ?? this.quickOnly,
      );
}
