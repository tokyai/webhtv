# iOS 版构建与签名指南

> 状态：**已实施**。任务族 `X1-ios`。
> 创建：2026-09-22。

---

## 1. 一句话说明

iOS 版与 Windows 桌面端**共用同一份 Flutter 代码**（`platform/desktop/lib/`，
14123 行），差异只在两处：

1. **平台工程**：多一个 `platform/desktop/ios/`（Xcode 工程 + Podfile）
2. **源服务承载方式**：桌面端起独立 `node.exe` 子进程；iOS 走**进程内 Node**
   （nodejs-mobile），因为 iOS 沙盒禁止 spawn 子进程

---

## 2. 架构：为什么 iOS 必须用 nodejs-mobile

### 2.1 两端的源服务承载差异

| | Windows 桌面端 | iOS |
|---|---|---|
| 承载形态 | **独立 Node 进程** | **进程内 Node**（同一进程内的 pthread） |
| 启动方式 | `Process.start(node.exe, [boot])` | FFI 调 `nodeStartThread(argc, argv, NULL)` |
| Node 来源 | 随包分发的 `runtime/node.exe`（87 MB） | `NodeMobile.framework`（54.9 MB，链进 App） |
| 通信 | HTTP `127.0.0.1:9988` | HTTP `127.0.0.1:9988`（**完全一样**） |
| 孤儿进程 | 需要看护（心跳 + ppid 双判据） | **不存在**（宿主死则 Node 死） |
| 能否停止 | 可以（杀进程） | **不能**（NodeMobile 无 `node_stop` 导出） |

对外的接口契约完全一致 —— 都监听 `127.0.0.1:9988`，都靠 `/health` 返回
`CatVodSpiderios` 判定就绪。**客户端代码零差异**。

### 2.2 代码分派点

`lib/backend/source_runtime.dart` 是唯一的平台分派层：

```dart
if (Platform.isIOS) {
  await _startInProcess(boot.path);     // iOS：进程内
} else {
  await _startSubprocess(nodeExecutable, boot.path);  // 桌面：子进程
}
```

`lib/tvbox/backend_bridge.dart` 的 `start()` 里，iOS 会**跳过两件事**：

- **不查找 `node.exe`**（不需要，Node 已链进 App）
- **不做端口 9988 预检**（进程内 Node 是单例，同进程内不可能有「别的程序占着」）

---

## 3. 关键文件清单

```
platform/desktop/
├── ios/
│   ├── Podfile                          ← 挂 vendored pod + -u 钉符号
│   ├── Runner/
│   │   ├── Info.plist                   ← ATS 放开 / 竖屏 / 后台音频
│   │   ├── AppDelegate.swift            ← Flutter 标准模板，未改
│   │   └── ...
│   └── flutter_node/                    ← 手工 vendor 的本地 pod（非 pub 插件）
│       ├── flutter_node.podspec
│       ├── Classes/
│       │   ├── NodeWrapper.c            ← 补齐 camelCase 三件套（11 KB）
│       │   ├── FlutterNodePlugin.h/.m
│       │   └── SwiftFlutterNodePlugin.swift
│       └── Frameworks/
│           └── NodeMobile.framework/    ← nodejs-mobile，54,959,120 B
└── lib/backend/ios_node_runtime.dart    ← FFI 绑定层
```

### 3.1 为什么 `flutter_node` 是 vendored pod 而不是 pub 插件

Flutter 的 `flutter_install_all_ios_pods` **只认** `.flutter-plugins-dependencies`
里登记的插件。`flutter_node` 不在这份清单里，因此必须在 Podfile 显式挂：

```ruby
pod 'flutter_node', :path => 'flutter_node'
```

### 3.2 为什么 podspec 必须 `static_framework = false`

Dart 侧是**运行期按名字查符号**（`DynamicLibrary.process().lookupFunction('nodeStartThread')`）。
链接器看不到任何对 `nodeStartThread` 的引用，如果做成**静态库**，
`-dead_strip` 会认为这些符号没人用而**直接删掉**。做成 dylib 才能保住导出表。

Podfile 里还加了 `-Wl,-u,_nodeStart` 等三个 `-u` 钉符号作**保险带** —— 双保险。

### 3.3 为什么 `NodeWrapper.c` 必须存在

`NodeMobile.framework` **只导出一个** C 符号：

```
_node_start    （extern "C"，int node_start(int argc, char** argv)，2 参、阻塞）
```

而 Dart 侧的 `flutter_node` 按 **camelCase** 查找：

```
nodeStart / nodeStartThread / nodeStop
```

原版 `flutter_node.framework` 的导出表里确实有这三个（`_nodeStart@0x400c`、
`_nodeStartThread@0x40ec`、`_nodeStop@0x4264`），`NodeWrapper.c` 就是按那份
二进制的**反汇编逐条还原**出来的 —— 包括：

