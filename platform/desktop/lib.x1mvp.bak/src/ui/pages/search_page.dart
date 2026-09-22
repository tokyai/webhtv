/// 搜索页 —— 移植并改造自 PeekPili `lib/pages/search/search_page.dart`。
///
/// 与安卓版 WebHTV 的对应：`SearchActivity` + `SearchFragment`
/// （`menu_search.xml` 的 `action_reset` / `action_site`）。
/// 桌面端把"切站点"做成顶栏按钮，"重置"做成输入框清空。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/source_models.dart';
import '../../state/app_state.dart';
import '../theme/peek_nav.dart';
import '../theme/peek_theme.dart';
import '../widgets/peek_common.dart';
import '../widgets/peek_poster_card.dart';
import '../widgets/peek_site_picker.dart';
import 'detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => SearchPageState();
}

class SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  bool _searched = false;
  bool _searching = false;
  List<VideoItem> _results = [];
  String? _error;

  /// 搜索历史（本机内存态，桌面端不做持久化，避免和源服务状态混淆）。
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _doSearch(String keyword) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return;
    _ctrl.text = kw;
    _focus.unfocus();
    setState(() {
      _searched = true;
      _searching = true;
      _results = [];
      _error = null;
      _history.remove(kw);
      _history.insert(0, kw);
      if (_history.length > 12) _history.removeLast();
    });

    final app = context.read<AppState>();
    await app.doSearch(kw);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _results = app.page.list;
      _error = app.lastError;
    });
  }

  Future<void> _openSitePicker() async {
    final app = context.read<AppState>();
    if (app.sites.isEmpty) {
      peekToast(context, '源未返回任何站点');
      return;
    }
    final picked = await showSitePicker(
      context,
      sites: app.sites,
      currentKey: app.currentSite?.key,
    );
    if (picked == null || !mounted) return;
    await app.selectSite(picked);
    if (!mounted) return;
    final kw = _ctrl.text.trim();
    if (kw.isNotEmpty) await _doSearch(kw);
  }

  void _open(VideoItem v) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailPage(vodId: v.vodId, preview: v),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _header(app),
            Expanded(child: _body(app)),
          ],
        ),
      ),
    );
  }

  Widget _header(AppState app) {
    return SizedBox(
      height: 60,
      child: Row(
        children: [
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            tooltip: '返回',
            onPressed: () => Navigator.maybePop(context),
          ),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onSubmitted: _doSearch,
              style: const TextStyle(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: '搜索影片、剧集、综艺…',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                suffixIcon: ListenableBuilder(
                  listenable: _ctrl,
                  builder: (_, _) => _ctrl.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: '清空',
                          onPressed: () {
                            _ctrl.clear();
                            setState(() {
                              _searched = false;
                              _results = [];
                              _error = null;
                            });
                            _focus.requestFocus();
                          },
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              textStyle: const TextStyle(fontSize: 13),
            ),
            onPressed: () => _doSearch(_ctrl.text),
            child: const Text('搜索'),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.dns_outlined, size: 20),
            tooltip: '切换站点（${app.currentSite?.shortName ?? '无'}）',
            onPressed: _openSitePicker,
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _body(AppState app) {
    if (_searching) {
      return PeekLoading(text: '正在「${app.currentSite?.shortName ?? ''}」搜索…');
    }
    if (!_searched) return _discover();
    if (_error != null && _results.isEmpty) {
      return PeekEmpty(
        icon: Icons.cloud_off_outlined,
        text: '搜索失败\n$_error',
        selectable: true,
        actionText: '重试',
        onAction: () => _doSearch(_ctrl.text),
      );
    }
    if (_results.isEmpty) {
      return PeekEmpty(
        icon: Icons.search_off_outlined,
        text: '没有搜索到「${_ctrl.text}」相关内容\n可尝试更换站点或更换关键词',
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth - PeekColors.contentPadding * 2;
        const gap = PeekColors.gridGap;
        const target = 181.0;
        final cols = ((w + gap) / (target + gap)).round().clamp(2, 7);
        final itemW = (w - gap * (cols - 1)) / cols;
        const textH = 41.0;
        final ratio = itemW / (itemW / PeekColors.posterAspect + textH);

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  PeekColors.contentPadding, 8, PeekColors.contentPadding, 4),
              child: Row(
                children: [
                  Text(
                    '「${_ctrl.text}」· ${_results.length} 个结果',
                    style: TextStyle(fontSize: 12.5, color: PeekColors.hint),
                  ),
                  const Spacer(),
                  Text(
                    '来自 ${app.currentSite?.shortName ?? ''}',
                    style: TextStyle(fontSize: 12, color: PeekColors.hint),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(
                    PeekColors.contentPadding, 8, PeekColors.contentPadding, 24),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: gap,
                  childAspectRatio: ratio,
                ),
                itemCount: _results.length,
                itemBuilder: (_, i) =>
                    PosterCard(vod: _results[i], onTap: () => _open(_results[i])),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _discover() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: [
        if (_history.isNotEmpty) ...[
          Row(
            children: [
              Text(
                '搜索历史',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: PeekColors.onSurface,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(_history.clear),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('清空', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final h in _history)
                InkWell(
                  onTap: () => _doSearch(h),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: PeekColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      h,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: PeekColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
        Text(
          '搜索说明',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: PeekColors.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '搜索在**当前站点**内进行。若结果不理想：\n'
          '  · 点右上角站点图标换一个源\n'
          '  · 换成更短的关键词（如只留片名）\n'
          '  · 部分站点不支持搜索，站点选择器里已标注「不可搜索」',
          style: TextStyle(fontSize: 12.5, height: 1.75, color: PeekColors.hint),
        ),
      ],
    );
  }
}
