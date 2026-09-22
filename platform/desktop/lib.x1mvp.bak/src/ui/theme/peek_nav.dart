/// 全局导航键 —— 移植自 PeekPili `lib/core/nav.dart`。
///
/// 作用：让任意层级（含弹层内部）都能弹 Toast，而不必依赖当前 `BuildContext`
/// 的祖先链。窗口级 SnackBar 走 rootMessengerKey。
library;

import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

NavigatorState? get rootNavigator => rootNavigatorKey.currentState;

/// 弹一个浮层提示。
void peekToast(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ));
    return;
  }
  rootMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 13)),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
}
