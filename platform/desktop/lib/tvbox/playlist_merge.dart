/// 「合并播放列表」。
///
/// ## 原版依据
///
/// 1. 首页 chips 行**第 1 个 Button**（`uiautomator dump` 原版语义树）：
///    ```
///    Button click=true [1724,149][1780,219] w=56 h=70
///      content-desc="合并播放列表（已关闭）"
///    ```
///    图标模板匹配 = `playlist_play_rounded`（0.8553；次名 `playlist_play` 仅
///    0.5440，`sort` 仅 0.0191 —— 完全不同的字形）。
/// 2. 原版字符串（AOT 快照，见 `.peekpili-analysis/orig_cjk.txt`）：
///    `合并播放列表（已开启）` / `合并播放列表（已关闭）` / `合并播放列表图标`
/// 3. 原版播放页语义树里出现独立的 **「合集」** 节点 —— 就是本开关打开后
///    播放源的名字。
///
/// ## 行为
///
/// 一个 TVBox 详情往往带多条线路（`vod_play_from` 用 `$$$` 分隔），而
/// **同一部剧在各线路里的剧集是重复的**（线路 A 有 1..40 集，线路 B 也有
/// 1..40 集）。默认按线路分开展示；开启本开关后合并成**一份**剧集列表，
/// 每集保留第一条能给出地址的线路，避免用户在多个几乎相同的列表里翻找。
///
/// ## 实测
///
/// 开关对**首页网格零影响**（原版开关前后首页截图
/// `ImageChops.difference().getbbox()` = `None`），所以它只作用于播放链路，
/// 不要把它接进首页数据流。
library;

import 'models.dart';

/// 合并后的播放源名称（原版播放页语义树里就是这两个字）。
const String kMergedLineName = '合集';

/// 把多条线路合并成一条「合集」线路。
///
/// * 去重键 = 归一化后的**剧集名**（去空白、去「第/集」这类包裹符号后小写）；
///   剧集名为空时退回 URL。
/// * 顺序 = **首次出现顺序**，不排序、不丢集。
/// * 每条剧集保留**第一条**非空 URL；后续重复集只记录来源线路，不覆盖地址。
/// * 只有 1 条线路时原样返回（此时「合并」是恒等变换，与原版「单线路无可见
///   变化」的实测一致）。
List<PlayLine> mergePlayLines(List<PlayLine> lines) {
  if (lines.length <= 1) return lines;

  final order = <String>[];
  final byKey = <String, _MergedEpisode>{};

  for (var li = 0; li < lines.length; li++) {
    final line = lines[li];
    for (final ep in line.episodes) {
      final key = _episodeKey(ep);
      if (key.isEmpty) continue;
      final hit = byKey[key];
      if (hit == null) {
        order.add(key);
        byKey[key] = _MergedEpisode(
          name: ep.name.isNotEmpty ? ep.name : ep.url,
          url: ep.url,
          lineName: line.name,
        );
      } else {
        if (hit.url.isEmpty && ep.url.isNotEmpty) {
          hit.url = ep.url;
          hit.lineName = line.name;
        }
        hit.dupLines.add(line.name);
      }
    }
  }

  // 所有线路都没有可用剧集时退回原样，避免把用户送进空列表。
  if (order.isEmpty) return lines;

  return <PlayLine>[
    PlayLine(
      name: kMergedLineName,
      episodes: <Episode>[
        for (final k in order)
          Episode(name: byKey[k]!.name, url: byKey[k]!.url),
      ],
    ),
  ];
}

/// 按开关状态决定要不要合并。
List<PlayLine> resolvePlayLines(List<PlayLine> lines, bool merge) =>
    merge ? mergePlayLines(lines) : lines;

/// 剧集去重键。
///
/// 原版各线路对同一集的命名并不统一（`第01集` / `01` / `S01E01` / `[1.9GB]S01E01.mkv`），
/// 所以先做一轮轻量归一化：去首尾空白、去体积前缀 `[xxx]`、去掉
/// `第`/`集`/`话`/`話` 这类包裹字，再统一小写。
String _episodeKey(Episode ep) {
  var s = ep.name.trim();
  if (s.isEmpty) return ep.url.trim();
  // 去掉「[1.9GB]」这类体积/清晰度前缀
  s = s.replaceAll(RegExp(r'^\[[^\]]*\]'), '');
  // 去掉「第」…「集/话/話」包裹
  s = s.replaceAll(RegExp(r'^第\s*'), '');
  s = s.replaceAll(RegExp(r'\s*[集话話]$'), '');
  s = s.trim().toLowerCase();
  return s;
}

class _MergedEpisode {
  final String name;
  String url;
  String lineName;

  /// 还有哪些线路也提供这一集（供 UI 提示「另有 N 条线路」）。
  final List<String> dupLines = <String>[];

  _MergedEpisode({
    required this.name,
    required this.url,
    required this.lineName,
  });
}