- `dlsym(RTLD_DEFAULT, "node_start")` + 静态缓存的解析包装
- 线程上下文的**内存布局**（`offset 0: int argc`、`offset 8: char** argv`、
  `offset 16: void* cb`，总 24 字节）
- `node_start` 只吃**两个**参数（第 3 个 `cb` 不进 `node_start`）

### 3.4 为什么必须用 `nodeStartThread` 而不是 `nodeStart`

`nodeStart` 是**阻塞**的（在调用者线程上跑完整个 Node 事件循环）。
在 Flutter 的 platform/UI 线程上调用会**直接冻住界面**。
`nodeStartThread` 起 pthread 后立即返回，是唯一正确用法。

---

## 4. 构建：GitHub Actions 出未签名包

### 4.1 为什么走 CI

构建 iOS 需要 **macOS + Xcode**，Windows 上无法完成。本仓库开发机是 Windows，
因此把构建搬到 GitHub Actions 的 macOS runner。

工作流：`.github/workflows/ios-release.yml`

```yaml
runs-on: macos-14
steps:
  - subosito/flutter-action@v2  (flutter 3.41.6, stable)
  - flutter pub get
  - pod install --repo-update          # 必须在 pub get 之后
  - flutter build ios --release --no-codesign
  - 手工组装 Payload/ → zip 成 .ipa
```

### 4.2 为什么产出「未签名」包

签名证书与私钥属敏感材料，放进仓库或 CI secret 都会扩大暴露面。
未签名 `.ipa` 有三种用途：

1. 交给 **Sideloadly / AltStore / TrollStore** 等工具，用本地证书重签后安装
2. 交给 `codesign` + 自签描述文件（本项目已有）重签
3. 作为归档留存，需要时再签

### 4.3 CI 里的两道自检

workflow 在打包前会检查：

- `Info.plist` 含 `NSAppTransportSecurity` / `UISupportedInterfaceOrientations`
  / `UIBackgroundModes`（缺了只是警告）
- `Runner.app/Frameworks/NodeMobile.framework` **必须存在**（缺了直接失败 ——
  这意味着源服务起不来）

---

## 5. 本地重签（在 Mac 上）

`scripts/sign_ios.sh` 把未签名 `.ipa` 用自签证书重签。

```bash
bash scripts/sign_ios.sh \
  --ipa  dist/WebHTV-0.1.0-ios-unsigned.ipa \
  --p12  /path/to/ios_sign.p12 \
  --profile /path/to/PeekPili_Dev_Profile.mobileprovision \
  --password 123456 \
  --bundle-id com.webhtv.app \
  --out  dist/WebHTV-0.1.0-ios-signed.ipa
```

> ⚠️ **本脚本不能在 Windows 上运行** —— 需要 macOS 的 `codesign` / `security`。
> Windows 下请改用 Sideloadly。

