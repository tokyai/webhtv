import 'package:flutter_test/flutter_test.dart';
import 'package:webhtv_win/core/netdisk_sources.dart';

/// 网盘源识别测试。
///
/// 夹具取自**实测的真实数据**（源服务 `/spider/<key>/3/detail` 的
/// `vod_play_url`），不是编造的样例 —— 见 `NetdiskSources` 文档里的
/// 判定表。
void main() {
  group('识别网盘源', () {
    test('夸克网盘（玩偶|4K 实测结构）', () {
      // 真实载荷：base64({"providerId":"quark","shareId":...,"fileId":...})
      const payload =
          'eyJwcm92aWRlcklkIjoicXVhcmsiLCJzaGFyZUlkIjoiODViM2Y4MDhjMTE3IiwiZmlsZUlkIjoiMzY1MzBmOTFlMmIwNDQwOGE5NWU0NDI2ODZjYjdjMzQiLCJuYW1lIjoiWzMuNkdCXVRoZS5Nb25nb29zZS4yMDI2LjEwODBw5Lit6Iux5a2X5bmVLm1wNOOAkOeMq+m8rOOAkSIsInBsYXlUb2tlbiI6IntcImZpZFwiOlwiMzY1MzBmOTFlM'
          'bIwNDQwOGE5NWU0NDI2ODZjYjdjMzRcIn0iLCJxdWFsaXR5IjoiMTA4MHAiLCJtb2RlIjoiIn0=';
      final url = '[3.6GB]The.Mongoose.2026.1080p中英字幕.mp4【猫鼬】\$$payload';
      expect(NetdiskSources.detectFromPlayUrl(url), 'quark');
    });

    test('115 网盘（木偶|4K 实测结构）', () {
      const payload = 'eyJwcm92aWRlcklkIjoicGFuMTE1Iiwic2hhcmVJZCI6InN3MTIzIn0=';
      expect(
        NetdiskSources.detectFromPlayUrl('115原画\$$payload'),
        'pan115',
      );
    });

    test('百度网盘', () {
      const payload = 'eyJwcm92aWRlcklkIjoiYmFpZHUiLCJzaGFyZUlkIjoiYWJjIn0=';
      expect(NetdiskSources.detectFromPlayUrl('百度原画\$$payload'), 'baidu');
    });

    test('UC / 迅雷', () {
      expect(
        NetdiskSources.detectFromPlayUrl(
            'UC原画\$${'eyJwcm92aWRlcklkIjoidWMiLCJzaGFyZUlkIjoieCJ9'}'),
        'uc',
      );
      expect(
        NetdiskSources.detectFromPlayUrl(
            '迅雷\$${'eyJwcm92aWRlcklkIjoidGh1bmRlciIsInNoYXJlSWQiOiJ5In0='}'),
        'thunder',
      );
    });

    test('多集时只看第一条', () {
      const a = 'eyJwcm92aWRlcklkIjoicXVhcmsiLCJzaGFyZUlkIjoiMSJ9';
      const b = 'eyJwcm92aWRlcklkIjoicXVhcmsiLCJzaGFyZUlkIjoiMiJ9';
      expect(
        NetdiskSources.detectFromPlayUrl('第01集\$$a#第02集\$$b'),
        'quark',
      );
    });

    test('base64 缺 = 填充也能认（源侧截断很常见）', () {
      // 去掉尾部所有 '='
      const payload = 'eyJwcm92aWRlcklkIjoicXVhcmsiLCJzaGFyZUlkIjoiMSJ9';
      final trimmed = payload.replaceAll(RegExp(r'=+$'), '');
      expect(NetdiskSources.detectFromPlayUrl('x\$$trimmed'), 'quark');
    });
  });

  group('不误判直链源', () {
    test('m3u8 直链', () {
      expect(
        NetdiskSources.detectFromPlayUrl('第01集\$https://cdn.x.com/a/index.m3u8'),
        isNull,
      );
    });

    test('mp4 直链', () {
      expect(
        NetdiskSources.detectFromPlayUrl('x\$https://cdn.x.com/a.mp4'),
        isNull,
      );
    });

    test('空字符串', () {
      expect(NetdiskSources.detectFromPlayUrl(''), isNull);
    });

    test('七味|4K 那种「名字带 4K 但实际直链」不会被误判', () {
      // 这正是「按名字过滤会误伤」的那类源。
      expect(
        NetdiskSources.detectFromPlayUrl('第01集\$https://v.qq.com/x.m3u8'),
        isNull,
      );
    });

    test('base64 但解出来不是 JSON 对象', () {
      // 'hello world' 的 base64
      expect(
        NetdiskSources.detectFromPlayUrl('x\$aGVsbG8gd29ybGQ='),
        isNull,
      );
    });

    test('JSON 但无 providerId 也不带网盘特征字段', () {
      const payload = 'eyJmb28iOiJiYXIifQ=='; // {"foo":"bar"}
      expect(NetdiskSources.detectFromPlayUrl('x\$$payload'), isNull);
    });
  });

  group('provider 白名单', () {
    test('覆盖实测出现过的全部 5 个网盘', () {
      expect(
        NetdiskSources.providers,
        containsAll(<String>['quark', 'baidu', 'uc', 'thunder', 'pan115']),
      );
    });
  });
}
