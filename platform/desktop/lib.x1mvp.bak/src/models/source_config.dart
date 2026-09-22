/// 用户添加的源（订阅）。**不内置任何源** —— 首次启动列表为空，
/// 必须由用户手工填入源地址。
library;

import 'dart:convert';

class SourceConfig {
  /// 稳定 id（源地址的哈希）。
  final String id;
  /// 用户填入的源地址，形如 `http://user:pass@host/index.js.md5`
  final String url;
  /// 用户可编辑的备注名。
  final String name;
  /// 本地已缓存正文的 MD5；null 表示尚未拉取。
  final String? cachedMd5;
  /// 缓存最后更新时间。
  final DateTime? updatedAt;
  /// 最近一次错误（用于 UI 展示）。
  final String? lastError;

  const SourceConfig({
    required this.id,
    required this.url,
    required this.name,
    this.cachedMd5,
    this.updatedAt,
    this.lastError,
  });

  SourceConfig copyWith({
    String? name,
    String? cachedMd5,
    DateTime? updatedAt,
    String? lastError,
    bool clearError = false,
  }) =>
      SourceConfig(
        id: id,
        url: url,
        name: name ?? this.name,
        cachedMd5: cachedMd5 ?? this.cachedMd5,
        updatedAt: updatedAt ?? this.updatedAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'name': name,
        if (cachedMd5 != null) 'cachedMd5': cachedMd5,
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (lastError != null) 'lastError': lastError,
      };

  factory SourceConfig.fromJson(Map<String, dynamic> j) => SourceConfig(
        id: '${j['id']}',
        url: '${j['url']}',
        name: '${j['name'] ?? ''}',
        cachedMd5: j['cachedMd5'] as String?,
        updatedAt: j['updatedAt'] == null
            ? null
            : DateTime.tryParse('${j['updatedAt']}'),
        lastError: j['lastError'] as String?,
      );

  static List<SourceConfig> decodeList(String raw) {
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((e) => SourceConfig.fromJson(e.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String encodeList(List<SourceConfig> list) =>
      jsonEncode(list.map((e) => e.toJson()).toList());
}

/// 生成稳定 id：对 url 做简单 FNV-1a 哈希（不引入额外依赖）。
String sourceIdOf(String url) {
  var hash = 0x811c9dc5;
  for (final unit in url.trim().codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
