import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/debug_log.dart';
import '../../core/http.dart';
import '../../core/storage.dart';
import '../../tvbox/backend_bridge.dart';
import 'danmaku_item.dart';
import 'danmaku_parser.dart';

/// 弹幕会话：全局单例，负责「取弹幕 → 解析 → 交给播放页渲染」。
///
/// ## 三个来源（优先级从高到低）
///
/// 1. **站源推送**（`messageToDart` 的 `danmuPush` action）
///    地址形如 `http://127.0.0.1:<nodePort>/danmu/manual?token=…`。
///    由 [push] 接收，可随时覆盖当前弹幕（原版「手动推送」）。
/// 2. **播放结果自带**（`PlayResult.danmaku`，DEX 源会给
///    `http://127.0.0.1:9978/proxy?do=wexautodanmu&t=…`）。
/// 3. **主动拉取**：`GET <Node服务>/danmu/auto?name=<片名>&episode=<集名>`
///    这是原版内置的弹幕 API（LogVar danmu_api，bundle 自带），
///    实测返回 **4 MB / 约 2 万条** 的 B 站格式 XML。
///
/// 第 3 条让弹幕**开箱即用**，不依赖用户在站源设置里打开
/// `autoDanmakuEnabled`（那才走第 1 条）。
class DanmakuSession {
  DanmakuSession._();

  /// 数据版本号：播放页监听它来刷新
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<DanmakuItem> _items = const <DanmakuItem>[];
  static List<DanmakuItem> get items => _items;

  /// 当前弹幕来源地址
  static String? sourceUrl;

  static bool loading = false;
  static String? error;

  /// 已加载 / 已尝试的 key，避免重复拉取
  static String? _loadedKey;

  static int get total => _items.length;

  /// 站源通过 `danmuPush` 推来的地址（手动推送，最高优先级）。
  static void push(String url) {
    if (url.trim().isEmpty) return;
    _loadedKey = 'push:$url';
    unawaited(_fetch(url, label: '推送'));
  }

  /// 起播时调用。三者按优先级择一。
  ///
  /// [directUrl] 非空时直接用它（来自 `PlayResult.danmaku`）；
  /// 否则用 Node 服务包的 `/danmu/auto`。
  static Future<void> load({
    required String title,
    required String episode,
    String? directUrl,
  }) async {
    if (!Store.get<bool>('danmakuEnabled', true)) {
      clear();
      return;
    }
    final name = title.trim();
    if (name.isEmpty) return;

    final direct = (directUrl ?? '').trim();
    if (direct.isNotEmpty) {
      final key = 'direct:$direct';
      if (key == _loadedKey) return;
      _loadedKey = key;
      await _fetch(direct, label: '源自带');
      return;
    }

    final base = SourceService.activeBase;
    if (base.isEmpty) {
      // Node 服务未就绪（DEX 源 / 未加载 Node 源）→ 没有弹幕来源
      if (_items.isNotEmpty) clear();
      return;
    }
    final key = 'auto:$name|$episode';
    if (key == _loadedKey) return;
    _loadedKey = key;

    final q = <String, String>{'name': name};
    if (episode.trim().isNotEmpty) q['episode'] = episode.trim();
    final url = Uri.parse('$base/danmu/auto').replace(queryParameters: q).toString();
    await _fetch(url, label: '自动');
  }

  static Future<void> _fetch(String url, {required String label}) async {
    loading = true;
    error = null;
    revision.value++;
    final sw = Stopwatch()..start();
    try {
      final raw = await Http.getText(url).timeout(const Duration(seconds: 40));
      if (raw.trim().isEmpty) {
        _items = const <DanmakuItem>[];
        error = '弹幕为空';
      } else {
        _items = await _parse(raw);
      }
      sourceUrl = url;
      if (Store.logEnabled) {
        DebugLog.add(
          '弹幕',
          '$label 载入 ${_items.length} 条（${raw.length} 字符，${sw.elapsedMilliseconds}ms）',
        );
      }
    } catch (e) {
      _items = const <DanmakuItem>[];
      error = '$e';
      if (Store.logEnabled) DebugLog.add('弹幕', '$label 载入失败: $e');
    } finally {
      loading = false;
      sw.stop();
      revision.value++;
    }
  }

  /// 解析。4 MB / 4 万条实测同步只需 ~31 ms，但放 isolate 可避免
  /// 起播瞬间掉 2 帧；isolate 不可用时（个别受限平台）退回同步解析。
  static Future<List<DanmakuItem>> _parse(String raw) async {
    try {
      return await compute(DanmakuParser.parse, raw);
    } catch (e) {
      if (Store.logEnabled) DebugLog.add('弹幕', 'isolate 解析不可用，改同步: $e');
      return DanmakuParser.parse(raw);
    }
  }

  /// 清空（关闭弹幕 / 换集 / 退出播放页）
  static void clear() {
    _items = const <DanmakuItem>[];
    sourceUrl = null;
    error = null;
    loading = false;
    _loadedKey = null;
    revision.value++;
  }

  // ------------------------------------------------------------ 自检（实验室用）

  /// 弹幕搜索页（原版 `GET /danmusearch`，bundle 自带）
  static String? get searchPageUrl {
    final base = SourceService.activeBase;
    return base.isEmpty ? null : '$base/danmusearch';
  }

  /// 主动探测一次弹幕获取，返回人类可读摘要。
  ///
  /// 「实验室 → 本地弹幕服务 → 测试弹幕获取」用它，
  /// 好处是不依赖播放链路就能验证「Node 弹幕 API + 解析器」是否正常。
  static Future<String> probe({
    required String name,
    String episode = '',
  }) async {
    final base = SourceService.activeBase;
    if (base.isEmpty) return '本地 Node 服务未启动，无法获取弹幕。';

    final q = <String, String>{'name': name};
    if (episode.trim().isNotEmpty) q['episode'] = episode.trim();
    final url =
        Uri.parse('$base/danmu/auto').replace(queryParameters: q).toString();

    final sw = Stopwatch()..start();
    try {
      final raw = await Http.getText(url).timeout(const Duration(seconds: 40));
      final fetchMs = sw.elapsedMilliseconds;
      if (raw.trim().isEmpty) return '接口返回空内容。\n$url';

      final parseSw = Stopwatch()..start();
      final list = DanmakuParser.parse(raw);
      parseSw.stop();
      sw.stop();
      if (list.isEmpty) {
        return '取到 ${raw.length} 字符但未解析出弹幕（可能该片无弹幕源）。\n$url';
      }
      final modes = <int, int>{};
      for (final d in list) {
        modes[d.mode] = (modes[d.mode] ?? 0) + 1;
      }
      final span = list.last.time;
      final head = list.take(3).map((d) => '· ${d.text}').join('\n');
      return '片名：$name${episode.isEmpty ? '' : ' · $episode'}\n'
          '接口：$url\n'
          '原始：${raw.length} 字符\n'
          '条数：${list.length}\n'
          '耗时：取回 ${fetchMs}ms / 解析 ${parseSw.elapsedMilliseconds}ms\n'
          '时间跨度：0 ~ ${span.toStringAsFixed(0)}s\n'
          '模式分布：$modes\n'
          '样例：\n$head';
    } catch (e) {
      return '获取失败：$e\n$url';
    }
  }
}
