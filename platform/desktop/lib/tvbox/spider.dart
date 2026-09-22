import 'dart:convert';

import 'models.dart';

/// 源侧业务异常。
///
/// 与 PeekPili 原版的同名类型保持完全一致的对外形状（`message` +
/// `toString()` 直接返回 message），因为 [friendlyError] 与播放页都靠它
/// 区分「业务提示」与「技术异常」。
///
/// 本工程的来源是 `SourceError(statusCode, message)` —— 源服务把网盘未登录
/// 这类业务错误编码成 `HTTP 500 + {"message":"还没有配置夸克 Cookie…"}`，
/// 适配层会把它转成这里的 [SpiderException]，UI 照原样展示。
class SpiderException implements Exception {
  final String message;
  SpiderException(this.message);
  @override
  String toString() => message;
}

/// 一条播放地址 + 它的清晰度 / 音质标签。
///
/// 本工程对接的 `CatVodSpiderios` 的 `play` 返回 `url` 字段仍可能是
/// CatVod 的成对数组形态（`["1080P","http://…","720P","http://…"]`），
/// 所以保留原版的归一化逻辑，避免 `toString()` 出
/// `[1080P, http://…]` 这种喂给 `Media()` 必炸的字符串。
class PlayQuality {
  final String label;
  final String url;
  const PlayQuality(this.label, this.url);

  @override
  String toString() => label.isEmpty ? url : '$label $url';
}

/// 从 `url` 字段（String 或成对数组）里挑出真正可播的地址。
String pickPlayUrl(dynamic raw) {
  if (raw == null) return '';
  if (raw is String) return raw.trim();
  if (raw is List) {
    final items = <String>[
      for (final e in raw)
        if (e != null) e.toString().trim(),
    ].where((e) => e.isNotEmpty).toList();
    for (final s in items) {
      if (s.startsWith('http://') || s.startsWith('https://')) return s;
    }
    return items.isEmpty ? '' : items.first;
  }
  return raw.toString().trim();
}

/// 解析成对数组形态的清晰度列表；单地址时返回长度为 1 的列表。
List<PlayQuality> parseQualities(dynamic raw) {
  if (raw is List) {
    final items = <String>[
      for (final e in raw)
        if (e != null) e.toString().trim(),
    ].where((e) => e.isNotEmpty).toList();
    if (items.length.isEven && items.length >= 2) {
      final out = <PlayQuality>[];
      var paired = true;
      for (var i = 0; i < items.length; i += 2) {
        if (!_looksLikeUrl(items[i + 1])) {
          paired = false;
          break;
        }
        out.add(PlayQuality(items[i], items[i + 1]));
      }
      if (paired) return out;
    }
    return [for (final s in items) PlayQuality('', s)];
  }
  final one = pickPlayUrl(raw);
  return one.isEmpty ? const <PlayQuality>[] : [PlayQuality('', one)];
}

bool _looksLikeUrl(String s) =>
    s.startsWith('http://') ||
    s.startsWith('https://') ||
    s.startsWith('rtmp://') ||
    s.startsWith('rtsp://');

/// `play` 的归一化结果 —— 与 PeekPili 原版字段名逐一对齐，
/// 因此播放页/详情页一行都不用改。
class PlayResult {
  final String url;

  /// 全部清晰度 / 音质（单地址时只有一条）。
  final List<PlayQuality> qualities;

  final String? parse;
  final Map<String, String>? header;
  final String? playUrl;

  /// 取不到播放地址时源给出的业务提示（如网盘 Cookie 未配置）。
  /// 原版会把这句话直接呈现给用户，而不是笼统地说「未获取到播放地址」。
  final String? msg;

  /// 弹幕地址（源若给出则直接用，否则走 [DanmakuSession] 的自动匹配）。
  final String? danmaku;

  PlayResult({
    required dynamic url,
    this.parse,
    this.header,
    this.playUrl,
    this.msg,
    this.danmaku,
  })  : qualities = parseQualities(url),
        url = pickPlayUrl(url);
}

/// 归一化 CatVod 的 `header` 字段（Map 或 JSON 字符串两种形态）。
Map<String, String>? parseHeaderField(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map) {
    if (raw.isEmpty) return null;
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
  if (raw is String) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    try {
      final j = jsonDecode(s);
      if (j is Map && j.isNotEmpty) {
        return j.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {
      // 不是 JSON 就当没有
    }
  }
  return null;
}

/// 统一给站点带上默认请求头。
Map<String, String> siteHeaders(Site site) => {
      'User-Agent': 'okhttp/5.0.0',
      'Accept': '*/*',
      'Connection': 'Keep-Alive',
      ...?site.header,
    };
