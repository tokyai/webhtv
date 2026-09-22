/// 应用级状态：源列表 + Node 运行时 + 当前站点内容。
///
/// 数据流：
///   用户填源地址 → [SourceFetcher] 拉取校验 → 落盘
///   → [SourceRuntime] 起 Node → [SourceClient] 读 `/config` 得站点清单
///   → UI 浏览
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/source_config.dart';
import '../models/source_models.dart';
import '../services/source_client.dart';
import '../services/source_fetcher.dart';
import '../services/source_runtime.dart';

/// 拉取过程中给用户看的阶段。
enum SourcePhase { idle, fetching, verifying, launching, ready, error }

/// 一条观看记录。
class WatchRecord {
  final VideoItem vod;
  final String episodeName;
  final DateTime watchedAt;

  const WatchRecord({
    required this.vod,
    required this.episodeName,
    required this.watchedAt,
  });

  Map<String, dynamic> toJson() => {
        'vodId': vod.vodId,
        'vodName': vod.vodName,
        'vodPic': vod.vodPic,
        'vodRemarks': vod.vodRemarks,
        'episodeName': episodeName,
        'watchedAt': watchedAt.toIso8601String(),
      };

  static WatchRecord? fromJson(Map<String, dynamic> j) {
    final id = '${j['vodId'] ?? ''}';
    if (id.isEmpty) return null;
    final at = DateTime.tryParse('${j['watchedAt'] ?? ''}');
    return WatchRecord(
      vod: VideoItem(
        vodId: id,
        vodName: '${j['vodName'] ?? ''}',
        vodPic: '${j['vodPic'] ?? ''}',
        vodRemarks: '${j['vodRemarks'] ?? ''}',
      ),
      episodeName: '${j['episodeName'] ?? ''}',
      watchedAt: at ?? DateTime.now(),
    );
  }
}

class AppState extends ChangeNotifier {
  // --- 持久化 ---
  static const _kSources = 'sources_v1';
  static const _kActiveId = 'active_source_v1';
  static const _kFavorites = 'favorites_v1';
  static const _kHistory = 'history_v1';
  static const _kLiveUrl = 'live_url_v1';

  final _fetcher = SourceFetcher();

  late Directory _dataRoot;
  late Directory _sourcesRoot;
  late Directory _runtimeRoot;

  SharedPreferences? _prefs;

  List<SourceConfig> _sources = [];
  String? _activeId;
  SourcePhase _phase = SourcePhase.idle;
  String _phaseMessage = '';
  String? _lastError;

  SourceRuntime? _runtime;
  SourceClient? _client;
  List<SiteEntry> _sites = [];
  SiteEntry? _currentSite;

  // 浏览态
  HomeContent _home = HomeContent.empty;
  PageResult _page = PageResult.empty;
  String? _currentTypeId;
  int _currentPage = 1;
  String _searchKeyword = '';
  bool _searchMode = false;

  // 收藏 / 历史 / 直播源
  List<VideoItem> _favorites = [];
  List<WatchRecord> _history = [];
  String? _liveUrl;

  // ---------------------------------------------------------------------------
  // 只读访问
  // ---------------------------------------------------------------------------

  List<SourceConfig> get sources => List.unmodifiable(_sources);
  String? get activeId => _activeId;
  SourceConfig? get activeSource =>
      _sources.where((s) => s.id == _activeId).firstOrNull;
  SourcePhase get phase => _phase;
  String get phaseMessage => _phaseMessage;
  String? get lastError => _lastError;
  bool get hasSources => _sources.isNotEmpty;

  List<SiteEntry> get sites => List.unmodifiable(_sites);
  SiteEntry? get currentSite => _currentSite;
  HomeContent get home => _home;
  PageResult get page => _page;
  String? get currentTypeId => _currentTypeId;
  int get currentPageNumber => _currentPage;
  String get searchKeyword => _searchKeyword;
  bool get searchMode => _searchMode;
  List<VideoItem> get favorites => List.unmodifiable(_favorites);
  List<WatchRecord> get history => List.unmodifiable(_history);
  String? get liveUrl => _liveUrl;
  bool isFavorite(String vodId) => _favorites.any((v) => v.vodId == vodId);
  bool get serviceReady => _runtime?.isRunning == true;
  String? get serviceBaseUrl => _runtime?.baseUrl;
  List<String> get runtimeLog => _runtime?.log ?? const [];

