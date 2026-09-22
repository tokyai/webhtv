/// 源管理页 —— 应用的入口。
///
/// **本地不内置任何源**：列表为空时展示引导，必须由用户手工填入源地址。
/// 布局沿用 PeekPili 的 `PeekTile` 行风格。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/source_config.dart';
import '../../state/app_state.dart';
import '../theme/peek_nav.dart';
import '../theme/peek_theme.dart';
import '../widgets/peek_common.dart';

class SourcePage extends StatelessWidget {
  const SourcePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sources = state.sources;

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
                '源管理',
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
                  sources.isEmpty ? '尚未添加任何源' : '共 ${sources.length} 个源',
                  style: TextStyle(fontSize: 12, color: PeekColors.hint),
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 3, left: 4),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 12.5),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onPressed: () => showAddSourceDialog(context),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加源'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (sources.isEmpty)
          Expanded(
            child: PeekEmpty(
              icon: Icons.cloud_download_outlined,
              text: '添加你的第一个源\n\n'
                  '本应用不内置任何播放源。\n'
                  '请填入你自己拥有的源地址，应用会下载并在本机运行它。',
              actionText: '添加源地址',
              onAction: () => showAddSourceDialog(context),
            ),
          )
        else ...[
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: sources.length,
              itemBuilder: (_, i) => _SourceTile(
                cfg: sources[i],
                active: sources[i].id == state.activeId,
                isBusy: state.phase == SourcePhase.fetching ||
                    state.phase == SourcePhase.launching,
                showDivider: i != sources.length - 1,
              ),
            ),
          ),
          if (state.phase == SourcePhase.error)
            _ErrorBanner(message: state.phaseMessage),
        ],
      ],
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.cfg,
    required this.active,
    required this.isBusy,
    required this.showDivider,
  });

  final SourceConfig cfg;
  final bool active;
  final bool isBusy;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();

    return PeekTile(
      icon: active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      title: cfg.name,
      subtitle: _subtitle(),
      showDivider: showDivider,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (active)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: PeekColors.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '当前',
                style: TextStyle(
                    fontSize: 10, color: PeekColors.onPrimaryContainer),
              ),
            )
          else
            TextButton(
              onPressed: isBusy ? null : () => state.setActive(cfg.id),
              child: const Text('启用', style: TextStyle(fontSize: 12.5)),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '重命名',
            icon: const Icon(Icons.edit_outlined, size: 17),
            onPressed: () => _showRenameDialog(context, cfg),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline, size: 17),
            onPressed: () => _confirmDelete(context, cfg),
          ),
        ],
      ),
      onTap: () {
        if (!active) state.setActive(cfg.id);
      },
    );
  }

  String _subtitle() {
    final parts = <String>[cfg.url];
    if (cfg.updatedAt != null) parts.add('更新于 ${_fmt(cfg.updatedAt!)}');
    if (cfg.cachedMd5 != null) {
      parts.add('md5 ${cfg.cachedMd5!.substring(0, 8)}…');
    }
    if (cfg.lastError != null) parts.add('⚠ ${cfg.lastError}');
    return parts.join('  ·  ');
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _showRenameDialog(BuildContext context, SourceConfig cfg) async {
    final state = context.read<AppState>();
    final controller = TextEditingController(text: cfg.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名源'),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '备注名',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await state.renameSource(cfg.id, name);
    }
  }

  Future<void> _confirmDelete(BuildContext context, SourceConfig cfg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除源'),
        content: Text('确定删除「${cfg.name}」？\n本机会同时移除已下载的源文件。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: PeekColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().removeSource(cfg.id);
    }
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: PeekColors.error.withValues(alpha: 0.14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: PeekColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(
              message,
              style: TextStyle(
                  fontSize: 12, color: PeekColors.error, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// 添加源对话框。对外暴露，便于空态按钮直接复用。
Future<void> showAddSourceDialog(BuildContext context) async {
  final urlCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();
  var submitting = false;
  String? error;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Future<void> submit() async {
          if (!(formKey.currentState?.validate() ?? false)) return;
          setLocal(() {
            submitting = true;
            error = null;
          });
          final state = ctx.read<AppState>();
          final err = await state.addSource(
            urlCtrl.text,
            displayName: nameCtrl.text,
          );
          if (!ctx.mounted) return;
          if (err == null) {
            Navigator.pop(ctx);
            peekToast(ctx, '源已添加并启动');
          } else {
            setLocal(() {
              submitting = false;
              error = err;
            });
          }
        }

        return AlertDialog(
          title: const Text('添加源'),
          content: SizedBox(
            width: 480,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: urlCtrl,
                    autofocus: true,
                    enabled: !submitting,
                    maxLines: 2,
                    minLines: 1,
                    decoration: const InputDecoration(
                      labelText: '源地址',
                      hintText: 'http://用户名:密码@主机/index.js.md5',
                      helperText: '应用会自动跟随重定向并校验 MD5',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final s = v?.trim() ?? '';
                      if (s.isEmpty) return '请填写源地址';
                      final u = Uri.tryParse(s);
                      if (u == null || !u.hasScheme || u.host.isEmpty) {
                        return '格式无效，需包含 http:// 或 https://';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: nameCtrl,
                    enabled: !submitting,
                    decoration: const InputDecoration(
                      labelText: '备注名（可选）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: PeekColors.error.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        error!,
                        style: TextStyle(fontSize: 12, color: PeekColors.error),
                      ),
                    ),
                  ],
                  if (submitting) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text('正在拉取并校验源…',
                            style: TextStyle(
                                fontSize: 12, color: PeekColors.hint)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: submitting ? null : submit,
              child: const Text('添加'),
            ),
          ],
        );
      },
    ),
  );
}
