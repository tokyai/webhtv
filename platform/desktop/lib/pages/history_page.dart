import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../state/app_state.dart';
import '../tvbox/models.dart';
import '../widgets/common.dart';
import 'detail/detail_page.dart';

/// 播放历史（原版顶栏「记录」图标）。
///
/// 原版形态：**横向滚动的卡片行**，每条记录一张卡：
///   缩略图（左上角源标签角标、右上角 ✕ 删除）
///   ├ 缩略图底部进度条
///   相对时间（`3天前`）/ 剧名 / 集号
/// 右上角「清空」。
///
/// 数据来自原版同名字段：
/// episode_name / episode_index / play_position / total_duration / play_time
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late List<Map<String, dynamic>> _list;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _list = Store.allProgress()
      ..sort((a, b) => (int.tryParse('${b['play_time'] ?? 0}') ?? 0)
          .compareTo(int.tryParse('${a['play_time'] ?? 0}') ?? 0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            PeekPageHeader(
              title: '播放历史',
              actions: [
                if (_list.isNotEmpty)
                  TextButton.icon(
                    onPressed: () async {
                      final ok = await peekConfirm(
                          context, '清空历史', '确定清空全部观看记录吗？');
                      if (!ok) return;
                      for (final e in _list) {
                        final k = e['_key']?.toString() ?? '';
                        final parts = k.split('|');
                        if (parts.length == 2) {
                          await Store.clearProgress(parts[0], parts[1]);
                        }
                      }
                      setState(_reload);
                    },
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('清空', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            Expanded(
              child: _list.isEmpty
                  ? const PeekEmpty(
                      icon: Icons.history,
                      text: '还没有观看记录',
                    )
                  // 原版是一条横向卡片行；这里按行数（每行 N 张）铺成横向列表
                  : _cardRow(),
            ),
          ],
        ),
      ),
    );
  }

  /// 横向卡片行 —— 原版播放历史的观感。
  Widget _cardRow() {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
      itemCount: _list.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (_, i) => _card(_list[i]),
    );
  }

  Widget _card(Map<String, dynamic> e) {
    final pos = int.tryParse('${e['play_position'] ?? 0}') ?? 0;
    final total = int.tryParse('${e['total_duration'] ?? 0}') ?? 0;
    final ratio = total > 0 ? (pos / total).clamp(0.0, 1.0) : 0.0;
    final pic = parsePicRef(e['vod_pic']?.toString() ?? '');
    final srcName = e['source_name']?.toString() ?? '';
    final epName = e['episode_name']?.toString() ?? '';

    return SizedBox(
      width: 140,
      child: InkWell(
        onTap: () {
          final site = _resolveSite(e);
          if (site == null) {
            peekToast(context, '找不到该记录对应的站源，请先加载接口');
            return;
          }
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailPage(
                site: site,
                vodId: e['vod_id']?.toString() ?? '',
                preview: Vod(
                  id: e['vod_id']?.toString() ?? '',
                  name: e['vod_name']?.toString() ?? '',
                  pic: e['vod_pic']?.toString() ?? '',
                  remarks: e['vod_remarks']?.toString() ?? '',
                ),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 缩略图 + 源角标 + 删除 ✕ + 底部进度条
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 140,
                height: 84,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    pic.url.isEmpty
                        ? Container(color: PeekColors.card)
                        : CachedNetworkImage(
                            imageUrl: pic.url,
                            httpHeaders: pic.header,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                Container(color: PeekColors.card),
                          ),
                    // 左上：源标签
                    if (srcName.isNotEmpty)
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: const BorderRadius.only(
                              bottomRight: Radius.circular(6),
                            ),
                          ),
                          child: Text(
                            srcName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 9.5, color: Colors.white),
                          ),
                        ),
                      ),
                    // 右上：删除
                    Positioned(
                      right: 2,
                      top: 2,
                      child: InkWell(
                        onTap: () async {
                          final k = e['_key']?.toString() ?? '';
                          final parts = k.split('|');
                          if (parts.length == 2) {
                            await Store.clearProgress(parts[0], parts[1]);
                          }
                          if (mounted) setState(_reload);
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                    // 底部：进度条
                    if (ratio > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 3,
                          backgroundColor: Colors.black38,
                          color: PeekColors.primary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _relativeTime(e['play_time']),
              style: TextStyle(fontSize: 11, color: PeekColors.hint),
            ),
            const SizedBox(height: 3),
            Text(
              e['vod_name']?.toString() ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: PeekColors.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              epName.isEmpty ? '全集' : epName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11, color: PeekColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// 相对时间（原版 `3天前` / `11小时前`）。
  String _relativeTime(Object? ms) {
    final t = int.tryParse('${ms ?? 0}') ?? 0;
    if (t == 0) return '';
    final diff = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(t));
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30}个月前';
    return '${diff.inDays ~/ 365}年前';
  }

  Site? _resolveSite(Map<String, dynamic> e) {
    final app = context.read<AppState>();
    final key = e['source_key']?.toString() ?? '';
    for (final s in app.sites) {
      if (s.displayKey == key || s.key == key) return s;
    }
    final api = e['source_api']?.toString() ?? '';
    if (api.isEmpty) return null;
    return Site(
      key: key,
      name: e['source_name']?.toString() ?? key,
      type: int.tryParse('${e['source_type'] ?? 3}') ?? 3,
      api: api,
      raw: const {},
    );
  }
}
