/// 设置页 —— 布局移植自 PeekPili `lib/pages/setting/settings_page.dart`
/// （`PeekTile` 行列表），内容改为 WebHTV 桌面端实际具备的能力。
///
/// 与安卓版 `SettingFragment`（`menu_nav` 第二项）的对应：
/// 播放设置 / 弹幕设置 / 增强设置 → 桌面端收敛为「播放」「外观」两项，
/// 弹幕与增强依赖 Android 侧的解码与渲染管线，桌面端暂不提供。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../theme/peek_nav.dart';
import '../theme/peek_theme.dart';
import '../widgets/peek_common.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic>? _providers;
  bool _loadingProviders = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
          child: Text(
            '设置',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: PeekColors.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 6),

        PeekTile(
          icon: Icons.cloud_download_outlined,
          title: '接口配置',
          subtitle: state.sources.isEmpty
              ? '尚未添加任何源地址'
              : '已添加 ${state.sources.length} 个源 · 当前「${state.activeSource?.name ?? '无'}」',
          onTap: () => _showSourceInfo(context),
        ),
        PeekTile(
          icon: Icons.dns_outlined,
          title: '站点管理',
          subtitle: state.sites.isEmpty
              ? '源服务未返回站点清单'
              : '源共提供 ${state.sites.length} 个站点',
          onTap: () => _showSiteInfo(context),
        ),
        PeekTile(
          icon: Icons.play_circle_outline,
          title: '播放设置',
          subtitle: '播放器内核 libmpv · 直链与网盘链路',
          onTap: () => _showPlayerInfo(context),
        ),
        PeekTile(
          icon: Icons.palette_outlined,
          title: '外观',
          subtitle: '跟随系统深浅色 · PeekPili 视觉规范',
          onTap: () => _showAppearanceInfo(context),
        ),

        const PeekSectionTitle('网盘凭证'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text(
            '该源的播放链路依赖网盘账号（夸克 / 百度 / 115 等）。\n'
            '未登录时播放会提示"请先去配置中心登录"，这是源本身的业务提示。',
            style: TextStyle(fontSize: 12, color: PeekColors.hint, height: 1.6),
          ),
        ),
        if (_providers == null)
          PeekTile(
            icon: Icons.vpn_key_outlined,
            title: '凭证状态',
            subtitle: _loadingProviders ? '正在查询…' : '点击查询',
            trailing: _loadingProviders
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: _loadProviders,
          )
        else
          for (final e in _providers!.entries)
            PeekTile(
              icon: _isConfigured(e.value)
                  ? Icons.check_circle_outline
                  : Icons.cancel_outlined,
              title: _labelOf(e.key, e.value),
              subtitle: _isConfigured(e.value) ? '已配置' : '未配置',
              showDivider: false,
            ),

        const PeekSectionTitle('运行状态'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('服务地址', state.serviceBaseUrl ?? '未启动', mono: true),
              _kv('当前源', state.activeSource?.name ?? '无'),
              _kv('源地址', state.activeSource?.url ?? '—', selectable: true),
              _kv('站点数', '${state.sites.length}'),
              _kv('工作目录', state.activeWorkDir ?? '—', selectable: true),
              _kv('收藏 / 历史',
                  '${state.favorites.length} 部 / ${state.history.length} 条'),
            ],
          ),
        ),

        const PeekSectionTitle('故障诊断'),
        PeekTile(
          icon: Icons.download_outlined,
          title: '重新拉取源',
          subtitle: '按 .md5 指针重新下载并校验源正文',
          onTap: () async {
            final app = context.read<AppState>();
            peekToast(context, '正在重新拉取源…');
            await app.refreshActiveSource();
            if (!context.mounted) return;
            peekToast(
              context,
              app.phase == SourcePhase.error ? '拉取失败：${app.phaseMessage}' : '源已更新',
            );
          },
        ),
        PeekTile(
          icon: Icons.restart_alt,
          title: '重启源服务',
          subtitle: '在 127.0.0.1:9988 上重新启动 Node 服务',
          onTap: () async {
            final app = context.read<AppState>();
            await app.startActive();
            if (!context.mounted) return;
            peekToast(context, app.phaseMessage);
          },
        ),
        PeekTile(
          icon: Icons.stop_circle_outlined,
          title: '停止源服务',
          subtitle: '停止后所有站点内容不可用',
          onTap: () async {
            await context.read<AppState>().stopActive();
            if (!context.mounted) return;
            peekToast(context, '源服务已停止');
          },
        ),
        PeekTile(
          icon: Icons.folder_open_outlined,
          title: '打开工作目录',
          subtitle: state.activeWorkDir ?? '—',
          onTap: _openWorkDir,
        ),

        const PeekSectionTitle('调试日志'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: _LogView(lines: state.runtimeLog),
        ),
      ],
    );
  }

  static String _labelOf(String key, Object? data) {
    if (data is Map) {
      final m = data.cast<String, dynamic>();
      return '${m['label'] ?? key}';
    }
    return key;
  }

  static bool _isConfigured(Object? data) =>
      data is Map && data['configured'] == true;

  Widget _kv(String k, String v, {bool selectable = false, bool mono = false}) {
    final style = TextStyle(
      fontSize: 12.5,
      color: PeekColors.onSurface,
      fontFamily: mono ? 'Consolas' : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              k,
              style: TextStyle(fontSize: 12.5, color: PeekColors.hint),
            ),
          ),
          Expanded(
            child: selectable
                ? SelectableText(v, style: style)
                : Text(v, style: style),
          ),
        ],
      ),
    );
  }

  Future<void> _loadProviders() async {
    final state = context.read<AppState>();
    if (!state.serviceReady) {
      peekToast(context, '源服务未就绪');
      return;
    }
    setState(() => _loadingProviders = true);
    try {
      final url = state.serviceBaseUrl;
      if (url == null) return;
      final data = await _providerProbe(url);
      if (!mounted) return;
      setState(() {
        _providers = data;
        _loadingProviders = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingProviders = false);
    }
  }

  Future<Map<String, dynamic>> _providerProbe(String baseUrl) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse('$baseUrl/website/api/status'));
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final bytes = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map) {
        final data = decoded['data'];
        if (data is Map) {
          final providers = data['providers'];
          if (providers is Map) return providers.cast<String, dynamic>();
        }
      }
      return const {};
    } finally {
      client.close(force: true);
    }
  }

  void _openWorkDir() {
    final dir = context.read<AppState>().activeWorkDir;
    if (dir == null) {
      peekToast(context, '当前没有工作目录（源服务未启动）');
      return;
    }
    try {
      Process.run('explorer', [dir.replaceAll('/', r'\')]);
    } catch (_) {}
  }

  void _showSourceInfo(BuildContext context) {
    final app = context.read<AppState>();
    showDialog<void>(
      context: context,
      builder: (_) => _InfoDialog(
        title: '接口配置',
        body: app.sources.isEmpty
            ? '尚未添加任何源地址。\n\n请到左栏「源管理」添加。'
            : app.sources
                .map((s) =>
                    '${s.id == app.activeId ? '● ' : '○ '}${s.name}\n    ${s.url}'
                    '${s.lastError == null ? '' : '\n    ⚠ ${s.lastError}'}')
                .join('\n\n'),
      ),
    );
  }

  void _showSiteInfo(BuildContext context) {
    final app = context.read<AppState>();
    showDialog<void>(
      context: context,
      builder: (_) => _InfoDialog(
        title: '站点管理',
        body: app.sites.isEmpty
            ? '源服务未返回站点清单。\n\n请确认源服务已启动（左栏「站点」可查看）。'
            : app.sites
                .map((s) =>
                    '${s.key == app.currentSite?.key ? '● ' : '○ '}${s.shortName}'
                    '  [${s.key}]${s.searchable ? '  可搜索' : '  不可搜索'}')
                .join('\n'),
      ),
    );
  }

  void _showPlayerInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _InfoDialog(
        title: '播放设置',
        body: '播放器内核：libmpv（media_kit）\n'
            '支持直链、HLS、网盘转链。\n\n'
            '播放请求头由源服务的 play 接口返回，自动透传给播放器。\n'
            '直播播放走 IPTV 直链，不经过源解析。',
      ),
    );
  }

  void _showAppearanceInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => const _InfoDialog(
        title: '外观',
        body: '深色 / 浅色跟随 Windows 系统主题自动切换。\n\n'
            '视觉规范（配色、左栏宽度、海报列数、药丸尺寸）\n'
            '按 PeekPili 的像素级实测值实现。',
      ),
    );
  }
}

class _InfoDialog extends StatelessWidget {
  const _InfoDialog({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 480),
        child: SingleChildScrollView(
          child: SelectableText(
            body,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.7,
              color: PeekColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: PeekColors.surfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(10),
      child: lines.isEmpty
          ? Center(
              child: Text(
                '暂无日志',
                style: TextStyle(fontSize: 12, color: PeekColors.hint),
              ),
            )
          : ListView.builder(
              reverse: true,
              itemCount: lines.length,
              itemBuilder: (_, i) {
                final line = lines[lines.length - 1 - i];
                return SelectableText(
                  line,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Consolas',
                    height: 1.45,
                    color: PeekColors.onSurfaceVariant,
                  ),
                );
              },
            ),
    );
  }
}
