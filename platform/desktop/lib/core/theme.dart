import 'package:flutter/material.dart';

/// 一套配色（深色或浅色）。
///
/// ## 原版依据
/// 原版「设置 → 外观与个性化 → 主题模式」弹层是 **3 个 RadioButton**：
///   `浅色` / `深色` / `跟随系统`（`uiautomator dump`，见
///   `.peekpili-analysis/g8/t_theme_mode.xml`）。
/// 弹层标题「主题模式」`[757,419][1163,451]`，选项 `[715,472][1205,556]` /
/// `[715,556][1205,640]` / `[715,640][1205,724]` —— 宽 490px = **280dp**、行高 84px = **48dp**。
/// 设置项副标题是 `当前：浅色` / `当前：深色` / `当前：跟随系统`。
///
/// ## 实测色值（`g8/sample_theme_colors.py`、`g8/sample_home_theme.py`）
/// | 角色 | 深色 | 浅色 |
/// |---|---|---|
/// | surface | `#1C1B1B` | `#FDFCFF` |
/// | railDivider | `#272728` | `#EFEEF2` |
/// | railSelected | `#123755` | `#E2EEFF` |
/// | railSelected 前景 | `#9FCAFF` | `#2E6195` |
/// | railIdle | `#808287` | `#8D9095` |
/// | onSurface | `#E2E2E6` | `#1C1B1B` |
/// | primary | `#9FCAFF` | `#2E6195` |
/// | iconTile | `#14324B` | `#DEEBFF` |
/// | hint | `#8A8B91` | `#42474E` |
/// | chip 描边 | `#7A7A7A` | `#AEC1D6` |
///
/// ⚠️ 采样注意：`shots/t_dlg_dark.png` 是**弹层打开时**截的，整页被 modal barrier
/// 压暗约 0.46 倍（surface 从 `#1C1B1B` 变 `#0D0C0C`），不能直接当基准用。
/// 干净的深色基准取 `shots/dark_home.png`。
class PeekPalette {
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;
  final Color primary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color iconTile;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color error;
  final Color ok;
  final Color railSelected;
  final Color railIdle;
  final Color railDivider;
  final Color hint;
  final Color card;
  final Color cardBorder;
  final Color chipFill;
  final Color chipBorder;
  final Color chipText;
  final Color chipSelectedFill;
  final Color chipSelectedBorder;
  final Color chipSelectedText;

  const PeekPalette({
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.primary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.iconTile,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.error,
    required this.ok,
    required this.railSelected,
    required this.railIdle,
    required this.railDivider,
    required this.hint,
    required this.card,
    required this.cardBorder,
    required this.chipFill,
    required this.chipBorder,
    required this.chipText,
    required this.chipSelectedFill,
    required this.chipSelectedBorder,
    required this.chipSelectedText,
  });
}

/// 原版深色（默认）。色值来自 1.2.5+2 实际运行界面采样。
const PeekPalette peekDark = PeekPalette(
  surface: Color(0xFF1C1B1B),
  surfaceContainer: Color(0xFF232324),
  surfaceContainerHigh: Color(0xFF2B2A2B),
  primary: Color(0xFF9FCAFF),
  primaryContainer: Color(0xFF0C497C),
  onPrimaryContainer: Color(0xFFD1E4FF),
  iconTile: Color(0xFF14324B),
  onSurface: Color(0xFFE2E2E6),
  onSurfaceVariant: Color(0xFFC3C6CF),
  outline: Color(0xFF43474E),
  error: Color(0xFFFFB4AB),
  ok: Color(0xFF7EDFA0),
  railSelected: Color(0xFF123755),
  railIdle: Color(0xFF808287),
  railDivider: Color(0xFF272728),
  hint: Color(0xFF8A8B91),
  card: Color(0xFF232324),
  cardBorder: Color(0xFF2E2E30),
  chipFill: Color(0xFF3E3D3D),
  chipBorder: Color(0xFF7A7A7A),
  chipText: Color(0xFFE2E2E6),
  chipSelectedFill: Color(0xFF545E6B),
  chipSelectedBorder: Color(0xFF8DAED9),
  chipSelectedText: Color(0xFF00325B),
);

