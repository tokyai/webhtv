/// 直播页。
///
/// ## 与安卓版的差异（重要）
/// 安卓 WebHTV 的直播走**独立的一套接口**：`LiveActivity` + `LiveFragment`
/// 消费 `m3u`/TXT 格式的 IPTV 播放列表（`liveUrl`），与点播站点（`csp_*`/
/// `nodejs_*`）完全分离。
///
/// 本源的 `CatVodSpiderios` **不提供 IPTV 列表接口**（`/config` 只有
/// `video/read/comic/music/pan`，没有 live 段）。因此桌面端无法凭空变出直播源，
/// 这里提供的是**手动导入 m3u/txt 播放列表**的入口 —— 与"不内置任何源"的
/// 总体约束一致：由用户自己提供直播源地址。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../theme/peek_theme.dart';
import '../widgets/peek_common.dart';
import '../widgets/player_sheet.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

/// 一个直播频道。
class LiveChannel {
  final String name;
  final String url;
  final String group;

  const LiveChannel({required this.name, required this.url, this.group = ''});
}

class _LivePageState extends State<LivePage> {
  List<LiveChannel> _channels = [];
  bool _loading = false;
  String? _error;
  String? _sourceUrl;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final url = context.read<AppState>().liveUrl;
    _sourceUrl = url;
    if (url != null && url.isNotEmpty) {
      await _load(url, silent: true);
    }
  }

  Future<void> _load(String url, {bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        throw Exception('HTTP ${r.statusCode}');
      }
      final text = utf8.decode(r.bodyBytes, allowMalformed: true);
      final list = _parse(text);
      if (!mounted) return;
      setState(() {
        _channels = list;
        _loading = false;
        _error = list.isEmpty ? '播放列表里没有解析到频道' : null;
        _sourceUrl = url;
      });
      await context.read<AppState>().setLiveUrl(url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// 同时支持 m3u (#EXTINF) 与 TXT（`分组,#genre#` + `频道名,地址`）两种格式。
  static List<LiveChannel> _parse(String text) {
    final out = <LiveChannel>[];
    final lines = text.split(RegExp(r'\r?\n'));
    String group = '';
    String pendingName = '';
    String pendingGroup = '';

    for (var raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF')) {
        // #EXTINF:-1 tvg-name="CCTV1" group-title="央视",CCTV-1 综合
        pendingGroup = _attr(line, 'group-title');
        final comma = line.lastIndexOf(',');
        pendingName =
            comma >= 0 ? line.substring(comma + 1).trim() : _attr(line, 'tvg-name');
        continue;
      }
      if (line.startsWith('#')) continue;

      if (line.contains('#genre#')) {
        group = line.split(',#genre#').first.trim();
        continue;
      }

      final comma = line.indexOf(',');
      if (comma < 0) continue;
      final name = line.substring(0, comma).trim();
      final url = line.substring(comma + 1).trim();
      if (url.isEmpty || !url.startsWith('http')) continue;

      out.add(LiveChannel(
        name: pendingName.isNotEmpty ? pendingName : name,
        url: url,
        group: pendingGroup.isNotEmpty ? pendingGroup : group,
      ));
      pendingName = '';
      pendingGroup = '';
    }
    return out;
  }

  static String _attr(String line, String key) {
    final m = RegExp('$key="([^"]*)"').firstMatch(line);
    return m?.group(1)?.trim() ?? '';
  }

  Future<void> _import() async {
    final ctrl = TextEditingController(text: _sourceUrl ?? '');
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入直播源'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '填入 m3u 或 txt 格式的 IPTV 播放列表地址。\n'
                '本应用不内置任何直播源，需由你自己提供。',
                style: TextStyle(fontSize: 12.5, color: PeekColors.hint, height: 1.6),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'http://example.com/live.m3u',
                  labelText: '播放列表地址',
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (url != null && url.trim().isNotEmpty && mounted) {
      await _load(url.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<LiveChannel>>{};
    for (final c in _channels) {
      grouped.putIfAbsent(c.group.isEmpty ? '未分组' : c.group, () => []).add(c);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '直播',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: PeekColors.onSurface,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  _channels.isEmpty ? '需自行导入播放列表' : '共 ${_channels.length} 个频道',
                  style: TextStyle(fontSize: 12, color: PeekColors.hint),
                ),
              ),
              const Spacer(),
              if (_sourceUrl != null && _channels.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: TextButton.icon(
                    onPressed: () => _load(_sourceUrl!),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('刷新', style: TextStyle(fontSize: 12.5)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 4),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 12.5),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onPressed: _import,
                  icon: const Icon(Icons.add_link, size: 16),
                  label: Text(_channels.isEmpty ? '导入直播源' : '更换直播源'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _body(grouped)),
      ],
    );
  }

  Widget _body(Map<String, List<LiveChannel>> grouped) {
    if (_loading) return const PeekLoading(text: '正在拉取播放列表…');
    if (_error != null && _channels.isEmpty) {
      return PeekEmpty(
        icon: Icons.cloud_off_outlined,
        text: '直播源加载失败\n$_error',
        selectable: true,
        actionText: '重新导入',
        onAction: _import,
      );
    }
    if (_channels.isEmpty) {
      return PeekEmpty(
        icon: Icons.live_tv_outlined,
        text: '还没有直播源\n\n'
            '安卓版的直播走独立的 IPTV 播放列表，与点播站点分离。\n'
            '本应用不内置直播源，请点右上角导入你自己的 m3u / txt 地址。',
        actionText: '导入直播源',
        onAction: _import,
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        for (final e in grouped.entries) ...[
          PeekSectionTitle(e.key),
          for (final c in e.value)
            PeekTile(
              icon: Icons.play_circle_outline,
              title: c.name,
              subtitle: c.url,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlayerSheet(
                    flag: '直播',
                    directUrl: c.url,
                    episodeName: c.name,
                    title: c.name,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
