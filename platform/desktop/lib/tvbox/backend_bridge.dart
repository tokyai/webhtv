/// 后端桥接层 —— 把本工程既有的「源服务子进程 + HTTP」后端，
/// 包装成 PeekPili 原版 `tvbox/engine.dart` + `spiders/**` 的对外形状。
///
/// ## 为什么要这一层
///
/// 界面层（`pages/**`、`widgets/**`）是从 PeekPili **整建制移植**的，
/// 它只认 [tvbox.models] 里的 `Site` / `Vod` / `PlayResult` 等类型，以及
/// `AppState` 的 `home/category/detail/search/player` 这几个方法。
///
/// 而本工程的后端是**独立进程**：`index.js.md5` → 拉取 → 落盘 → 起
/// `node.exe` → 监听 `127.0.0.1:9988` → 之后全走 HTTP。
/// 这与 PeekPili 的「Dart 进程内直接跑 spider」在**实现上完全不同**，
/// 但对界面的**契约完全一致**。
///
/// 所以这里只做形状转换，不搬 PeekPili 那套引擎：
/// * PeekPili 的 `DexSpider` / `NodeJsHost` / `T4Spider` 依赖
///   `libcnode_wrapper.so`、`libnode.so`、DEX 加固库 —— 桌面端不存在，
///   搬过来必然编译失败，也没有意义；
/// * 本工程的 Node 子进程方案在 X1-2 已实测跑通（含 md5 校验、原子写、
///   端口预检），保留它就是保留已验证的成果。
///
/// ## 与 PeekPili 的行为差异（诚实记录）
///
/// * PeekPili 的 `Site.api` 形如 `csp_xxx` / `/spider/xxx/3`；
///   本工程的 `SiteEntry.key` 形如 `nodejs_wogg`，实际 POST 路径是
///   `/spider/<key 去掉 nodejs_ 前缀>/<type>`（见 [SiteEntry.prefix]）。
///   为了让界面层与 `Site.displayKey` 等展示逻辑保持一致，这里把
///   key 原样赋给 [Site.key]，`api` 填服务端给出的原始 api 串。
/// * `parse` 接口（解析接口列表）本工程的 `/config` **不提供**，
///   因此 [parseInterfaces] 恒为空 —— 对应「解析接口选择」入口不出现。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../backend/source_client.dart';
import '../backend/source_config.dart';
import '../backend/source_fetcher.dart';
import '../backend/source_runtime.dart';
import '../backend/source_models.dart' as be;
import 'models.dart';
import 'spider.dart';

/// 源服务自身异常 → UI 可读的业务异常。
///
/// `SourceError.message` 里装的就是源给的原文（如
/// 「还没有配置夸克 Cookie，请先去配置中心登录夸克」），必须原样透传。
SpiderException _toSpiderError(Object e) {
  if (e is be.SourceError) return SpiderException(e.message);
  return SpiderException('$e');
}

/// 把后端的一个站点映射成界面层认识的 [Site]。
Site siteFromEntry(SiteEntry e) => Site(
      key: e.key,
      name: e.name,
      type: e.type,
      api: e.api,
      searchable: e.searchable,
      quickSearch: e.searchable,
      filterable: e.filterable,
      changeable: true,
      hide: false,
      raw: {'__nodejs': true, 'key': e.key, 'type': e.type, 'api': e.api},
    );

/// 把后端的条目映射成界面层的 [Vod]。
Vod vodFromItem(be.VideoItem v) {
  final picRef = parsePicRef(v.vodPic);
  return Vod(
    id: v.vodId,
    name: v.vodName,
    pic: picRef.url,
    remarks: v.vodRemarks,
    picHeaders: picRef.header,
  );
}

/// 把后端详情映射成界面层的 [Vod]（含 playFrom / playUrl）。
Vod? vodFromDetail(be.VideoDetail d) {
  if (d.vodId.isEmpty && d.vodName.isEmpty) return null;
  final picRef = parsePicRef(d.vodPic);
  return Vod(
    id: d.vodId,
    name: d.vodName,
    pic: picRef.url,
    remarks: d.vodRemarks,
    content: d.vodContent,
    playFrom: d.vodPlayFrom,
    playUrl: d.vodPlayUrl,
    picHeaders: picRef.header,
  );
}

