import 'dart:convert';

import 'storage.dart';

/// 网盘分享源识别。
///
/// ## 为什么需要这个
///
/// 源里有十几个「4K」站点，它们本身不托管视频，而是把**网盘分享链接**
/// 包装成播放地址（夸克 / 百度 / UC / 迅雷 / 115）。这类源要播放必须先在
/// 「配置中心」登录对应网盘账号 —— 也就是用户说的「需要登录的 4K 站点」。
///
/// 用户希望有一个开关：关掉时把这类源从搜索里屏蔽。
///
/// ## 为什么不能按站点名过滤
///
/// 直觉是「名字带 4K 就屏蔽」，但**实测推翻了这个假设**。名字带 4K 的源里
/// 有相当一部分是直链，完全不需要登录：
///
/// | 站点 | 名字 | 播放地址实际形态 | 需要登录 |
/// |---|---|---|---|
/// | `nodejs_wogg`   | 玩偶\|4K | 夸克网盘（base64 JSON） | 是 |
/// | `nodejs_muou`   | 木偶\|4K | 115 网盘（base64 JSON） | 是 |
/// | `nodejs_huajuan`| 花卷\|4K | 夸克网盘 | 是 |
/// | `nodejs_zhinan4k`| 原盘\|4K| 夸克网盘 | 是 |
/// | `nodejs_jutou`  | 剧透\|4K | 夸克网盘 | 是 |
/// | `nodejs_qwmkv`  | 七味\|4K | **直链** | 否 |
/// | `nodejs_libvio` | 立播\|4K | **直链** | 否 |
/// | `nodejs_woniu4k`| 蜗牛\|4K | **直链** | 否 |
///
/// 按名字过滤会把七味、立播、蜗牛这三个**能正常播**的源一起误伤。
///
/// ## 判定方法：看播放地址的结构
///
/// 网盘源的 `vod_play_url` 是 `base64(JSON)`，解出来形如：
/// ```json
/// {"providerId":"quark","shareId":"85b3f808c117","fileId":"36530f…",
///  "playToken":"…","quality":"…","mode":"…","name":"…"}
/// ```
/// 关键字段是 **`providerId`**。直链源的这一格是 `https://…m3u8` 或空，
/// base64 解码后不是合法 JSON，自然不会被误判。
///
/// ## 渐进式判定
///
/// 判定信息只在 `detail` 之后才有（搜索结果不带 `play_url`），所以判定
/// 必然是**渐进**的：某源第一次被解出网盘地址时记下来，**持久化**到本地。
/// 下次搜索就能提前把它排除，不必再等一次 detail。
///
/// 这与「搜索时就立刻排除」相比，代价是**首次遇到某个网盘源要漏一屏**；
/// 好处是**零误伤**——只有真实解出 `providerId` 的源才会被标记。
class NetdiskSources {
  static const _key = 'netdiskSiteKeys';

  /// 已知需要登录的网盘源 key 集合（持久化）。
  static Set<String> get known {
    final raw = Store.get<List<dynamic>>('$_key.list', const <dynamic>[]);
    return {for (final e in raw) e.toString()};
  }

  static bool isNetdisk(String siteKey) => known.contains(siteKey);

  static Future<void> mark(String siteKey) async {
    if (siteKey.isEmpty) return;
    final set = known..add(siteKey);
    await Store.set('$_key.list', set.toList());
  }

  /// 批量标记（一次 detail 可能同时确认多个源）。
  static Future<void> markAll(Iterable<String> siteKeys) async {
    final set = known..addAll(siteKeys.where((e) => e.isNotEmpty));
    await Store.set('$_key.list', set.toList());
  }

  /// 清空判定缓存（设置页「重新检测」用）。
  static Future<void> reset() async {
    await Store.set('$_key.list', const <String>[]);
  }

  /// 已知的网盘 provider 标识（源侧实测出现过的全集）。
  ///
  /// `quark` 夸克 / `baidu` 百度 / `uc` UC / `thunder` 迅雷 / `pan115` 115。
  static const providers = <String>{
    'quark',
    'baidu',
    'uc',
    'thunder',
    'pan115',
  };

  /// 从一段 `vod_play_url` 判断它是不是网盘分享地址。
  ///
  /// 返回识别到的 `providerId`；不是网盘则返回 `null`。
  ///
  /// `vod_play_url` 的结构是：
  /// ```text
  /// 剧集名$base64载荷#剧集名$base64载荷#…
  /// ```
  /// 即用 `#` 分集、用 `$` 分「显示名 / 地址」。这里只判定**第一条**即可
  /// —— 同一个源的所有剧集用的是同一种分发方式。
  static String? detectFromPlayUrl(String playUrl) {
    if (playUrl.isEmpty) return null;
    final first = playUrl.split('#').first;
    final seg = first.contains(r'$') ? first.split(r'$').last : first;
    final prov = _providerOf(seg);
    if (prov != null) return prov;
    // 有些源把整段（含 `#`）都当成一条，再兜底试一次整段。
    if (playUrl.contains('#')) return _providerOf(playUrl);
    return null;
  }

  static String? _providerOf(String seg) {
    var s = seg.trim();
    if (s.isEmpty) return null;
    // 补齐 base64 的 `=` 填充（源侧截断很常见）。
    s = s.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
    if (s.length < 8) return null;
    while (s.length % 4 != 0) {
      s += '=';
    }
    try {
      final txt = utf8.decode(base64.decode(s), allowMalformed: true);
      if (!txt.startsWith('{')) return null;
      final j = jsonDecode(txt);
      if (j is! Map) return null;
      final p = j['providerId']?.toString().toLowerCase() ?? '';
      if (p.isEmpty) return null;
      // 只认已知 provider；但若结构完全吻合也一并认（源侧将来可能加新盘）。
      if (providers.contains(p)) return p;
      // 有 providerId 且带网盘特征字段，视为网盘。
      if (j.containsKey('shareId') || j.containsKey('shareFidToken')) {
        return p;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
