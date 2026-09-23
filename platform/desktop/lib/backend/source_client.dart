/// CatVodSpiderios 源服务的 HTTP 客户端。
///
/// 严格遵循实测契约（`.workbuddy-ai/tmp/x1probe/API-CONTRACT.md`）：
///   - 站点内容接口一律 **POST** + JSON body
///   - 路由前缀 `/spider/<key 去 nodejs_ 前缀>/<type>`
///   - `GET /config` 拿站点清单，每项自带 `api` 字段
///   - `play` 返回 500 是**合法业务错误**（网盘未登录），需把 message 透给用户
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'source_models.dart';

/// 源清单中的一个站点。
class SiteEntry {
  final String key;
  final String name;
  final int type;
  final bool enable;
  final bool searchable;
  final bool filterable;
  /// 形如 `/spider/wogg/3`
  final String api;

  const SiteEntry({
    required this.key,
    required this.name,
    required this.type,
    required this.enable,
    required this.searchable,
    required this.filterable,
    required this.api,
  });

  factory SiteEntry.fromJson(Map<String, dynamic> j) => SiteEntry(
        key: _s(j['key']),
        name: _s(j['name']),
        type: _i(j['type']),
        enable: j['enable'] == true,
        searchable: _i(j['searchable']) == 1,
        filterable: _i(j['filterable']) == 1,
        api: _s(j['api']),
      );

  /// 实际可用的调用前缀。
  ///
  /// 优先使用服务端给出的 `api` 字段；但它形如 `/spider/douban/3`，
  /// 而 **实际可 POST 的路径是 `/spider/<key去前缀>/<type>`**（实测：
  /// 直接用 `api` 会 404）。因此这里统一按 key 重新拼。
  String get prefix {
    final k = key.startsWith('nodejs_') ? key.substring(7) : key;
    return '/spider/$k/$type';
  }

  /// 用于展示的短名（去掉 `|` 后的副标题）。
  String get shortName {
    final idx = name.indexOf('|');
    return idx > 0 ? name.substring(0, idx) : name;
  }

  /// 副标题。
  String get subtitle {
    final idx = name.indexOf('|');
    return idx > 0 ? name.substring(idx + 1) : '';
  }
}

/// 源服务客户端。
///
/// ## ⚠️ 必须绕开系统代理（实测踩坑）
///
/// `package:http` 的默认 `Client()`（即 `IOClient(HttpClient())`）在
/// **Dart 的 `HttpClient` 会读取 `http_proxy` / `HTTP_PROXY` 环境变量**。
/// 一旦用户机器（或 CI、企业网络、本机抓包工具）设了代理，发往
/// `127.0.0.1:9988` 的请求就会被**送到代理服务器**，代理无法回源到本机
/// 回环地址，直接返回 **HTTP 502 Bad Gateway**。
///
/// 表现极具迷惑性：
///   * 直连 `curl` / Python `http.client`（都不读环境变量代理）→ 200，一切正常
///   * App 内聚合搜索 → 93 个站源**全部** `SourceError(502): 源返回 HTTP 502`
///   * 用户看到「聚合搜索没有搜索结果」，而源本身完全健康
///
/// 实测证据（Node 源在线，同一时刻同一个请求）：
/// ```text
/// http_proxy=http://127.0.0.1:53436
/// DEFAULT Client  -> 502 len=94     ← 走了代理
/// NO-PROXY Client -> 200 len=…      ← 直连成功
/// ```
///
/// 修复：用 [HttpOverrides.runZoned] + `findProxy = 'DIRECT'` 强制直连，
/// 仅在**创建这个客户端时**生效，不影响 App 其它需要走代理的外网请求。
class SourceClient {
  final String baseUrl;
  final http.Client _http;
  static const _timeout = Duration(seconds: 30);

  SourceClient(this.baseUrl, {http.Client? client})
      : _http = client ?? _directClient();

  /// 构造一个**永不使用代理**的 `http.Client`。
  ///
  /// `HttpOverrides.runZoned` 只在该异步区域内生效，用来包住
  /// `http.Client()` 的**创建**即可；客户端实例化完成后，内部持有的
  /// `HttpClient` 已经带上了 `findProxy = DIRECT`，后续请求全部直连。
  ///
  /// ⚠️ 注意 **不能**在 `createHttpClient` 里直接 `HttpClient()` —— 那会
  /// 再次进入 override，导致无限递归 → `Stack Overflow`（实测踩坑）。
  /// 必须走 [HttpOverrides.createHttpClient] 的 `super` 实现拿到底层实例。
  static http.Client _directClient() {
    late http.Client c;
    HttpOverrides.runZoned(
      () => c = http.Client(),
      createHttpClient: _DirectHttpOverrides().createHttpClient,
    );
    return c;
  }

  void dispose() => _http.close();

  /// `GET /health`
  Future<bool> health() async {
    try {
      final r = await _http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return r.statusCode == 200 && r.body.contains('CatVodSpiderios');
    } catch (_) {
      return false;
    }
  }

