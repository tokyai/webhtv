/// TVBox 配置与数据模型（与原版 1.2.5+2 的字段命名保持一致）。
library;

class TvBoxConfig {
  final String? spider;
  final String? wallpaper;
  final String? logo;
  final List<Site> sites;
  final List<Parse> parses;
  final List<LiveGroup> lives;
  final Map<String, dynamic> raw;

  TvBoxConfig({
    this.spider,
    this.wallpaper,
    this.logo,
    required this.sites,
    required this.parses,
    required this.lives,
    required this.raw,
  });

  factory TvBoxConfig.fromJson(Map<String, dynamic> json) {
    final sites = <Site>[];
    for (final s in (json['sites'] as List? ?? const [])) {
      if (s is Map) {
        final site = Site.fromJson(Map<String, dynamic>.from(s));
        if (site.name.isNotEmpty) sites.add(site);
      }
    }
    final parses = <Parse>[];
    for (final p in (json['parses'] as List? ?? const [])) {
      if (p is Map) parses.add(Parse.fromJson(Map<String, dynamic>.from(p)));
    }
    final lives = <LiveGroup>[];
    for (final l in (json['lives'] as List? ?? const [])) {
      if (l is Map) lives.add(LiveGroup.fromJson(Map<String, dynamic>.from(l)));
    }
    return TvBoxConfig(
      spider: json['spider']?.toString(),
      wallpaper: json['wallpaper']?.toString(),
      logo: json['logo']?.toString(),
      sites: sites,
      parses: parses,
      lives: lives,
      raw: json,
    );
  }

  Site? siteByKey(String? key) {
    if (key == null) return null;
    for (final s in sites) {
      if (s.key == key) return s;
    }
    return null;
  }

  /// 追加站点（用于合并本地 Node 服务 `/full-config` 注册的站点）
  TvBoxConfig withExtraSites(List<Site> extra) {
    if (extra.isEmpty) return this;
    final keys = sites.map((s) => s.key).toSet();
    final merged = <Site>[
      ...sites,
      ...extra.where((s) => !keys.contains(s.key)),
    ];
    return TvBoxConfig(
      spider: spider,
      wallpaper: wallpaper,
      logo: logo,
      sites: merged,
      parses: parses,
      lives: lives,
      raw: raw,
    );
  }
}

/// 站源。type 含义沿用 TVBox 约定：
/// 0 = 纯 XML 接口，1 = JSON 接口，3 = 自建 Spider(csp_*)，4 = 远程 API
class Site {
  final String key;
  final String name;
  final int type;
  final String api;
  final String? ext;
  final String? jar;
  final bool searchable;
  final bool quickSearch;
  final bool filterable;
  final bool changeable;
  final bool hide;
  final int? indexs;
  final int? timeout;
  final Map<String, String>? header;
  final String? playerType;
  final String? style;
  final Map<String, dynamic> raw;

  Site({
    required this.key,
    required this.name,
    required this.type,
    required this.api,
    this.ext,
    this.jar,
    this.searchable = true,
    this.quickSearch = true,
    this.filterable = true,
    this.changeable = true,
    this.hide = false,
    this.indexs,
    this.timeout,
    this.header,
    this.playerType,
    this.style,
    required this.raw,
  });

  factory Site.fromJson(Map<String, dynamic> j) {
    Map<String, String>? header;
    final h = j['header'];
    if (h is Map) {
      header = h.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    return Site(
      key: j['key']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      type: _int(j['type'], 3),
      api: j['api']?.toString() ?? '',
      ext: j['ext']?.toString(),
      jar: j['jar']?.toString(),
      searchable: _bool(j['searchable'], true),
      quickSearch: _bool(j['quickSearch'], true),
      filterable: _bool(j['filterable'], true),
      changeable: _bool(j['changeable'], true),
      hide: _bool(j['hide'], false),
      indexs: j['indexs'] == null ? null : _int(j['indexs'], 0),
      timeout: j['timeout'] == null ? null : _int(j['timeout'], 0),
      header: header,
      playerType: j['playerType']?.toString(),
      style: j['style']?.toString(),
      raw: Map<String, dynamic>.from(j),
    );
  }

  /// 是否走本地脚本运行时（Node / CatJS / Python）
  bool get isScriptSource => api.startsWith('/spider/') || api.startsWith('csp_');

  /// 是否由本地 Node 服务注册（api 指向 127.0.0.1 的 NodeJsSpider 站点）
  bool get isNodeJs =>
      raw['__nodejs'] == true ||
      api.startsWith('http://127.0.0.1:') ||
      api.startsWith('http://localhost:');

  /// 站点标识（写源助手、调试日志中显示的 key）
  String get displayKey => key.isEmpty ? api : key;
}

class Parse {
  final String name;
  final String type;
  final String url;
  final String? ext;
  final Map<String, String>? header;
  final Map<String, dynamic> raw;

