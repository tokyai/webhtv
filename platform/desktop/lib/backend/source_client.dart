/// CatVodSpiderios 源服务的 HTTP 客户端。
///
/// 严格遵循实测契约（`.workbuddy-ai/tmp/x1probe/API-CONTRACT.md`）：
///   - 站点内容接口一律 **POST** + JSON body
///   - 路由前缀 `/spider/<key 去 nodejs_ 前缀>/<type>`
///   - `GET /config` 拿站点清单，每项自带 `api` 字段
///   - `play` 返回 500 是**合法业务错误**（网盘未登录），需把 message 透给用户
library;

import 'dart:convert';

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
class SourceClient {
  final String baseUrl;
  final http.Client _http;
  static const _timeout = Duration(seconds: 30);

  SourceClient(this.baseUrl, {http.Client? client})
      : _http = client ?? http.Client();

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