签名材料（本项目已有，位于 `D:\Work\workSpace\PeekPiliRelease\app\anzhuangbao\ios\`）：

| 文件 | 用途 |
|---|---|
| `development.cer` | 开发证书（DER） |
| `ios_sign.key` | 私钥 |
| `ios_sign.csr` | 证书签名请求 |
| `ios_sign.p12` | 上面三个合成，**密码 `123456`** |
| `PeekPili_Dev_Profile.mobileprovision` | 开发描述文件 |

合成 p12 的命令（`1.txt` 里记的）：

```bash
openssl x509 -inform DER -in development.cer -out ios_sign.pem -outform PEM
openssl pkcs12 -export -inkey ios_sign.key -in ios_sign.pem -out ios_sign.p12
# 密码: 123456
```

---

## 6. 竖屏适配

### 6.1 自适应导航（核心）

`lib/widgets/bottom_nav_bar.dart` 的 `AdaptiveNav` 按可用宽度**自动切换**：

| 宽度 | 形态 | 理由 |
|---|---|---|
| ≥ 600dp | 左侧 `NavRail`（76dp 宽） | 桌面窗口 / iPad / 手机横屏 |
| < 600dp | 底部 `BottomNavBar`（56dp 高） | 手机竖屏 |

**断点为什么取 600dp**：Material 3 的 `compact`/`medium` 分界，也恰好落在
「iPhone 竖屏最宽 430dp（Pro Max）」与「iPad 竖屏最窄 744dp（iPad mini）」
之间的空档，不会误判。

**竖屏为什么不能用侧栏**：430dp 宽下侧栏吃掉 76dp ≈ **18%** 可用宽度，
内容区被压缩到难以浏览海报栅格。底栏只损耗纵向 56dp，而竖屏本来就要滚动。

### 6.2 风格一致性怎么保证

「风格一致」不是「长得一样」，而是**同一套设计语言**：

- 选中项都用 `PeekColors.railSelected` 底 + `PeekColors.primary` 图标
- 未选中都用 `PeekColors.railIdle`
- 图标都沿用 `*_outlined`（未选）/ `*_rounded`（选中）的成对规律
- 圆角、字重从 `PeekColors` 取同一组常量

差异只在**几何**：侧栏是 59×59.5dp 方块 + 12px 文字（纵向堆叠），
底栏是图标在上、11px 文字在下的窄条（横向均分）。

### 6.3 方向策略

**iOS 不锁方向**（`main.dart` 里只有 `Platform.isAndroid` 才会强制横屏）。
理由：用户要竖屏结构，但播放器需要能转横屏全屏观看，所以交给系统跟随设备，
界面层用 `AdaptiveNav` 做自适应。

### 6.4 海报栅格无需改动

`home_page.dart` 的栅格**已经是按可用宽度算列数**：

```dart
final w = c.maxWidth - PeekColors.contentPadding * 2;
final cols = ((w + gap) / (target + gap)).round().clamp(2, 8);
```

因此竖屏自动变 2 列、横屏自动变 6 列，**零改动**。

### 6.5 已锁进测试的行为

`test/widget_test.dart` 的「自适应导航」组（6 个测试）：

- 390dp（iPhone 竖屏）→ 底栏，无侧栏
- 1280dp（桌面窗口）→ 侧栏，无底栏
- 599dp / 600dp 断点两侧行为
- 两种形态都渲染全部导航条目
- 底栏点击回调正确下标
- 底栏为 Home Indicator 留出底部安全区

---

## 7. iOS 特有配置（`Info.plist`）

| 键 | 值 | 为什么 |
|---|---|---|
| `NSAppTransportSecurity.NSAllowsArbitraryLoads` | `true` | 绝大多数站源是 `http://`，ATS 默认会掐断 |
| `NSAllowsLocalNetworking` | `true` | 源服务监听 `127.0.0.1:9988`，属本地网络 |
| `UIBackgroundModes` | `[audio]` | 息屏/切后台继续播放 |
| `UISupportedInterfaceOrientations` | 竖屏 + 横屏左右 | 竖屏浏览，播放器转横屏 |
| `CFBundleDisplayName` | `WebHTV` | 桌面图标名 |

---

## 8. 平台部署目标：iOS 13.0

`NodeMobile.framework` 的 `Info.plist` 声明 `MinimumOSVersion = 13.0`，
Podfile 与 podspec 都对齐到 13.0。

**模拟器不支持**：`NodeMobile` 只有 arm64 **真机**切片，没有模拟器切片。
Podfile 里设了 `EXCLUDED_ARCHS[sdk=iphonesimulator*] = 'arm64 x86_64'`
—— 在模拟器上构建会直接失败，这是**预期行为**，不是 bug。

---

## 9. 已知限制

1. **进程内 Node 无法重启**：`nodeStop` 只重置标志位，不真正停止事件循环。
   这与安卓端「内嵌 Node 刻意不停止（进程级单例）」的结论一致。
   实际影响：切换到另一个源时，旧源的服务仍在跑（但它不占额外端口，
   新源复用同一端口会失败）。
2. **未签名包不能直接安装**：必须经 Sideloadly 或 `sign_ios.sh` 重签。
3. **Windows 上无法构建 iOS**：必须走 CI 或 Mac。
4. **无 Apple 开发者账号时的 7 天限制**：免费开发者证书签的应用每 7 天过期，
   需重新签名安装。

---

## 10. 验证记录（2026-09-22）

| 检查项 | 结果 |
|---|---|
| `flutter analyze lib test` | ✅ No issues found! |
| `flutter test` | ✅ 46/46 passed（含 6 个新增自适应导航测试） |
| `flutter build windows --release` | ✅ Built（42.3s，双平台改造未破坏桌面端） |
| `ios/` 文件齐全 | ✅ 50 个文件（含 NodeMobile 54,959,120 B） |
| `NodeWrapper.c` 与源一致 | ✅ 11,224 B |
| `Podfile` 与参考工程一致 | ✅ 3,259 B |

**未验证**（受环境限制）：

- **iOS 实际构建** —— 需 macOS，本机无法执行。workflow 与 Podfile 按参考工程
  （已验证可出的 `PeekPili_ios_1.2.5+2.ipa`）1:1 复刻，但**未在本仓库 CI 上跑过一次**。
- **iOS 运行时行为**（进程内 Node 能否正常起服务、`/health` 是否响应）——
  需真机，本机无法验证。