/// 原版浅色。surface / rail / primary / iconTile / hint / chip 描边为实测值，
/// 其余按同一明度关系反推（原版浅色下卡片与页面同底，靠描边分层）。
const PeekPalette peekLight = PeekPalette(
  surface: Color(0xFFFDFCFF),
  surfaceContainer: Color(0xFFF1F0F4),
  surfaceContainerHigh: Color(0xFFE7E6EA),
  primary: Color(0xFF2E6195),
  primaryContainer: Color(0xFFD6E4FF),
  onPrimaryContainer: Color(0xFF0C497C),
  iconTile: Color(0xFFDEEBFF),
  onSurface: Color(0xFF1C1B1B),
  onSurfaceVariant: Color(0xFF44474E),
  outline: Color(0xFF74777F),
  error: Color(0xFFBA1A1A),
  ok: Color(0xFF1E7B45),
  railSelected: Color(0xFFE2EEFF),
  railIdle: Color(0xFF8D9095),
  railDivider: Color(0xFFEFEEF2),
  hint: Color(0xFF42474E),
  card: Color(0xFFFFFFFF),
  cardBorder: Color(0xFFE3E2E6),
  chipFill: Color(0xFFFFFFFF),
  chipBorder: Color(0xFFAEC1D6),
  chipText: Color(0xFF1C1B1B),
  chipSelectedFill: Color(0xFFD6E4FF),
  chipSelectedBorder: Color(0xFF2E6195),
  chipSelectedText: Color(0xFF0C497C),
);

/// 颜色门面。
///
/// ## 为什么是 getter 而不是 const
/// 全工程有 **477 处** `PeekColors.xxx` 引用（35 个文件）。要让浅色/深色真正生效，
/// 这些取值必须随主题变化。把颜色字段改成 **static getter** 读当前调色板，
/// 调用点一行都不用动（代价：44 处 `const` 上下文要去掉 `const`）。
///
/// **几何常量保持 `const`** —— 它们不随主题变，`const gap = PeekColors.gridGap`
/// 这类写法继续有效。
///
/// ## 生效时机
/// [use] 必须在**构建树之前**调用。`main.dart` 的 `PeekPiliApp.build()` 里
/// 先解析 brightness → `PeekColors.use(...)` → 再返回 `MaterialApp`，
/// 于是整棵树 build 时读到的都是新调色板。
class PeekColors {
  PeekColors._();

  static PeekPalette _p = peekDark;

  /// 当前生效的调色板。
  static PeekPalette get current => _p;

  /// 按亮度切换调色板。
  static void use(Brightness b) => _p = b == Brightness.dark ? peekDark : peekLight;

  /// 是否处于深色。
  static bool get isDark => identical(_p, peekDark);

  // ---- 颜色（随主题变化）----
  static Color get surface => _p.surface;
  static Color get surfaceContainer => _p.surfaceContainer;
  static Color get surfaceContainerHigh => _p.surfaceContainerHigh;
  static Color get primary => _p.primary;
  static Color get primaryContainer => _p.primaryContainer;
  static Color get onPrimaryContainer => _p.onPrimaryContainer;
  static Color get iconTile => _p.iconTile;
  static Color get onSurface => _p.onSurface;
  static Color get onSurfaceVariant => _p.onSurfaceVariant;
  static Color get outline => _p.outline;
  static Color get error => _p.error;
  static Color get ok => _p.ok;
  static Color get railSelected => _p.railSelected;
  static Color get railIdle => _p.railIdle;
  static Color get railDivider => _p.railDivider;
  static Color get hint => _p.hint;
  static Color get card => _p.card;
  static Color get cardBorder => _p.cardBorder;
  static Color get chipFill => _p.chipFill;
  static Color get chipBorder => _p.chipBorder;
  static Color get chipText => _p.chipText;
  static Color get chipSelectedFill => _p.chipSelectedFill;
  static Color get chipSelectedBorder => _p.chipSelectedBorder;
  static Color get chipSelectedText => _p.chipSelectedText;

  // ---- 以下为原版界面实测采样（device px 采样值，见 .peekpili-analysis/shots）----
  /// 药丸高度。原版实测 63px / 1.75 = 36dp
  static const chipHeight = 36.0;
  /// 药丸横向内边距。由「精选」100px、「热门电影」152px 两个宽度联立反推 ≈ 12.5dp
  static const chipPaddingH = 12.5;
  /// 药丸描边宽（原版 1px 视觉宽 → 1dp）
  static const chipBorderWidth = 1.0;

