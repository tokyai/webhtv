/// 数据模型 —— 与 CatVodSpiderios 源服务的 JSON 契约一一对应。
///
/// 契约来源见 `.workbuddy-ai/tmp/x1probe/API-CONTRACT.md`（实测）。
/// 所有 [fromJson] 都做宽松解析：字段缺失返回空串/null，绝不抛异常，
/// 因为不同站点的返回结构存在差异（实测 `nodejs_douban` 的 detail 就返回 `{}`）。
library;

import 'dart:convert';

/// 单个视频条目（home / category / search 的 list 元素）。
class VideoItem {
  final String vodId;
  final String vodName;
  final String vodPic;
  final String vodRemarks;

  const VideoItem({
    required this.vodId,
    required this.vodName,
    required this.vodPic,
    required this.vodRemarks,
  });

  factory VideoItem.fromJson(Map<String, dynamic> j) => VideoItem(
        vodId: _str(j['vod_id']),
        vodName: _str(j['vod_name']),
        vodPic: _str(j['vod_pic']),
        vodRemarks: _str(j['vod_remarks']),
      );
}

/// 分类项（`class[]`）。
class CategoryClass {
  final String typeId;
  final String typeName;

  const CategoryClass({required this.typeId, required this.typeName});

  factory CategoryClass.fromJson(Map<String, dynamic> j) => CategoryClass(
        typeId: _str(j['type_id']),
        typeName: _str(j['type_name']),
      );
}

/// 筛选组内的单个选项。
class FilterValue {
  final String name;
  final String value;

  const FilterValue({required this.name, required this.value});

  factory FilterValue.fromJson(Map<String, dynamic> j) => FilterValue(
        name: _str(j['n']),
        value: _str(j['v']),
      );
}

/// 筛选组（`filters[typeId][]`）。
class FilterGroup {
  final String key;
  final String name;
  final String init;
  final List<FilterValue> values;

  const FilterGroup({
    required this.key,
    required this.name,
    required this.init,
    required this.values,
  });

  factory FilterGroup.fromJson(Map<String, dynamic> j) => FilterGroup(
        key: _str(j['key']),
        name: _str(j['name']),
        init: _str(j['init']),
        values: _mapList(j['value'], FilterValue.fromJson),
      );
}

/// `POST <prefix>/home` 的返回。
class HomeContent {
  final List<CategoryClass> classes;
  final Map<String, List<FilterGroup>> filters;
  final List<VideoItem> list;

  const HomeContent({
    required this.classes,
    required this.filters,
    required this.list,
  });

  static const empty = HomeContent(classes: [], filters: {}, list: []);

  factory HomeContent.fromJson(Map<String, dynamic> j) {
    final rawFilters = j['filters'];
    final filters = <String, List<FilterGroup>>{};
    if (rawFilters is Map) {
      rawFilters.forEach((k, v) {
        filters['$k'] = _mapList(v, FilterGroup.fromJson);
      });
    }
    return HomeContent(
      classes: _mapList(j['class'], CategoryClass.fromJson),
      filters: filters,
      list: _mapList(j['list'], VideoItem.fromJson),
    );
  }
}

/// `POST <prefix>/category` 与 `/search` 的返回（同构）。
class PageResult {
  final int page;
  final int pageCount;
  final List<VideoItem> list;

  const PageResult({
    required this.page,
    required this.pageCount,
    required this.list,
  });

  static const empty = PageResult(page: 1, pageCount: 1, list: []);

  factory PageResult.fromJson(Map<String, dynamic> j) => PageResult(
        page: _int(j['page'], 1),
        pageCount: _int(j['pagecount'], 1),
        list: _mapList(j['list'], VideoItem.fromJson),
      );
}

/// `POST <prefix>/detail` 的单个条目。
class VideoDetail {
  final String vodId;
  final String vodName;
  final String vodPic;
  final String vodContent;
  final String vodRemarks;
  /// 线路名，多线路用 `$$$` 分隔。
  final String vodPlayFrom;
  /// 剧集列表，格式：`线路1剧集1$id1#线路1剧集2$id2$$$线路2…`
  final String vodPlayUrl;

