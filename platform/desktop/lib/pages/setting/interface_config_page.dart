import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/source_config.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 点播接口管理（WebHTV 设置页第 1 项「点播」的落点）。
///
/// ## 为什么不叫「接口配置」
///
/// WebHTV 安卓端点「点播」弹 `ConfigDialog.create().vod()`，里面是**接口列表**
/// （`VodConfig` 的多条接口 + 当前选中项）。本工程的等价结构是
/// 「源列表 + 一个激活源」，所以这个页就是**源管理**：
/// 添加 / 编辑 / 删除 / 切换 / 刷新 / 查看运行状态。
///
/// ## 硬约束：不内置任何源
/// 首次启动为空态；用户必须自己粘一个 `.md5` 指针地址（例如
/// `http://user:pass@host/index.js.md5`）。「推荐源」弹层里的条目只是**快捷填充**，
/// 点一下才写入列表，不存在预置数据。
class InterfaceConfigPage extends StatefulWidget {
  const InterfaceConfigPage({super.key});

  /// 快捷填充用的候选地址（点一下才添加，不是内置源）。
  ///
  /// 全部是 `index.js.md5` 形式的 **CatVod Node 服务包**：桌面端由随包 Node
  /// 运行时派生子进程执行。安卓端的 DEX 加固来源（`csp_*`）在这里没有意义，
  /// 因此不列出。
  static const recommended = <(String name, String url)>[
    (
      '原版实机接口（Node 服务包）',
      'http://wexfnw:wexfnw@cat.xn--4kq62z5rby2qupq9ub.top/index.js.md5',
    ),
    ('牛二猫源（Node 服务包）', 'https://9280.kstore.vip/cat/index.js.md5'),
  ];

  @override
  State<InterfaceConfigPage> createState() => _InterfaceConfigPageState();
}

