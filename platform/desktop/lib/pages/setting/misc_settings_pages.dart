import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/debug_log.dart';
import '../../core/netdisk_sources.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../widgets/common.dart';

/// 参与备份 / 恢复的 Hive 盒子名（与 `Store` 里 openBox 的五个一致）。
const _boxNames = <String>[
  Store.setting,
  Store.watchprogress,
  Store.historyword,
  Store.favorite,
  Store.tvbox,
];

/// 备份页里每个盒子的中文说明（键 = Hive 盒子名）。
const _boxDesc = <String, String>{
  Store.setting: '设置',
  Store.watchprogress: '观看进度',
  Store.historyword: '历史记录',
  Store.favorite: '收藏',
  Store.tvbox: '接口与站源',
};

// ============================================================
// 弹幕API配置
// ============================================================
class DanmakuConfigPage extends StatefulWidget {
  const DanmakuConfigPage({super.key});

  @override
  State<DanmakuConfigPage> createState() => _DanmakuConfigPageState();
}

class _DanmakuConfigPageState extends State<DanmakuConfigPage> {
  final _ctrl = TextEditingController(text: Store.get<String>('danmakuApi', ''));
  bool _enabled = Store.get<bool>('danmakuEnabled', true);
  double _opacity = Store.get<double>('danmakuOpacity', 1.0);
  double _fontSize = Store.get<double>('danmakuFontSize', 16);
  bool _scroll = Store.get<bool>('danmakuScroll', true);
  bool _bold = Store.get<bool>('danmakuBold', true);
  double _area = Store.get<double>('danmakuArea', 0.6);
  double _speed = Store.get<double>('danmakuSpeed', 8.0);
  double _fixed = Store.get<double>('danmakuFixedSeconds', 4.0);
  bool _merge = Store.get<bool>('danmakuMerge', false);
  bool _blockMini = Store.get<bool>('danmakuBlockMiniWindow', false);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            PeekPageHeader(
              title: '弹幕API配置',
              actions: [
                TextButton(
                  onPressed: () async {
                    await Store.set('danmakuApi', _ctrl.text.trim());
                    if (mounted) peekToast(context, '已保存');
                  },
                  child: const Text('保存', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  const PeekSectionTitle('弹幕接口'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: TextField(
                      controller: _ctrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'http(s)://…/{id}  或 {url} 占位符形式',
                        isDense: true,
                      ),
                    ),
                  ),
                  PeekTile(
                    icon: Icons.subtitles_outlined,
                    title: '启用弹幕',
                    trailing: Switch(
                      value: _enabled,
                      onChanged: (v) async {
                        setState(() => _enabled = v);
                        await Store.set('danmakuEnabled', v);
                      },
                    ),
                    onTap: () async {
                      setState(() => _enabled = !_enabled);
                      await Store.set('danmakuEnabled', _enabled);
                    },
                  ),
                  const PeekSectionTitle('弹幕样式'),
                  _sliderTile(
                    icon: Icons.format_size,
                    title: '弹幕字号',
                    value: _fontSize,
                    min: 10,
                    max: 28,
                    divisions: 18,
                    label: '${_fontSize.round()}',
                    key: 'danmakuFontSize',
                    onChanged: (v) => setState(() => _fontSize = v),
                  ),
                  _sliderTile(
                    icon: Icons.vertical_align_center,
                    title: '弹幕透明度',
                    value: _opacity,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    label: '${(_opacity * 100).round()}%',
                    key: 'danmakuOpacity',
                    onChanged: (v) => setState(() => _opacity = v),
                  ),
                  _sliderTile(
                    icon: Icons.crop_free,
                    title: '显示区域',
                    subtitle: '弹幕最多占用的屏幕高度比例',
                    value: _area,
                    min: 0.25,
                    max: 1.0,
                    divisions: 15,
                    label: '${(_area * 100).round()}%',
                    key: 'danmakuArea',
                    onChanged: (v) => setState(() => _area = v),
                  ),
                  _sliderTile(
                    icon: Icons.speed,
                    title: '弹幕速度',
                    subtitle: '滚动弹幕穿屏时长，越短越快',
                    value: _speed,
                    min: 3.0,
                    max: 14.0,
                    divisions: 22,
                    label: '${_speed.toStringAsFixed(1)}s',
                    key: 'danmakuSpeed',
                    onChanged: (v) => setState(() => _speed = v),
                  ),
                  _sliderTile(
                    icon: Icons.timer_outlined,
                    title: '静止弹幕时长',
                    subtitle: '顶部/底部固定弹幕的停留时间',
                    value: _fixed,
                    min: 2.0,
                    max: 10.0,
                    divisions: 16,
                    label: '${_fixed.toStringAsFixed(1)}s',
                    key: 'danmakuFixedSeconds',
                    onChanged: (v) => setState(() => _fixed = v),
                  ),
                  PeekTile(
                    icon: Icons.format_bold,
                    title: '粗体弹幕',
                    subtitle: '关闭后使用常规字重',
                    trailing: Switch(
                      value: _bold,
                      onChanged: (v) async {
                        setState(() => _bold = v);
                        await Store.set('danmakuBold', v);
                      },
                    ),
                    onTap: () async {
                      setState(() => _bold = !_bold);
                      await Store.set('danmakuBold', _bold);
                    },
                  ),
                  PeekTile(
                    icon: Icons.swap_horiz,
                    title: '滚动弹幕',
                    subtitle: '关闭后只显示顶部固定弹幕',
                    showDivider: false,
                    trailing: Switch(
                      value: _scroll,
                      onChanged: (v) async {
                        setState(() => _scroll = v);
                        await Store.set('danmakuScroll', v);
                      },
                    ),
                    onTap: () async {
                      setState(() => _scroll = !_scroll);
                      await Store.set('danmakuScroll', _scroll);
                    },
                  ),
                  const PeekSectionTitle('弹幕过滤'),
                  PeekTile(
                    icon: Icons.merge_type,
                    title: '合并弹幕',
                    subtitle: '合并一段时间内获取到的相同弹幕',
                    trailing: Switch(
                      value: _merge,
                      onChanged: (v) async {
                        setState(() => _merge = v);
                        await Store.set('danmakuMerge', v);
                      },
                    ),
                    onTap: () async {
                      setState(() => _merge = !_merge);
                      await Store.set('danmakuMerge', _merge);
                    },
                  ),
                  PeekTile(
                    icon: Icons.visibility_off_outlined,
                    title: '画中画不加载弹幕',
                    subtitle: '当弹幕开关开启时，小窗屏蔽弹幕以获得较好的体验',
                    showDivider: false,
                    trailing: Switch(
                      value: _blockMini,
                      onChanged: (v) async {
                        setState(() => _blockMini = v);
                        await Store.set('danmakuBlockMiniWindow', v);
                      },
                    ),
                    onTap: () async {
                      setState(() => _blockMini = !_blockMini);
                      await Store.set('danmakuBlockMiniWindow', _blockMini);
                    },
                  ),
                  const PeekSectionTitle('屏蔽词'),
                  _ruleField('danmakuBlockWords', '关键词',
                      '每行一条，弹幕包含该词则屏蔽', Icons.block_outlined),
                  _ruleField('danmakuBlockRegex', '正则',
                      '每行一条正则，写错的行会被忽略', Icons.code),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sliderTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String label,
    required String key,
    required ValueChanged<double> onChanged,
    bool showDivider = true,
  }) {
    return PeekTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      showDivider: showDivider,
      trailing: SizedBox(
        width: 180,
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: onChanged,
          onChangeEnd: (v) => Store.set(key, v),
        ),
      ),
    );
  }

  Widget _ruleField(String key, String label, String hint, IconData icon) {
    final ctrl = TextEditingController(text: Store.get<String>(key, ''));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: TextField(
        controller: ctrl,
        maxLines: 3,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          prefixIcon: Icon(icon, size: 18),
        ),
        onChanged: (v) => Store.set(key, v),
      ),
    );
  }
}

