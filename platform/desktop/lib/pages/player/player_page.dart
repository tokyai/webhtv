import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/debug_log.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../core/window.dart';
import '../../state/app_state.dart';
import '../../tvbox/backend_bridge.dart';
import '../../tvbox/models.dart';
import '../../tvbox/playlist_merge.dart';
import '../../tvbox/spider.dart';
import '../search/multi_search_page.dart';
import '../../player/danmaku/danmaku_controller.dart';
import '../../player/danmaku/danmaku_item.dart';
import '../../player/danmaku/danmaku_overlay.dart';
import '../../player/danmaku/danmaku_session.dart';
import 'floating_ball.dart';

/// 播放页。
///
/// 三端统一走 media_kit（Windows/iOS 用 libmpv，Android 用 media3/libmpv），
/// 因此一套源码即可在 Android / iOS / Windows 上播放。
class PlayerPage extends StatefulWidget {
  final Site site;
  final Vod vod;
  final int lineIndex;
  final int episodeIndex;

  /// 覆盖线路列表。
  ///
  /// 上游详情页开启「合并播放列表」后，会先把 `vod.lines` 合成一条「合集」
  /// 线路再进来 —— 那时 `vod.lines` 的原始下标与合并后的剧集下标已经对不上，
  /// 必须由调用方把**已经合并好的**列表传进来，播放页直接用，不重新推导。
  final List<PlayLine>? linesOverride;

  /// 从悬浮球恢复时传入：复用已有的播放器与渲染控制器，
  /// 不重新创建、不重新 open —— 进度不丢（原版 `_restoreFromFloatingBall`）。
  final FloatingHandoff? handoff;

