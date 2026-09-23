import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'core/debug_log.dart';
import 'core/nav.dart';
import 'core/storage.dart';
import 'core/theme.dart';
import 'pages/main_shell.dart';
import 'pages/player/floating_ball.dart';
import 'pages/player/player_page.dart';
import 'state/app_state.dart';

/// 全局持有，防止 `AppLifecycleListener` 被 GC 回收。
// ignore: unused_element
AppLifecycleListener? _appLifecycle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // media_kit 初始化（Windows 走 libmpv）
  MediaKit.ensureInitialized();

  await Store.init();

  // 调试日志落盘。
  //
  // 为什么落盘：用户报「搜不到结果」时，界面本身无法区分下面几种情况 ——
  //   ① 源服务没起来（一个源都没搜）
  //   ② 源起来了但所有源都超时
  //   ③ 拿到了数据但客户端没渲染
  // 把每一步写进文件后，复现一次就能拿到铁证（见 `DebugLog.enableFileSink`）。
  // 位置：<应用支持目录>/logs/search.log
  try {
    final dir = await getApplicationSupportDirectory();
    await DebugLog.enableFileSink(
      File('${dir.path}${Platform.pathSeparator}logs'
          '${Platform.pathSeparator}search.log'),
    );
  } catch (_) {
    // 落盘失败不影响功能
  }

  // 退出前回收 Node 子进程。
  //
  // 为什么需要：桌面端的源服务是**独立进程**，监听固定的 9988 端口。若不显式
  // 回收，关闭窗口后它会变成孤儿并永久占住端口 —— 下次启动就会报「端口被占用」。
  //
  // 这里挂 `AppLifecycleListener.onExitRequested`（桌面端关窗时触发），
  // 给一点时间让 stop() 走完；同时把返回码交给框架决定是否真的退出。
  // 另外配合 Node 侧的心跳看护（见 `backend/source_runtime.dart`）双保险：
  // 即使本回调因崩溃/强杀没跑到，子进程也会在约 15 秒内自杀。
  //
  // iOS 上这段是空转：Node 在同进程内，宿主退出即随之消失，无孤儿问题。
  final lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      try {
        await AppState.I.stopService();
      } catch (_) {
        // 退出路径尽力而为，失败也不能阻塞关闭
      }
      return AppExitResponse.exit;
    },
  );
  // 显式持有引用，避免被 GC 回收后回调失效（`AppLifecycleListener` 不会自我保活）。
  _appLifecycle = lifecycle;

  // 悬浮球「回全屏」：用根 navigator 重新 push 播放页，
  // 并把被接管的播放器交还（原版 `_restoreFromFloatingBall`）。
  FloatingBall.onRestore = () {
    final nav = rootNavigatorKey.currentState;
    final h = FloatingBall.restore();
    if (nav == null || h == null) return;
    nav.push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        site: h.session.site,
        vod: h.session.vod,
        lineIndex: h.session.lineIndex,
        episodeIndex: h.session.episodeIndex,
        handoff: h,
      ),
    ));
  };

  // ---- 屏幕方向策略 ----
  //
  // **iOS：不锁方向**。用户要求「竖屏结构 + 元素符合竖屏配置」，但播放器
  // 需要能转横屏全屏观看。因此这里**不调用** setPreferredOrientations，
  // 让系统跟随设备；界面层用 `LayoutBuilder` 做竖/横自适应（见 main_shell）。
  //
  // 桌面端：窗口可自由缩放，同样不锁。
  //
  // （历史上这里对非桌面平台强制横屏，是为 Android 电视端准备的；
  //   本工程只有 Windows + iOS 两个目标，该分支已无适用对象。）
  if (Platform.isAndroid) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // AppState 必须先 init 才能读 themeMode，因此放在 runApp 之前。
  await AppState.I.init();

  runApp(const WebHtvApp());
}

class WebHtvApp extends StatelessWidget {
  const WebHtvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: AppState.I,
      child: const _AppRoot(),
    );
  }
}

/// 主题模式需要读 [AppState]，所以单独抽一层。
///
/// ⚠️ **`PeekColors.use(...)` 必须在构建树之前调用** —— 调色板是一组
/// `static getter`，全局只有一份；晚一步调用，这一帧就会用错颜色。
class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final mode = switch (app.themeMode) {
      PeekThemeMode.light => ThemeMode.light,
      PeekThemeMode.dark => ThemeMode.dark,
      PeekThemeMode.system => ThemeMode.system,
    };

    final platformBrightness =
        MediaQuery.maybePlatformBrightnessOf(context) ?? Brightness.dark;
    final effective = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };
    PeekColors.use(effective);

    return MaterialApp(
      title: 'WebHTV',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      scaffoldMessengerKey: rootMessengerKey,
      theme: buildPeekLightTheme(),
      darkTheme: buildPeekTheme(),
      themeMode: mode,
      scrollBehavior: const _PeekScrollBehavior(),
      home: const MainShell(),
    );
  }
}

/// 桌面端支持鼠标拖拽滚动。
class _PeekScrollBehavior extends MaterialScrollBehavior {
  const _PeekScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