/// 后端首页 → 界面层 [HomeContent]。
HomeContent homeFrom(be.HomeContent h) {
  final classes = <VodClass>[];
  for (final c in h.classes) {
    classes.add(VodClass(
      typeId: c.typeId,
      typeName: c.typeName,
      filters: _filtersOf(h.filters[c.typeId]),
    ));
  }
  return HomeContent(
    classes: classes,
    list: [for (final v in h.list) vodFromItem(v)],
    filterMap: null,
  );
}

List<FilterGroup> _filtersOf(List<be.FilterGroup>? raw) {
  if (raw == null) return const [];
  return [
    for (final g in raw)
      FilterGroup(
        key: g.key,
        name: g.name,
        // 后端契约里 `init` 是**默认选中值**。PeekPili 的 FilterGroup
        // 没有 init 字段，而内联筛选面板靠 `selected[g.key]` 判选中态，
        // 所以适配层要把 init 回填进 extend，否则默认项不高亮。
        // 本工程给 models.FilterGroup 补了可选 `init` 字段来承载它。
        init: g.init,
        values: [for (final v in g.values) FilterValue(n: v.name, v: v.value)],
      ),
  ];
}

/// 后端分页 → 界面层 [CategoryContent]。
CategoryContent categoryFrom(be.PageResult r) => CategoryContent(
      list: [for (final v in r.list) vodFromItem(v)],
      page: r.page,
      pageCount: r.pageCount,
      limit: r.list.length,
      total: 0,
    );

/// `play` 的后端返回 → 界面层 [PlayResult]。
PlayResult playFrom(be.PlayResult r) {
  final header = r.header.isEmpty ? null : r.header;
  return PlayResult(
    url: r.url,
    header: header,
    playUrl: null,
    parse: r.parse ? '1' : null,
    msg: null,
    danmaku: null,
  );
}

/// 首页筛选组的默认选中值（`init`）。
///
/// PeekPili 的 `FilterGroup` 没有 `init` 字段，而内联筛选面板靠
/// `selected[g.key]` 判选中态。源的 `filters[typeId][].init` 是**默认选中值**，
/// 必须回填，否则首屏筛选项全部不高亮（与原版观感不一致）。
Map<String, String> defaultExtendOf(
  Map<String, Map<String, String>> initByType,
  String typeId,
) =>
    Map<String, String>.from(initByType[typeId] ?? const {});


/// ---------------------------------------------------------------- 服务端管理器
///
/// 生命周期与 `AppState` 里那套（拉取 → 校验 → 起进程 → 读站点）一致，
/// 只是把「结果」暴露成界面层习惯的类型。
class SourceService {
  final _fetcher = SourceFetcher();

  /// 当前 Node 源服务的 base URL（`http://127.0.0.1:9988`），未启动时为空串。
  ///
  /// ## 为什么是静态的
  ///
  /// 弹幕层（`player/danmaku/danmaku_session.dart`）要在**不持有 AppState**
  /// 的静态上下文里取这个地址 —— 它原先读 PeekPili 的
  /// `NodeJsHost.activeBase`。本工程没有进程内 Node，等价物就是这里。
  /// 由 [SourceRuntime] 的 start / stop 路径同步维护，读写都在主 isolate。
  static String activeBase = '';

  late Directory _dataRoot;
  late Directory _sourcesRoot;
  late Directory _runtimeRoot;

  SourceRuntime? _runtime;
  SourceClient? _client;

  /// 复用既有服务时的心跳维持器。
  ///
  /// 「复用」路径下进程不是我们起的，没有 [SourceRuntime] 实例来喂心跳；
  /// 但那个进程（若是新版 bootstrap）仍在等待心跳文件。不喂它就会在
  /// 约 15 秒后自杀 —— 用户会看到「刚加好源就断了」。
  Timer? _adoptedHeartbeat;

  /// 被接管的端口（复用路径下用于退出时反查 PID 回收）。null 表示未接管。
  int? _adoptedPort;

  List<Site> _sites = const [];
  HomeContent? _home;
  String? _lastError;

  List<Site> get sites => _sites;
  HomeContent? get home => _home;
  String? get lastError => _lastError;

  /// 是否可用。
  ///
  /// 注意：**不能只看 `_runtime`** ——「复用既有服务」路径下不会新建
  /// [SourceRuntime]（进程不是我们起的），此时 `_runtime` 为 null 但服务可用。
  /// 因此以「客户端已就绪」为准，它是两条路径的共同产物。
  bool get ready => _client != null && (_runtime == null || _runtime!.isRunning);
  String? get baseUrl => _runtime?.baseUrl ?? (_client == null ? null : activeBase);
  List<String> get log => _runtime?.log ?? const [];
  String? get workDir => _runtime?.workDir;