  const VideoDetail({
    required this.vodId,
    required this.vodName,
    required this.vodPic,
    required this.vodContent,
    required this.vodRemarks,
    required this.vodPlayFrom,
    required this.vodPlayUrl,
  });

  factory VideoDetail.fromJson(Map<String, dynamic> j) => VideoDetail(
        vodId: _str(j['vod_id']),
        vodName: _str(j['vod_name']),
        vodPic: _str(j['vod_pic']),
        vodContent: _str(j['vod_content']),
        vodRemarks: _str(j['vod_remarks']),
        vodPlayFrom: _str(j['vod_play_from']),
        vodPlayUrl: _str(j['vod_play_url']),
      );

  /// 解析出的线路列表。
  ///
  /// `vod_play_from` 与 `vod_play_url` 都按 `$$$` 分段；段数不一致时以 url 段数为准。
  List<PlaySource> get sources {
    final names = vodPlayFrom.split(r'$$$');
    final urls = vodPlayUrl.split(r'$$$');
    final out = <PlaySource>[];
    for (var i = 0; i < urls.length; i++) {
      if (urls[i].trim().isEmpty) continue;
      out.add(PlaySource(
        name: i < names.length && names[i].trim().isNotEmpty
            ? names[i].trim()
            : '线路${i + 1}',
        episodes: _parseEpisodes(urls[i]),
      ));
    }
    return out;
  }

  /// 单段剧集字符串 → 剧集列表。格式 `剧集名$id`，多集用 `#` 分隔。
  static List<PlayEpisode> _parseEpisodes(String segment) {
    final out = <PlayEpisode>[];
    final parts = segment.split('#');
    for (var i = 0; i < parts.length; i++) {
      final p = parts[i].trim();
      if (p.isEmpty) continue;
      final idx = p.indexOf(r'$');
      final name = idx >= 0 ? p.substring(0, idx) : p;
      final id = idx >= 0 ? p.substring(idx + 1) : p;
      if (id.trim().isEmpty) continue;
      out.add(PlayEpisode(
        name: name.trim().isEmpty ? '第${i + 1}集' : name.trim(),
        id: id.trim(),
      ));
    }
    return out;
  }
}

/// 一条线路及其剧集。
class PlaySource {
  final String name;
  final List<PlayEpisode> episodes;

  const PlaySource({required this.name, required this.episodes});
}

/// 单集。
class PlayEpisode {
  final String name;
  final String id;

  const PlayEpisode({required this.name, required this.id});
}

/// `POST <prefix>/play` 的返回。
class PlayResult {
  /// 直链或需二次请求的地址。
  final String url;
  /// 播放请求头。
  final Map<String, String> header;
  /// 是否由客户端代理播放。
  final bool parse;

  const PlayResult({
    required this.url,
    required this.header,
    required this.parse,
  });

  static const empty = PlayResult(url: '', header: {}, parse: false);

  factory PlayResult.fromJson(Map<String, dynamic> j) {
    final h = <String, String>{};
    final raw = j['header'];
    if (raw is Map) {
      raw.forEach((k, v) => h['$k'] = '$v');
    } else if (raw is String && raw.trim().isNotEmpty) {
      // 部分站点把 header 塞成 JSON 字符串
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) decoded.forEach((k, v) => h['$k'] = '$v');
      } catch (_) {}
    }
    return PlayResult(
      url: _str(j['url']),
      header: h,
      parse: j['parse'] == 1 || j['parse'] == true,
    );
  }
}

/// 源服务自身的错误响应。
class SourceError implements Exception {
  final int statusCode;
  final String message;

  const SourceError(this.statusCode, this.message);

  @override
  String toString() => 'SourceError($statusCode): $message';
}

// ---------------------------------------------------------------------------
// 宽松解析工具
// ---------------------------------------------------------------------------

String _str(Object? v) => v == null ? '' : '$v';

int _int(Object? v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? fallback;
}

/// 把任意值当列表解析；元素非 Map 时跳过。
List<T> _mapList<T>(Object? v, T Function(Map<String, dynamic>) f) {
  if (v is! List) return const [];
  final out = <T>[];
  for (final e in v) {
    if (e is Map) {
      try {
        out.add(f(e.cast<String, dynamic>()));
      } catch (_) {
        // 单条解析失败不影响整页
      }
    }
  }
  return out;
}

