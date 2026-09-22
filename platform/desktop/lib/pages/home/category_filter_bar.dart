import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../tvbox/models.dart';

/// 分类筛选（原版「电影筛选 / 电视筛选」等分类的筛选条件弹层）。
/// 返回选中后的 extend 参数；取消返回 null。
Future<Map<String, String>?> showCategoryFilter(
  BuildContext context,
  VodClass cls,
  Map<String, String> current,
) {
  if (cls.filters.isEmpty) return Future.value(null);
  return showDialog<Map<String, String>>(
    context: context,
    builder: (_) => _FilterDialog(cls: cls, current: current),
  );
}

class _FilterDialog extends StatefulWidget {
  final VodClass cls;
  final Map<String, String> current;
  const _FilterDialog({required this.cls, required this.current});

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late Map<String, String> _sel;

  @override
  void initState() {
    super.initState();
    _sel = Map<String, String>.from(widget.current);
    for (final g in widget.cls.filters) {
      _sel.putIfAbsent(g.key, () => '');
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
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 6),
              child: Row(
                children: [
                  Text('${widget.cls.typeName} · 筛选',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: PeekColors.onSurface)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        for (final g in widget.cls.filters) {
                          _sel[g.key] = '';
                        }
                      });
                    },
                    child: const Text('重置', style: TextStyle(fontSize: 13)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                children: [
                  for (final g in widget.cls.filters) _group(g),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(_sel),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(g.name,
                style: TextStyle(
                    fontSize: 13, color: PeekColors.onSurfaceVariant)),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final v in g.values)
                _chip(
                  label: v.n.isEmpty ? '全部' : v.n,
                  selected: (_sel[g.key] ?? '') == v.v,
                  onTap: () => setState(() => _sel[g.key] = v.v),
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
