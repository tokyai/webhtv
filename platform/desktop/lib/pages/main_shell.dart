import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/storage.dart';
import '../core/theme.dart';
import '../state/app_state.dart';
import '../widgets/nav_rail.dart';
import 'favorite_page.dart';
import 'history_page.dart';
import 'home/home_page.dart';
import 'setting/settings_page.dart';

/// 主框架：左侧竖向导航栏 + 右侧内容区。
///
/// 导航项与 WebHTV 安卓版的底部导航语义一致（点播 / 直播 / 设置），
/// 桌面端按平台特点把「历史」「收藏」也放进左栏 —— 桌面屏幕宽，
/// 这两个高频入口没必要藏在顶栏图标里。
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowDisclaimer());
  }

  Future<void> _maybeShowDisclaimer() async {
    const version = '0.1.0+1';
    if (Store.get<String>('disclaimerAcceptedVersion', '') == version) return;
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: PeekColors.surfaceContainerHigh,
        title: const Text('免责声明', style: TextStyle(fontSize: 16)),
        content: const SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Text(
              '本软件为技术学习与研究用途的开源客户端，本身不提供、不存储、不制作任何音视频内容。\n\n'
              '软件内所有内容均来自用户自行导入的第三方接口，接口的可用性、合法性、'
              '内容准确性均由接口提供方负责。\n\n'
              '用户应自行确保所使用的第三方接口及其中内容符合其所在国家或地区的法律法规。\n\n'
              '本软件不收集、不上传任何个人信息，所有观看记录、收藏、接口配置等数据'
              '均仅保存在本机。\n\n'
              '继续使用即表示您已阅读、理解并同意上述全部条款。',
              style: TextStyle(fontSize: 13, height: 1.8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('退出'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('同意并继续'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await Store.set('disclaimerAcceptedVersion', version);
      await Store.set('disclaimerAcceptedDontShowAgain', true);
    } else {
      // 不同意则退出（桌面端 SystemNavigator.pop 无效，直接结束进程）
      exit(0);
    }
  }

  static List<NavItem> _itemsOf(AppState app) => kNavItems;

  List<NavItem> get _items => _itemsOf(context.read<AppState>());

  void _go(int i, List<NavItem> items) {
    if (i < 0 || i >= items.length) return;
    if (i == _index) {
      // 再次点击当前项：回到首页顶部
      if (items[i].id == 'home') _homeKey.currentState?.reload();
      return;
    }
    setState(() => _index = i);
  }

  /// 按 id 切页。保留自 PeekPili —— 它被「外部入口」（如通知点击、
  /// 悬浮球恢复、深链）调用。本工程目前没有这类入口，故暂时无引用。
  // ignore: unused_element
  void _goById(String id) {
    final i = _items.indexWhere((e) => e.id == id);
    if (i >= 0) setState(() => _index = i);
  }

  Widget _pageFor(String id) {
    switch (id) {
      case 'home':
        return HomePage(key: _homeKey);
      case 'star':
        return const FavoritePage();
      case 'history':
        return const HistoryPage();
      default:
        return const SettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final items = _itemsOf(app);
    // 开关切换后条目数会变，下标要夹紧
    final index = _index.clamp(0, items.isEmpty ? 0 : items.length - 1);
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
}
