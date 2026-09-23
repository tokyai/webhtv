import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../tvbox/models.dart';
import '../../widgets/common.dart';

/// 自动换源配置 —— 对齐原版设置里的独立页面。
///
/// 原版形态：
///   顶部说明 + `全选 / 全不选 / 刷新` 三个按钮
///   下面逐个站源的开关列表，每项带 **等级标签**（原版显示 `T3源`）与
///   `默认 开启/关闭` 状态文字。
///
/// 存储：站源级的开关落在本地 Hive（键 `autoChangeDisabledSources`），
/// 全局策略（enabled / 最多次数 / 仅快搜源）沿用 [AutoChangeSourceConfig]。
class AutoChangeSourcePage extends StatefulWidget {
  const AutoChangeSourcePage({super.key});

  @override
  State<AutoChangeSourcePage> createState() => _AutoChangeSourcePageState();
}

class _AutoChangeSourcePageState extends State<AutoChangeSourcePage> {
  late AutoChangeSourceConfig _cfg = AutoChangeSourceConfig.load();

  /// 被排除在自动换源之外的站源 key
  Set<String> get _disabled => Store.get<List>('autoChangeDisabledSources',
          const <String>[])
      .map((e) => e.toString())
      .toSet();

  Future<void> _setDisabled(Set<String> v) async {
    await Store.set('autoChangeDisabledSources', v.toList());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sites = context.watch<AppState>().sites;
    final disabled = _disabled;

    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const PeekPageHeader(title: '自动换源'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  // 顶部说明
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                    child: Text(
                      '播放失败时按下面的顺序依次尝试其它站源，'
                      '找到能播的就自动接管。关闭某个站源的开关后，'
                      '它不会被自动换源使用（手动搜索仍可用）。',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.7,
                          color: PeekColors.hint),
                    ),
                  ),

                  const PeekSectionTitle('全局策略'),
                  PeekTile(
                    icon: Icons.swap_horiz,
                    title: '启用自动换源',
                    subtitle: '播放失败时自动搜索并切换站源',
                    trailing: Switch(
                      value: _cfg.enabled,
                      onChanged: (v) async {
                        _cfg = _cfg.copyWith(enabled: v);
                        await AutoChangeSourceConfig.save(_cfg);
                        if (mounted) setState(() {});
                      },
                    ),
                    onTap: () async {
                      _cfg = _cfg.copyWith(enabled: !_cfg.enabled);
                      await AutoChangeSourceConfig.save(_cfg);
                      if (mounted) setState(() {});
                    },
                  ),
                  PeekTile(
                    icon: Icons.speed,
                    title: '仅使用快搜源',
                    subtitle: '只从标记了快搜的源里找，速度更快',
                    trailing: Switch(
                      value: _cfg.quickOnly,
                      onChanged: _cfg.enabled
                          ? (v) async {
                              _cfg = _cfg.copyWith(quickOnly: v);
                              await AutoChangeSourceConfig.save(_cfg);
                              if (mounted) setState(() {});
                            }
                          : null,
                    ),
                    onTap: _cfg.enabled
                        ? () async {
                            _cfg = _cfg.copyWith(quickOnly: !_cfg.quickOnly);
                            await AutoChangeSourceConfig.save(_cfg);
                            if (mounted) setState(() {});
                          }
                        : null,
                  ),
                  PeekTile(
                    icon: Icons.repeat,
                    title: '最多换源次数',
                    subtitle: '当前 ${_cfg.maxAttempts} 次',
                    trailing: SizedBox(
                      width: 150,
                      child: Slider(
                        value: _cfg.maxAttempts.toDouble(),
                        min: 1,
                        max: 8,
                        divisions: 7,
                        label: '${_cfg.maxAttempts}',
                        onChanged: _cfg.enabled
                            ? (v) async {
                                _cfg =
                                    _cfg.copyWith(maxAttempts: v.round());
                                await AutoChangeSourceConfig.save(_cfg);
                                if (mounted) setState(() {});
                              }
                            : null,
                      ),
                    ),
                  ),

                  // 全选 / 全不选 / 刷新
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 10, 4),
                    child: Row(
                      children: [
                        Text('参与换源的站源',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: PeekColors.onSurface)),
                        const SizedBox(width: 10),
                        Text('${sites.length - disabled.length}/${sites.length}',
                            style: TextStyle(
                                fontSize: 11.5, color: PeekColors.hint)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _setDisabled(<String>{}),
                          child: const Text('全选',
                              style: TextStyle(fontSize: 12)),
                        ),
                        TextButton(
                          onPressed: () =>
                              _setDisabled(sites.map((s) => s.key).toSet()),
                          child: const Text('全不选',
                              style: TextStyle(fontSize: 12)),
                        ),
                        IconButton(
                          tooltip: '刷新',
                          onPressed: () => setState(() {}),
                          icon: const Icon(Icons.refresh, size: 18),
                        ),
                      ],
                    ),
                  ),

                  if (sites.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: PeekEmpty(
                        icon: Icons.dns_outlined,
                        text: '还没有加载任何站源',
                      ),
                    )
                  else
                    for (final s in sites)
                      _siteTile(s, !disabled.contains(s.key), disabled),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _siteTile(Site s, bool on, Set<String> disabled) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13.5,
                      color:
                          on ? PeekColors.onSurface : PeekColors.railIdle),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // 等级标签（原版 `T3源`）
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: PeekColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(_tierOf(s),
                          style: TextStyle(
                              fontSize: 10, color: PeekColors.hint)),
                    ),
                    const SizedBox(width: 7),
                    Text('默认 开启',
                        style: TextStyle(
                            fontSize: 10.5, color: PeekColors.railIdle)),
                  ],
                ),
              ],
            ),
          ),
          Switch(
            value: on,
            onChanged: (v) {
              final next = {...disabled};
              if (v) {
                next.remove(s.key);
              } else {
                next.add(s.key);
              }
              _setDisabled(next);
            },
          ),
        ],
      ),
    );
  }

  /// 从站源类型/名称推导等级标签（原版显示形如 `T3源`）。
  String _tierOf(Site s) {
    if (s.name.contains('4K')) return 'T3源';
    if (s.name.contains('秒播')) return 'T4源';
    return 'T${s.type}源';
  }
}
