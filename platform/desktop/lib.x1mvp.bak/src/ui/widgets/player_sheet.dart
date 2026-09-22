import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';

/// 播放器页。
///
/// 两种进入方式：
///  - 点播：[flag] + [episodeId] → 先向源请求 `play` 拿直链
///  - 直播：直接给 [directUrl]，跳过解析
///
/// **重要**：源返回 500 时，`message` 是面向用户的**业务提示**
/// （实测："还没有配置百度网盘 Cookie，请先去配置中心登录百度网盘"），
/// 必须原样展示，不能让用户以为是程序崩溃。
class PlayerSheet extends StatefulWidget {
  const PlayerSheet({
    super.key,
    required this.flag,
    this.episodeId = '',
    this.episodeName = '',
    required this.title,
    this.directUrl,
  });

  final String flag;
  final String episodeId;
  final String episodeName;
  final String title;

  /// 直链播放（直播频道走这条路径，不需要请求源）。
  final String? directUrl;

  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<PlayerSheet> {
  late final Player _player;
  late final VideoController _controller;

  bool _resolving = true;
  String? _error;
  String? _url;

  @override
  void initState() {
    super.initState();
    MediaKit.ensureInitialized();
    _player = Player();
    _controller = VideoController(_player);
    _resolveAndPlay();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _resolveAndPlay() async {
    setState(() {
      _resolving = true;
      _error = null;
    });

    // 直播等直链场景：跳过源解析
    final direct = widget.directUrl;
    if (direct != null && direct.isNotEmpty) {
      setState(() {
        _resolving = false;
        _url = direct;
      });
      try {
        await _player.open(Media(direct));
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = '播放器打开失败：$e');
      }
      return;
    }

    final state = context.read<AppState>();
    final (result, err) = await state.resolvePlay(
      flag: widget.flag,
      episodeId: widget.episodeId,
    );

    if (!mounted) return;

    if (result == null) {
      setState(() {
        _resolving = false;
        _error = err ?? '未知错误';
      });
      return;
    }

    setState(() {
      _resolving = false;
      _url = result.url;
    });

    try {
      // httpHeaders 属于 Media 构造参数（media_kit 1.2.x），不是 open() 的参数
      await _player.open(
        Media(
          result.url,
          httpHeaders: result.header.isEmpty ? null : result.header,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '播放器打开失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940, maxHeight: 660),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.flag} · ${widget.episodeName}',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 19),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _resolving
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorPanel(
                          message: _error!,
                          onRetry: _resolveAndPlay,
                          onClose: () => Navigator.pop(context),
                        )
                      : _PlayerView(controller: _controller, player: _player),
            ),
            if (_url != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                color: theme.colorScheme.surfaceContainerLowest,
                child: Row(
                  children: [
                    Icon(Icons.link, size: 13, color: theme.hintColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SelectableText(
                        _url!,
                        maxLines: 1,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.hintColor),
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
}

class _PlayerView extends StatelessWidget {
  const _PlayerView({required this.controller, required this.player});

  final VideoController controller;
  final Player player;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Video(
            controller: controller,
            controls: AdaptiveVideoControls,
          ),
          StreamBuilder<bool>(
            stream: player.stream.error.map((e) => e.isNotEmpty),
            builder: (_, snap) {
              if (snap.data != true) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                color: Colors.red.withValues(alpha: 0.85),
                child: StreamBuilder<String>(
                  stream: player.stream.error,
                  builder: (_, s) => Text(
                    '播放错误：${s.data ?? ''}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 错误面板 —— 把源的业务提示原样展示，并提供必要的引导。
class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 网盘未配置是最常见的业务错误，给出明确的下一步指引
    final needsLogin = message.contains('Cookie') ||
        message.contains('登录') ||
        message.contains('配置');

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                needsLogin ? Icons.vpn_key_outlined : Icons.error_outline,
                size: 40,
                color: needsLogin ? theme.colorScheme.primary : theme.colorScheme.error,
              ),
              const SizedBox(height: 14),
              Text(
                needsLogin ? '需要先登录网盘账号' : '无法播放',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: SelectableText(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.55),
                ),
              ),
              if (needsLogin) ...[
                const SizedBox(height: 12),
                Text(
                  '这是源本身的提示，不是程序故障 —— 该源的播放链路依赖网盘账号。\n'
                  '配置完成后点击"重试"即可。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.hintColor, height: 1.5),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(onPressed: onClose, child: const Text('关闭')),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
