import 'package:flutter/material.dart';

import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// 播放设置（原版设置第 3 项）。
/// 原版含：音乐模式、数据源模式（T4）、后台播放、全局迷你播放器。
class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  State<PlayerSettingsPage> createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  bool _bgPlay = Store.get<bool>('backgroundPlay', true);
  bool _miniPlayer = Store.get<bool>('miniPlayer', true);
  bool _musicMode = Store.get<bool>('musicMode', false);
  String _dataSource = Store.get<String>('dataSourceMode', 'T4');
  double _defaultSpeed = Store.get<double>('defaultSpeed', 1.0);
  bool _autoNext = Store.get<bool>('autoNextEpisode', true);

  // 本轮新增：对齐原版播放页交互的开关
  bool _skipTail = Store.get<bool>('skipTailEnabled', false);
  int _skipTailSec = Store.get<int>('skipTailSeconds', 90);
  double _longPressRate = Store.get<double>('longPressRate', 3.0);
  bool _autoChange = AutoChangeSourceConfig.load().enabled;

  Future<void> _set(String key, Object v) => Store.set(key, v);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const PeekPageHeader(title: '播放设置'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  const PeekSectionTitle('音乐模式'),
                  _switch(
                    icon: Icons.music_note_outlined,
                    title: '音乐模式',
                    subtitle: '以音频方式播放，锁屏与通知栏显示播放控制',
                    value: _musicMode,
                    onChanged: (v) {
                      setState(() => _musicMode = v);
                      _set('musicMode', v);
                    },
                  ),
                  PeekTile(
                    icon: Icons.cloud_outlined,
                    title: '数据源模式',
                    subtitle: _dataSource,
                    onTap: () async {
                      final v = await showModalBottomSheet<String>(
                        context: context,
                        backgroundColor: PeekColors.surfaceContainer,
                        builder: (ctx) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final s in ['T4', 'T3', '内置'])
                                ListTile(
                                  title: Text(s,
                                      style: const TextStyle(fontSize: 14)),
                                  trailing: s == _dataSource
                                      ? Icon(Icons.check,
                                          size: 18, color: PeekColors.primary)
                                      : null,
                                  onTap: () => Navigator.of(ctx).pop(s),
                                ),
                            ],
                          ),
                        ),
                      );
                      if (v != null) {
                        setState(() => _dataSource = v);
                        _set('dataSourceMode', v);
                      }
                    },
                  ),
                  const PeekSectionTitle('播放行为'),
                  _switch(
                    icon: Icons.picture_in_picture_alt_outlined,
                    title: '后台播放',
                    subtitle: '切到后台后继续播放音频',
                    value: _bgPlay,
                    onChanged: (v) {
                      setState(() => _bgPlay = v);
                      _set('backgroundPlay', v);
                    },
                  ),
                  _switch(
                    icon: Icons.smart_display_outlined,
                    title: '全局迷你播放器',
                    subtitle: '退出播放页后以悬浮窗形式继续播放',
                    value: _miniPlayer,
                    onChanged: (v) {
                      setState(() => _miniPlayer = v);
                      _set('miniPlayer', v);
                    },
                  ),
                  _switch(
                    icon: Icons.skip_next_outlined,
                    title: '自动连播',
                    subtitle: '一集播完自动播放下一集',
                    value: _autoNext,
                    onChanged: (v) {
                      setState(() => _autoNext = v);
                      _set('autoNextEpisode', v);
                    },
                  ),
                  PeekTile(
                    icon: Icons.speed,
                    title: '默认倍速',
                    subtitle: '${_defaultSpeed}x',
                    showDivider: false,
                    trailing: SizedBox(
                      width: 180,
                      child: Slider(
                        value: _defaultSpeed,
                        min: 0.5,
                        max: 2.0,
                        divisions: 6,
                        label: '${_defaultSpeed}x',
                        onChanged: (v) => setState(() => _defaultSpeed = v),
                        onChangeEnd: (v) => _set('defaultSpeed', v),
                      ),
                    ),
                  ),
                  const PeekSectionTitle('播放页交互'),
                  _switch(
                    icon: Icons.skip_next_outlined,
                    title: '跳过片尾',
                    subtitle: '片尾剩余 $_skipTailSec 秒时自动跳下一集',
                    value: _skipTail,
                    onChanged: (v) {
                      setState(() => _skipTail = v);
                      _set('skipTailEnabled', v);
                    },
                  ),
                  PeekTile(
                    icon: Icons.timer_outlined,
                    title: '片尾时长',
                    subtitle: '剩余 $_skipTailSec 秒时触发跳过',
                    trailing: SizedBox(
                      width: 180,
                      child: Slider(
                        value: _skipTailSec.toDouble(),
                        min: 30,
                        max: 180,
                        divisions: 10,
                        label: '$_skipTailSec 秒',
                        onChanged: (v) =>
                            setState(() => _skipTailSec = v.round()),
                        onChangeEnd: (v) => _set('skipTailSeconds', v.round()),
                      ),
                    ),
                  ),
                  PeekTile(
                    icon: Icons.fast_forward_outlined,
                    title: '长按倍速',
                    subtitle: '按住画面时以 ${_longPressRate}x 播放',
                    trailing: SizedBox(
                      width: 180,
                      child: Slider(
                        value: _longPressRate,
                        min: 1.5,
                        max: 5.0,
                        divisions: 7,
                        label: '${_longPressRate}x',
                        onChanged: (v) =>
                            setState(() => _longPressRate = v),
                        onChangeEnd: (v) => _set('longPressRate', v),
                      ),
                    ),
                  ),
                  _switch(
                    icon: Icons.swap_horiz,
                    title: '播放失败自动换源',
                    subtitle: '播放失败时用片名快搜其他站源并自动接管',
                    value: _autoChange,
                    onChanged: (v) {
                      setState(() => _autoChange = v);
                      // 走 AutoChangeSourceConfig，保留 maxAttempts/quickOnly
                      AutoChangeSourceConfig.save(
                        AutoChangeSourceConfig.load().copyWith(enabled: v),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switch({
    required IconData icon,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return PeekTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}
