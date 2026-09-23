import 'package:flutter/material.dart';

import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../widgets/common.dart';
import '../../widgets/nav_rail.dart';

/// 外观与语言（WebHTV 安卓版设置页第 7 项，副标题「4 项」）。
///
/// ## 权威依据
/// `app/src/mobile/java/com/fongmi/android/tv/ui/dialog/AppearanceDialog.java`
/// 的 `addRow(...)` 顺序 —— 原版就是 **4 行**，副标题 `setting_appearance_summary`
/// = 「4 项」：
///
/// | # | 键 | 原版文案 | 选项来源 |
/// |---|---|---|---|
/// | 1 | `uiScale`      | 界面大小 | `R.array.select_ui_scale` |
/// | 2 | `themeColor`   | 主题色彩 | `ThemeDialog.COLORS`（14 色，首项「跟随系统」） |
/// | 3 | `imageSize`    | 图片尺寸 | `R.array.select_size` |
/// | 4 | `language`     | 语言     | `R.array.select_language` |
///
/// 原版点任一行弹 `ChoiceDialog.showSingle`（单选列表）。桌面端用同样的
/// 单选弹层，视觉与 [peekConfirm] 一致。
///
/// ## 与 PeekPili 的差异（诚实记录）
///
/// PeekPili 的「外观与个性化」是主题色块 + 深色开关 + 海报标题 + 紧凑标题 +
/// 三个「显示 X 入口」开关 + 网格列数滑杆。其中「显示短剧/音乐/阅读入口」
/// 三个开关的宿主模块已被裁掉，整项删除；其余非 WebHTV 项也一并删除。
/// 海报标题 / 紧凑标题 / 合并播放列表属于**首页交互开关**，按 WebHTV
/// 的分工留在首页顶栏（原版是首页右上角的按钮组），不放这里。
class AppearancePage extends StatefulWidget {
  const AppearancePage({super.key});

  @override
  State<AppearancePage> createState() => _AppearancePageState();
}

class _AppearancePageState extends State<AppearancePage> {
  /// `R.array.select_ui_scale`（`main/res/values-zh-rCN/strings.xml:1298`）。
  static const _uiScales = <String>[
    '跟随系统',
    '标准',
    '较紧凑',
    '紧凑',
    '更紧凑',
    '更小',
  ];

  /// `R.array.select_size`（同文件 :1291）。原版索引顺序即「小/中/大/特大」，
  /// 默认值 `PlayerSetting.getSize()` = 1（中）。
  static const _imageSizes = <String>['小', '中', '大', '特大'];

  /// `R.array.select_language`（同文件 :1306）。
  static const _languages = <String>['跟随系统', '简体中文', '繁体中文'];

  /// `ThemeDialog.COLORS`（`ThemeDialog.java:14`）。第 1 项 `-1` = 跟随系统。
  static const _themeColors = <int>[
    -1,
    0,
    0xFF6750A4,
    0xFF3949AB,
    0xFF1E88E5,
    0xFF00ACC1,
    0xFF00897B,
    0xFF43A047,
    0xFF7CB342,
    0xFFFB8C00,
    0xFFE53935,
    0xFFD81B60,
    0xFF8E24AA,
    0xFF6D4C41,
  ];

  int _uiScale = Store.get<int>('uiScaleIndex', 0);
  int _imageSize = Store.get<int>('imageSize', 1);
  int _language = Store.get<int>('languageIndex', 0);
  int _themeColor = Store.get<int>('themeColorArgb', -1);

  /// 原版 `AppearanceDialog.getThemeText()`：`-1` → 「关闭」，`0` → 「自动」，
  /// 其余显示「自定义」。
  String get _themeText => switch (_themeColor) {
        -1 => '关闭',
        0 => '自动',
        _ => '自定义',
      };

  Future<void> _pick({
    required String title,
    required List<String> options,
    required int selected,
    required ValueChanged<int> onPick,
  }) async {
    final idx = await _showSingle(context, title, options, selected);
    if (idx == null) return;
    setState(() => onPick(idx));
  }