  const PlayerPage({
    super.key,
    required this.site,
    required this.vod,
    required this.lineIndex,
    required this.episodeIndex,
    this.linesOverride,
    this.handoff,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player = widget.handoff?.player ?? Player();
  late final VideoController _controller =
      widget.handoff?.controller ?? VideoController(_player);

  late final int _lineIndex = widget.lineIndex;
  late int _episodeIndex = widget.episodeIndex;

  bool _loading = true;
  String? _error;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;
  bool _showControls = true;
  Timer? _hideTimer;
  Timer? _saveTimer;
  final List<StreamSubscription> _subs = <StreamSubscription>[];

  // ---------------- 弹幕 ----------------
  final DanmakuController _danmaku = DanmakuController();
  bool _danmakuOn = Store.get<bool>('danmakuEnabled', true);

  // ---------------- 跳过片尾 ----------------
  //
  // 对齐原版 `[T4] 触发跳过片尾: 剩余=` —— 播放到距片尾 N 秒时自动跳下一集。
  bool get _skipTailEnabled => Store.get<bool>('skipTailEnabled', false);
  int get _skipTailSeconds => Store.get<int>('skipTailSeconds', 90);
  bool _tailSkipped = false;

  // ---------------- 锁定屏幕 ----------------
  bool _locked = false;

  // ---------------- 长按倍速 ----------------
  //
  // 原版按住画面加速、松手复原。这里按住时切 `_longPressRate`，松手切回 `_speed`。
  bool _longPressing = false;
  double get _longPressRate => Store.get<double>('longPressRate', 3.0);

  // ---------------- 手势进度条 ----------------
  Duration _dragTarget = Duration.zero;
  bool _dragging = false;

  /// 点按定位：暂停状态点左/右半屏后退/前进 10 秒，
  /// 播放中点按只切控件显隐（与原版一致）。
  void _tapSeek(TapUpDetails d) {
    if (_locked) {
      setState(() => _showControls = !_showControls);
      return;
    }
    if (!_playing || _duration.inMilliseconds == 0) {
      _toggleControls();
      return;
    }
    final w = MediaQuery.of(context).size.width;
    final dx = d.localPosition.dx;
    const step = Duration(seconds: 10);
    if (dx < w * 0.35) {
      final t = _position - step;
      _player.seek(t < Duration.zero ? Duration.zero : t);
      peekToast(context, '后退 10 秒');
    } else if (dx > w * 0.65) {
      final t = _position + step;
      _player.seek(t > _duration ? _duration : t);
      peekToast(context, '前进 10 秒');
    } else {
      _toggleControls();
    }
  }

  /// 从设置页读取弹幕外观与行为（对应原版「弹幕设置」各项）
  static DanmakuStyle _danmakuStyleFromStore() => DanmakuStyle(
        fontSize: Store.get<double>('danmakuFontSize', 16),
        opacity: Store.get<double>('danmakuOpacity', 1.0),
        scrollEnabled: Store.get<bool>('danmakuScroll', true),
        areaRatio: Store.get<double>('danmakuArea', 0.6),
        scrollSeconds: Store.get<double>('danmakuSpeed', 8.0),
        fixedSeconds: Store.get<double>('danmakuFixedSeconds', 4.0),
        bold: Store.get<bool>('danmakuBold', true),
      );

  /// 按设置整理弹幕：屏蔽词 → 合并重复。
  ///
  /// 原版在加载后即做这两步，渲染层拿到的永远是「最终要显示的集合」，
  /// 这样切换开关只需重新走一遍，不用改渲染逻辑。
  static List<DanmakuItem> _prepareDanmaku(List<DanmakuItem> raw) {
    var list = raw;
    list = DanmakuController.filterBlocked(
      list,
      keywords: DanmakuController.splitRules(
          Store.get<String>('danmakuBlockWords', '')),
      regexes:
          DanmakuController.splitRules(Store.get<String>('danmakuBlockRegex', '')),
    );
    if (Store.get<bool>('danmakuMerge', false)) {
      list = DanmakuController.mergeDuplicates(list);
    }
    return list;
  }

  PlayLine get _line {
    final lines = widget.linesOverride ?? widget.vod.lines;
    if (_lineIndex >= lines.length) return PlayLine(name: '', episodes: const []);
    return lines[_lineIndex];
  }

  Episode? get _episode {
    final eps = _line.episodes;
    if (_episodeIndex >= eps.length) return null;
    return eps[_episodeIndex];
  }

  bool _fromFloating = false;

  @override
  void initState() {
    super.initState();
    // 从悬浮球恢复：画面已经在播，不能再走一遍解析/open
    _fromFloating = widget.handoff != null;
    if (_fromFloating) {
      _loading = false;
      _position = _player.state.position;
      _duration = _player.state.duration;
      _playing = _player.state.playing;
    }
    _subs.add(_player.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
      FloatingBall.refresh();
    }));
    _subs.add(_player.stream.position.listen((v) {
      if (mounted) setState(() => _position = _dragging ? _dragTarget : v);
      _checkSkipTail(v);
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
        // 原版 `[T4] 自动换源: ExoPlayer 播放失败` →
        // 播放失败且开启了自动换源时，用片名快搜其他源并跳转
        _tryAutoChange('播放失败：${friendlyError(e)}');
      }
    }));
    _subs.add(_player.stream.completed.listen((done) {
      if (done && mounted) _playNext();
    }));
    WakelockPlus.enable();
    DanmakuSession.revision.addListener(_onDanmakuRevision);
    if (!_fromFloating) _resolveAndPlay();
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) => _save());
    _scheduleHide();
  }

  @override
  void dispose() {
    _save();
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    // 原版 `[T4] dispose: 悬浮球模式` —— 转悬浮球时不释放播放器，
    // 所有权已交给 FloatingBall，播放继续。
    if (FloatingBall.shouldKeepPlaying()) {
      DebugLog.add('播放', 'dispose: 悬浮球模式');
    } else {
      _player.dispose();
    }
    WakelockPlus.disable();
    DanmakuSession.revision.removeListener(_onDanmakuRevision);
    DanmakuSession.clear();
    _danmaku.dispose();
    super.dispose();
  }

  /// 最小化到悬浮球（原版播放页左上角的「小窗」按钮）
  void _toFloatingBall() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    FloatingBall.enter(
      player: _player,
      controller: _controller,
      session: FloatingSession(
        site: widget.site,
        vod: widget.vod,
        lineIndex: _lineIndex,
        episodeIndex: _episodeIndex,
      ),
      overlay: overlay,
    );
    Navigator.of(context).maybePop();
  }

  /// 弹幕数据变化（加载完成 / 清空 / 推送覆盖）→ 重建渲染层
  void _onDanmakuRevision() {
    if (!mounted) return;
    final style = _danmakuStyleFromStore();
    final on = Store.get<bool>('danmakuEnabled', true);
    if (DanmakuSession.items.isEmpty) {
      _danmaku.clear();
    } else {
      _danmaku.setItems(_prepareDanmaku(DanmakuSession.items), style: style);
    }
    setState(() => _danmakuOn = on);
  }

  /// 触发弹幕拉取（起播时 / 用户重新打开弹幕时）
  void _loadDanmaku() {
    final ep = _episode;
    unawaited(DanmakuSession.load(
      title: widget.vod.name,
      episode: ep?.name ?? '',
    ));
  }

  Future<void> _toggleDanmaku() async {
    final v = !_danmakuOn;
    setState(() => _danmakuOn = v);
    await Store.set('danmakuEnabled', v);
    if (v && DanmakuSession.items.isEmpty) _loadDanmaku();
  }


  Future<void> _resolveAndPlay() async {
    final ep = _episode;
    if (ep == null) {
      setState(() {
        _loading = false;
        _error = '该线路没有可播放的剧集';
      });
      return;
    }
    // 说明：PeekPili 在这里调 `PlaySession.update(...)`，把当前播放信息
    // 发布到全局，供**进程内** spider 通过 `messageToDart({action:'getPlayInfo'})`
    // 反向读取。本工程的源跑在独立 Node 子进程里，读不到本进程内存，
    // 这条路（以及对应的 `getPlayInfo` 能力）在桌面端不存在，故移除。
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await context.read<AppState>().player(
            widget.site,
            _line.name,
            ep.url,
          );
      var url = res.url.isNotEmpty ? res.url : (res.playUrl ?? '');
      if (url.isEmpty) {
        // spider 给了业务提示就照原样呈现（原版行为），否则用通用文案
        final msg = res.msg?.trim() ?? '';
        throw SpiderException(msg.isNotEmpty ? msg : '未获取到播放地址');
      }
      // 形如 解析名$地址 的返回，取地址部分
      if (url.contains(r'$') && !url.startsWith('http')) {
        url = url.split(r'$').last;
      }
      // 有些源返回的是**网页地址**而不是媒体直链（原版
      // `[T4DetailView] 需要嗅探，URL:`），PeekPili 会调 `VideoSniffer`。
      //
      // 桌面端没有内置 webview，也就没有嗅探器。这里的处理是：
      // 识别出明显的 HTML 页面后，给出可操作提示而不是把网页当视频播
      // （直接喂给 mpv 会得到一个毫无信息的解码失败）。
      // 提示里带上原始地址，用户可用系统浏览器打开确认。
      if (_looksLikeWebPage(url)) {
        throw SpiderException(
          '该线路返回的是网页而不是视频地址，桌面端无法自动嗅探。\n'
          '地址：$url',
        );
      }
      DebugLog.add(
        '播放',
        '${widget.site.name} | ${_line.name}\n'
            'URL: $url\n'
            'Header: ${res.header?.entries.map((e) => '${e.key}=${e.value}').join('; ') ?? '无'}'
            '${res.danmaku == null ? '' : '\n弹幕: ${res.danmaku}'}',
      );
      // spider 给的 Referer/User-Agent 必须带给播放器，否则部分 CDN 直接 403。
      // 实测 DEX 源（瓜子┃秒播）返回
      //   User-Agent: Lavf/57.83.100
      //   Referer: http://WJiZxLXA2.com/
      await _player.open(Media(url, httpHeaders: res.header), play: true);
      await _player.setRate(_speed);
      if (mounted) setState(() => _loading = false);
      _restorePosition();
      // 弹幕：优先用站源自带的 danmaku 地址，否则走 Node 服务包的 /danmu/auto
      if (_danmakuOn) {
        unawaited(DanmakuSession.load(
          title: widget.vod.name,
          episode: ep.name,
          directUrl: res.danmaku,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _restorePosition() {
    final p = Store.progressOf(widget.site.displayKey, widget.vod.id);
    if (p == null) return;
    final idx = int.tryParse('${p['episode_index'] ?? ''}');
    if (idx != _episodeIndex) return;
    final pos = int.tryParse('${p['play_position'] ?? ''}') ?? 0;
    if (pos > 3000) {
      _player.seek(Duration(milliseconds: pos));
    }
  }

  void _save() {
    if (_duration.inMilliseconds <= 0) return;
    final ep = _episode;
    Store.saveProgress(widget.site.displayKey, widget.vod.id, {
      'vod_id': widget.vod.id,
      'vod_name': widget.vod.name,
      'vod_pic': widget.vod.pic,
      'vod_remarks': widget.vod.remarks,
      'source_name': widget.site.name,
      'source_key': widget.site.displayKey,
      'source_api': widget.site.api,
      'source_type': widget.site.type,
      'episode_index': _episodeIndex,
      'episode_name': ep?.name ?? '',
      'play_position': _position.inMilliseconds,
      'total_duration': _duration.inMilliseconds,
      'play_time': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 跳过片尾：剩余时长进入阈值后自动跳下一集。
  ///
  /// 原版 `[T4] 触发跳过片尾: 剩余=` 只在**时长已知**时触发；
  /// 直播 / 时长未知的源直接跳过，避免误判。
  void _checkSkipTail(Duration pos) {
    if (!_skipTailEnabled) return;
    if (_tailSkipped || _duration.inMilliseconds <= 0) return;
    if (_episodeIndex + 1 >= _line.episodes.length) return;
    final remain = _duration - pos;
    if (remain.inSeconds > _skipTailSeconds) return;
    _tailSkipped = true;
    final sec = remain.inSeconds;
    peekToast(context, '已跳过片尾（剩余 $sec 秒）');
    _playNext();
  }

  void _playEpisode(int index) {
    final eps = _line.episodes;
    if (index < 0 || index >= eps.length) return;
    _tailSkipped = false;
    setState(() => _episodeIndex = index);
    _resolveAndPlay();
  }

  void _playNext() {
    if (_episodeIndex + 1 < _line.episodes.length) {
      _playEpisode(_episodeIndex + 1);
    }
  }

  // ---------------------------------------------------- 自动换源
  //
  // 对齐原版 `[T4] 自动换源:` 日志族。行为：
  //   播放失败 → 用片名进多元搜索页（换源模式）→
  //   自动化场景下直接把最佳命中作为新源继续播，
  //   人工场景下让用户在页面上挑。
  //
  // `t4_auto_change_source_config.maxAttempts` 限制次数，
  // 用完仍失败提示「所有换源方式都已尝试，无法继续」。

  int _changeAttempts = 0;
  bool _changing = false;

  Future<void> _tryAutoChange(String reason) async {
    final cfg = AutoChangeSourceConfig.load();
    if (!cfg.enabled) return;
    if (_changing) return;
    if (_changeAttempts >= cfg.maxAttempts) {
      if (mounted) peekToast(context, '所有换源方式都已尝试，无法继续');
      return;
    }
    final name = widget.vod.name.trim();
    if (name.isEmpty) {
      DebugLog.add('换源', '没有视频名称，无法快搜换源');
      return;
    }
    _changing = true;
    _changeAttempts++;
    DebugLog.add('换源',
        '第 $_changeAttempts/${cfg.maxAttempts} 次 | 原因: $reason | 片名: $name');

    final pick = await Navigator.of(context).push<AutoChangePick>(
      MaterialPageRoute(
        builder: (_) => MultiSearchPage(
          keyword: name,
          autoChange: true,
          originName: name,
          originSite: widget.site.name,
        ),
      ),
    );
    _changing = false;
    if (!mounted) return;
    if (pick == null) return;
    // 换到新源：重新拉详情拿线路，然后跳新的播放页
    await _switchTo(pick);
  }

  Future<void> _switchTo(AutoChangePick pick) async {
    try {
      final app = context.read<AppState>();
      final detail = await app.detail(pick.site, pick.vod.id);
      if (!mounted) return;
      if (detail == null) {
        peekToast(context, '该源详情加载失败，继续换源');
        _tryAutoChange('目标源详情加载失败');
        return;
      }
      final lines = detail.lines;
      if (lines.isEmpty) {
        peekToast(context, '该源没有可播放的线路，继续换源');
        _tryAutoChange('目标源无线路');
        return;
      }
      final nav = Navigator.of(context);
      // 「合并播放列表」开启时，换源后的新详情同样要走合并后的线路，
      // 否则播放页会用未合并的原始下标去取剧集。
      final merged = resolvePlayLines(lines, app.mergePlaylist);
      await nav.pushReplacement(
        MaterialPageRoute(
          builder: (_) => PlayerPage(
            site: pick.site,
            vod: detail,
            lineIndex: 0,
            episodeIndex: 0,
            linesOverride: app.mergePlaylist ? merged : null,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      peekToast(context, '换源失败：${friendlyError(e)}');
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        onHover: (_) {
          if (!_showControls && !_locked) {
            setState(() => _showControls = true);
          }
          _scheduleHide();
        },
        child: GestureDetector(
          onTapUp: _tapSeek,
          // 桌面端：播放器上点鼠标右键切换全屏（对齐原版行为）
          onSecondaryTapUp: (_) => _toggleFullscreen(),
          onDoubleTap: _locked ? null : () => _player.playOrPause(),
          onLongPressStart: _locked
              ? null
              : (_) {
                  setState(() => _longPressing = true);
                  _player.setRate(_longPressRate);
                },
          onLongPressEnd: _locked
              ? null
              : (_) {
                  setState(() => _longPressing = false);
                  _player.setRate(_speed);
                },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                  fill: Colors.black,
                ),
              ),
              // 弹幕层：在视频之上、控件之下（控件区可遮挡弹幕，与原版一致）
              DanmakuOverlay(
                player: _player,
                controller: _danmaku,
                style: _danmakuStyleFromStore(),
                enabled: _danmakuOn,
              ),
              if (_longPressing) _longPressBadge(),
              if (_loading)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 30,
                        height: 30,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white70),
                      ),
                      SizedBox(height: 14),
                      Text('正在解析播放地址…',
                          style:
                              TextStyle(fontSize: 13, color: Colors.white70)),
                    ],
                  ),
                ),
              if (_error != null) _errorView(),
              AnimatedOpacity(
                opacity: _showControls && !_locked ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !_showControls || _locked,
                  child: _overlay(),
                ),
              ),
              // 锁定后仅保留一个解锁按钮，其他交互全部屏蔽
              if (_locked) _unlockButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// 长按加速时在画面顶部显示的倍速徽标
  Widget _longPressBadge() {
    return Positioned(
      top: 46,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${_longPressRate}x 快进中',
            style: const TextStyle(fontSize: 12.5, color: Colors.white),
          ),
        ),
      ),
    );
  }

  /// 锁定态下的解锁入口（原版「锁定屏幕」同一语义）
  Widget _unlockButton() {
    return Positioned(
      left: 16,
      bottom: 24,
      child: SafeArea(
        child: Material(
          color: Colors.black45,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              setState(() => _locked = false);
              _scheduleHide();
            },
            child: const Padding(
              padding: EdgeInsets.all(9),
              child: Icon(Icons.lock_outline, size: 20, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorView() {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: Colors.white54),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 60),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonal(
                onPressed: _resolveAndPlay,
                child: const Text('重试'),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('返回', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
          // 提示指向「配置中心」时给个直达入口。
          // 实测：玩偶|4K 的夸克线路回「还没有配置夸克 Cookie，请先去配置中心登录夸克」——
          // 只说这句话，用户找不到配置中心在哪。
          if (needsConfigCenter(_error))
            TextButton.icon(
              onPressed: _openConfigCenter,
              icon: const Icon(Icons.settings_outlined, size: 16, color: Colors.white70),
              label: const Text('去配置中心',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ),
        ],
      ),
    );
  }

  /// 打开站源配置中心（`<Node 服务>/website`）—— 登录夸克/阿里云盘等网盘账号。
  ///
  /// PeekPili 用内置 webview 打开，本工程（桌面端）没有 webview 依赖，
  /// 改为交给系统默认浏览器。登录状态的 Cookie 存在源侧（Node 侧），
  /// 与用哪个浏览器登录无关，因此这个替换不影响功能。
  Future<void> _openConfigCenter() async {
    final base = SourceService.activeBase;
    if (!mounted) return;
    if (base.isEmpty) {
      peekToast(context, '源服务尚未启动，稍后再试');
      return;
    }
    final url = '$base/website';
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      peekToast(context, '无法打开浏览器，请手动访问 $url');
    }
  }

  /// 判断一个地址看起来是不是**网页**而不是媒体直链。
  ///
  /// 原版/PeekPili 靠嗅探器解决这种情况；桌面端没有嗅探器，
  /// 但至少要能识别出来并给出可读提示。判据取「扩展名不是常见媒体后缀
  /// 且路径不像直链」这种保守组合，避免把正常的带 query 的直链误判。
  static bool _looksLikeWebPage(String url) {
    final u = Uri.tryParse(url);
    if (u == null) return false;
    final p = u.path.toLowerCase();
    // m3u8 / mp4 / flv / ts / mkv / avi / mov / webm / mp3 / m4a …
    const media = <String>[
      '.m3u8', '.mp4', '.flv', '.ts', '.mkv', '.avi', '.mov',
      '.webm', '.mp3', '.m4a', '.aac', '.mpd', '.wmv', '.rmvb',
    ];
    if (media.any(p.endsWith)) return false;
    // 结尾像 html 页面，或路径不含任何扩展名但带 do=/php 这类动态页特征
    if (p.endsWith('.html') || p.endsWith('.htm') || p.endsWith('.php')) {
      return true;
    }
    return u.queryParameters.keys.any(
      (k) => const ['do', 'url', 'id', 'vid', 'play'].contains(k.toLowerCase()),
    ) &&
        !media.any(p.endsWith);
  }

  Widget _overlay() {
    return Column(
      children: [
        _topBar(),
        const Spacer(),
        _centerButtons(),
        const Spacer(),
        _bottomBar(),
      ],
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, size: 22, color: Colors.white),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.vod.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                  if (_episode != null)
                    Text(
                      '${_line.name} · ${_episode!.name}',
                      style: const TextStyle(fontSize: 11.5, color: Colors.white60),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: '悬浮球（小窗播放）',
              onPressed: _toFloatingBall,
              icon: const Icon(Icons.picture_in_picture_alt_outlined,
                  size: 21, color: Colors.white),
            ),
            IconButton(
              tooltip: '剧集',
              onPressed: _showEpisodeSheet,
              icon: const Icon(Icons.list, size: 22, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _centerButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          iconSize: 34,
          color: Colors.white,
          onPressed: _episodeIndex > 0 ? () => _playEpisode(_episodeIndex - 1) : null,
          icon: const Icon(Icons.skip_previous),
        ),
        const SizedBox(width: 26),
        IconButton(
          iconSize: 52,
          color: Colors.white,
          onPressed: () => _player.playOrPause(),
          icon: Icon(_playing
              ? Icons.pause_circle_filled
              : Icons.play_circle_filled),
        ),
        const SizedBox(width: 26),
        IconButton(
          iconSize: 34,
          color: Colors.white,
          onPressed: _episodeIndex + 1 < _line.episodes.length
              ? () => _playEpisode(_episodeIndex + 1)
              : null,
          icon: const Icon(Icons.skip_next),
        ),
      ],
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 30, 16, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  fmtDuration(_position),
                  style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2.6,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: PeekColors.primary,
                      thumbColor: PeekColors.primary,
                      inactiveTrackColor: Colors.white24,
                    ),
                    child: Slider(
                      value: _duration.inMilliseconds == 0
                          ? 0
                          : _position.inMilliseconds
                              .clamp(0, _duration.inMilliseconds)
                              .toDouble(),
                      max: _duration.inMilliseconds == 0
                          ? 1
                          : _duration.inMilliseconds.toDouble(),
                      onChangeStart: (v) {
                        _dragging = true;
                        _dragTarget = Duration(milliseconds: v.toInt());
                      },
                      onChanged: (v) {
                        setState(() =>
                            _dragTarget = Duration(milliseconds: v.toInt()));
                      },
                      onChangeEnd: (v) {
                        _dragging = false;
                        _player.seek(Duration(milliseconds: v.toInt()));
                      },
                    ),
                  ),
                ),
                Text(
                  fmtDuration(_duration),
                  style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  color: Colors.white,
                  iconSize: 20,
                  tooltip: '静音',
                  onPressed: () => _player.setVolume(
                      _player.state.volume > 0 ? 0 : 100),
                  icon: Icon(_player.state.volume > 0
                      ? Icons.volume_up
                      : Icons.volume_off),
                ),
                IconButton(
                  color: _danmakuOn ? Colors.white : Colors.white38,
                  iconSize: 20,
                  tooltip: _danmakuOn
                      ? '关闭弹幕（已载入 ${DanmakuSession.total} 条）'
                      : '开启弹幕',
                  onPressed: _toggleDanmaku,
                  icon: Icon(_danmakuOn
                      ? Icons.subtitles
                      : Icons.subtitles_off_outlined),
                ),
                IconButton(
                  color: Colors.white,
                  iconSize: 20,
                  tooltip: '解析接口',
                  onPressed: _showParseSheet,
                  icon: const Icon(Icons.hub_outlined),
                ),
                const Spacer(),
                PopupMenuButton<double>(
                  tooltip: '倍速',
                  initialValue: _speed,
                  color: PeekColors.surfaceContainerHigh,
                  onSelected: (v) {
                    setState(() => _speed = v);
                    _player.setRate(v);
                  },
                  itemBuilder: (_) => [
                    for (final s in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                      PopupMenuItem(
                        value: s,
                        height: 36,
                        child: Text('${s}x',
                            style: const TextStyle(fontSize: 13)),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    child: Text(
                      '${_speed}x',
                      style: const TextStyle(fontSize: 12.5, color: Colors.white),
                    ),
                  ),
                ),
                IconButton(
                  color: Colors.white,
                  iconSize: 20,
                  tooltip: '锁定屏幕',
                  onPressed: () {
                    setState(() {
                      _locked = true;
                      _showControls = false;
                    });
                  },
                  icon: const Icon(Icons.lock_open_outlined),
                ),
                IconButton(
                  color: Colors.white,
                  iconSize: 20,
                  tooltip: _skipTailEnabled
                      ? '已开启跳过片尾（剩余 $_skipTailSeconds 秒时自动跳集）'
                      : '跳过片尾',
                  onPressed: _toggleSkipTail,
                  icon: Icon(_skipTailEnabled
                      ? Icons.skip_next
                      : Icons.skip_next_outlined),
                ),
                IconButton(
                  color: Colors.white,
                  iconSize: 20,
                  tooltip: '全屏',
                  onPressed: _toggleFullscreen,
                  icon: const Icon(Icons.fullscreen),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 切换全屏。
  ///
  /// * 桌面端（Windows）：直接调 `user32!ShowWindow` 最大化/还原窗口，
  ///   效果等同点标题栏最大化按钮；右键与工具栏「全屏」按钮共用此逻辑。
  /// * 移动端：切换系统 UI 可见性（沉浸式）。
  void _toggleFullscreen() {
    if (Platform.isWindows) {
      DesktopWindow.toggleFullscreen();
      return;
    }
    SystemChrome.setEnabledSystemUIMode(
      _showControls ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// 跳过片尾开关（原版「跳过片尾」+ 秒数阈值）
  Future<void> _toggleSkipTail() async {
    if (!_skipTailEnabled) {
      // 关 → 开：若用户还没设过阈值，先给一个默认值
      if (Store.get<int>('skipTailSeconds', 0) <= 0) {
        await Store.set('skipTailSeconds', 90);
      }
      await Store.set('skipTailEnabled', true);
      _tailSkipped = false;
      if (mounted) {
        peekToast(context, '已开启跳过片尾（剩余 $_skipTailSeconds 秒时自动跳集）');
        setState(() {});
      }
      return;
    }
    await Store.set('skipTailEnabled', false);
    if (mounted) {
      peekToast(context, '已关闭跳过片尾');
      setState(() {});
    }
  }

  /// 解析接口选择。
  ///
  /// 原版 `[T4] 用户手动选择解析接口:` —— 当站源给的是需要二次解析的地址
  /// （`解析名$http://…`）时，用户可以手动指定走哪个解析接口。
  /// 复刻版把可用接口交给 Node 服务包（`/api/config` 的 `parses` 字段），
  /// 选中后写入 `parseName`，播放时随 `player()` 一起下发给源。
  Future<void> _showParseSheet() async {
    final app = context.read<AppState>();
    final parses = app.parseInterfaces;
    final current = Store.get<String>('parseName', '');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PeekColors.surfaceContainer,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 60.0 + 46.0 * (parses.length + 1).clamp(1, 8),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Row(
                  children: [
                    Text('解析接口',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: PeekColors.onSurface)),
                    const SizedBox(width: 10),
                    Text('共 ${parses.length} 个',
                        style: TextStyle(
                            fontSize: 12, color: PeekColors.hint)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      dense: true,
                      leading: Icon(
                        current.isEmpty
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 20,
                        color: current.isEmpty
                            ? PeekColors.primary
                            : PeekColors.railIdle,
                      ),
                      title: const Text('自动（使用源自带解析）',
                          style: TextStyle(fontSize: 13.5)),
                      onTap: () async {
                        await Store.set('parseName', '');
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) {
                          peekToast(context, '解析接口：自动');
                          _resolveAndPlay();
                        }
                      },
                    ),
                    for (final p in parses)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          current == p.name
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: current == p.name
                              ? PeekColors.primary
                              : PeekColors.railIdle,
                        ),
                        title: Text(p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5)),
                        subtitle: p.url.isEmpty
                            ? null
                            : Text(p.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: PeekColors.hint)),
                        onTap: () async {
                          await Store.set('parseName', p.name);
                          if (ctx.mounted) Navigator.of(ctx).pop();
                          if (mounted) {
                            peekToast(context, '解析接口：${p.name}');
                            _resolveAndPlay();
                          }
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEpisodeSheet() {
    final eps = _line.episodes;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PeekColors.surfaceContainer,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: 420,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                child: Row(
                  children: [
                    Text('选集',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: PeekColors.onSurface)),
                    const SizedBox(width: 12),
                    Text('${_line.name} · 共 ${eps.length} 集',
                        style: TextStyle(
                            fontSize: 12, color: PeekColors.hint)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 110,
                    mainAxisExtent: 40,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemCount: eps.length,
                  itemBuilder: (_, i) => InkWell(
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _playEpisode(i);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == _episodeIndex
                            ? PeekColors.primaryContainer
                            : PeekColors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        eps[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: i == _episodeIndex
                              ? PeekColors.onPrimaryContainer
                              : PeekColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