  /// `GET /config` → 站点清单。
  Future<List<SiteEntry>> sites() async {
    final r = await _http
        .get(Uri.parse('$baseUrl/config'))
        .timeout(_timeout);
    if (r.statusCode != 200) {
      throw SourceError(r.statusCode, '拉取站点配置失败');
    }
    final json = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    // 实测：{"video":{"sites":[...]}, "read":…, "comic":…}
    final video = json['video'];
    List<dynamic> raw = const [];
    if (video is Map && video['sites'] is List) {
      raw = video['sites'] as List;
    } else if (json['sites'] is List) {
      // 兼容扁平结构
      raw = json['sites'] as List;
    }
    return raw
        .whereType<Map>()
        .map((e) => SiteEntry.fromJson(e.cast<String, dynamic>()))
        .where((s) => s.key.isNotEmpty && s.enable)
        .toList();
  }

  /// `POST /website/api/status` → 网盘凭证状态。
  Future<Map<String, dynamic>> providerStatus() async {
    final r = await _http
        .get(Uri.parse('$baseUrl/website/api/status'))
        .timeout(_timeout);
    if (r.statusCode != 200) return const {};
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final data = j['data'];
    return data is Map ? data.cast<String, dynamic>() : const {};
  }

  // ---------------------------------------------------------------------------
  // 站点内容接口
  // ---------------------------------------------------------------------------

  /// `POST <prefix>/home`
  Future<HomeContent> home(SiteEntry site) async =>
      HomeContent.fromJson(await _post(site, 'home', const {}));

  /// `POST <prefix>/category`
  Future<PageResult> category(
    SiteEntry site, {
    required String typeId,
    int page = 1,
    Map<String, String> filters = const {},
  }) async =>
      PageResult.fromJson(await _post(site, 'category', {
        'id': typeId,
        'page': page,
        'filters': filters,
      }));

  /// `POST <prefix>/detail`
  ///
  /// [vodId] **原样透传**：各站点形态不同（`/voddetail/131674.html`、
  /// `msearch:36850814`、纯数字等），不要解析或转换。
  Future<VideoDetail?> detail(SiteEntry site, String vodId) async {
    final j = await _post(site, 'detail', {'id': vodId});
    final list = j['list'];
    if (list is List && list.isNotEmpty && list.first is Map) {
      return VideoDetail.fromJson((list.first as Map).cast<String, dynamic>());
    }
    // 部分站点（豆瓣等排行榜类）返回 {}，这是正常的
    if (j['vod_name'] != null || j['vod_play_url'] != null) {
      return VideoDetail.fromJson(j);
    }
    return null;
  }

  /// `POST <prefix>/search`
  Future<PageResult> search(SiteEntry site, String keyword,
          {int page = 1}) async =>
      PageResult.fromJson(await _post(site, 'search', {
        'wd': keyword,
        'page': page,
      }));

  /// `POST <prefix>/play`
  ///
  /// 返回 500 且带 `message` 时抛 [SourceError]，其 `message` 是**面向用户的
  /// 业务提示**（如"还没有配置百度网盘 Cookie，请先去配置中心登录百度网盘"），
  /// UI 应原样展示。
  Future<PlayResult> play(
    SiteEntry site, {
    required String flag,
    required String id,
  }) async =>
      PlayResult.fromJson(await _post(site, 'play', {
        'flag': flag,
        'id': id,
      }));

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _post(
    SiteEntry site,
    String action,
    Map<String, dynamic> body,
  ) async {
    final url = Uri.parse('$baseUrl${site.prefix}/$action');
    http.Response r;
    try {
      r = await _http
          .post(
            url,
            headers: const {
              'content-type': 'application/json; charset=utf-8',
              'accept': 'application/json',
            },
            body: utf8.encode(jsonEncode(body)),
          )
          .timeout(_timeout);
    } catch (e) {
      throw SourceError(-1, '请求源服务失败：$e');
    }

    final text = utf8.decode(r.bodyBytes, allowMalformed: true);
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(text);
      json = decoded is Map ? decoded.cast<String, dynamic>() : {};
    } catch (_) {
      json = {};
    }

    if (r.statusCode != 200) {
      // 源把业务错误也放在 message 字段
      final msg = json['message'] ??
          json['msg'] ??
          json['error'] ??
          '源返回 HTTP ${r.statusCode}';
      throw SourceError(r.statusCode, '$msg');
    }
    return json;
  }
}

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

/// 强制直连的 [HttpOverrides]（禁用一切代理环境变量）。
///
/// 见 [SourceClient] 文档字符串：`package:http` 的默认客户端会读取
/// `http_proxy` / `HTTP_PROXY`，把发往 `127.0.0.1` 的请求也交给代理，
/// 代理无法回源到本机回环地址 → 全部 502。
class _DirectHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    // super 拿到底层实例，再覆盖 findProxy；直接 `HttpClient()` 会无限递归。
    final client = super.createHttpClient(context);
    client.findProxy = (uri) => 'DIRECT';
    return client;
  }
}

