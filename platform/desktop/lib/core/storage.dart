import 'dart:convert';
import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// 本地存储层。
///
/// 盒子命名与 PeekPili 原版 1.2.5+2 的落盘结构保持一致：
///   setting / watchprogress / historyword / favorite / tvbox
///
/// 目录使用**本工程自己的**应用数据目录
/// （Windows 端 `%APPDATA%/webhtv_win/webhtv_win/hive/`），
/// 与 PeekPili 安装不共用 —— 两个独立程序写同一组 Hive 盒子会互相覆盖
/// 设置与收藏，因此刻意分开。
class Store {
  static const setting = 'setting';
  static const watchprogress = 'watchprogress';
  static const historyword = 'historyword';
  static const favorite = 'favorite';
  static const tvbox = 'tvbox';

  static late Box _setting;
  static late Box _progress;
  static late Box _historyword;
  static late Box _favorite;
  static late Box _tvbox;

  static Future<void> init() async {
    // 落盘位置（由 getApplicationSupportDirectory 决定）：
    //   Windows  %APPDATA%/webhtv_win/webhtv_win/hive
    final dir = await getApplicationSupportDirectory();
    final hiveDir = Directory('${dir.path}${Platform.pathSeparator}hive');
    if (!await hiveDir.exists()) {
      await hiveDir.create(recursive: true);
    }
    Hive.init(hiveDir.path);
    _setting = await Hive.openBox(setting);
    _progress = await Hive.openBox(watchprogress);
    _historyword = await Hive.openBox(historyword);
    _favorite = await Hive.openBox(favorite);
    _tvbox = await Hive.openBox(tvbox);
  }

  // ---------------- setting ----------------
  static T get<T>(String key, T fallback) {
    final v = _setting.get(key);
    if (v == null) return fallback;
    if (v is T) return v;
    if (T == bool) return (v.toString() == 'true') as T;
    if (T == int) return (int.tryParse(v.toString()) ?? fallback) as T;
    if (T == double) return (double.tryParse(v.toString()) ?? fallback) as T;
    if (T == String) return v.toString() as T;
    return fallback;
  }

  static Future<void> set(String key, Object? value) => _setting.put(key, value);
  static Box get settingBox => _setting;

  /// 调试日志开关（原版设置第 11 项）
  static bool get logEnabled => get<bool>('debugLogEnabled', false);

  // ---------------- 播放进度 ----------------
  /// key: sourceKey|vodId
  static Map<String, dynamic>? progressOf(String sourceKey, String vodId) {
    final raw = _progress.get('$sourceKey|$vodId');
    if (raw is String) {
      try {
        return jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  static Future<void> saveProgress(
    String sourceKey,
    String vodId,
    Map<String, dynamic> data,
  ) =>
      _progress.put('$sourceKey|$vodId', jsonEncode(data));

  static Future<void> clearProgress(String sourceKey, String vodId) =>
      _progress.delete('$sourceKey|$vodId');

  static List<Map<String, dynamic>> allProgress() {
    final out = <Map<String, dynamic>>[];
    for (final k in _progress.keys) {
      final raw = _progress.get(k);
      Map<String, dynamic>? m;
      if (raw is String) {
        try {
          m = jsonDecode(raw) as Map<String, dynamic>;
        } catch (_) {}
      } else if (raw is Map) {
        m = Map<String, dynamic>.from(raw);
      }
      if (m != null) {
        m['_key'] = k.toString();
        out.add(m);
      }
    }
    return out;
  }

  // ---------------- 收藏 ----------------
  static bool isFavorite(String key) => _favorite.containsKey(key);

  static Future<void> toggleFavorite(String key, Map<String, dynamic> data) async {
    if (_favorite.containsKey(key)) {
      await _favorite.delete(key);
    } else {
      await _favorite.put(key, jsonEncode(data));
    }
  }

  static List<Map<String, dynamic>> allFavorites() {
    final out = <Map<String, dynamic>>[];
    for (final k in _favorite.keys) {
      final raw = _favorite.get(k);
      if (raw is String) {
        try {
          final m = jsonDecode(raw) as Map<String, dynamic>;
          m['_key'] = k.toString();
          out.add(m);
        } catch (_) {}
      }
    }
    return out;
  }

  // ---------------- 搜索历史 ----------------
  static List<String> get searchHistory =>
      (_historyword.get('search') as List?)?.cast<String>() ?? <String>[];

  static Future<void> addSearchHistory(String kw) async {
    final list = searchHistory..remove(kw);
    list.insert(0, kw);
    if (list.length > 30) list.removeRange(30, list.length);
    await _historyword.put('search', list);
  }

  static Future<void> clearSearchHistory() => _historyword.delete('search');

  // ---------------- 聚合源配置 ----------------
  static String? get activeConfigUrl => _tvbox.get('activeConfigUrl') as String?;

  static Future<void> setActiveConfigUrl(String? url) =>
      url == null ? _tvbox.delete('activeConfigUrl') : _tvbox.put('activeConfigUrl', url);

  static List<String> get configHistory =>
      (_tvbox.get('configHistory') as List?)?.cast<String>() ?? <String>[];

  static Future<void> addConfigHistory(String url) async {
    final list = configHistory..remove(url);
    list.insert(0, url);
    if (list.length > 20) list.removeRange(20, list.length);
    await _tvbox.put('configHistory', list);
  }

  static String? get cachedConfig => _tvbox.get('cachedConfig') as String?;

  static Future<void> setCachedConfig(String json) => _tvbox.put('cachedConfig', json);

  static Future<void> clearCachedConfig() => _tvbox.delete('cachedConfig');

  static String? get selectedSourceKey => _tvbox.get('selectedSourceKey') as String?;

  static Future<void> setSelectedSourceKey(String? key) => key == null
      ? _tvbox.delete('selectedSourceKey')
      : _tvbox.put('selectedSourceKey', key);
}