  Future<void> init() async {
    final base = await getApplicationSupportDirectory();
    _dataRoot = Directory(p.join(base.path, 'webhtv'));
    _sourcesRoot = Directory(p.join(_dataRoot.path, 'sources'));
    _runtimeRoot = Directory(p.join(_dataRoot.path, 'runtime'));
    for (final d in [_dataRoot, _sourcesRoot, _runtimeRoot]) {
      if (!d.existsSync()) d.createSync(recursive: true);
    }
  }

  Future<void> dispose() async {
    _stopAdoptedHeartbeat();
    await _runtime?.stop();
    _runtime = null;
    activeBase = '';
    _client?.dispose();
    _client = null;
    _fetcher.dispose();
  }

  String entryPathOf(String id) => p.join(_sourcesRoot.path, id, 'index.js');

  /// 拉取并安装源正文。
  Future<String?> fetchAndInstall(SourceConfig cfg) async {
    final dir = Directory(p.join(_sourcesRoot.path, cfg.id));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(p.join(dir.path, 'index.js'));
    try {
      final result = await _fetcher.fetch(cfg.url, knownMd5: cfg.cachedMd5);
      if (result.updated && result.body.isNotEmpty) {
        final tmp = File(p.join(dir.path, 'index.js.tmp'));
        tmp.writeAsStringSync(result.body, flush: true);
        tmp.renameSync(file.path);
      }
      return null;
    } on SourceFetchException catch (e) {
      return e.message;
    } catch (e) {
      return '$e';
    }
  }

  /// 启动源服务并读取站点清单。返回 null 表示成功。
  ///
  /// 两种承载形态：
  ///   - **桌面端**：起独立 node.exe 子进程，需要先定位可执行文件并做端口预检
  ///   - **iOS**：进程内 Node（nodejs-mobile），无需可执行文件、无需端口预检
  ///     （Node 单例，同进程内不可能出现「别的程序占着 9988」）
  Future<String?> start(SourceConfig cfg) async {
    final entry = entryPathOf(cfg.id);
    if (!File(entry).existsSync()) {
      final err = await fetchAndInstall(cfg);
      if (err != null) return err;
    }

    String? nodeExe;
    if (!Platform.isIOS) {
      nodeExe = await _resolveNodeExecutable();
      if (nodeExe == null) {
        return '未找到 node.exe。请把 node.exe 放到应用目录下的 runtime/ 文件夹，'
            '或确保系统 PATH 中存在 node。';
      }
    }

    await _runtime?.stop();
    _runtime = null;
    _client?.dispose();
    _client = null;

    // ---- iOS：进程内 Node，单例，直接起 ----
    if (Platform.isIOS) {
      final runtime = SourceRuntime(
        sourceId: cfg.id,
        workDir: p.join(_runtimeRoot.path, cfg.id),
        entryFile: entry,
        port: 9988,
      );
      try {
        await runtime.start();
      } on SourceRuntimeException catch (e) {
        return e.message;
      }
      _runtime = runtime;
      activeBase = runtime.baseUrl;
      _client = SourceClient(runtime.baseUrl);

      try {
        final entries = await _client!.sites();
        _sites = [for (final e in entries) siteFromEntry(e)];
      } catch (e) {
        return '读取站点清单失败：${_toSpiderError(e).message}';
      }
      if (_sites.isEmpty) return '源未返回任何可用站点';
      _lastError = null;
      return null;
    }

    // 端口 9988 预检 —— 关键：**区分「同类服务可复用」和「异类占用」**
    //
    // 早期实现只做 TCP 连通性探测，凡能连上就判为冲突并放弃启动。
    // 实测踩坑：上一轮运行遗留的 node 子进程仍监听 9988，且它**本来就是
    // 同一个源服务**（`/health` 返回 CatVodSpiderios）。此时用户看到的是
    // 「端口被占用」——明明是自己的服务，却既连不上也不让起新的。
    //
    // 现在改为三态判定：
    //   free        → 正常拉起新进程
    //   sameService → 该端口上就是同一个源服务，**直接复用**，不重复起进程
    //   foreign     → 别的程序占着，这才报错（无法安全抢占）
    final probe = await _probePort(9988);

    if (probe == _PortState.foreign) {
      return '端口 9988 已被其他程序占用。源服务的端口是固定的，请先释放该端口。';
    }

    if (probe == _PortState.sameService) {
      // 复用既有服务：不新建进程，只把客户端接上去。
      // `_runtime` 保持 null（进程不是我们起的），改由 [_adoptedPort] 记录，
      // 退出时按端口反查 PID 回收 —— 见 [stop]。
      activeBase = 'http://127.0.0.1:9988';
      _client = SourceClient(activeBase);
      _adoptedPort = 9988;

      // 接管心跳：那个进程若是新版 bootstrap，正等着被喂。
      // 心跳文件路径与 SourceRuntime 一致：<runtimeRoot>/<sourceId>/.host-alive
      _stopAdoptedHeartbeat();
      final hbDir = p.join(_runtimeRoot.path, cfg.id);
      Directory(hbDir).createSync(recursive: true);
      _touchAdoptedHeartbeat(hbDir);
      _adoptedHeartbeat = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _touchAdoptedHeartbeat(hbDir),
      );
    } else {
      final runtime = SourceRuntime(
        sourceId: cfg.id,
        workDir: p.join(_runtimeRoot.path, cfg.id),
        entryFile: entry,
        port: 9988,
      );
      try {
        await runtime.start(nodeExecutable: nodeExe);
      } on SourceRuntimeException catch (e) {
        return e.message;
      }

      _runtime = runtime;
      activeBase = runtime.baseUrl;
      _client = SourceClient(runtime.baseUrl);
    }

