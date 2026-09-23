import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/window.dart';
import '../../player/danmaku/danmaku_controller.dart';
import '../../player/danmaku/danmaku_overlay.dart';
import '../../player/danmaku/danmaku_session.dart';

/// 一条可直接播放的媒体。
///
/// 网盘（AList / WebDAV）里列表项只有文件名，真正的直链要现场解析，
/// 所以播放页拿的是「按需解析」的回调而不是现成地址。
class DirectMedia {
  final String url;

  /// 标题（顶栏 + 弹幕匹配）
  final String title;

  /// 副标题（文件名 / 集名）
  final String? subtitle;

  /// 请求头，直接透传给 media_kit（网盘直链普遍需要 Referer / UA）
  final Map<String, String>? headers;

  const DirectMedia({
    required this.url,
    required this.title,
    this.subtitle,
    this.headers,
  });
}

/// 直链播放页 —— 播放**已知完整地址**的视频/音频，支持列表连播。
///
/// 网盘（AList / WebDAV）、115 分享、推送播放这类场景拿到的就是最终直链，
/// 不需要再走站源的 `detail` / `play` 解析，因此单独开一个轻量播放页，
/// 而不是硬塞进 [PlayerPage] 的 Site+Vod 模型里。
///
/// 与 [PlayerPage] 的差异：
/// * 没有线路 / 剧集概念，只有列表上一个 / 下一个（由 [resolve] 现场取地址）
/// * 支持自定义请求头
/// * 弹幕按标题匹配，可随时开关
class DirectPlayerPage extends StatefulWidget {
  /// 列表长度（1 表示单个文件，不显示上一/下一）
  final int count;

  /// 起播下标
  final int startIndex;

  /// 按需解析第 [index] 项；返回 null 视为该项不可播（自动跳过）
  final Future<DirectMedia?> Function(int index) resolve;

  /// 是否尝试加载弹幕
  final bool enableDanmaku;

  const DirectPlayerPage({
    super.key,
    required this.resolve,
    this.count = 1,
    this.startIndex = 0,
    this.enableDanmaku = true,
  });

  @override
  State<DirectPlayerPage> createState() => _DirectPlayerPageState();
}

