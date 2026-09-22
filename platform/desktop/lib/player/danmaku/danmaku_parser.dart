import 'dart:convert';

import 'danmaku_item.dart';

/// 弹幕解析器：把站源返回的弹幕文本转成 [DanmakuItem] 列表。
///
/// 实测数据源（原版 Node 服务包的 `/danmu/auto`）：
/// ```
/// GET /danmu/auto?name=庆余年&episode=第01集
/// 200  application/xml  4,188,577 bytes   ← 约 2 万条
/// <?xml version="1.0" ?>
/// <i>
///     <d p="0.0,1,25,16777215,1751533608,0,0,17393824600">庆帝 x 14</d>
///     ...
/// </i>
/// ```
///
/// 也兼容 JSON 形态（部分弹幕 API 返回 `{"code":0,"data":[{...}]}`）。
///
/// ## 性能
///
/// 4 MB / 2 万条用单遍正则扫描 + 手写字段切分，实测在桌面端 < 400 ms。
/// 调用方应在 `compute()` / `Isolate` 里跑，避免卡住播放线程。
class DanmakuParser {
  /// `<d p="...">text</d>`；`[\s\S]` 覆盖正文里的换行
  static final RegExp _dTag = RegExp(r'<d\s+p="([^"]*)"\s*>([\s\S]*?)</d>');

  /// 入口：自动判别 XML / JSON。
  static List<DanmakuItem> parse(String raw) {
    if (raw.isEmpty) return const <DanmakuItem>[];
    final head = raw.length > 64 ? raw.substring(0, 64).trimLeft() : raw.trimLeft();
    if (head.startsWith('{') || head.startsWith('[')) return _parseJson(raw);
    return _parseXml(raw);
  }

  // ------------------------------------------------------------------- XML

  static List<DanmakuItem> _parseXml(String raw) {
    final out = <DanmakuItem>[];
    for (final m in _dTag.allMatches(raw)) {
      final it = _fromP(m.group(1)!, m.group(2)!);
      if (it != null) out.add(it);
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  static DanmakuItem? _fromP(String p, String textRaw) {
    // 无正文的弹幕（含自闭合 `<d p="..."/>`）不可渲染，直接丢弃
    final text = _unescape(textRaw).trim();
    if (text.isEmpty) return null;

    // p 是逗号分隔的八元组；至少要有「时间 + 模式」
    final c1 = p.indexOf(',');
    if (c1 < 0) return null;
    final time = double.tryParse(p.substring(0, c1));
    if (time == null || time.isNaN) return null;

    final c2 = p.indexOf(',', c1 + 1);
    final mode = c2 < 0
        ? 1
        : (int.tryParse(p.substring(c1 + 1, c2)) ?? 1);

    var size = 25;
    var color = 0xFFFFFF;
    if (c2 >= 0) {
      final c3 = p.indexOf(',', c2 + 1);
      if (c3 >= 0) {
        size = int.tryParse(p.substring(c2 + 1, c3)) ?? 25;
        final c4 = p.indexOf(',', c3 + 1);
        final colorStr = c4 < 0 ? p.substring(c3 + 1) : p.substring(c3 + 1, c4);
        color = int.tryParse(colorStr) ?? 0xFFFFFF;
      }
    }

    return DanmakuItem(
      time: time < 0 ? 0 : time,
      mode: mode,
      size: size <= 0 ? 25 : size,
      color: color,
      text: text,
    );
  }

  /// XML 实体还原。`&amp;` 必须**最后**处理，否则 `&amp;lt;` 会被二次解码。
  static String _unescape(String s) {
    if (!s.contains('&')) return s;
    return s
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
  }

  // ------------------------------------------------------------------ JSON

  static List<DanmakuItem> _parseJson(String raw) {
    Object? v;
    try {
      v = jsonDecode(raw);
    } catch (_) {
      return const <DanmakuItem>[];
    }
    final list = _pickList(v);
    if (list == null) return const <DanmakuItem>[];

    final out = <DanmakuItem>[];
    for (final e in list) {
      if (e is! Map) continue;
      final text = '${e['m'] ?? e['text'] ?? e['content'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      final t = _num(e['t'] ?? e['time'] ?? e['p']);
      if (t == null) continue;
      out.add(DanmakuItem(
        time: t,
        mode: (_num(e['mode'] ?? e['type']))?.toInt() ?? 1,
        size: (_num(e['size']))?.toInt() ?? 25,
        color: (_num(e['color']))?.toInt() ?? 0xFFFFFF,
        text: text,
      ));
    }
    out.sort((a, b) => a.time.compareTo(b.time));
    return out;
  }

  /// fongmi / 弹弹play 常见几种包裹：`{data:[...]}` / `{data:{comments:[...]}}` / `[...]`
  static List? _pickList(Object? v) {
    if (v is List) return v;
    if (v is! Map) return null;
    final d = v['data'] ?? v['comments'] ?? v['list'];
    if (d is List) return d;
    if (d is Map) {
      final c = d['comments'] ?? d['list'] ?? d['items'];
      if (c is List) return c;
    }
    return null;
  }

  /// 弹幕时间可能是 `12`、`12.5` 或 `"12.5"`，甚至 `"00:00:12.50"`
  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    final s = '$v'.trim();
    if (s.isEmpty) return null;
    final direct = double.tryParse(s);
    if (direct != null) return direct;
    // hh:mm:ss.ms / mm:ss.ms
    final parts = s.split(':');
    if (parts.length < 2) return null;
    var total = 0.0;
    for (final p in parts) {
      final n = double.tryParse(p);
      if (n == null) return null;
      total = total * 60 + n;
    }
    return total;
  }
}