  Parse({
    required this.name,
    required this.type,
    required this.url,
    this.ext,
    this.header,
    required this.raw,
  });

  factory Parse.fromJson(Map<String, dynamic> j) {
    Map<String, String>? header;
    final h = j['header'];
    if (h is Map) header = h.map((k, v) => MapEntry(k.toString(), v.toString()));
    return Parse(
      name: j['name']?.toString() ?? '',
      type: j['type']?.toString() ?? '0',
      url: j['url']?.toString() ?? '',
      ext: j['ext']?.toString() == null ? null : j['ext'].toString(),
      header: header,
      raw: Map<String, dynamic>.from(j),
    );
  }
}

class LiveGroup {
  final String name;
  final String url;
  final String? ext;
  final Map<String, dynamic> raw;

  LiveGroup({required this.name, required this.url, this.ext, required this.raw});

  factory LiveGroup.fromJson(Map<String, dynamic> j) => LiveGroup(
        name: j['name']?.toString() ?? '',
        url: j['url']?.toString() ?? '',
        ext: j['ext']?.toString(),
        raw: Map<String, dynamic>.from(j),
      );
}

/// CatVod / TVBox 的图片地址约定：`<url>@Referer=<r>@User-Agent=<ua>`。
///
/// 豆瓣系 spider 返回的海报地址普遍带这串后缀（防盗链），必须把 URL 与
/// 请求头拆开：URL 直接给图片组件，请求头交给 HTTP 层，否则图片一律 403/空图。
class PicRef {
  final String url;
  final Map<String, String> header;
  const PicRef(this.url, this.header);
}

/// 拆解 `url@Key=Value@Key2=Value2`。
/// 只在第一个 `@` 之前是 http(s) 地址、且后续片段形如 `Key=Value` 时才认作请求头，
/// 避免误伤本身含 `@` 的普通 URL。
PicRef parsePicRef(String raw) {
  final at = raw.indexOf('@');
  if (at <= 0) return PicRef(raw, const {});
  final url = raw.substring(0, at);
  if (!url.startsWith('http')) return PicRef(raw, const {});
  final header = <String, String>{};
  for (final seg in raw.substring(at + 1).split('@')) {
    final i = seg.indexOf('=');
    if (i <= 0) continue;
    final k = seg.substring(0, i).trim();
    // 头名不含路径/协议字符，避免把 `https://a@b/c` 这类 URL 误判成请求头
    if (k.isEmpty || k.contains('/') || k.contains(':')) continue;
    header[k] = seg.substring(i + 1).trim();
  }
  return PicRef(url, header);
}

/// 还原成 `url@Key=Value...` 形式（写历史/收藏时保持原样）
String joinPicRef(String url, Map<String, String> header) {
  if (header.isEmpty) return url;
  final sb = StringBuffer(url);
  header.forEach((k, v) => sb.write('@$k=$v'));
  return sb.toString();
}

/// 影片条目
class Vod {
  final String id;
  final String name;
  final String pic;
  final String remarks;
  final String year;
  final String area;
  final String typeName;
  final String actor;
  final String director;
  final String content;
  final String playFrom;
  final String playUrl;
  final double score;
  final Map<String, String> picHeaders;
  final Map<String, dynamic> raw;

  Vod({
    required this.id,
    required this.name,
    this.pic = '',
    this.remarks = '',
    this.year = '',
    this.area = '',
    this.typeName = '',
    this.actor = '',
    this.director = '',
    this.content = '',
    this.playFrom = '',
    this.playUrl = '',
    this.score = 0,
    this.picHeaders = const {},
    this.raw = const {},
  });

  factory Vod.fromJson(Map<String, dynamic> j) {
    final picRef = parsePicRef(j['vod_pic']?.toString() ?? '');
    return Vod(
      id: j['vod_id']?.toString() ?? '',
      name: j['vod_name']?.toString() ?? '',
      pic: picRef.url,
      remarks: j['vod_remarks']?.toString() ?? '',
      year: j['vod_year']?.toString() ?? '',
      area: j['vod_area']?.toString() ?? '',
      typeName: j['type_name']?.toString() ?? '',
      actor: j['vod_actor']?.toString() ?? '',
      director: j['vod_director']?.toString() ?? '',
      content: j['vod_content']?.toString() ?? '',
      playFrom: j['vod_play_from']?.toString() ?? '',
      playUrl: j['vod_play_url']?.toString() ?? '',
      score: _double(j['vod_score']),
      picHeaders: picRef.header,
      raw: Map<String, dynamic>.from(j),
    );
  }

