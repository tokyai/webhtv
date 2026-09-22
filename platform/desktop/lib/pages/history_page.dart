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

/// 观看历史（原版顶栏「历史」图标）。
/// 数据来自原版同名字段：episode_name / episode_index / play_position / total_duration / play_time
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
              title: '观看历史',
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
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 20),
                      itemCount: _list.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        indent: 122,
                        color: PeekColors.cardBorder,
                      ),
                      itemBuilder: (_, i) => _tile(_list[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> e) {
    final pos = int.tryParse('${e['play_position'] ?? 0}') ?? 0;
    final total = int.tryParse('${e['total_duration'] ?? 0}') ?? 0;
    final ratio = total > 0 ? (pos / total).clamp(0.0, 1.0) : 0.0;
    return InkWell(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 78,
                height: 106,
                child: (e['vod_pic']?.toString() ?? '').isEmpty
                    ? Container(color: PeekColors.card)
                    : CachedNetworkImage(
                        imageUrl: parsePicRef(e['vod_pic'].toString()).url,
                        httpHeaders:
                            parsePicRef(e['vod_pic'].toString()).header,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(color: PeekColors.card),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e['vod_name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14.5, color: PeekColors.onSurface),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '看到 ${e['episode_name'] ?? ''}',
                    style: TextStyle(
                        fontSize: 12, color: PeekColors.primary),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '${e['source_name'] ?? ''} · ${_fmtTime(e['play_time'])}',
                    style: TextStyle(fontSize: 11.5, color: PeekColors.hint),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 3,
                      backgroundColor: PeekColors.cardBorder,
                      color: PeekColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtTime(Object? ms) {
    final t = int.tryParse('${ms ?? 0}') ?? 0;
    if (t == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(t);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
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