  /// 当前源的工作目录（用于"在资源管理器中打开"）。
  String? get activeWorkDir => _runtime?.workDir;

  // ---------------------------------------------------------------------------
  // 初始化
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    final base = await getApplicationSupportDirectory();
    _dataRoot = Directory(p.join(base.path, 'webhtv'));
    _sourcesRoot = Directory(p.join(_dataRoot.path, 'sources'));
    _runtimeRoot = Directory(p.join(_dataRoot.path, 'runtime'));
    for (final d in [_dataRoot, _sourcesRoot, _runtimeRoot]) {
      if (!d.existsSync()) d.createSync(recursive: true);
    }

    _sources = SourceConfig.decodeList(_prefs?.getString(_kSources) ?? '');
    _activeId = _prefs?.getString(_kActiveId);
    _favorites = _decodeFavorites(_prefs?.getString(_kFavorites) ?? '');
    _history = _decodeHistory(_prefs?.getString(_kHistory) ?? '');
    _liveUrl = _prefs?.getString(_kLiveUrl);

    notifyListeners();

    // 有源则自动启动
    if (_activeId != null && _sources.any((s) => s.id == _activeId)) {
      unawaited(startActive());
    }
  }

  @override
  void dispose() {
    _runtime?.stop();
    _client?.dispose();
    _fetcher.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 源管理
  // ---------------------------------------------------------------------------

  /// 添加一个源。
  ///
  /// [url] 用户输入的源地址。[displayName] 可选备注名。
  /// 返回 null 表示成功，否则返回错误信息。
  Future<String?> addSource(String url, {String? displayName}) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return '请填写源地址';

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return '源地址格式无效，需形如 http://user:pass@host/index.js.md5';
    }

    final id = sourceIdOf(trimmed);
    if (_sources.any((s) => s.id == id)) {
      return '该源已存在';
    }

    final name = (displayName?.trim().isNotEmpty ?? false)
        ? displayName!.trim()
        : _defaultNameFrom(trimmed);

    final cfg = SourceConfig(id: id, url: trimmed, name: name);
    _sources = [..._sources, cfg];

    // 立即拉取校验，失败则保留条目但记录错误
    final err = await _fetchAndInstall(cfg);
    await _persist();

    _activeId ??= id;
    if (err == null) {
      _activeId = id;
      notifyListeners();
      await startActive();
    } else {
      notifyListeners();
    }
    return err;
  }

  /// 删除源。
  Future<void> removeSource(String id) async {
    if (_activeId == id) {
      await _runtime?.stop();
      _runtime = null;
      _client?.dispose();
      _client = null;
      _sites = const [];
      _home = HomeContent.empty;
      _page = PageResult.empty;
      _currentSite = null;
    }
    _sources = _sources.where((s) => s.id != id).toList();
    if (_activeId == id) {
      _activeId = _sources.isEmpty ? null : _sources.first.id;
    }
    final dir = Directory(p.join(_sourcesRoot.path, id));
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
    await _persist();
    notifyListeners();
    if (_activeId != null) unawaited(startActive());
  }

  /// 切换当前源。
  Future<void> setActive(String id) async {
    if (_activeId == id) return;
    await _runtime?.stop();
    _runtime = null;
    _client?.dispose();
    _client = null;
    _activeId = id;
    _sites = const [];
    _home = HomeContent.empty;
    _page = PageResult.empty;
    _currentSite = null;
    await _persist();
    notifyListeners();
    await startActive();
  }

  /// 更新源的备注名。
  Future<void> renameSource(String id, String name) async {
    _sources = _sources
        .map((s) => s.id == id ? s.copyWith(name: name.trim()) : s)
        .toList();
    await _persist();
    notifyListeners();
  }

  /// 重新拉取当前源并重启服务。
  Future<void> refreshActiveSource() async {
    final cfg = activeSource;
    if (cfg == null) return;
    await _runtime?.stop();
    _runtime = null;
    final err = await _fetchAndInstall(cfg);
    await _persist();
    if (err != null) {
      _phase = SourcePhase.error;
      _phaseMessage = err;
      _lastError = err;
      notifyListeners();
      return;
    }
    await startActive();
  }

  // ---------------------------------------------------------------------------
  // 运行时
  // ---------------------------------------------------------------------------

  /// 启动当前源的 Node 服务并加载站点清单。
  Future<void> startActive() async {
    final cfg = activeSource;
    if (cfg == null) return;

    final entry = _entryPath(cfg.id);
    if (!File(entry).existsSync()) {
      // 本地没有正文 → 先拉
      _setPhase(SourcePhase.fetching, '正在拉取源…');
      final err = await _fetchAndInstall(cfg);
      await _persist();
      if (err != null) {
        _setPhase(SourcePhase.error, err);
        return;
      }
    }

    final nodeExe = await _resolveNodeExecutable();
    if (nodeExe == null) {
      _setPhase(SourcePhase.error,
          '未找到 node.exe。请把 node.exe 放到应用目录下的 runtime/ 文件夹，'
          '或确保系统 PATH 中存在 node。');
      return;
    }

    _setPhase(SourcePhase.launching, '正在启动源服务…');

    final workDir = p.join(_runtimeRoot.path, cfg.id);
    final runtime = SourceRuntime(
      sourceId: cfg.id,
      workDir: workDir,
      entryFile: entry,
      port: 9988,
    );

    // 端口占用预检 —— 源端口是硬编码的
    if (await _portInUse(9988)) {
      _setPhase(SourcePhase.error,
          '端口 9988 已被占用。源服务的端口是固定的，请先释放该端口（'
          '可能有另一个 WebHTV 实例或源服务在运行）。');
      return;
    }

    try {
      await runtime.start(nodeExecutable: nodeExe);
    } on SourceRuntimeException catch (e) {
      _setPhase(SourcePhase.error, e.message);
      return;
    }

    _runtime = runtime;
    _client?.dispose();
    _client = SourceClient(runtime.baseUrl);

    // 读站点清单
    try {
      _sites = await _client!.sites();
    } catch (e) {
      _setPhase(SourcePhase.error, '读取站点清单失败：$e');
      return;
    }

    if (_sites.isEmpty) {
      _setPhase(SourcePhase.error, '源未返回任何可用站点');
      return;
    }

    // 选一个可搜索的、非"配置中心"类的站点作为默认
    _currentSite = _sites.firstWhere(
      (s) => s.searchable && !s.key.contains('baseset') && !s.key.contains('gengxin'),
      orElse: () => _sites.first,
    );

    _setPhase(SourcePhase.ready, '就绪 · ${_sites.length} 个站点');
    notifyListeners();

    await loadHome();
  }

  Future<void> stopActive() async {
    await _runtime?.stop();
    _runtime = null;
    _client?.dispose();
    _client = null;
    _setPhase(SourcePhase.idle, '已停止');
  }

  // ---------------------------------------------------------------------------
  // 浏览
  // ---------------------------------------------------------------------------

  Future<void> selectSite(SiteEntry site) async {
    _currentSite = site;
    _searchMode = false;
    _searchKeyword = '';
    _currentTypeId = null;
    notifyListeners();
    await loadHome();
  }

  Future<void> loadHome() async {
    final client = _client;
    final site = _currentSite;
    if (client == null || site == null) return;
    try {
      _home = await client.home(site);
      _currentTypeId = _home.classes.isNotEmpty ? _home.classes.first.typeId : null;
      _currentPage = 1;
      _page = PageResult(
        page: 1,
        pageCount: 1,
        list: _home.list.isEmpty && _currentTypeId != null ? const [] : _home.list,
      );
      _lastError = null;
    } catch (e) {
      _lastError = '$e';
    }
    notifyListeners();
  }

  Future<void> loadCategory(
    String typeId, {
    int page = 1,
    Map<String, String> filters = const {},
  }) async {
    final client = _client;
    final site = _currentSite;
    if (client == null || site == null) return;
    _searchMode = false;
    _currentTypeId = typeId;
    _currentPage = page;
    notifyListeners();
    try {
      _page = await client.category(site, typeId: typeId, page: page, filters: filters);
      _lastError = null;
    } catch (e) {
      _lastError = '$e';
      _page = PageResult(page: page, pageCount: page, list: const []);
    }
    notifyListeners();
  }

  Future<void> doSearch(String keyword) async {
    final client = _client;
    final site = _currentSite;
    if (client == null || site == null) return;
    if (keyword.trim().isEmpty) return;
    _searchMode = true;
    _searchKeyword = keyword.trim();
    _currentPage = 1;
    notifyListeners();
    try {
      _page = await client.search(site, _searchKeyword, page: 1);
      _lastError = null;
    } catch (e) {
      _lastError = '$e';
      _page = PageResult.empty;
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    final client = _client;
    final site = _currentSite;
    if (client == null || site == null) return;
    if (_currentPage >= _page.pageCount) return;
    final next = _currentPage + 1;
    try {
      final PageResult more;
      if (_searchMode) {
        more = await client.search(site, _searchKeyword, page: next);
      } else if (_currentTypeId != null) {
        more = await client.category(site, typeId: _currentTypeId!, page: next);
      } else {
        return;
      }
      _currentPage = next;
      _page = PageResult(
        page: more.page,
        pageCount: more.pageCount,
        list: [..._page.list, ...more.list],
      );
      notifyListeners();
    } catch (e) {
      _lastError = '$e';
      notifyListeners();
    }
  }

  /// 拉取详情。
  Future<VideoDetail?> loadDetail(String vodId) async {
    final client = _client;
    final site = _currentSite;
    if (client == null || site == null) return null;
    try {
      final d = await client.detail(site, vodId);
      _lastError = null;
      return d;
    } catch (e) {
      _lastError = '$e';
      return null;
    }
  }

  /// 解析播放地址。返回 (结果, 错误信息)。
  Future<(PlayResult?, String?)> resolvePlay({
    required String flag,
    required String episodeId,
  }) async {
    final client = _client;
    final site = _currentSite;
    if (client == null || site == null) return (null, '源服务未就绪');
    try {
      final r = await client.play(site, flag: flag, id: episodeId);
      if (r.url.isEmpty) return (null, '源未返回播放地址');
      return (r, null);
    } on SourceError catch (e) {
      // 500 + message 是业务提示（如网盘未登录），原样透给用户
      return (null, e.message);
    } catch (e) {
      return (null, '$e');
    }
  }

  // ---------------------------------------------------------------------------
  // 收藏 / 历史 / 直播源
  // ---------------------------------------------------------------------------

  /// 加入或移出收藏。
  Future<void> toggleFavorite(VideoItem vod) async {
    if (isFavorite(vod.vodId)) {
      _favorites = _favorites.where((v) => v.vodId != vod.vodId).toList();
    } else {
      _favorites = [vod, ..._favorites];
    }
    await _prefs?.setString(_kFavorites, _encodeFavorites(_favorites));
    notifyListeners();
  }

  /// 记录一次播放（同 id 只保留最新一条，置顶）。
  Future<void> addHistory(VideoItem vod, String episodeName) async {
    _history = _history.where((h) => h.vod.vodId != vod.vodId).toList();
    _history = [
      WatchRecord(vod: vod, episodeName: episodeName, watchedAt: DateTime.now()),
      ..._history,
    ];
    if (_history.length > 200) _history = _history.sublist(0, 200);
    await _prefs?.setString(_kHistory, _encodeHistory(_history));
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history = [];
    await _prefs?.remove(_kHistory);
    notifyListeners();
  }

  Future<void> setLiveUrl(String url) async {
    _liveUrl = url;
    await _prefs?.setString(_kLiveUrl, url);
    notifyListeners();
  }

  static String _encodeFavorites(List<VideoItem> list) => jsonEncode([
        for (final v in list)
          {
            'vod_id': v.vodId,
            'vod_name': v.vodName,
            'vod_pic': v.vodPic,
            'vod_remarks': v.vodRemarks,
          },
      ]);

  static List<VideoItem> _decodeFavorites(String raw) {
    if (raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => VideoItem.fromJson(e.cast<String, dynamic>()))
          .where((v) => v.vodId.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String _encodeHistory(List<WatchRecord> list) =>
      jsonEncode([for (final h in list) h.toJson()]);

  static List<WatchRecord> _decodeHistory(String raw) {
    if (raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => WatchRecord.fromJson(e.cast<String, dynamic>()))
          .whereType<WatchRecord>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  void _setPhase(SourcePhase phase, String message) {
    _phase = phase;
    _phaseMessage = message;
    if (phase == SourcePhase.error) _lastError = message;
    notifyListeners();
  }

  /// 拉取并安装源正文到 `<sourcesRoot>/<id>/index.js`。
  ///
  /// 返回 null 表示成功，否则为错误信息。
  Future<String?> _fetchAndInstall(SourceConfig cfg) async {
    final dir = Directory(p.join(_sourcesRoot.path, cfg.id));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(p.join(dir.path, 'index.js'));

    try {
      final result = await _fetcher.fetch(cfg.url, knownMd5: cfg.cachedMd5);
      if (result.updated && result.body.isNotEmpty) {
        // 原子写：先写临时文件再改名，避免半截文件被 Node 加载
        final tmp = File(p.join(dir.path, 'index.js.tmp'));
        tmp.writeAsStringSync(result.body, flush: true);
        tmp.renameSync(file.path);
      }
      _replaceConfig(cfg.id, (s) => s.copyWith(
            cachedMd5: result.md5,
            updatedAt: DateTime.now(),
            clearError: true,
          ));
      return null;
    } on SourceFetchException catch (e) {
      _replaceConfig(cfg.id, (s) => s.copyWith(lastError: e.message));
      return e.message;
    } catch (e) {
      _replaceConfig(cfg.id, (s) => s.copyWith(lastError: '$e'));
      return '$e';
    }
  }

  void _replaceConfig(String id, SourceConfig Function(SourceConfig) f) {
    _sources = _sources.map((s) => s.id == id ? f(s) : s).toList();
  }

  String _entryPath(String id) =>
      p.join(_sourcesRoot.path, id, 'index.js');

  /// 定位 node.exe：优先应用自带的 `runtime/node.exe`，其次 PATH。
  Future<String?> _resolveNodeExecutable() async {
    // 1) 应用目录下的 runtime/node.exe（打包时会放进去）
    final appDir = File(Platform.resolvedExecutable).parent;
    final candidates = [
      p.join(appDir.path, 'runtime', 'node.exe'),
      p.join(appDir.path, 'node.exe'),
      // 开发期：仓库内的探针目录
      p.join(appDir.path, '..', 'runtime', 'node.exe'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }

    // 2) PATH
    final pathEnv = Platform.environment['PATH'] ?? '';
    for (final dir in pathEnv.split(';')) {
      if (dir.trim().isEmpty) continue;
      final exe = p.join(dir.trim(), 'node.exe');
      if (File(exe).existsSync()) return exe;
    }
    return null;
  }

  /// 检测端口是否已被占用。
  Future<bool> _portInUse(int port) async {
    try {
      final socket = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(milliseconds: 600));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _persist() async {
    await _prefs?.setString(_kSources, SourceConfig.encodeList(_sources));
    if (_activeId != null) {
      await _prefs?.setString(_kActiveId, _activeId!);
    } else {
      await _prefs?.remove(_kActiveId);
    }
  }

  static String _defaultNameFrom(String url) {
    try {
      final u = Uri.parse(url);
      final host = u.host;
      return host.isEmpty ? '我的源' : host;
    } catch (_) {
      return '我的源';
    }
  }
}