  // ---- 原版界面几何实测（device px @density1.75 -> dp）----
  //
  // ⚠️ 历史坑（2026-09-22 修）：这批常量最初是按 @density1.5 换算的
  // （注释写「131px -> 88dp」，即 131/1.5=87.3），但实机是 **280dpi = 1.75**。
  // 于是整条左栏比原版大 1.75/1.5 = 16.7%，在 MuMu(1920x1080 @280dpi) 上
  // 同屏并排一眼可见。下面这组是逐项像素复测后的值，判据写在各条注释里。
  /// 左侧导航栏**总宽**（含右侧 1dp 分割线）。
  ///
  /// 原版结构 = 「75dp 内容盒 + 右侧 1dp 分割线」= 76dp = **133px**。
  /// 判据（逐像素，见 `.peekpili-analysis/g8/measure_home.py`）：
  ///   x=130 = (28,27,27) 左栏底色 → 内容盒右边界在 131.25px = 75dp
  ///   x=131 = (36,36,37) 覆盖率 0.75 的混合像素
  ///   x=132 = (39,39,40) 分割线纯色
  ///   x=133 = (28,27,27) 内容区底色 → 分割线右边界在 133.0px
  ///
  /// `Container(width, decoration: Border(right))` 会把 border 画在宽度**内侧**，
  /// 且 `BoxDecoration.padding` = border 尺寸，会顺势把 child 内缩 1dp ——
  /// 于是 child 拿到的正好是 75dp，与原版一致。
  static const railWidth = 76.0;
  /// 导航条目槽高。原版实测：相邻条目中心间距 112px → 64.0dp
  static const railItemHeight = 64.0;
  /// 选中块。原版实测：#123755 填充的 bbox = 103x104px → 58.9 x 59.4dp
  static const railChipWidth = 59.0;
  static const railChipHeight = 59.5;
  /// 海报卡 181x248dp（271x372px），列间距 14dp，内容区左右内边距 18dp
  static const posterAspect = 0.73;

  /// 海报墙列间隙。
  ///
  /// 由原版实测反推：内容左起 161px、最后一列右边缘 1892px、6 列海报各 270px
  ///   → 5 * gap = 1892 - 161 - 6*270 = 111 → gap = **22.2px = 12.7dp**
  /// 取 12.5dp（=21.875px）：反推海报宽 = (989.14 - 5*12.5) / 6 = 154.44dp
  /// = **270.27px**，右边缘 = 92 + 926.64 + 62.5 = 1081.14dp = **1892.0px** ✓
  /// 与实测完全吻合，左右边距各 28px 精确对称。
  ///
  /// ⚠️ 曾写 12.0（=21px）。单看 1px 无所谓，但 5 个间隙累计 5px，
  /// 会让第 6 列右边缘落在 1887px 而不是实测的 1892px —— 回归测试会抓到。
  static const gridGap = 12.5;

  /// 内容区左右内边距。
  ///
  /// 原版实测：内容左起 161px、最后一列右边缘 1892px，屏幕 1920px
  ///   → 左 161-133 = **28px**，右 1920-1892 = **28px**，即 16dp，左右严格对称。
  ///
  /// ⚠️ 曾写 17dp（「左 30 / 右 29」）—— 那是把 [railWidth] 当成 131px（75dp）
  /// 算的。实际左栏总宽 133px（76dp），所以内边距是 16dp 而不是 17dp。
  /// 两者凑出的「内容左起 161px」相同，但右边缘会差 2px。
  ///
  /// 必须与 [railWidth] 配套：内容左起 = railWidth + contentPadding
  /// = 76 + 16 = 92dp = 161px ✓
  static const contentPadding = 16.0;

  /// 网格目标列宽（用于「按目标宽算列数」，不是实际列宽）。
  ///
  /// 原版实测海报宽 270.27px = 154.44dp。内容区 989.14dp、间隙 12.5dp
  /// → (989.14 + 12.5) / (155 + 12.5) = 5.98 → round 6 → 恰好 6 列。
  /// 目标值取 155（略大于真实列宽）是为了让 5.98 向上收敛，余量不被吃掉。
  static const gridTargetWidth = 155.0;
}

ThemeData buildPeekTheme() => _buildTheme(peekDark, Brightness.dark);

/// 浅色主题。
ThemeData buildPeekLightTheme() => _buildTheme(peekLight, Brightness.light);

