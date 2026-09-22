import 'dart:async';

import 'package:flutter/material.dart';

import '../tvbox/spider.dart';
import 'theme.dart';

/// 时长格式化：01:23 / 1:02:03
String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// 热度格式化：53508 -> 5.4万
String fmtCount(int n) {
  if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
  return '$n';
}

String fmtBytes(num bytes) {
  if (bytes < 1024) return '${bytes.toInt()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

void peekToast(BuildContext context, String msg) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: PeekColors.surfaceContainerHigh,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
}

Future<void> peekAlert(BuildContext context, String title, String content) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: PeekColors.surfaceContainerHigh,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Text(content, style: const TextStyle(fontSize: 13, height: 1.6)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

Future<bool> peekConfirm(
  BuildContext context,
  String title,
  String content, {
  String okText = '确定',
  String cancelText = '取消',
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: PeekColors.surfaceContainerHigh,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Text(content, style: const TextStyle(fontSize: 13, height: 1.6)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelText),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(okText),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> peekPrompt(
  BuildContext context, {
  required String title,
  String? hint,
  String? initial,
  int maxLines = 1,
}) {
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: PeekColors.surfaceContainerHigh,
      title: Text(title, style: const TextStyle(fontSize: 16)),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
          child: const Text('确定'),
        ),
      ],
    ),
  );
}

/// 安全地触发一次异步调用，忽略结果
void fire(Future<void> Function() body) {
  unawaited(body().catchError((_) {}));
}

/// 把底层异常翻译成用户能看懂的一句话。
///
/// 直接 `e.toString()` 会在界面上糊出这种东西：
/// ```text
/// DioException [bad response]: This exception was thrown because the response
/// has a status code of 500 and RequestOptions.validateStatus was configured to
/// throw for this status code. The status code of 500 has the following meaning:
/// "Server error - the server failed to fulfil an apparently valid request" …
/// ```
/// 原版从不这样展示 —— 它给的是源自己的业务提示，例如
/// 「百度cookie已失效或者未配置，请前往【配置中心】站源进行配置」。
String friendlyError(Object e) {
  if (e is SpiderException) return e.message;

  final s = e.toString();

  // 源侧业务提示：Node 服务把 {msg:"…"} 放在响应体里
  final m = RegExp(r'"msg"\s*:\s*"([^"]+)"').firstMatch(s);
  if (m != null && m.group(1)!.trim().isNotEmpty) return m.group(1)!;

  if (e is TimeoutException || s.contains('TimeoutException')) {
    return '请求超时，请重试或换一个源';
  }
  if (s.contains('SocketException') || s.contains('Failed host lookup')) {
    return '网络不可用或域名解析失败';
  }
  if (s.contains('HandshakeException')) return 'HTTPS 证书校验失败';
  if (s.contains('status code of 500')) {
    return '源服务器返回 500，通常是该源需要先到【配置中心】登录或配置 Cookie';
  }
  if (s.contains('status code of 404')) return '接口地址不存在（404），请检查接口配置';
  if (s.contains('status code of 403')) return '源拒绝访问（403），可能需要 Cookie 或换源';

  // 兜底：只取首行并截断，绝不把整段堆栈糊到界面上
  final one = s.split('\n').first.trim();
  if (one.isEmpty) return '未知错误';
  return one.length > 120 ? '${one.substring(0, 120)}…' : one;
}

/// 这条业务提示是否在要求「先去配置中心配置」。
///
/// 光把提示原文摆出来是不够的 —— 用户不知道「配置中心」在哪儿。命中时播放页
/// 会多给一个「去配置中心」按钮，直达 `<Node 服务>/website`。
///
/// 实测原文（`/spider/wogg/3/play`，玩偶|4K 的夸克线路，2026-09-22）：
/// 「还没有配置夸克 Cookie，请先去配置中心登录夸克」
bool needsConfigCenter(String? msg) {
  final s = msg?.trim() ?? '';
  if (s.isEmpty) return false;
  final low = s.toLowerCase();
  return s.contains('配置中心') ||
      s.contains('登录') ||
      s.contains('扫码') ||
      s.contains('未登录') ||
      low.contains('cookie') ||
      low.contains('token');
}
