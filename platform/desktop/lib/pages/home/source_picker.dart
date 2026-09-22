import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_state.dart';
import '../../tvbox/models.dart';

/// 站源选择器（原版点击顶栏「源名|分类名」或「换源」图标弹出）。
/// 支持按名称搜索 —— 原版导入的接口可能含上百个站源。
Future<Site?> showSourcePicker(BuildContext context) async {
  final app = context.read<AppState>();
  if (!app.hasConfig) {
    peekToast(context, '尚未加载接口，请先在设置中配置接口');
    return null;
  }
  final selected = await showDialog<Site>(
    context: context,
    builder: (_) => const _SourcePickerDialog(),
  );
  if (selected != null && context.mounted) {
    await app.selectSite(selected);
  }
  return selected;
}

class _SourcePickerDialog extends StatefulWidget {
  const _SourcePickerDialog();

  @override
  State<_SourcePickerDialog> createState() => _SourcePickerDialogState();
}

class _SourcePickerDialogState extends State<_SourcePickerDialog> {
  final TextEditingController _ctrl = TextEditingController();
  String _kw = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final all = app.sites;
    final list = _kw.isEmpty
        ? all
        : all
            .where((s) =>
                s.name.toLowerCase().contains(_kw.toLowerCase()) ||
                s.key.toLowerCase().contains(_kw.toLowerCase()))
            .toList();
    final current = app.currentSite;

    return Dialog(
      backgroundColor: PeekColors.surfaceContainer,
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
              child: Row(
                children: [
                  Text('选择播放源',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: PeekColors.onSurface)),
                  const SizedBox(width: 8),
                  Text('共 ${all.length} 个',
                      style: TextStyle(
                          fontSize: 12, color: PeekColors.hint)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: TextField(
                controller: _ctrl,
                onChanged: (v) => setState(() => _kw = v),
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '搜索站源名称或标识',
                  prefixIcon: Icon(Icons.search, size: 18),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text('没有匹配的站源',
                          style: TextStyle(
                              fontSize: 13, color: PeekColors.hint)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final s = list[i];
                        final active = current?.key == s.key;
                        return ListTile(
                          dense: true,
                          onTap: () => Navigator.of(context).pop(s),
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
                              s.name.isEmpty ? '?' : s.name.characters.first,
                              style: TextStyle(
                                fontSize: 14,
                                color: active
                                    ? PeekColors.primary
                                    : PeekColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                          title: Text(
                            s.name,
                            style: TextStyle(
                              fontSize: 14,
                              color: active
                                  ? PeekColors.primary
                                  : PeekColors.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            'type=${s.type}  ${s.api}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: PeekColors.hint),
                          ),
                          trailing: active
                              ? Icon(Icons.check,
                                  size: 18, color: PeekColors.primary)
                              : null,
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
