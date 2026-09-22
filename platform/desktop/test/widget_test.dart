import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:webhtv_win/backend/source_client.dart' show SiteEntry;
import 'package:webhtv_win/backend/source_config.dart';
import 'package:webhtv_win/backend/source_models.dart' as be;
import 'package:webhtv_win/core/theme.dart';
import 'package:webhtv_win/tvbox/backend_bridge.dart';
import 'package:webhtv_win/tvbox/models.dart';
import 'package:webhtv_win/tvbox/playlist_merge.dart';
import 'package:webhtv_win/tvbox/spider.dart';
import 'package:webhtv_win/widgets/common.dart';

/// 本工程的测试只覆盖**纯逻辑**与**无 IO 的渲染**。
///
/// 不测：真实网络、Node 子进程、播放器 —— 那些靠实机验证，
/// 放进单元测试会成为不确定性来源。
void main() {
  // ---------------------------------------------------------------------------
  // 几何常量：PeekPili 像素实测值（`theme.dart` 注释里有逐条判据）
  // ---------------------------------------------------------------------------
  group('几何常量（PeekPili 实测值）', () {
    test('左栏宽度 = 75dp 内容 + 1dp 分割线', () {
      expect(PeekColors.railWidth, 76.0);
    });

    test('内容左起 = railWidth + contentPadding（原版 161px）', () {
      // 原版实测：左栏总宽 133px、内容左起 161px
      //   → 161 - 133 = 28px = 16dp
      expect(PeekColors.railWidth + PeekColors.contentPadding, 92.0);
    });

    test('网格参数能收敛到 6 列（原版 1920px @1.75 下）', () {
      // 内容区宽 = 1920/1.75 - railWidth - 2*contentPadding ≈ 989.14dp
      const contentW = 1920 / 1.75 - 76.0 - 2 * 16.0;
      final cols = ((contentW + PeekColors.gridGap) /
              (PeekColors.gridTargetWidth + PeekColors.gridGap))
          .round()
          .clamp(2, 8);
      expect(cols, 6);
    });

    test('导航条目与海报几何', () {
      expect(PeekColors.railItemHeight, 64.0);
      expect(PeekColors.railChipWidth, 59.0);
      expect(PeekColors.railChipHeight, 59.5);
      expect(PeekColors.posterAspect, 0.73);
      expect(PeekColors.chipHeight, 36.0);
    });
  });

  // ---------------------------------------------------------------------------
  // 调色板：颜色必须是 getter（否则浅色/深色切不动）
  // ---------------------------------------------------------------------------
  group('调色板', () {
    test('use(Brightness) 切换后颜色随之变化，且 must 在构建前生效', () {
      PeekColors.use(Brightness.dark);
      final darkSurface = PeekColors.surface;
      final darkOnSurface = PeekColors.onSurface;
      expect(PeekColors.isDark, isTrue);

      PeekColors.use(Brightness.light);
      expect(PeekColors.isDark, isFalse);
      expect(PeekColors.surface, isNot(darkSurface));
      expect(PeekColors.onSurface, isNot(darkOnSurface));

      // 收尾：恢复默认，避免影响同进程内其他 test
      PeekColors.use(Brightness.dark);
    });

    test('深色底为暗色、前景为亮色（可读性下限）', () {
      expect(const Color(0xFF1C1B1B).computeLuminance() < 0.2, isTrue,
          reason: '深色 surface 必须够暗');
      expect(const Color(0xFFE2E2E6).computeLuminance() > 0.6, isTrue,
          reason: '深色 onSurface 必须够亮');
    });

    test('几何常量保持 const（不随主题变）', () {
      // `const x = PeekColors.gridGap` 必须能编译 —— 这行本身就是断言
      const gap = PeekColors.gridGap;
      expect(gap, 12.5);
    });
  });

  // ---------------------------------------------------------------------------
  // 播放线路拆分：`Vod.lines`（`$$$` 线路 / `#` 剧集 / `$` 名址）
  // ---------------------------------------------------------------------------
  group('Vod.lines 拆分', () {
    test('单线路多剧集', () {
      final vod = Vod(
        id: '1',
        name: '测试片',
        playFrom: '线路一',
        // Dart 里 `$$$` 必须用 raw string，否则被当成插值
        playUrl: r'第1集$http://a/1.m3u8#第2集$http://a/2.m3u8',
      );
      final lines = vod.lines;
      expect(lines.length, 1);
      expect(lines.first.name, '线路一');
      expect(lines.first.episodes.length, 2);
      expect(lines.first.episodes[0].name, '第1集');
      expect(lines.first.episodes[0].url, 'http://a/1.m3u8');
      expect(lines.first.episodes[1].url, 'http://a/2.m3u8');
    });

    test('多线路', () {
      final vod = Vod(
        id: '1',
        name: '测试片',
        playFrom: r'线路一$$$线路二',
        playUrl: r'第1集$http://a/1.m3u8$$$第1集$http://b/1.m3u8',
      );
      final lines = vod.lines;
      expect(lines.length, 2);
      expect(lines.map((e) => e.name).toList(), ['线路一', '线路二']);
      expect(lines[1].episodes.first.url, 'http://b/1.m3u8');
    });

    test('playUrl 为空 → 无线路', () {
      final vod = Vod(id: '1', name: 'x', playFrom: '', playUrl: '');
      expect(vod.lines, isEmpty);
    });

    test('剧集段没有分隔符时按原样当地址', () {
      final vod = Vod(
        id: '1',
        name: 'x',
        playFrom: '线路一',
        playUrl: 'http://a/direct.m3u8',
      );
      final lines = vod.lines;
      expect(lines.length, 1);
      expect(lines.first.episodes.length, 1);
      expect(lines.first.episodes.first.url, 'http://a/direct.m3u8');
    });

    test('空段被跳过', () {
      final vod = Vod(
        id: '1',
        name: 'x',
        playFrom: '线路一',
        playUrl: r'第1集$http://a/1##第2集$http://a/2',
      );
      expect(vod.lines.first.episodes.length, 2);
    });
  });

  // ---------------------------------------------------------------------------
  // mergePlayLines / resolvePlayLines
  // ---------------------------------------------------------------------------
  group('播放线路合并', () {
    PlayLine line(String name, List<(String, String)> eps) => PlayLine(
          name: name,
          episodes: [for (final e in eps) Episode(name: e.$1, url: e.$2)],
        );

    test('merge=false 原样返回', () {
      final src = [
        line('线路一', [('第1集', 'http://a/1')]),
        line('线路二', [('第1集', 'http://b/1')]),
      ];
      expect(resolvePlayLines(src, false).length, 2);
    });

    test('merge=true 合并同名剧集成一条「合集」，保留首条地址', () {
      final src = [
        line('线路一', [('第1集', 'http://a/1')]),
        line('线路二', [('第1集', 'http://b/1')]),
      ];
      final merged = resolvePlayLines(src, true);
      expect(merged.length, 1);
      // 原版播放页语义树里这条线路就叫「合集」（见 playlist_merge.dart）
      expect(merged.first.name, kMergedLineName);
      expect(merged.first.name, '合集');
      expect(merged.first.episodes.length, 1);
      expect(merged.first.episodes.first.url, 'http://a/1',
          reason: '重复集保留首次出现的地址，不被后面的线路覆盖');
    });

    test('merge=true 不同剧集名都保留，顺序按首次出现', () {
      final src = [
        line('线路一', [('第1集', 'http://a/1'), ('第2集', 'http://a/2')]),
        line('线路二', [('第2集', 'http://b/2'), ('第3集', 'http://b/3')]),
      ];
      final merged = resolvePlayLines(src, true);
      expect(merged.length, 1);
      expect(
        merged.first.episodes.map((e) => e.name).toList(),
        ['第1集', '第2集', '第3集'],
      );
      expect(
        merged.first.episodes.map((e) => e.url).toList(),
        ['http://a/1', 'http://a/2', 'http://b/3'],
      );
    });

    test('单线路时 merge 不改变结果', () {
      final src = [line('线路一', [('第1集', 'http://a/1')])];
      expect(resolvePlayLines(src, true).length, 1);
      expect(resolvePlayLines(src, false).length, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // spider.dart：播放地址归一化与异常
  // ---------------------------------------------------------------------------
  group('PlayResult 归一化', () {
    test('字符串地址：url 取该串，qualities 有一条无标签项', () {
      final r = PlayResult(url: 'http://a/1.m3u8');
      expect(r.url, 'http://a/1.m3u8');
      expect(r.qualities.length, 1);
      expect(r.qualities.first.label, '');
      expect(r.qualities.first.url, 'http://a/1.m3u8');
    });

    test('成对数组：首个 http 作 url，全部进 qualities', () {
      final r = PlayResult(
        url: <dynamic>['1080P', 'http://a/1080.m3u8', '720P', 'http://a/720.m3u8'],
      );
      expect(r.url, 'http://a/1080.m3u8');
      expect(r.qualities.length, 2);
      expect(r.qualities[0].label, '1080P');
      expect(r.qualities[1].url, 'http://a/720.m3u8');
    });

    test('纯地址列表取首个', () {
      final r = PlayResult(url: <dynamic>['http://a/1.m3u8', 'http://a/2.m3u8']);
      expect(r.url, 'http://a/1.m3u8');
    });

    test('空列表 → 空串', () {
      expect(PlayResult(url: <dynamic>[]).url, '');
    });

    test('null → 空串', () {
      expect(PlayResult(url: null).url, '');
    });
  });

  group('SpiderException / siteHeaders / parseHeaderField', () {
    test('toString 直接返回 message（页面原样展示）', () {
      expect(
        SpiderException('还没有配置夸克 Cookie').toString(),
        '还没有配置夸克 Cookie',
      );
    });

    test('siteHeaders 带默认 UA，可被 site.header 覆盖', () {
      final site = Site(key: 'k', name: 'n', type: 3, api: 'csp_x', raw: const {});
      expect(siteHeaders(site)['User-Agent'], 'okhttp/5.0.0');

      final custom = Site(
        key: 'k',
        name: 'n',
        type: 3,
        api: 'csp_x',
        header: {'User-Agent': 'custom/1.0'},
        raw: const {},
      );
      expect(siteHeaders(custom)['User-Agent'], 'custom/1.0');
    });

    test('parseHeaderField 接受 Map / JSON 字符串 / 非法值', () {
      expect(parseHeaderField({'Referer': 'http://r/'})?['Referer'], 'http://r/');
      expect(parseHeaderField('{"Referer":"http://r/"}')?['Referer'], 'http://r/');
      expect(parseHeaderField(null), isNull);
      expect(parseHeaderField('not json'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // backend_bridge：后端模型 → 界面模型 的类型转换
  // ---------------------------------------------------------------------------
  group('backend_bridge 转换', () {
    test('siteFromEntry：searchable 映射到 quickSearch，nodejs 标记进 raw', () {
      const e = SiteEntry(
        key: 'nodejs_douban',
        name: '豆瓣',
        type: 3,
        enable: true,
        searchable: true,
        filterable: true,
        api: 'csp_douban',
      );
      final s = siteFromEntry(e);
      expect(s.key, 'nodejs_douban');
      expect(s.type, 3);
      expect(s.searchable, isTrue);
      expect(s.quickSearch, isTrue);
      expect(s.filterable, isTrue);
      expect(s.displayKey, 'nodejs_douban');
    });

    test('siteFromEntry：key 为空时 displayKey 退回 api', () {
      const e = SiteEntry(
        key: '',
        name: 'x',
        type: 3,
        enable: true,
        searchable: false,
        filterable: false,
        api: 'csp_x',
      );
      final s = siteFromEntry(e);
      expect(s.displayKey, 'csp_x');
      expect(s.searchable, isFalse);
    });

    test('vodFromItem：PicRef 防盗链头被拆出来', () {
      final v = const be.VideoItem(
        vodId: '42',
        vodName: '测试片',
        vodPic: 'http://img/a.jpg@Referer=http://r/@User-Agent=okhttp/5.0.0',
        vodRemarks: '更新至 10 集',
      );
      final vod = vodFromItem(v);
      expect(vod.id, '42');
      expect(vod.name, '测试片');
      expect(vod.pic, 'http://img/a.jpg');
      expect(vod.picHeaders['Referer'], 'http://r/');
      expect(vod.picHeaders['User-Agent'], 'okhttp/5.0.0');
      expect(vod.remarks, '更新至 10 集');
    });

    test('vodFromItem：无 `@` 的 pic 不带 header', () {
      final v = const be.VideoItem(
        vodId: '1',
        vodName: 'x',
        vodPic: 'http://img/a.jpg',
        vodRemarks: '',
      );
      final vod = vodFromItem(v);
      expect(vod.pic, 'http://img/a.jpg');
      expect(vod.picHeaders, isEmpty);
    });

    test('categoryFrom：hasMore 由 page < pageCount 推导', () {
      final r = const be.PageResult(
        page: 1,
        pageCount: 3,
        list: [be.VideoItem(vodId: '1', vodName: 'a', vodPic: '', vodRemarks: '')],
      );
      final c = categoryFrom(r);
      expect(c.page, 1);
      expect(c.pageCount, 3);
      expect(c.hasMore, isTrue);

      final last =
          categoryFrom(const be.PageResult(page: 3, pageCount: 3, list: []));
      expect(last.hasMore, isFalse);
    });

    test('homeFrom：filters 的 init 被带到界面层 FilterGroup', () {
      const h = be.HomeContent(
        classes: [
          be.CategoryClass(typeId: '1', typeName: '电影'),
        ],
        filters: {
          '1': [
            be.FilterGroup(
              key: 'area',
              name: '地区',
              init: '大陆',
              values: [be.FilterValue(name: '大陆', value: '大陆')],
            ),
          ],
        },
        list: [],
      );
      final home = homeFrom(h);
      expect(home.classes.length, 1);
      final fg = home.classes.first.filters;
      expect(fg.length, 1);
      expect(fg.first.key, 'area');
      expect(fg.first.init, '大陆',
          reason: '后端 filters[].init 是默认选中值，界面层靠它高亮默认项');
      expect(fg.first.values.first.n, '大陆');
      expect(fg.first.values.first.v, '大陆');
    });

    test('homeFrom：无 filters 时列表为空（不抛）', () {
      const h = be.HomeContent(classes: [], filters: {}, list: []);
      expect(homeFrom(h).classes, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // source_config：编解码与 id 稳定性
  // ---------------------------------------------------------------------------
  group('SourceConfig', () {
    test('id 由 URL 决定且稳定', () {
      const url = 'http://u:p@host/index.js.md5';
      expect(sourceIdOf(url), sourceIdOf(url));
      expect(sourceIdOf(url), isNot(sourceIdOf('$url?v=2'))); // ignore: unnecessary_brace_in_string_interps
    });

    test('encode/decode 往返一致', () {
      final list = [
        SourceConfig(
          id: 'a',
          url: 'http://a/i.md5',
          name: '源A',
          updatedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ),
        const SourceConfig(
          id: 'b',
          url: 'http://b/i.md5',
          name: '源B',
          lastError: '拉取失败',
        ),
      ];
      final back = SourceConfig.decodeList(SourceConfig.encodeList(list));
      expect(back.length, 2);
      expect(back[0].url, 'http://a/i.md5');
      expect(back[0].name, '源A');
      expect(back[1].lastError, '拉取失败');
    });

    test('copyWith(clearError: true) 清掉错误', () {
      const c = SourceConfig(id: 'a', url: 'u', name: 'n', lastError: 'err');
      expect(c.copyWith(clearError: true).lastError, isNull);
      expect(c.copyWith(name: 'n2').name, 'n2');
      // 不清时保留原错误
      expect(c.copyWith(name: 'n2').lastError, 'err');
    });

    test('decodeList 容忍脏数据', () {
      expect(SourceConfig.decodeList('not json'), isEmpty);
      expect(SourceConfig.decodeList('{"a":1}'), isEmpty);
      expect(SourceConfig.decodeList('[]'), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // 组件渲染（无 IO 的部分）
  // ---------------------------------------------------------------------------
  group('组件渲染', () {
    testWidgets('PeekEmpty 渲染文案与操作按钮', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: PeekColors.surface,
            body: PeekEmpty(
              text: '还没有收藏',
              icon: Icons.star_outline_rounded,
              actionText: '去逛逛',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );
      expect(find.text('还没有收藏'), findsOneWidget);
      expect(find.text('去逛逛'), findsOneWidget);
      await tester.tap(find.text('去逛逛'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('PeekLoading 渲染文案与转圈', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: PeekColors.surface,
            body: const PeekLoading(text: '加载中…'),
          ),
        ),
      );
      expect(find.text('加载中…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('PeekSectionTitle 渲染标题', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: PeekColors.surface,
            body: const PeekSectionTitle('写源助手'),
          ),
        ),
      );
      expect(find.text('写源助手'), findsOneWidget);
    });

    testWidgets('PeekTile 渲染标题/副标题并能点击', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: PeekColors.surface,
            body: PeekTile(
              icon: Icons.link,
              title: '点播',
              subtitle: '未添加接口',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      expect(find.text('点播'), findsOneWidget);
      expect(find.text('未添加接口'), findsOneWidget);
      await tester.tap(find.text('点播'));
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('PeekPageHeader 渲染标题', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: PeekColors.surface,
            body: const PeekPageHeader(title: '设置'),
          ),
        ),
      );
      expect(find.text('设置'), findsOneWidget);
    });
  });
}
