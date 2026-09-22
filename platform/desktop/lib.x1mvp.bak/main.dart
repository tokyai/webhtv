import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'src/state/app_state.dart';
import 'src/ui/pages/home_page.dart';
import 'src/ui/pages/live_page.dart';
import 'src/ui/pages/favorite_page.dart';
import 'src/ui/pages/history_page.dart';
import 'src/ui/pages/search_page.dart';
import 'src/ui/pages/settings_page.dart';
import 'src/ui/pages/site_page.dart';
import 'src/ui/pages/source_page.dart';
import 'src/ui/theme/peek_nav.dart';
import 'src/ui/theme/peek_theme.dart';
import 'src/ui/widgets/peek_nav_rail.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const WebHtvApp(),
    ),
  );
  // 初始化放到 runApp 之后，避免阻塞首帧
  state.init();
}

class WebHtvApp extends StatefulWidget {
  const WebHtvApp({super.key});

  @override
  State<WebHtvApp> createState() => _WebHtvAppState();
}

class _WebHtvAppState extends State<WebHtvApp> with WidgetsBindingObserver {
  Brightness _brightness = Brightness.dark;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncPlatformBrightness();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _syncPlatformBrightness();

  void _syncPlatformBrightness() {
    final b = PlatformDispatcher.instance.platformBrightness;
    if (b != _brightness) {
      setState(() => _brightness = b);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ 必须在构建树之前切换调色板 —— 整棵树 build 时读到的才是新值
    PeekColors.use(_brightness);

    return MaterialApp(
      title: 'WebHTV',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootMessengerKey,
      theme: _brightness == Brightness.dark
          ? buildPeekTheme()
          : buildPeekLightTheme(),
      home: const MainShell(),
    );
  }
}

/// 主框架：左栏 + 内容区（无全局 SafeArea，各页自行处理顶部留白）。
///
/// 结构对齐 PeekPili `MainShell`：条目可见性由 [AppState] 决定，
/// 内容用 [IndexedStack] 保活（切页不重建、不丢滚动位置）。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();
  final GlobalKey<SearchPageState> _searchKey = GlobalKey<SearchPageState>();

  /// 条目可见性：
  /// - 没有源时只留「源管理」和「设置」，避免用户点进空白页
  /// - 有源但服务未就绪时，站点/收藏/历史仍可见（可先看缓存态）
  static List<NavItem> _itemsOf(AppState app) {
    if (!app.hasSources) {
      return const [
        NavItem('source', Icons.cloud_download_outlined,
            Icons.cloud_download_rounded, '源管理'),
        NavItem('setting', Icons.settings_outlined, Icons.settings_rounded, '设置'),
      ];
    }
    return kNavItems;
  }

  Widget _pageFor(String id) {
    switch (id) {
      case 'home':
        return HomePage(key: _homeKey);
      case 'live':
        return const LivePage();
      case 'history':
        return const HistoryPage();
      case 'star':
        return const FavoritePage();
      case 'site':
        return const SitePage();
      case 'source':
        return const SourcePage();
      default:
        return const SettingsPage();
    }
  }

  void _go(int i, List<NavItem> items) {
    if (i < 0 || i >= items.length) return;
    // 重按当前「首页」→ 回到顶部并刷新（对齐 PeekPili 的 _homeKey 行为）
    if (i == _index && items[i].id == 'home') {
      _homeKey.currentState?.reload();
      return;
    }
    setState(() => _index = i);
  }

  /// 打开搜索页（首页顶栏的搜索按钮走这里，走全局导航而非切左栏）。
  Future<void> _openSearch() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SearchPage(key: _searchKey),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = _itemsOf(app);
    final index = _index.clamp(0, items.isEmpty ? 0 : items.length - 1);

    // 没有源时给首页/搜索一个明确的引导入口
    if (!app.hasSources) {
      return Scaffold(
        backgroundColor: PeekColors.surface,
        body: Row(
          children: [
            NavRail(items: items, index: index, onChanged: (i) => _go(i, items)),
            Expanded(
              child: IndexedStack(
                index: index,
                children: [for (final it in items) _pageFor(it.id)],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: Row(
        children: [
          NavRail(items: items, index: index, onChanged: (i) => _go(i, items)),
          Expanded(
            child: _ContentHost(
              index: index,
              items: items,
              pageFor: _pageFor,
              onOpenSearch: _openSearch,
            ),
          ),
        ],
      ),
    );
  }
}

/// 内容宿主 —— 把「打开搜索」的入口注入首页（首页自己不持有 Navigator 逻辑）。
class _ContentHost extends StatelessWidget {
  const _ContentHost({
    required this.index,
    required this.items,
    required this.pageFor,
    required this.onOpenSearch,
  });

  final int index;
  final List<NavItem> items;
  final Widget Function(String) pageFor;
  final VoidCallback onOpenSearch;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: index,
      children: [
        for (final it in items)
          it.id == 'home'
              ? HomePageHost(onOpenSearch: onOpenSearch)
              : pageFor(it.id),
      ],
    );
  }
}

/// 首页宿主 —— 让 HomePage 能拿到 shell 级的「打开搜索」回调，
/// 同时保证 `HomePageState.reload()` 仍可通过 GlobalKey 触达。
class HomePageHost extends StatefulWidget {
  const HomePageHost({super.key, required this.onOpenSearch});

  final VoidCallback onOpenSearch;

  @override
  State<HomePageHost> createState() => _HomePageHostState();
}

class _HomePageHostState extends State<HomePageHost> {
  @override
  Widget build(BuildContext context) {
    return HomePage(onOpenSearch: widget.onOpenSearch);
  }
}