  /// 单选弹层。原版是 `ChoiceDialog.showSingle`：标题 + 选项列表，
  /// 当前项打勾。这里保持「标题 + 打勾单选」的形状。
  static Future<int?> _showSingle(
    BuildContext context,
    String title,
    List<String> options,
    int selected,
  ) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PeekColors.surfaceContainer,
        title: Text(title,
            style: TextStyle(fontSize: 16, color: PeekColors.onSurface)),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: 280,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (_, i) => InkWell(
              onTap: () => Navigator.of(ctx).pop(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        options[i],
                        style: TextStyle(
                          fontSize: 14,
                          color: i == selected
                              ? PeekColors.primary
                              : PeekColors.onSurface,
                        ),
                      ),
                    ),
                    if (i == selected)
                      Icon(Icons.check, size: 18, color: PeekColors.primary),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('关闭', style: TextStyle(color: PeekColors.hint)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickThemeColor() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PeekColors.surfaceContainer,
        title: Text('主题色彩',
            style: TextStyle(fontSize: 16, color: PeekColors.onSurface)),
        content: SizedBox(
          width: 300,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final c in _themeColors)
                InkWell(
                  onTap: () => Navigator.of(ctx).pop(c),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c <= 0 ? PeekColors.surfaceContainerHigh : Color(c),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: c == _themeColor
                            ? PeekColors.primary
                            : PeekColors.cardBorder,
                        width: c == _themeColor ? 2 : 1,
                      ),
                    ),
                    child: c == -1
                        ? Icon(Icons.block, size: 18, color: PeekColors.hint)
                        : c == 0
                            ? Icon(Icons.auto_awesome,
                                size: 18, color: PeekColors.hint)
                            : null,
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('关闭', style: TextStyle(color: PeekColors.hint)),
          ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() => _themeColor = picked);
    await Store.set('themeColorArgb', picked);
    if (!mounted) return;
    peekToast(context, '主题色彩：$_themeText');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            const PeekPageHeader(title: '外观与语言'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  PeekTile(
                    icon: Icons.aspect_ratio,
                    title: '界面大小',
                    subtitle: _uiScales[_uiScale],
                    onTap: () => _pick(
                      title: '界面大小',
                      options: _uiScales,
                      selected: _uiScale,
                      onPick: (i) async {
                        _uiScale = i;
                        await Store.set('uiScaleIndex', i);
                      },
                    ),
                  ),
                  PeekTile(
                    icon: Icons.palette_outlined,
                    title: '主题色彩',
                    subtitle: _themeText,
                    onTap: _pickThemeColor,
                  ),
                  PeekTile(
                    icon: Icons.photo_size_select_large,
                    title: '图片尺寸',
                    subtitle: _imageSizes[_imageSize],
                    onTap: () => _pick(
                      title: '图片尺寸',
                      options: _imageSizes,
                      selected: _imageSize,
                      onPick: (i) async {
                        _imageSize = i;
                        await Store.set('imageSize', i);
                      },
                    ),
                  ),
                  PeekTile(
                    icon: Icons.language,
                    title: '语言',
                    subtitle: _languages[_language],
                    onTap: () => _pick(
                      title: '语言',
                      options: _languages,
                      selected: _language,
                      onPick: (i) async {
                        _language = i;
                        await Store.set('languageIndex', i);
                      },
                    ),
                  ),
                  // 导航栏设置（原版「外观与个性化 → 导航栏设置」）
                  const PeekSectionTitle('导航栏设置'),
                  PeekTile(
                    icon: Icons.view_sidebar_outlined,
                    title: '导航栏样式',
                    subtitle: NavStyle.fromName(
                            Store.get<String>('navStyle', 'classic'))
                        .label,
                    onTap: _pickNavStyle,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 2, 18, 14),
                    child: Text(
                      '横屏模式下将显示侧边导航栏，竖屏模式下将显示底部导航栏',
                      style: TextStyle(
                          fontSize: 11.5, color: PeekColors.hint),
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

  /// 导航栏样式（原版 6 选 1）
  Future<void> _pickNavStyle() async {
    final cur = NavStyle.fromName(Store.get<String>('navStyle', 'classic'));
    final picked = await showModalBottomSheet<NavStyle>(
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
                child: Text('导航栏样式',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: PeekColors.onSurface)),
              ),
            ),
            for (final s in NavStyle.values)
              ListTile(
                dense: true,
                title: Text(s.label,
                    style: const TextStyle(fontSize: 13.5)),
                trailing: s == cur
                    ? Icon(Icons.check, size: 18, color: PeekColors.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(s),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await Store.set('navStyle', picked.name);
    if (mounted) setState(() {});
  }
}
