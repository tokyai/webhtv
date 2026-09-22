/// 站点选择弹窗 —— 移植自 PeekPili `lib/pages/home/source_picker.dart`，
/// 数据源换成 WebHTV 源服务返回的站点清单（`SiteEntry`）。
library;

import 'package:flutter/material.dart';

import '../../services/source_client.dart';
import '../theme/peek_nav.dart';
import '../theme/peek_theme.dart';

/// 弹出站点选择器。返回用户选中的站点，取消返回 null。
Future<SiteEntry?> showSitePicker(
  BuildContext context, {
  required List<SiteEntry> sites,
  required String? currentKey,
}) {
  if (sites.isEmpty) {
    peekToast(context, '源未返回任何站点');
    return Future.value(null);
  }
  return showDialog<SiteEntry>(
    context: context,
    builder: (_) => _SitePickerDialog(sites: sites, currentKey: currentKey),
  );
}

class _SitePickerDialog extends StatefulWidget {
  const _SitePickerDialog({required this.sites, required this.currentKey});

  final List<SiteEntry> sites;
  final String? currentKey;

  @override
  State<_SitePickerDialog> createState() => _SitePickerDialogState();
}

class _SitePickerDialogState extends State<_SitePickerDialog> {
  String _kw = '';

  @override
  Widget build(BuildContext context) {
    final all = widget.sites;
    final list = _kw.isEmpty
        ? all
        : all
            .where((s) =>
                s.name.toLowerCase().contains(_kw.toLowerCase()) ||
                s.key.toLowerCase().contains(_kw.toLowerCase()))
            .toList();

    return Dialog(
      backgroundColor: PeekColors.surfaceContainer,
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 8, 8),
              child: Row(
                children: [
                  Text(
                    '选择站点',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: PeekColors.onSurface,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '共 ${all.length} 个',
                    style: TextStyle(fontSize: 12, color: PeekColors.hint),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: TextField(
                autofocus: true,
                style: const TextStyle(fontSize: 13.5),
                decoration: const InputDecoration(
                  hintText: '搜索站源名称或标识',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _kw = v.trim()),
              ),
            ),
            Flexible(
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(30),
                      child: Text(
                        '没有匹配「$_kw」的站点',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: PeekColors.hint),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 10),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final s = list[i];
                        final active = s.key == widget.currentKey;
                        return ListTile(
                          dense: true,
                          leading: Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: active
                                  ? PeekColors.railSelected
                                  : PeekColors.iconTile,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Text(
                              s.shortName.isEmpty
                                  ? '?'
                                  : s.shortName.characters.first,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? PeekColors.primary
                                    : PeekColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          title: Text(
                            s.shortName,
                            style: TextStyle(
                              fontSize: 14,
                              color: active
                                  ? PeekColors.primary
                                  : PeekColors.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            _subtitleOf(s),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: PeekColors.hint),
                          ),
                          trailing: active
                              ? Icon(Icons.check, size: 18, color: PeekColors.primary)
                              : null,
                          onTap: () => Navigator.pop(context, s),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String _subtitleOf(SiteEntry s) {
    final parts = <String>[];
    if (s.subtitle.isNotEmpty) parts.add(s.subtitle);
    parts.add(s.key);
    if (!s.searchable) parts.add('不可搜索');
    return parts.join('  ·  ');
  }
}