class _DirectPlayerPageState extends State<DirectPlayerPage> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  final DanmakuController _danmaku = DanmakuController();
  bool _danmakuOn = false;

  late int _index = widget.startIndex;
  DirectMedia? _media;

  bool _loading = true;
  bool _playing = false;
  bool _showControls = true;
  String? _error;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;

  /// 视频宽高比（media_kit 通过 width/height 流给出，0 表示未知）
  double _aspect = 16 / 9;

  Timer? _hideTimer;
  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  static DanmakuStyle _styleFromStore() => DanmakuStyle(
        fontSize: Store.get<double>('danmakuFontSize', 16),
        opacity: Store.get<double>('danmakuOpacity', 1.0),
        scrollEnabled: Store.get<bool>('danmakuScroll', true),
        areaRatio: Store.get<double>('danmakuArea', 0.6),
        scrollSeconds: Store.get<double>('danmakuSpeed', 8.0),
        fixedSeconds: Store.get<double>('danmakuFixedSeconds', 4.0),
        bold: Store.get<bool>('danmakuBold', true),
      );

  @override
  void initState() {
    super.initState();
    _subs.add(_player.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
    }));
    _subs.add(_player.stream.position.listen((v) {
      if (mounted) setState(() => _position = v);
    }));
    _subs.add(_player.stream.duration.listen((v) {
      if (mounted) setState(() => _duration = v);
    }));
    _subs.add(_player.stream.error.listen((e) {
      if (mounted && _loading) {
        setState(() {
          _loading = false;
          _error = '播放失败：${friendlyError(e)}';
        });
      }
    }));
    _subs.add(_player.stream.completed.listen((done) {
      if (done && mounted) _next(auto: true);
    }));
    _subs.add(_player.stream.width.listen((w) => _syncAspect(w, null)));
    _subs.add(_player.stream.height.listen((h) => _syncAspect(null, h)));
    WakelockPlus.enable();
    DanmakuSession.revision.addListener(_onDanmakuRevision);
    _open(_index);
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    WakelockPlus.disable();
    DanmakuSession.revision.removeListener(_onDanmakuRevision);
    DanmakuSession.clear();
    _danmaku.dispose();
    super.dispose();
  }

  /// 打开列表第 [i] 项。解析失败会顺延到下一项（最多绕一圈）。
  Future<void> _open(int i) async {
    setState(() {
      _loading = true;
      _error = null;
      _index = i;
    });
    final n = widget.count;
    for (var step = 0; step < n; step++) {
      final idx = (i + step) % n;
      DirectMedia? m;
      try {
        m = await widget.resolve(idx);
      } catch (e) {
        m = null;
      }
      if (m == null || m.url.isEmpty) continue;
      try {
        await _player.open(Media(m.url, httpHeaders: m.headers), play: true);
        if (!mounted) return;
        setState(() {
          _media = m;
          _index = idx;
          _loading = false;
        });
        DanmakuSession.clear();
        _danmaku.clear();
        if (widget.enableDanmaku && Store.get<bool>('danmakuEnabled', true)) {
          setState(() => _danmakuOn = true);
          unawaited(DanmakuSession.load(
            title: m.title,
            episode: m.subtitle ?? '',
          ));
        } else {
          setState(() => _danmakuOn = false);
        }
        return;
      } catch (_) {
        // 该条打不开，继续试下一条
      }
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _error = '没有可播放的地址';
      });
    }
  }

  int _vw = 0;
  int _vh = 0;

  /// 宽高任一变化都重算比例（竖屏短剧是 9:16，横屏是 16:9）
  void _syncAspect(int? w, int? h) {
    if (w != null) _vw = w;
    if (h != null) _vh = h;
    if (_vw <= 0 || _vh <= 0) return;
    final a = _vw / _vh;
    if (!mounted || (a - _aspect).abs() < 0.001) return;
    setState(() => _aspect = a);
  }

  void _prev() {
    if (widget.count <= 1) return;
    _open((_index - 1 + widget.count) % widget.count);
  }

  void _next({bool auto = false}) {
    if (widget.count <= 1) return;
    if (auto && _index + 1 >= widget.count) return; // 播完最后一集不循环
    _open((_index + 1) % widget.count);
  }

  void _onDanmakuRevision() {
    if (!mounted) return;
    final style = _styleFromStore();
    if (DanmakuSession.items.isEmpty) {
      _danmaku.clear();
      return;
    }
    var list = DanmakuController.filterBlocked(
      DanmakuSession.items,
      keywords: DanmakuController.splitRules(
          Store.get<String>('danmakuBlockWords', '')),
      regexes: DanmakuController.splitRules(
          Store.get<String>('danmakuBlockRegex', '')),
    );
    if (Store.get<bool>('danmakuMerge', false)) {
      list = DanmakuController.mergeDuplicates(list);
    }
    _danmaku.setItems(list, style: style);
    setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  /// 切换全屏。桌面端（Windows）最大化/还原窗口，移动端切换系统 UI。
  void _toggleFullscreen() {
    if (Platform.isWindows) {
      DesktopWindow.toggleFullscreen();
      return;
    }
    SystemChrome.setEnabledSystemUIMode(
      _showControls ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFromStore();
    final media = _media;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        // 桌面端：播放器上点鼠标右键切换全屏（对齐原版行为）
        onSecondaryTapUp: (_) => _toggleFullscreen(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _aspect,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Video(
                      controller: _controller,
                      controls: NoVideoControls,
                      fill: Colors.black,
                    ),
                    DanmakuOverlay(
                      player: _player,
                      controller: _danmaku,
                      style: style,
                      enabled: _danmakuOn,
                    ),
                  ],
                ),
              ),
            ),
            if (_loading)
              const Center(
                child: SizedBox(
                    width: 34,
                    height: 34,
                    child: CircularProgressIndicator(strokeWidth: 2.4)),
              ),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.white70, size: 40),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13, height: 1.6),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => _open(_index),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ),
            if (_showControls) _topBar(media),
            if (_showControls) _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _topBar(DirectMedia? media) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 6,
          left: 8,
          right: 12,
          bottom: 24,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xCC000000), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    media?.title ?? '正在解析…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  if ((media?.subtitle ?? '').isNotEmpty)
                    Text(
                      media!.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: '弹幕',
              icon: Icon(
                _danmakuOn ? Icons.subtitles : Icons.subtitles_off_outlined,
                color: _danmakuOn ? PeekColors.primary : Colors.white70,
              ),
              onPressed: () {
                setState(() => _danmakuOn = !_danmakuOn);
                if (_danmakuOn && DanmakuSession.items.isEmpty) {
                  final m = _media;
                  if (m != null) {
                    unawaited(DanmakuSession.load(
                      title: m.title,
                      episode: m.subtitle ?? '',
                    ));
                  }
                }
                _scheduleHide();
              },
            ),
            IconButton(
              tooltip: '复制播放地址',
              icon: const Icon(Icons.link, color: Colors.white70),
              onPressed: () async {
                final u = _media?.url ?? '';
                if (u.isEmpty) return;
                await Clipboard.setData(ClipboardData(text: u));
                if (context.mounted) peekToast(context, '已复制播放源');
                _scheduleHide();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    final total = _duration.inMilliseconds;
    final pos = _position.inMilliseconds.clamp(0, total == 0 ? 1 : total);
    final multi = widget.count > 1;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: MediaQuery.of(context).padding.bottom + 8,
          top: 30,
        ),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xCC000000), Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(_fmt(_position),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
                Expanded(
                  child: Slider(
                    value: total == 0 ? 0 : pos / total,
                    onChanged: (v) {
                      _player
                          .seek(Duration(milliseconds: (v * total).round()));
                      _scheduleHide();
                    },
                  ),
                ),
                Text(_fmt(_duration),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (multi)
                  IconButton(
                    tooltip: '上一个',
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    onPressed: _prev,
                  ),
                IconButton(
                  iconSize: 40,
                  icon: Icon(
                    _playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    _player.playOrPause();
                    _scheduleHide();
                  },
                ),
                if (multi)
                  IconButton(
                    tooltip: '下一个',
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: _next,
                  ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () {
                    final next = _speed >= 2.0 ? 1.0 : _speed + 0.25;
                    _player.setRate(next);
                    setState(() => _speed = next);
                    _scheduleHide();
                  },
                  child: Text('${_speed}x',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12)),
                ),
                if (multi)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text('${_index + 1}/${widget.count}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
