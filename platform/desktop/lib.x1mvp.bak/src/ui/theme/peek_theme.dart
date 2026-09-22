/// 视觉基座 —— 移植自 PeekPili `lib/core/theme.dart`（像素级复刻原版安卓界面）。
///
/// 保留原文件的两条关键约束：
/// 1. **颜色必须走 `static getter`**，不能 `static const` —— 否则切换主题时
///    首次求值结果会被永久钉死。
/// 2. **几何常量保持 `const`** —— 它们不随主题变，`const gap = PeekColors.gridGap`
///    这类写法继续有效。
///
/// [PeekColors.use] 必须在**构建树之前**调用（见 `main.dart` 的 `build()`）。
library;

import 'package:flutter/material.dart';

/// 一套配色（深色或浅色）。
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

/// 深色（默认）。色值来自原版实际运行界面采样。
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

/// 浅色。
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

/// 颜色门面 + 几何常量。
class PeekColors {
  PeekColors._();

  static PeekPalette _p = peekDark;

  static PeekPalette get current => _p;

  /// 按亮度切换调色板。**必须在构建树之前调用**。
  static void use(Brightness b) =>
      _p = b == Brightness.dark ? peekDark : peekLight;

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

  // ---- 药丸（分类 chip）几何 ----
  /// 药丸高度。原版实测 63px / 1.75 = 36dp
  static const chipHeight = 36.0;
  /// 药丸横向内边距。由「精选」100px、「热门电影」152px 两个宽度联立反推 ≈ 12.5dp
  static const chipPaddingH = 12.5;
  /// 药丸描边宽（原版 1px 视觉宽 → 1dp）
  static const chipBorderWidth = 1.0;

  // ---- 左栏几何（device px @density1.75 -> dp）----
  /// 左侧导航栏**总宽**（含右侧 1dp 分割线）= 75dp 内容盒 + 1dp 分割线。
  static const railWidth = 76.0;
  /// 导航条目槽高。原版实测：相邻条目中心间距 112px → 64.0dp
  static const railItemHeight = 64.0;
  /// 选中块。原版实测：#123755 填充的 bbox = 103x104px → 58.9 x 59.4dp
  static const railChipWidth = 59.0;
  static const railChipHeight = 59.5;

  /// 海报卡 181x248dp（271x372px）。
  static const posterAspect = 0.73;

  /// 海报墙列间隙。由原版实测反推 ≈ 12.7dp，取 12.5dp 可与右边缘像素级对齐。
  static const gridGap = 12.5;

  /// 内容区左右内边距。内容左起 = railWidth + contentPadding = 76 + 16 = 92dp。
  static const contentPadding = 16.0;

  /// 网格目标列宽（用于「按目标宽算列数」，不是实际列宽）。
  static const gridTargetWidth = 155.0;
}

ThemeData buildPeekTheme() => _buildTheme(peekDark, Brightness.dark);

ThemeData buildPeekLightTheme() => _buildTheme(peekLight, Brightness.light);

ThemeData _buildTheme(PeekPalette p, Brightness brightness) {
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.primary,
    onPrimary:
        brightness == Brightness.dark ? const Color(0xFF00315C) : Colors.white,
    primaryContainer: p.primaryContainer,
    onPrimaryContainer: p.onPrimaryContainer,
    secondary: brightness == Brightness.dark
        ? const Color(0xFFBEC6DC)
        : const Color(0xFF535F70),
    onSecondary: brightness == Brightness.dark
        ? const Color(0xFF283042)
        : Colors.white,
    secondaryContainer: brightness == Brightness.dark
        ? const Color(0xFF3E4759)
        : const Color(0xFFD7E3F8),
    onSecondaryContainer: brightness == Brightness.dark
        ? const Color(0xFFDAE2F9)
        : const Color(0xFF101C2B),
    tertiary: brightness == Brightness.dark
        ? const Color(0xFFDEBCDF)
        : const Color(0xFF6C5772),
    onTertiary:
        brightness == Brightness.dark ? const Color(0xFF3F2844) : Colors.white,
    tertiaryContainer: brightness == Brightness.dark
        ? const Color(0xFF573E5C)
        : const Color(0xFFF4D9F9),
    onTertiaryContainer: brightness == Brightness.dark
        ? const Color(0xFFFBD7FC)
        : const Color(0xFF261430),
    error: p.error,
    onError:
        brightness == Brightness.dark ? const Color(0xFF690005) : Colors.white,
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
/// 必须是 **getter** 而不是 `static const` —— 颜色随主题变。
class PeekText {
  static TextStyle get sectionTitle => TextStyle(
      fontSize: 15, fontWeight: FontWeight.w600, color: PeekColors.onSurface);
  static TextStyle get tileTitle =>
      TextStyle(fontSize: 15, color: PeekColors.onSurface);
  static TextStyle get tileSubtitle =>
      TextStyle(fontSize: 12, color: PeekColors.hint);
  static TextStyle get caption =>
      TextStyle(fontSize: 11, color: PeekColors.hint);
  static TextStyle get railLabel =>
      TextStyle(fontSize: 11, color: PeekColors.onSurfaceVariant);
}
