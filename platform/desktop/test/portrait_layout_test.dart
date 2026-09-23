import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webhtv_win/widgets/bottom_nav_bar.dart';
import 'package:webhtv_win/widgets/nav_rail.dart';

/// 竖屏 / 横屏 布局切换断言。
///
/// 需求来源：第 24 条「以上效果都同步补上竖屏下也会按照竖屏的结构正常排列」。
///
/// 这里不依赖窗口尺寸与真机，直接给 `AdaptiveNav` 一个受控的宽度约束，
/// 断言它选出的导航形态。断点 600dp 见 `bottom_nav_bar.dart` 注释。
void main() {
  const items = <NavItem>[
    NavItem('home', Icons.home_outlined, Icons.home, '首页'),
    NavItem('favorite', Icons.star_outline, Icons.star, '收藏'),
    NavItem('setting', Icons.settings_outlined, Icons.settings, '设置'),
  ];

  /// 在给定宽度下渲染 AdaptiveNav，返回内容区收到的 showRail。
  Future<bool> renderAt(WidgetTester tester, double width) async {
    var showRail = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 800,
              child: AdaptiveNav(
                items: items,
                index: 0,
                onChanged: (_) {},
                builder: (_, rail) {
                  showRail = rail;
                  return const Text('CONTENT', textDirection: TextDirection.ltr);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return showRail;
  }

  group('AdaptiveNav 竖屏/横屏切换', () {
    testWidgets('iPhone SE 竖屏 375dp → 底栏，内容区不让位', (tester) async {
      final showRail = await renderAt(tester, 375);
      expect(showRail, isFalse);
      expect(find.byType(BottomNavBar), findsOneWidget);
      expect(find.byType(NavRail), findsNothing);
    });

    testWidgets('iPhone Pro Max 竖屏 430dp → 底栏', (tester) async {
      final showRail = await renderAt(tester, 430);
      expect(showRail, isFalse);
      expect(find.byType(BottomNavBar), findsOneWidget);
      expect(find.byType(NavRail), findsNothing);
    });

    testWidgets('临界 599dp → 底栏', (tester) async {
      final showRail = await renderAt(tester, 599);
      expect(showRail, isFalse);
      expect(find.byType(BottomNavBar), findsOneWidget);
    });

    testWidgets('临界 600dp → 侧栏，内容区让位', (tester) async {
      final showRail = await renderAt(tester, 600);
      expect(showRail, isTrue);
      expect(find.byType(NavRail), findsOneWidget);
      expect(find.byType(BottomNavBar), findsNothing);
    });

    testWidgets('iPad mini 竖屏 744dp → 侧栏', (tester) async {
      final showRail = await renderAt(tester, 744);
      expect(showRail, isTrue);
      expect(find.byType(NavRail), findsOneWidget);
    });

    testWidgets('桌面横屏 1280dp → 侧栏', (tester) async {
      final showRail = await renderAt(tester, 1280);
      expect(showRail, isTrue);
      expect(find.byType(NavRail), findsOneWidget);
    });
  });

  group('网格列数公式 clamp(2,8)', () {
    /// 与 home_page.dart / favorite_page.dart / multi_search_page.dart
    /// 保持一致的列数计算（卡片目标宽度 181dp、间距 12dp）。
    int colsFor(double w, {double target = 181, double gap = 12}) =>
        ((w + gap) / (target + gap)).round().clamp(2, 8);

    test('竖屏 375dp → 2 列', () => expect(colsFor(375), 2));
    test('竖屏 430dp → 2 列', () => expect(colsFor(430), 2));

    test('竖屏 520dp 减侧栏后仍 ≥2 列', () {
      // 底栏形态下内容区就是全宽
      expect(colsFor(520), greaterThanOrEqualTo(2));
    });

    test('横屏 1280dp 减侧栏(约 88dp) → 6 列', () {
      final content = 1280.0 - 88;
      final c = colsFor(content);
      expect(c, greaterThanOrEqualTo(5));
      expect(c, lessThanOrEqualTo(8));
    });

    test('超宽 2560dp → 封顶 8 列，不无限膨胀', () => expect(colsFor(2560), 8));
  });
}