    try {
      final entries = await _client!.sites();
      _sites = [for (final e in entries) siteFromEntry(e)];
    } catch (e) {
      return '读取站点清单失败：${_toSpiderError(e).message}';
    }
    if (_sites.isEmpty) return '源未返回任何可用站点';

    _lastError = null;
    return null;
  }

  Future<void> stop() async {
    _stopAdoptedHeartbeat();
    await _runtime?.stop();
    _runtime = null;

    // 被接管的进程：进程不是我们起的，`SourceRuntime` 拿不到句柄，
    // 因此按端口反查 PID 再回收。反查失败（权限/工具缺失）不视为错误 ——
    // 至少心跳已经停了，新版 bootstrap 会在约 15 秒内自行退出。
    final adopted = _adoptedPort;
    _adoptedPort = null;
    if (adopted != null) await _killListenerOnPort(adopted);

    activeBase = '';
    _client?.dispose();
    _client = null;
    _sites = const [];
    _home = null;
  }

  /// 按端口反查监听进程并结束它（仅 Windows 桌面端使用）。
  ///
  /// 用 `netstat -ano` 拿 PID 再 `taskkill /F`。之所以不引入额外依赖：
  /// 两者都是系统自带，且这是退出路径，失败也无副作用。
  Future<void> _killListenerOnPort(int port) async {
    if (!Platform.isWindows) return;
    try {
      final ns = await Process.run('netstat', ['-ano']);
      final line = (ns.stdout as String)
          .split('\n')
          .where((l) => l.contains(':$port') && l.contains('LISTENING'))
          .firstOrNull;
      if (line == null) return;
      final parts = line.trim().split(RegExp(r'\s+'));
      final pid = int.tryParse(parts.last);
      if (pid == null || pid <= 0) return;
      await Process.run('taskkill', ['/F', '/PID', '$pid']);
    } catch (_) {
      // 尽力而为：失败时依赖子进程侧的心跳看护收尾
    }
  }

  void _stopAdoptedHeartbeat() {
    _adoptedHeartbeat?.cancel();
    _adoptedHeartbeat = null;
  }

  /// 为「被接管的」源服务喂心跳（覆写、不删除，避免 statSync 竞态）。
  void _touchAdoptedHeartbeat(String hbDir) {
    try {
      final f = File(p.join(hbDir, '.host-alive'));
      if (!f.existsSync()) f.createSync(recursive: true);
      f.writeAsStringSync('${DateTime.now().millisecondsSinceEpoch}');
    } catch (_) {
      // 不致命
    }
  }

  SourceClient? get _api => _client;

  /// 在站点清单里按 key 找站点（含后端原始 [SiteEntry]）。
  SiteEntry? _entryOf(Site site) {
    if (_client == null) return null;
    for (final e in _sites) {
      if (e.key == site.key) {
        return SiteEntry(
          key: e.key,
          name: e.name,
          type: e.type,
          enable: true,
          searchable: e.searchable,
          filterable: e.filterable,
          api: e.api,
        );
      }
    }
    return null;
  }

  SiteEntry _entryRaw(Site site) =>
      _entryOf(site) ??
      SiteEntry(
        key: site.key,
        name: site.name,
        type: site.type,
        enable: true,
        searchable: site.searchable,
        filterable: site.filterable,
        api: site.api,
      );

  // ---------------------------------------------------------------- 六个动作

  Future<HomeContent> homeOf(Site site) async {
    final api = _api;
    if (api == null) throw SpiderException('源服务未就绪');
    try {
      final h = homeFrom(await api.home(_entryRaw(site)));
      _home = h;
      return h;
    } catch (e) {
      throw _toSpiderError(e);
    }
  }

  Future<CategoryContent> categoryOf(
    Site site, {
    required String typeId,
    required int page,
    Map<String, String> extend = const {},
  }) async {
    final api = _api;
    if (api == null) throw SpiderException('源服务未就绪');
    try {
      final r = await api.category(
        _entryRaw(site),
        typeId: typeId,
        page: page,
        filters: extend,
      );
      return categoryFrom(r);
    } catch (e) {
      throw _toSpiderError(e);
    }
  }

  Future<List<Vod>> searchOf(Site site, String keyword) async {
    final api = _api;
    if (api == null) throw SpiderException('源服务未就绪');
    try {
      final r = await api.search(_entryRaw(site), keyword, page: 1);
      return [for (final v in r.list) vodFromItem(v)];
    } catch (e) {
      throw _toSpiderError(e);
    }
  }

  Future<Vod?> detailOf(Site site, String id) async {
    final api = _api;
    if (api == null) throw SpiderException('源服务未就绪');
    try {
      final d = await api.detail(_entryRaw(site), id);
      return d == null ? null : vodFromDetail(d);
    } catch (e) {
      throw _toSpiderError(e);
    }
  }

  Future<PlayResult> playOf(Site site, String flag, String id) async {
    final api = _api;
    if (api == null) throw SpiderException('源服务未就绪');
    try {
      return playFrom(await api.play(_entryRaw(site), flag: flag, id: id));
    } catch (e) {
      throw _toSpiderError(e);
    }
  }

  /// 网盘凭证状态（设置页「运行状态」用）。
  Future<Map<String, dynamic>> providerStatus() async {
    try {
      return await _client?.providerStatus() ?? const {};
    } catch (_) {
      return const {};
    }
  }

  /// 应用目录下的 node.exe（打包时随包分发）。
  Future<String?> _resolveNodeExecutable() async {
    final appDir = File(Platform.resolvedExecutable).parent;
    final candidates = [
      p.join(appDir.path, 'runtime', 'node.exe'),
      p.join(appDir.path, 'node.exe'),
      p.join(appDir.path, '..', 'runtime', 'node.exe'),
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }
    final pathEnv = Platform.environment['PATH'] ?? '';
    for (final dir in pathEnv.split(';')) {
      if (dir.trim().isEmpty) continue;
      final exe = p.join(dir.trim(), 'node.exe');
      if (File(exe).existsSync()) return exe;
    }
    return null;
  }

  /// 探测 9988 的占用性质。
  ///
  /// 先做 TCP 连通性判断（快，600 ms），连通后**再问一次 `/health`**：
  /// 若返回 `CatVodSpiderios`，说明端口上跑的就是我们要的源服务，可以复用。
  ///
  /// 不依赖进程名 / PID 判断 —— 那种做法要 shell out 到 tasklist，慢且脆；
  /// 而 `/health` 里的自报名是源自己写的，是**语义层面**最可靠的凭据。
  Future<_PortState> _probePort(int port) async {
    final connected = await _portInUse(port);
    if (!connected) return _PortState.free;
    if (await _isOurService(port)) return _PortState.sameService;
    return _PortState.foreign;
  }

  /// `/health` 是否返回本工程预期的源服务标识。
  Future<bool> _isOurService(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port/health'))
          .timeout(const Duration(seconds: 2));
      final resp = await req.close().timeout(const Duration(seconds: 2));
      if (resp.statusCode != 200) return false;
      final body = await resp.transform(utf8.decoder).join();
      return body.contains('CatVodSpiderios');
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

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
}

/// 端口 9988 的占用性质。
enum _PortState {
  /// 无人监听 —— 可正常拉起新进程。
  free,

  /// 端口上就是同一个源服务（`/health` 自报名匹配）—— 直接复用。
  sameService,

  /// 被其他程序占用 —— 无法安全抢占，须报错让用户处理。
  foreign,
}