// ============================================================
// 缓存大小
// ============================================================
class CacheSettingsPage extends StatefulWidget {
  const CacheSettingsPage({super.key});

  @override
  State<CacheSettingsPage> createState() => _CacheSettingsPageState();
}

class _CacheSettingsPageState extends State<CacheSettingsPage> {
  int _bytes = 0;
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    var total = 0;
    try {
      final dir = await getApplicationSupportDirectory();
      total = await _dirSize(dir);
    } catch (_) {}
    await Store.set('cacheBytes', total);
    if (!mounted) return;
    setState(() {
      _bytes = total;
      _scanning = false;
    });
  }

  Future<int> _dirSize(Directory dir) async {
    var total = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> _clear() async {
    final ok = await peekConfirm(context, '清理缓存', '将清除图片缓存与本地接口缓存，'
        '观看记录和收藏不受影响。确定继续吗？');
    if (!ok) return;
    try {
      final dir = await getApplicationCacheDirectory();
      if (await dir.exists()) {
        await for (final e in dir.list()) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
    await Store.setCachedConfig('');
    if (mounted) {
      peekToast(context, '缓存已清理');
      _scan();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const PeekPageHeader(title: '缓存大小'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('当前占用',
                            style: TextStyle(
                                fontSize: 12, color: PeekColors.hint)),
                        const SizedBox(height: 8),
                        Text(
                          _scanning ? '统计中…' : fmtBytes(_bytes),
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: PeekColors.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PeekTile(
                    icon: Icons.refresh,
                    title: '重新统计',
                    subtitle: '重新计算本地缓存占用',
                    onTap: _scan,
                  ),
                  PeekTile(
                    icon: Icons.delete_sweep_outlined,
                    title: '清理缓存',
                    subtitle: '清除图片缓存与本地接口缓存',
                    showDivider: false,
                    onTap: _clear,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 调试日志
// ============================================================
class DebugLogPage extends StatefulWidget {
  const DebugLogPage({super.key});

  @override
  State<DebugLogPage> createState() => _DebugLogPageState();
}

class _DebugLogPageState extends State<DebugLogPage> {
  bool _enabled = Store.get<bool>('debugLogEnabled', false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            PeekPageHeader(
              title: '调试日志',
              actions: [
                IconButton(
                  tooltip: '复制',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: DebugLog.dump()));
                    if (mounted) peekToast(context, '日志已复制到剪贴板');
                  },
                  icon: const Icon(Icons.copy_all_outlined, size: 19),
                ),
                IconButton(
                  tooltip: '清空',
                  onPressed: () => setState(DebugLog.clear),
                  icon: const Icon(Icons.delete_outline, size: 19),
                ),
              ],
            ),
            PeekTile(
              icon: Icons.bug_report_outlined,
              title: '记录接口请求日志',
              subtitle: '开启后会记录每次网络请求的地址与状态',
              showDivider: false,
              trailing: Switch(
                value: _enabled,
                onChanged: (v) async {
                  setState(() => _enabled = v);
                  await Store.set('debugLogEnabled', v);
                  DebugLog.add('APP', '调试日志已${v ? '开启' : '关闭'}');
                },
              ),
              onTap: () async {
                setState(() => _enabled = !_enabled);
                await Store.set('debugLogEnabled', _enabled);
              },
            ),
            Divider(height: 1, color: PeekColors.cardBorder),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: DebugLog.revision,
                builder: (_, __, ___) {
                  final logs = DebugLog.entries;
                  if (logs.isEmpty) {
                    return const PeekEmpty(
                      icon: Icons.article_outlined,
                      text: '暂无日志\n开启上方开关后，接口请求会被记录在这里',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: logs.length,
                    itemBuilder: (_, i) {
                      final e = logs[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.stamp,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                    color: PeekColors.railIdle)),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: PeekColors.iconTile,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(e.tag,
                                  style: TextStyle(
                                      fontSize: 10, color: PeekColors.primary)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                e.message,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.45,
                                    color: PeekColors.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 免责声明
// ============================================================
class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  static const _text = '''
一、本软件为技术学习与研究用途的开源客户端，本身不提供、不存储、不制作任何音视频内容。

二、软件内所有内容均来自第三方接口（即用户自行导入的「接口配置」），
    接口的可用性、合法性、内容准确性均由接口提供方负责，与本软件无关。

三、用户应自行确保所使用的第三方接口及其中内容符合其所在国家或地区的法律法规。
    因使用第三方接口产生的一切后果，由用户自行承担。

四、本软件不收集、不上传任何用户个人信息。所有观看记录、收藏、接口配置等数据
    均仅保存在本机（Hive 本地数据库）。

五、请通过官方渠道获取本软件。任何第三方修改、二次打包版本均与本项目无关。

六、继续使用即表示您已阅读、理解并同意上述全部条款。
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const PeekPageHeader(title: '免责声明'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
                child: Text(
                  _text.trim(),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.9,
                    color: PeekColors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 壁纸（WebHTV 设置页第 3 项）
// ============================================================

/// 壁纸设置。
///
/// ## 原版依据
/// `SettingFragment.onWall()` → `ConfigDialog.wall()`，并另有两个快捷动作
/// `setWallDefault`（`Setting.putWall(Setting.nextDefaultWall()); putWallType(0)`）
/// 和 `setWallRefresh`（`Setting.putWall(0)`）。
/// 原版键：`wall`（内置壁纸序号）与 `wall_type`（壁纸来源类型）。
///
/// 桌面端没有「桌面壁纸」概念，这里落成**播放页背景图**：可选内置渐变，
/// 或填一个图片 URL。语义与原版一致 —— 都是「给界面换一张底图」。
class WallpaperSettingsPage extends StatefulWidget {
  const WallpaperSettingsPage({super.key});

  @override
  State<WallpaperSettingsPage> createState() => _WallpaperSettingsPageState();
}

class _WallpaperSettingsPageState extends State<WallpaperSettingsPage> {
  /// 原版 `Setting.nextDefaultWall()` 在内置壁纸间轮换，对应 `wall_type=0`。
  static const _builtin = <String>[
    '内置壁纸 1 · 极夜',
    '内置壁纸 2 · 深蓝',
    '内置壁纸 3 · 墨绿',
    '内置壁纸 4 · 暮紫',
    '内置壁纸 5 · 炭灰',
  ];

  int _wallType = Store.get<int>('wallType', 0);
  int _wall = Store.get<int>('wall', 0);
  final _urlCtl = TextEditingController(text: Store.get<String>('wallUrl', ''));

  @override
  void dispose() {
    _urlCtl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    await Store.set('wallType', _wallType);
    await Store.set('wall', _wall);
    await Store.set('wallUrl', _urlCtl.text.trim());
    await Store.set(
      'wallDesc',
      _wallType == 0 ? _builtin[_wall] : (_urlCtl.text.trim().isEmpty ? '未设置' : '自定义图片'),
    );
    if (!mounted) return;
    peekToast(context, '壁纸已更新');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const PeekPageHeader(title: '壁纸'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  const PeekSectionTitle('内置壁纸'),
                  PeekTile(
                    icon: Icons.wallpaper_outlined,
                    title: '当前内置壁纸',
                    subtitle: _builtin[_wall.clamp(0, _builtin.length - 1)],
                    trailing: TextButton(
                      // 原版 `setWallDefault`：切到下一张内置壁纸并置 wall_type=0。
                      onPressed: () {
                        setState(() {
                          _wall = (_wall + 1) % _builtin.length;
                          _wallType = 0;
                        });
                      },
                      child: Text('换一张', style: TextStyle(color: PeekColors.primary)),
                    ),
                    onTap: () => setState(() => _wallType = 0),
                  ),
                  const PeekSectionTitle('自定义'),
                  PeekTile(
                    icon: Icons.image_outlined,
                    title: '图片地址',
                    subtitle: '留空则不使用自定义壁纸',
                    showDivider: false,
                    onTap: () => setState(() => _wallType = 1),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    child: TextField(
                      controller: _urlCtl,
                      style: TextStyle(fontSize: 13, color: PeekColors.onSurface),
                      decoration: InputDecoration(
                        hintText: 'https://…',
                        hintStyle: TextStyle(color: PeekColors.hint, fontSize: 13),
                        filled: true,
                        fillColor: PeekColors.surfaceContainer,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: PeekColors.cardBorder),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: PeekColors.cardBorder),
                        ),
                      ),
                      onChanged: (_) => setState(() => _wallType = 1),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        // 原版 `setWallRefresh`：清空自定义，回到内置。
                        OutlinedButton(
                          onPressed: () async {
                            _urlCtl.clear();
                            setState(() {
                              _wall = 0;
                              _wallType = 0;
                            });
                            await _apply();
                          },
                          child: Text('恢复内置',
                              style: TextStyle(color: PeekColors.hint)),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _apply,
                          child: const Text('应用'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 增强功能（WebHTV 设置页第 4 项）
// ============================================================

/// 增强功能。原版 `SettingFragment.onEnhance()` → `SettingEnhanceActivity`，
/// 页面里是一组开关。这里只保留**桌面端有实际作用**的那几个，
/// 键名沿用 `Setting.java`（`site_health_sort` / `compact_episode_title` /
/// `csp_warmup` / `web_home_extension`）。
class EnhanceSettingsPage extends StatefulWidget {
  const EnhanceSettingsPage({super.key});

  @override
  State<EnhanceSettingsPage> createState() => _EnhanceSettingsPageState();
}

class _EnhanceSettingsPageState extends State<EnhanceSettingsPage> {
  bool _healthSort = Store.get<bool>('site_health_sort', true);
  bool _compactEpisode = Store.get<bool>('compact_episode_title', false);
  bool _cspWarmup = Store.get<bool>('csp_warmup', true);
  bool _debugLog = Store.get<bool>('debugLogEnabled', false);
  bool _showAllSites = Store.get<bool>('showAllSites', true);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const PeekPageHeader(title: '增强功能'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  PeekTile(
                    icon: Icons.dns_outlined,
                    title: '全部站点显示',
                    // 关闭后会屏蔽「需要登录的网盘源」（4K 分享类）。
                    // 判定依据是播放地址的结构（base64 JSON 里的 providerId），
                    // 不是站点名 —— 详见 NetdiskSources 的注释。
                    subtitle: _showAllSites
                        ? '关闭后不显示需要登录的网盘源（4K 分享类）'
                        : '已屏蔽 ${NetdiskSources.known.length} 个需登录网盘源',
                    trailing: Switch(
                      value: _showAllSites,
                      onChanged: (v) async {
                        setState(() => _showAllSites = v);
                        await Store.set('showAllSites', v);
                      },
                    ),
                    onTap: () async {
                      final v = !_showAllSites;
                      setState(() => _showAllSites = v);
                      await Store.set('showAllSites', v);
                    },
                  ),
                  PeekTile(
                    icon: Icons.sort_outlined,
                    title: '站源健康排序',
                    subtitle: '按上次请求成功率排序站源列表',
                    trailing: Switch(
                      value: _healthSort,
                      onChanged: (v) async {
                        setState(() => _healthSort = v);
                        await Store.set('site_health_sort', v);
                      },
                    ),
                    onTap: () async {
                      setState(() => _healthSort = !_healthSort);
                      await Store.set('site_health_sort', _healthSort);
                    },
                  ),
                  PeekTile(
                    icon: Icons.compress,
                    title: '紧凑剧集标题',
                    subtitle: '剧集按钮只显示集数，去掉前缀',
                    trailing: Switch(
                      value: _compactEpisode,
                      onChanged: (v) async {
                        setState(() => _compactEpisode = v);
                        await Store.set('compact_episode_title', v);
                      },
                    ),
                    onTap: () async {
                      setState(() => _compactEpisode = !_compactEpisode);
                      await Store.set('compact_episode_title', _compactEpisode);
                    },
                  ),
                  PeekTile(
                    icon: Icons.bolt_outlined,
                    title: '源预热',
                    subtitle: '启动时提前拉起 Node 源进程，缩短首次点播等待',
                    trailing: Switch(
                      value: _cspWarmup,
                      onChanged: (v) async {
                        setState(() => _cspWarmup = v);
                        await Store.set('csp_warmup', v);
                      },
                    ),
                    onTap: () async {
                      setState(() => _cspWarmup = !_cspWarmup);
                      await Store.set('csp_warmup', _cspWarmup);
                    },
                  ),
                  PeekTile(
                    icon: Icons.bug_report_outlined,
                    title: '调试日志',
                    subtitle: '记录接口请求与脚本运行日志',
                    showDivider: false,
                    trailing: Switch(
                      value: _debugLog,
                      onChanged: (v) async {
                        setState(() => _debugLog = v);
                        await Store.set('debugLogEnabled', v);
                      },
                    ),
                    onTap: () async {
                      setState(() => _debugLog = !_debugLog);
                      await Store.set('debugLogEnabled', _debugLog);
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
}

// ============================================================
// 备份 / 恢复（WebHTV 设置页第 11、12 项）
// ============================================================

/// 备份页。原版 `onBackup()` 走 `AppDatabase.backup(...)` 导出应用数据。
/// 桌面端把 5 个 Hive 盒子序列化成一个 JSON 文件写到用户选定路径。
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  bool _busy = false;
  String _lastPath = '';

  Future<void> _doBackup() async {
    setState(() => _busy = true);
    try {
      final dir = await getApplicationSupportDirectory();
      final data = <String, dynamic>{
        'app': 'webhtv-win',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'boxes': {
          for (final name in _boxNames)
            name: {
              for (final k in Hive.box(name).keys)
                k.toString(): Hive.box(name).get(k),
            },
        },
      };
      final f = File(
        '${dir.path}${Platform.pathSeparator}webhtv-backup-'
        '${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      setState(() => _lastPath = f.path);
      if (!mounted) return;
      peekToast(context, '备份完成');
    } catch (e) {
      if (!mounted) return;
      peekToast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const PeekPageHeader(title: '备份'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  const PeekSectionTitle('将导出的数据'),
                  for (final e in _boxDesc.entries)
                    PeekTile(
                      icon: Icons.inventory_2_outlined,
                      title: e.value,
                      subtitle: '${Hive.box(e.key).length} 条',
                    ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _doBackup,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_alt, size: 18),
                      label: const Text('导出到文件'),
                    ),
                  ),
                  if (_lastPath.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                      child: SelectableText(
                        '已保存：$_lastPath',
                        style: TextStyle(fontSize: 11.5, color: PeekColors.hint),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 恢复页。原版 `onRestore()` 走 `RestoreDialog` 选备份文件导入。
class RestorePage extends StatefulWidget {
  const RestorePage({super.key});

  @override
  State<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends State<RestorePage> {
  bool _busy = false;

  Future<void> _restoreFromPath(String path) async {
    setState(() => _busy = true);
    try {
      final raw = await File(path).readAsString();
      final data = jsonDecode(raw);
      if (data is! Map || data['app'] != 'webhtv-win') {
        throw Exception('不是 WebHTV 桌面版的备份文件');
      }
      final boxes = (data['boxes'] as Map).cast<String, dynamic>();
      var n = 0;
      for (final name in _boxNames) {
        final box = Hive.box(name);
        final m = boxes[name];
        if (m is! Map) continue;
        await box.clear();
        await box.putAll(m.cast<String, dynamic>());
        n += m.length;
      }
      if (!mounted) return;
      peekToast(context, '恢复完成，共导入 $n 条数据');
    } catch (e) {
      if (!mounted) return;
      peekToast(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 列出应用数据目录下的备份文件。
  Future<List<String>> _listBackups() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path)
        .where((p) => p.contains('webhtv-backup-') && p.endsWith('.json'))
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  Future<void> _pickManual() async {
    final path = await peekPrompt(
      context,
      title: '从备份文件恢复',
      hint: '请输入备份 JSON 的完整路径',
      initial: _lastSuggested,
    );
    if (path == null || path.trim().isEmpty) return;
    await _restoreFromPath(path.trim());
  }

  final String _lastSuggested = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const PeekPageHeader(title: '恢复'),
            Expanded(
              child: FutureBuilder<List<String>>(
                future: _listBackups(),
                builder: (context, snap) {
                  final files = snap.data ?? const <String>[];
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 28),
                    children: [
                      const PeekSectionTitle('本机备份文件'),
                      if (snap.connectionState != ConnectionState.done)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: PeekLoading(text: '扫描中…')),
                        )
                      else if (files.isEmpty)
                        PeakEmptyHint(
                          text: '暂无备份文件，可在「备份」页导出一份。',
                          actionText: '手动指定路径',
                          onAction: _pickManual,
                        )
                      else
                        for (final p in files)
                          PeekTile(
                            icon: Icons.restore,
                            title: p.split(Platform.pathSeparator).last,
                            subtitle: p,
                            onTap: _busy
                                ? null
                                : () async {
                                    final ok = await peekConfirm(
                                      context,
                                      '恢复数据',
                                      '将清空当前全部设置、收藏与历史，并导入该文件。此操作不可撤销，确定继续？',
                                    );
                                    if (!ok) return;
                                    await _restoreFromPath(p);
                                  },
                          ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _pickManual,
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('手动指定备份文件'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// 关于（WebHTV 设置页第 13 项）
// ============================================================

/// 关于页。原版 `onVersion()` → `AboutDialog.show(...)` + `Updater`。
/// 桌面端不自建更新通道，改为展示版本、仓库与完整免责声明。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const PeekPageHeader(title: '关于'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            'assets/images/logo/logo.png',
                            width: 76,
                            height: 76,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 76,
                              height: 76,
                              color: PeekColors.iconTile,
                              child: Icon(Icons.live_tv,
                                  size: 36, color: PeekColors.primary),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text('WebHTV',
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: PeekColors.onSurface)),
                        const SizedBox(height: 6),
                        Text('桌面版 v0.1.0 · Windows x64',
                            style: TextStyle(fontSize: 12, color: PeekColors.hint)),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: PeekColors.iconTile,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('完全免费',
                              style: TextStyle(
                                  fontSize: 11.5, color: PeekColors.primary)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  PeekTile(
                    icon: Icons.info_outline,
                    title: '版本',
                    subtitle: 'v0.1.0 (1)',
                  ),
                  PeekTile(
                    icon: Icons.memory,
                    title: '运行环境',
                    subtitle: 'Flutter · media_kit (libmpv) · Node 源子进程',
                  ),
                  PeekTile(
                    icon: Icons.dns_outlined,
                    title: '源服务端口',
                    subtitle: '127.0.0.1:9988',
                    showDivider: false,
                  ),
                  const PeekSectionTitle('免责声明'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(
                      _disclaimer.trim(),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.85,
                        color: PeekColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _disclaimer = '''
WebHTV 是基于开源生态二次开发的技术学习与研究项目，软件本体完全免费，
不提供任何付费服务、影视内容、直播源、接口源、资源存储或内容分发能力。

本软件不内置、不售卖、不传播任何影视资源，不对用户自行添加的接口、站源、
插件、脚本、链接、网盘资源或第三方服务内容负责。使用者应遵守所在地法律法规，
尊重版权方和内容提供方的合法权益。

严禁任何个人或组织以本软件名义进行售卖、引流、收费维护、会员服务、
广告变现、盒子预装或其他任何形式的获益行为。

如你不同意以上声明，请立即停止使用并卸载本软件。
''';
}

/// 空态提示（带一个操作按钮）。比 [PeekEmpty] 更轻，用于列表内联空态。
class PeakEmptyHint extends StatelessWidget {
  const PeakEmptyHint({
    super.key,
    required this.text,
    this.actionText,
    this.onAction,
  });

  final String text;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
      child: Column(
        children: [
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: PeekColors.hint)),
          if (actionText != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(actionText!)),
          ],
        ],
      ),
    );
  }
}