ThemeData _buildTheme(PeekPalette p, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.primary,
    onPrimary: brightness == Brightness.dark
        ? const Color(0xFF00315C)
        : const Color(0xFFFFFFFF),
    primaryContainer: p.primaryContainer,
    onPrimaryContainer: p.onPrimaryContainer,
    secondary: brightness == Brightness.dark
        ? const Color(0xFFBEC6DC)
        : const Color(0xFF535F70),
    onSecondary: brightness == Brightness.dark
        ? const Color(0xFF283042)
        : const Color(0xFFFFFFFF),
    secondaryContainer: brightness == Brightness.dark
        ? const Color(0xFF3E4759)
        : const Color(0xFFD7E3F8),
    onSecondaryContainer: brightness == Brightness.dark
        ? const Color(0xFFDAE2F9)
        : const Color(0xFF101C2B),
    tertiary: brightness == Brightness.dark
        ? const Color(0xFFDEBCDF)
        : const Color(0xFF6C5772),
    onTertiary: brightness == Brightness.dark
        ? const Color(0xFF3F2844)
        : const Color(0xFFFFFFFF),
    tertiaryContainer: brightness == Brightness.dark
        ? const Color(0xFF573E5C)
        : const Color(0xFFF4D9F9),
    onTertiaryContainer: brightness == Brightness.dark
        ? const Color(0xFFFBD7FC)
        : const Color(0xFF261430),
    error: p.error,
    onError: brightness == Brightness.dark
        ? const Color(0xFF690005)
        : const Color(0xFFFFFFFF),
    errorContainer: brightness == Brightness.dark
        ? const Color(0xFF93000A)
        : const Color(0xFFFFDAD6),
    onErrorContainer: brightness == Brightness.dark
        ? const Color(0xFFFFDAD6)
        : const Color(0xFF410002),
    surface: p.surface,
    onSurface: p.onSurface,
    surfaceContainerHighest: brightness == Brightness.dark
        ? const Color(0xFF33343A)
        : const Color(0xFFE3E2E6),
    onSurfaceVariant: p.onSurfaceVariant,
    outline: p.outline,
    outlineVariant: brightness == Brightness.dark
        ? const Color(0xFF43474E)
        : const Color(0xFFC3C6CF),
    scrim: Colors.black,
    inverseSurface: brightness == Brightness.dark
        ? const Color(0xFFE2E2E6)
        : const Color(0xFF313033),
    onInverseSurface: brightness == Brightness.dark
        ? const Color(0xFF2F3033)
        : const Color(0xFFF4EFF4),
    inversePrimary: brightness == Brightness.dark
        ? const Color(0xFF2A6191)
        : const Color(0xFF9FCAFF),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.surface,
    canvasColor: p.surface,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.compact,
  );

  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: p.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      iconTheme: IconThemeData(color: p.onSurface),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.onSurfaceVariant,
      textColor: p.onSurface,
    ),
    dividerTheme: DividerThemeData(
      color: p.cardBorder,
      thickness: 1,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surfaceContainerHigh,
      selectedColor: p.primaryContainer,
      side: BorderSide.none,
      labelStyle: TextStyle(color: p.onSurfaceVariant, fontSize: 13),
      secondaryLabelStyle: TextStyle(color: p.onPrimaryContainer, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceContainer,
      hintStyle: TextStyle(color: p.hint),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: p.primary,
      thumbColor: p.primary,
      inactiveTrackColor: p.outline,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.onPrimaryContainer : null,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.primaryContainer : null,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.primaryContainer,
      labelTextStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
    ),
    dialogTheme: DialogThemeData(backgroundColor: p.surfaceContainerHigh),
    textTheme: base.textTheme.apply(
      bodyColor: p.onSurface,
      displayColor: p.onSurface,
    ),
  );
}

/// 与原版一致的常用文本样式。
///
/// ⚠️ 必须是 **getter** 而不是 `static const` —— 颜色随主题变，
/// `const` 会把首次求值结果永久钉死（这正是「切了浅色但文字还是浅灰」的成因）。
class PeekText {
  static TextStyle get sectionTitle => TextStyle(
      fontSize: 15, fontWeight: FontWeight.w600, color: PeekColors.onSurface);
  static TextStyle get tileTitle =>
      TextStyle(fontSize: 15, color: PeekColors.onSurface);
  static TextStyle get tileSubtitle =>
      TextStyle(fontSize: 12, color: PeekColors.hint);
  static TextStyle get caption => TextStyle(fontSize: 11, color: PeekColors.hint);
  static TextStyle get railLabel =>
      TextStyle(fontSize: 11, color: PeekColors.onSurfaceVariant);
}
