/// 分类筛选弹窗 —— 移植自 PeekPili `lib/pages/home/category_filter_bar.dart`。
///
/// 交互：分组标签 + 药丸多选（每组单选，值 `''` 表示"全部"）→ 返回
/// `{groupKey: value}`。取消返回 null。
library;

import 'package:flutter/material.dart';

import '../../models/source_models.dart';
import '../theme/peek_theme.dart';

/// 弹出筛选面板。返回 null 表示用户取消。
Future<Map<String, String>?> showCategoryFilter(
  BuildContext context,
  String typeName,
  List<FilterGroup> groups,
  Map<String, String> current,
) async {
  if (groups.isEmpty) return null;
  return showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _FilterDialog(
      typeName: typeName,
      groups: groups,
      current: current,
    ),
  );
}

class _FilterDialog extends StatefulWidget {
  const _FilterDialog({
    required this.typeName,
    required this.groups,
    required this.current,
  });

  final String typeName;
  final List<FilterGroup> groups;
  final Map<String, String> current;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late Map<String, String> _sel;

  @override
  void initState() {
    super.initState();
    _sel = Map<String, String>.from(widget.current);
    // 未指定的分组按源给的 init 预置
    for (final g in widget.groups) {
      _sel.putIfAbsent(g.key, () => g.init);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: PeekColors.surfaceContainer,
      insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 8, 10),
              child: Row(
                children: [
                  Text(
                    '${widget.typeName} · 筛选',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: PeekColors.onSurface,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _sel = {};
                      for (final g in widget.groups) {
                        _sel[g.key] = g.init;
                      }
                    }),
                    child: const Text('重置', style: TextStyle(fontSize: 13)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                children: [
                  for (final g in widget.groups) _group(g),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    onPressed: () => Navigator.pop(context, _sel),
                    child: const Text('确定'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(FilterGroup g) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            g.name,
            style: TextStyle(fontSize: 13, color: PeekColors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              // 源本身就把「全部」作为首个取值返回，这里不再额外补一个
              for (final v in g.values)
                _chip(
                  label: v.name.isEmpty ? '全部' : v.name,
                  selected: (_sel[g.key] ?? '') == v.value,
                  onTap: () => setState(() => _sel[g.key] = v.value),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? PeekColors.primaryContainer
              : PeekColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            color: selected
                ? PeekColors.onPrimaryContainer
                : PeekColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