class _InterfaceConfigPageState extends State<InterfaceConfigPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sources = app.sourceConfigs;
    final activeId = app.activeId;

    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            PeekPageHeader(
              title: '点播',
              actions: [
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                IconButton(
                  tooltip: '快捷填充',
                  onPressed: _busy ? null : _showRecommended,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 20),
                ),
                IconButton(
                  tooltip: '添加接口',
                  onPressed: _busy ? null : () => _edit(),
                  icon: const Icon(Icons.add, size: 20),
                ),
              ],
            ),

            // 运行状态条
            Container(
              margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PeekColors.surfaceContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    app.serviceReady
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    size: 16,
                    color: app.serviceReady ? PeekColors.ok : PeekColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      app.serviceReady
                          ? '源服务已就绪（${app.serviceBaseUrl}）· '
                              '${app.sites.length} 个站源'
                          : (app.hasSources ? '源服务未启动' : '尚未添加任何接口'),
                      style: TextStyle(
                          fontSize: 12, color: PeekColors.onSurfaceVariant),
                    ),
                  ),
                  if (app.hasSources)
                    TextButton(
                      onPressed: _busy ? null : _refresh,
                      child: const Text('刷新', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),

            if (app.lastServiceError != null || app.nodeSourceError != null)
              _ErrorCard(
                text: app.lastServiceError ?? app.nodeSourceError ?? '',
              ),

            if (sources.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '还没有接口。\n\n'
                          '点击右上角「+」粘贴一个 .md5 指针地址，\n'
                          '例如 http://user:pass@host/index.js.md5',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.8,
                            color: PeekColors.hint,
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: () => _edit(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加接口'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: sources.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    indent: 18,
                    color: PeekColors.cardBorder,
                  ),
                  itemBuilder: (_, i) {
                    final s = sources[i];
                    final active = s.id == activeId;
                    return ListTile(
                      onTap: _busy ? null : () => _activate(s, active),
                      leading: Icon(
                        active
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: active ? PeekColors.primary : PeekColors.railIdle,
                      ),
                      title: Text(
                        s.name,
                        style: TextStyle(
                          fontSize: 14,
                          color: active ? PeekColors.primary : PeekColors.onSurface,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 2),
                          Text(
                            s.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11.5, color: PeekColors.hint),
                          ),
                          if (s.lastError != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              s.lastError!,
                              style: TextStyle(
                                  fontSize: 11, color: PeekColors.error),
                            ),
                          ],
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: '重命名',
                            onPressed: () => _rename(s),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                          IconButton(
                            tooltip: '删除',
                            onPressed: () => _remove(s),
                            icon: const Icon(Icons.delete_outline, size: 18),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 动作
  // ---------------------------------------------------------------------------

  Future<void> _showRecommended() async {
    final app = context.read<AppState>();
    final pick = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: PeekColors.surfaceContainerHigh,
        title: Text('快捷填充', style: TextStyle(
            fontSize: 15, color: PeekColors.onSurface)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              '这些都是 index.js.md5 形式的 CatVod Node 服务包，'
              '桌面端由随包 Node 运行时派生子进程执行。\n'
              '点一下只是**填入地址**，仍会在下一步由你确认。',
              style: TextStyle(fontSize: 11.5, color: PeekColors.hint),
            ),
          ),
          for (final r in InterfaceConfigPage.recommended)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(r),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.$1,
                      style: TextStyle(
                          fontSize: 13.5, color: PeekColors.onSurface)),
                  const SizedBox(height: 2),
                  Text(r.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: PeekColors.hint)),
                ],
              ),
            ),
        ],
      ),
    );
    if (pick == null || !mounted) return;
    // 已存在则直接切换，否则带着预填地址进编辑框
    final exist = app.sourceConfigs.where((s) => s.url == pick.$2).firstOrNull;
    if (exist != null) {
      await _activate(exist, exist.id == app.activeId);
      return;
    }
    await _edit(prefillName: pick.$1, prefillUrl: pick.$2);
  }

  Future<void> _edit({SourceConfig? source, String? prefillName, String? prefillUrl}) async {
    final nameCtrl =
        TextEditingController(text: source?.name ?? prefillName ?? '');
    final urlCtrl = TextEditingController(text: source?.url ?? prefillUrl ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PeekColors.surfaceContainerHigh,
        title: Text(source == null ? '添加接口' : '重命名接口',
            style: TextStyle(fontSize: 16, color: PeekColors.onSurface)),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(fontSize: 13, color: PeekColors.onSurface),
                decoration: const InputDecoration(
                  labelText: '接口名称',
                  hintText: '留空则按域名自动命名',
                ),
              ),
              if (source == null) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: urlCtrl,
                  maxLines: 3,
                  minLines: 1,
                  style: TextStyle(fontSize: 13, color: PeekColors.onSurface),
                  decoration: const InputDecoration(
                    labelText: '接口链接',
                    hintText: 'http://user:pass@host/index.js.md5',
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '只支持 .md5 指针地址：程序会先拉取该文件拿到真实 '
                    'md5，再下载源正文并校验。',
                    style: TextStyle(fontSize: 11, color: PeekColors.hint),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final app = context.read<AppState>();
    final name = nameCtrl.text.trim();

    if (source != null) {
      await app.renameSource(source.id, name.isEmpty ? source.name : name);
      if (mounted) peekToast(context, '已重命名');
      return;
    }

    final url = urlCtrl.text.trim();
    if (url.isEmpty) {
      peekToast(context, '接口链接不能为空');
      return;
    }

    setState(() => _busy = true);
    final err = await app.addSource(url, displayName: name.isEmpty ? null : name);
    if (!mounted) return;
    setState(() => _busy = false);
    peekToast(
      context,
      err ?? '已添加并切换到该接口，共 ${app.sites.length} 个站源',
    );
  }

  Future<void> _activate(SourceConfig s, bool alreadyActive) async {
    if (alreadyActive) return;
    setState(() => _busy = true);
    final app = context.read<AppState>();
    await app.setActive(s.id);
    if (!mounted) return;
    setState(() => _busy = false);
    peekToast(
      context,
      app.serviceReady
          ? '已切换到「${s.name}」，共 ${app.sites.length} 个站源'
          : '已切换到「${s.name}」，但源服务未就绪',
    );
  }

  Future<void> _rename(SourceConfig s) => _edit(source: s);

  Future<void> _remove(SourceConfig s) async {
    final ok = await peekConfirm(
      context,
      '删除接口',
      '确定删除「${s.name}」吗？已下载的源文件会一并清理。',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    await context.read<AppState>().removeSource(s.id);
    if (!mounted) return;
    setState(() => _busy = false);
    peekToast(context, '已删除');
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await context.read<AppState>().refreshConfig();
    if (!mounted) return;
    setState(() => _busy = false);
    final app = context.read<AppState>();
    peekToast(
      context,
      app.activeSource?.lastError ?? '已刷新，共 ${app.sites.length} 个站源',
    );
  }
}

/// 顶部错误提示卡。
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PeekColors.error.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PeekColors.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: PeekColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 11.5, color: PeekColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
