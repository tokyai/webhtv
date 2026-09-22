import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../core/utils.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'appearance_page.dart';
import 'interface_config_page.dart';
import 'misc_settings_pages.dart';
import 'player_settings_page.dart';

/// 设置页。
///
/// ## 顺序的权威依据
/// `app/src/mobile/res/layout/fragment_setting.xml` 里各行的 **布局顺序**
/// （即用户从上往下看到的顺序）。注意它与 `SettingFragment.initEvent()`
/// 的绑定顺序**不同**（绑定顺序是 `vod, doh, live, wall, appearance, cache,
/// backup, enhance, player, danmaku, restore, version`），以布局为准：
///
/// | # | id | 原版文案 | 副标题 |
/// |---|---|---|---|
/// | 1  | `vod`        | 点播     | 当前接口 |
/// | 2  | `live`       | 直播     | 当前直播源 |
/// | 3  | `wall`       | 壁纸     | `Setting.getWallDesc` |
/// | 4  | `enhance`    | 增强功能 | 功能开关 |
/// | 5  | `player`     | 播放设置 | 解码/缩放/长按倍速… |
/// | 6  | `danmaku`    | 弹幕设置 | 开关/透明度/字号… |
/// | 7  | `appearance` | 外观与语言 | 「4 项」 |
/// | 8  | `incognito`  | 无痕模式 | 开 / 关 |
/// | 9  | `doh`        | DoH      | 当前 DoH |
/// | 10 | `cache`      | 缓存     | 缓存占用 |
/// | 11 | `backup`     | 备份     | 导出应用数据 |
/// | 12 | `restore`    | 恢复     | 导入应用数据 |
/// | 13 | `version`    | 关于     | 版本号 |
///
/// 文案取自 `app/src/main/res/values-zh-rCN/strings.xml`
/// （`setting_vod=点播` / `setting_live=直播` / `setting_wall=壁纸` /
/// `setting_enhance=增强功能` / `setting_player=播放设置` / `setting_danmaku=弹幕设置` /
/// `setting_appearance=外观与语言` + `setting_appearance_summary=4 项` /
/// `setting_incognito=无痕模式` / `setting_doh=DoH` / `setting_cache=缓存` /
/// `setting_backup=备份` / `setting_restore=恢复` / `setting_about=关于`；
/// 开/关 = `setting_on=开` / `setting_off=关`）。
///
/// ## 被删掉的 PeekPili 独有项
/// `弹幕API配置` 已并入 `弹幕设置`；`外观与个性化` → 收窄为 `外观与语言`；
/// `TMDB 配置`、`追剧推荐设置`、`写源助手 ×3`、`检查更新` 全部删除。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// 原版 `getSwitch(boolean)` → `R.string.setting_on` / `setting_off`。
  static String _sw(bool v) => v ? '开' : '关';

  /// 原版 `Setting.DOH_LIST` 的可选项（`Setting.java`）。
  static const _dohList = <String>['关闭', '阿里', '腾讯', '360', 'Google', 'Cloudflare'];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cacheMb =
        (Store.get<int>('cacheBytes', 0) / 1024 / 1024).toStringAsFixed(1);
    final incognito = Store.get<bool>('incognito', false);
    final dohIndex = Store.get<int>('dohIndex', 0);

    return Scaffold(
      backgroundColor: PeekColors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
              child: Text('设置',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: PeekColors.onSurface)),
            ),

            // 1. 点播 —— 原版弹 ConfigDialog 管理点播接口。
            //    本工程的等价物就是「源管理」，复用 InterfaceConfigPage。
            PeekTile(
              icon: Icons.link,
              title: '点播',
              subtitle: app.activeSource?.name ??
                  (app.hasSources ? '未启动' : '未添加接口'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const InterfaceConfigPage()),
              ),
            ),

            // 2. 直播 —— 本工程的源（CatVodSpiderios）`GET /config` 不含 `live`
            //    段，没有直播源可配，按「无数据置灰」处理，与原版空态一致。
            PeekTile(
              icon: Icons.live_tv_outlined,
              title: '直播',
              subtitle: '当前接口未提供直播源',
              onTap: () => peekToast(context, '当前接口不含直播段（源返回的 config 无 live）'),
            ),

            // 3. 壁纸
            PeekTile(
              icon: Icons.wallpaper_outlined,
              title: '壁纸',
              subtitle: Store.get<String>('wallDesc', '内置壁纸'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WallpaperSettingsPage()),
              ),
            ),

            // 4. 增强功能
            PeekTile(
              icon: Icons.auto_awesome_outlined,
              title: '增强功能',
              subtitle: '站源健康排序、无痕搜索等',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EnhanceSettingsPage()),
              ),
            ),

            // 5. 播放设置
            PeekTile(
              icon: Icons.play_circle_outline,
              title: '播放设置',
              subtitle: '解码、缩放、长按倍速、自动换源',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PlayerSettingsPage()),
              ),
            ),

            // 6. 弹幕设置
            PeekTile(
              icon: Icons.subtitles_outlined,
              title: '弹幕设置',
              subtitle: '开关、透明度、字号、速度',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DanmakuConfigPage()),
              ),
            ),

            // 7. 外观与语言（4 项）
            PeekTile(
              icon: Icons.palette_outlined,
              title: '外观与语言',
              subtitle: '4 项',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AppearancePage()),
              ),
            ),

            // 8. 无痕模式（开关）
            PeekTile(
              icon: Icons.visibility_off_outlined,
              title: '无痕模式',
              subtitle: _sw(incognito),
              onTap: () async {
                final v = !Store.get<bool>('incognito', false);
                await Store.set('incognito', v);
                if (context.mounted) peekToast(context, '无痕模式：${_sw(v)}');
              },
            ),

            // 9. DoH（单选）
            PeekTile(
              icon: Icons.dns_outlined,
              title: 'DoH',
              subtitle: _dohList[dohIndex.clamp(0, _dohList.length - 1)],
              onTap: () async {
                final i = await _single(context, 'DoH', _dohList, dohIndex);
                if (i == null) return;
                await Store.set('dohIndex', i);
              },
            ),

            // 10. 缓存
            PeekTile(
              icon: Icons.cleaning_services_outlined,
              title: '缓存',
              subtitle: '$cacheMb MB',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CacheSettingsPage()),
              ),
            ),

            // 11. 备份
            PeekTile(
              icon: Icons.file_upload_outlined,
              title: '备份',
              subtitle: '导出设置与收藏到文件',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BackupPage()),
              ),
            ),

            // 12. 恢复
            PeekTile(
              icon: Icons.file_download_outlined,
              title: '恢复',
              subtitle: '从备份文件导入',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RestorePage()),
              ),
            ),

            // 13. 关于
            PeekTile(
              icon: Icons.info_outline,
              title: '关于',
              subtitle: 'WebHTV $kAppVersion',
              showDivider: false,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单选弹层（原版 `ChoiceDialog.showSingle` 的形状）。
  static Future<int?> _single(
    BuildContext context,
    String title,
    List<String> options,
    int selected,
  ) {
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PeekColors.surfaceContainer,
        title: Text(title,
            style: TextStyle(fontSize: 16, color: PeekColors.onSurface)),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: SizedBox(
          width: 280,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (_, i) => InkWell(
              onTap: () => Navigator.of(ctx).pop(i),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        options[i],
                        style: TextStyle(
                          fontSize: 14,
                          color: i == selected
                              ? PeekColors.primary
                              : PeekColors.onSurface,
                        ),
                      ),
                    ),
                    if (i == selected)
                      Icon(Icons.check, size: 18, color: PeekColors.primary),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('关闭', style: TextStyle(color: PeekColors.hint)),
          ),
        ],
      ),
    );
  }
}

/// 应用版本号（与 `pubspec.yaml` 的 `version:` 保持一致）。
const kAppVersion = 'v0.1.0';