  Map<String, dynamic> toJson() => {
        'vod_id': id,
        'vod_name': name,
        'vod_pic': joinPicRef(pic, picHeaders),
        'vod_remarks': remarks,
        'vod_year': year,
        'vod_area': area,
        'type_name': typeName,
        'vod_actor': actor,
        'vod_director': director,
        'vod_content': content,
        'vod_play_from': playFrom,
        'vod_play_url': playUrl,
        'vod_score': score,
      };

  /// 解析 vod_play_url 得到线路 -> 剧集
  List<PlayLine> get lines {
    if (playUrl.isEmpty) return const [];
    final froms = playFrom.isEmpty ? <String>[] : playFrom.split(r'$$$');
    final groups = playUrl.split(r'$$$');
    final out = <PlayLine>[];
    for (var i = 0; i < groups.length; i++) {
      final episodes = <Episode>[];
      for (final seg in groups[i].split('#')) {
        if (seg.trim().isEmpty) continue;
        final idx = seg.indexOf(r'$');
        if (idx < 0) {
          episodes.add(Episode(name: seg, url: seg));
        } else {
          episodes.add(Episode(
            name: seg.substring(0, idx),
            url: seg.substring(idx + 1),
          ));
        }
      }
      out.add(PlayLine(
        name: i < froms.length && froms[i].isNotEmpty ? froms[i] : '线路${i + 1}',
        episodes: episodes,
      ));
    }
    return out;
  }
}

class PlayLine {
  final String name;
  final List<Episode> episodes;
  PlayLine({required this.name, required this.episodes});
}

class Episode {
  final String name;
  final String url;
  Episode({required this.name, required this.url});
}

/// 分类（首页 tab）
class VodClass {
  final String typeId;
  final String typeName;
  final List<FilterGroup> filters;
  VodClass({required this.typeId, required this.typeName, this.filters = const []});

  factory VodClass.fromJson(Map<String, dynamic> j, Map<String, dynamic>? filterMap) {
    final typeId = j['type_id']?.toString() ?? '';
    final list = <FilterGroup>[];
    final raw = filterMap?[typeId];
    if (raw is List) {
      for (final g in raw) {
        if (g is Map) {
          final values = <FilterValue>[];
          for (final v in (g['value'] as List? ?? const [])) {
            if (v is Map) {
              values.add(FilterValue(
                n: v['n']?.toString() ?? '',
                v: v['v']?.toString() ?? '',
              ));
            }
          }
          list.add(FilterGroup(
            key: g['key']?.toString() ?? '',
            name: g['name']?.toString() ?? '',
            values: values,
          ));
        }
      }
    }
    return VodClass(
      typeId: typeId,
      typeName: j['type_name']?.toString() ?? '',
      filters: list,
    );
  }
}

class FilterGroup {
  final String key;
  final String name;
  final List<FilterValue> values;

  /// 后端契约里 `filters[].init` 是**默认选中值**。
  ///
  /// PeekPili 原版没有这个字段（它的 `filterMap` 直接带 `init`，页面从
  /// `HomeContent.filterMap` 读）。本工程的源走 HTTP，`init` 挂在每组
  /// filter 上，所以这里补一个可选字段把它带过来，供首页内联筛选面板
  /// 判断默认高亮。可选具名参数，不改变任何既有调用点。
  final String init;

  FilterGroup({
    required this.key,
    required this.name,
    required this.values,
    this.init = '',
  });
}

class FilterValue {
  final String n;
  final String v;
  FilterValue({required this.n, required this.v});
}

/// 首页内容
class HomeContent {
  final List<VodClass> classes;
  final List<Vod> list;
  final Map<String, dynamic>? filterMap;
  HomeContent({required this.classes, required this.list, this.filterMap});
}

/// 分类页内容
class CategoryContent {
  final List<Vod> list;
  final int page;
  final int pageCount;
  final int limit;
  final int total;
  CategoryContent({
    required this.list,
    required this.page,
    required this.pageCount,
    required this.limit,
    required this.total,
  });

  bool get hasMore => page < pageCount;
}

int _int(Object? v, int fallback) {
  if (v == null) return fallback;
  if (v is int) return v;
  return int.tryParse(v.toString()) ?? fallback;
}

bool _bool(Object? v, bool fallback) {
  if (v == null) return fallback;
  if (v is bool) return v;
  final s = v.toString();
  if (s == '1' || s.toLowerCase() == 'true') return true;
  if (s == '0' || s.toLowerCase() == 'false') return false;
  return fallback;
}

double _double(Object? v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}
