import 'package:flutter/material.dart';

/// 全局导航 / 提示入口。
///
/// 站源（Node / DEX / JS）在**没有 BuildContext** 的地方也会回调宿主，
/// 例如 `messageToDart` 的 `toast` / `openInternalWebview`。
/// 因此把根 Navigator 与根 ScaffoldMessenger 暴露成全局 key，
/// 让 `NodeBridge` 能在任意位置弹提示、推页面。
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 取当前根 Navigator（可能为 null，调用方需判空）。
NavigatorState? get rootNavigator => rootNavigatorKey.currentState;

/// 弹一条 toast（原版「识别为普通消息，显示 toast」）。
void showPeekToast(String message) {
  rootMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
}
