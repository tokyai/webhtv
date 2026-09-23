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

  // 对齐原版播放设置清单的其余项
  String _playerEngine = Store.get<String>('playerEngine', 'MPV');
  bool _autoPlay = Store.get<bool>('autoPlay', true);
  bool _showCoverWhenLoading =
      Store.get<bool>('showCoverWhenLoading', true);
  bool _doubleTapSeek = Store.get<bool>('doubleTapSeek', true);
  bool _resumeToDetail = Store.get<bool>('resumeToDetail', true);
  bool _autoPip = Store.get<bool>('autoPip', false);
  bool _floatBall = Store.get<bool>('floatBall', true);
  bool _mergeIcon = Store.get<bool>('mergePlaylistIcon', true);
  bool _disableSsl = Store.get<bool>('disableSslVerify', false);
  String _headerStrategy = Store.get<String>('headerStrategy', '智能');
  String _pushMode = Store.get<String>('pushMode', '直链');

  /// 播放器内核选择（原版：MPV / MDK / Exo）
  Future<void> _pickPlayerEngine() async {
    const opts = ['MPV', 'MDK', 'Exo'];
    final v = await _pick('默认播放器', opts, _playerEngine);
    if (v == null) return;
    setState(() => _playerEngine = v);
    await _set('playerEngine', v);
  }

  /// 播放请求头策略（原版：智能 / 完整 / 最小）
  Future<void> _pickHeaderStrategy() async {
    const opts = ['智能', '完整', '最小'];
    final v = await _pick('播放请求头策略', opts, _headerStrategy);
    if (v == null) return;
    setState(() => _headerStrategy = v);
    await _set('headerStrategy', v);
  }

  /// 推送模式（原版：直链 / 解析 / 接口 / 磁力）
  Future<void> _pickPushMode() async {
    const opts = ['直链', '解析', '接口', '磁力'];
    final v = await _pick('推送模式', opts, _pushMode);
    if (v == null) return;
    setState(() => _pushMode = v);
    await _set('pushMode', v);
  }

  Future<String?> _pick(String title, List<String> opts, String cur) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: PeekColors.surfaceContainer,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: PeekColors.onSurface)),
              ),
            ),
            for (final o in opts)
              ListTile(
                dense: true,
                title: Text(o, style: const TextStyle(fontSize: 13.5)),
                trailing: o == cur
                    ? Icon(Icons.check, size: 18, color: PeekColors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(o),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

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

                  // ---------- 对齐原版播放设置的其余项 ----------
                  const PeekSectionTitle('播放行为'),
                  PeekTile(
                    icon: Icons.play_circle_outline,
                    title: '默认播放器',
                    subtitle: _playerEngine,
                    trailing: Icon(Icons.chevron_right,
                        size: 18, color: PeekColors.railIdle),
                    onTap: _pickPlayerEngine,
                  ),
                  _switch(
                    icon: Icons.play_arrow_outlined,
                    title: '自动播放',
                    subtitle: '进入播放页后自动起播，无需手动点播放',
                    value: _autoPlay,
                    onChanged: (v) {
                      setState(() => _autoPlay = v);
                      _set('autoPlay', v);
                    },
                  ),
                  _switch(
                    icon: Icons.image_outlined,
                    title: '加载时显示封面',
                    subtitle: '缓冲期间用影片封面占位，避免黑屏',
                    value: _showCoverWhenLoading,
                    onChanged: (v) {
                      setState(() => _showCoverWhenLoading = v);
                      _set('showCoverWhenLoading', v);
                    },
                  ),
                  _switch(
                    icon: Icons.fast_forward_outlined,
                    title: '双击快进快退',
                    subtitle: '暂停时点画面左/右半屏后退/前进 10 秒',
                    value: _doubleTapSeek,
                    onChanged: (v) {
                      setState(() => _doubleTapSeek = v);
                      _set('doubleTapSeek', v);
                    },
                  ),
                  _switch(
                    icon: Icons.playlist_play,
                    title: '续播详情页',
                    subtitle: '播放页返回时回到详情页而非直接退出',
                    value: _resumeToDetail,
                    onChanged: (v) {
                      setState(() => _resumeToDetail = v);
                      _set('resumeToDetail', v);
                    },
                  ),
                  _switch(
                    icon: Icons.picture_in_picture_alt_outlined,
                    title: '后台自动画中画',
                    subtitle: '切到后台自动进入画中画继续播放',
                    value: _autoPip,
                    onChanged: (v) {
                      setState(() => _autoPip = v);
                      _set('autoPip', v);
                    },
                  ),
                  _switch(
                    icon: Icons.bubble_chart_outlined,
                    title: '应用内悬浮球',
                    subtitle: '退出播放页后以小窗悬浮球继续播放',
                    value: _floatBall,
                    onChanged: (v) {
                      setState(() => _floatBall = v);
                      _set('floatBall', v);
                    },
                  ),
                  _switch(
                    icon: Icons.merge_type,
                    title: '合并播放列表图标',
                    subtitle: '首页显示「合并播放列表」快捷开关',
                    value: _mergeIcon,
                    onChanged: (v) {
                      setState(() => _mergeIcon = v);
                      _set('mergePlaylistIcon', v);
                    },
                  ),

                  const PeekSectionTitle('网络与安全'),
                  PeekTile(
                    icon: Icons.http,
                    title: '播放请求头策略',
                    subtitle: _headerStrategy,
                    trailing: Icon(Icons.chevron_right,
                        size: 18, color: PeekColors.railIdle),
                    onTap: _pickHeaderStrategy,
                  ),
                  _switch(
                    icon: Icons.verified_user_outlined,
                    title: '禁用 SSL 证书验证',
                    subtitle: '部分源使用自签证书时开启（会降低安全性）',
                    value: _disableSsl,
                    onChanged: (v) {
                      setState(() => _disableSsl = v);
                      _set('disableSslVerify', v);
                    },
                  ),

                  const PeekSectionTitle('推送'),
                  PeekTile(
                    icon: Icons.cast_outlined,
                    title: '推送模式',
                    subtitle: _pushMode,
                    trailing: Icon(Icons.chevron_right,
                        size: 18, color: PeekColors.railIdle),
                    onTap: _pickPushMode,
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
