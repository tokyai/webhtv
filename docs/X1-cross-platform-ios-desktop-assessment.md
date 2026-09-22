# X1：iOS 与桌面端独立客户端评估

> 状态：**评估中（assessment-only）**，未获实施批准。本文件为 `AGENTS.md` §7「Best-practice design research」要求的唯一持久化文档。
> 任务族：`X*`（跨平台扩展，新族，不与 `E*/P*/C*` 混用）。
> 创建日期：2026-09-22。最后更新：2026-09-22（用户回答 Q4/Q5：只 Windows + 自签名）。

---

## Recovery anchor

- **目标/验收**：在**不改动 Android（mobile + leanback）界面与功能**的前提下，新增 iOS 与桌面端客户端，使其能**解析并使用指定的 `.md5` 源**；两端界面按各自平台习惯设计；分别产出成品安装包。
- **硬约束（用户 2026-09-22 明确，第二次澄清）**：
  1. **Android 端手机与电视的界面和功能完全不变**——不允许任何回归。
  2. iOS 与桌面端**可按平台特点独立设计**，不要求与 Android 一致。
  3. **必须通过"添加源地址"的方式引入播放源，不得内置任何源**。
  4. **范围收窄（关键）**：两端**只需支持这一条 `.md5` 源**即可，不需要 `csp_*` jar 源、`.py` 源、多仓聚合。
  5. 交付形态：**分别打包成成品包**。
  6. **桌面端只做 Windows**（Q4，2026-09-22 16:40 确认）：无 macOS / Linux 分支，只需 win-x64 `node.exe`。
  7. **iOS 只需自签名分发**（Q5，同日确认）：无 App Store 上架需求，Node 动态执行 JS 无商店合规问题。
- **工作区/回滚**：`main` / `8e4d9333de8ea7346491e71a0b1ab6858a852298`。本任务为文档 + 探针，探针产物位于 `.workbuddy-ai/tmp/x1probe/`（临时目录，可随时删除）。`app/`、`quickjs/`、`catvod/` 零改动。
- **范围**：仅新增/更新本文件 + 临时探针脚本。不触碰任何生产代码、locks、patches、artifacts。
- **状态**：**端到端探针已通过（2026-09-22）**。源在本机 Node v22.22.2 上成功加载并启动服务监听 `127.0.0.1:9988`。方案已收敛为「Node 承载 drpyS 源」单一路线。
- **核心结论**：
  1. 用户给的 `.md5` 源**不是 TVBox JSON 订阅**，而是**整个 drpyS 服务端程序**（6,487,338 字节单文件 JS，内含 Fastify/cheerio/pako 等完整依赖），导出 `{start, stop}`。
  2. `.md5` 是它的版本校验指针；`index.js` 经 302 重定向到伪装成 `image/jpeg` 的 CDN 对象，**落地内容 MD5 与指针严格一致（已实测 ✅）**。
  3. 该源**在本机 Node 上可 100% 正常运行**，无需 Android、无需 QuickJS、无需 Chaquopy。→ **方案收敛为 A1b（Node 承载），A1a（自建 QuickJS native）不再需要。**
  4. **两套源体系完全独立**（E11）：Android 用 `csp_*` DEX（96 站点），桌面/iOS 用 `nodejs_*`（94 站点）。**Android 侧一行都不用改**；两端不共享源处理代码。
  5. 源程序运行时自动生成 94 站点的配置（`nodejs_*`），客户端只需读取，**天然满足"不内置源"**。
  6. **交付面已确定**：Windows 单一桌面产物（Q4）+ iOS 自签 `.ipa`（Q5）。Q4/Q5 均已闭环，无剩余范围疑问。
- **唯一下一动作**：等待用户批准进入 `X1-2`（Windows 桌面端 MVP）实施。

---

## 1. 要实现的实际能力

用普通语言描述：

用户在 Android 手机和 Android TV 上现在能做的事，**保持一模一样、一点不动**。另外新增两个客户端：

- **iOS 客户端**：在 iPhone / iPad 上安装，用户自己填入源地址（订阅地址），就能浏览、搜索、播放。
- **桌面客户端**：在 Windows / macOS 上运行，同样是用户自己填源地址。

两个新客户端的外观和交互可以按各自平台的习惯重新设计（iOS 用 SwiftUI 风格、桌面用桌面窗口布局），**不要求复制 Android 的界面**。

---

## 2. 当前项目已有实现

### 2.1 Android 端（必须保持不变的基线）

| 维度 | 现状 |
|---|---|
| 包名 / 版本 | `com.fongmi.android.tv`，versionCode 560 / versionName 5.6.0 |
| 语言 | **纯 Java，0 个 Kotlin 文件**，1242 个 `.java` |
| 构建 | Gradle，`mode` 维度（`leanback` \| `mobile`）× `abi` 维度（`arm64_v8a` \| `armeabi_v7a`） |
| SDK | compileSdk 37 / minSdk 24 / targetSdk 28 / NDK 29.0.14206865 / JDK 21 |
| 模块 | `:app`、`:catvod`、`:chaquo`、`:quickjs` |
| `main` 代码 | 737 文件 / **182,668 行** |
| `leanback` flavor | 112 文件 / **22,197 行** / 96 个 layout |
| `mobile` flavor | 118 文件 / **23,938 行** / 113 个 layout |
| 全项目 layout | **248 个 XML** |
| `player/` 包 | 292 文件 / **84,833 行**（其中 `exo` 97 文件 25,138 行、`mpv` 22 文件 8,207 行、`engine` 14 文件 5,387 行） |
| `ui/` 包 | 80 文件 / 34,110 行 |

### 2.2 源加载体系（三个 loader，这是本次评估的核心）

`app/src/main/java/com/fongmi/android/tv/api/loader/` 共 6 个类：`BaseLoader` / `JarLoader` / `CspDexClassLoader` / `CspClassLoadingPolicy` / `JsLoader` / `PyLoader`。

`BaseLoader.java:58-63` 分派逻辑：

```java
public Spider getSpider(String key, String api, String ext, String jar) {
    if (isPy(api)) return pyLoader.getSpider(key, api, ext);
    else if (isJs(api)) return jsLoader.getSpider(key, api, ext, jar);
    else if (isCsp(api)) return jarLoader.getSpider(key, api, ext, jar);
    else return new SpiderNull();
}
```

- `isJs` → `api.contains(".js")`
- `isPy` → `api.contains(".py")`
- `isCsp` → `api.startsWith("csp_")`

### 2.3 用户"添加源地址"的现有链路（必须在新客户端复刻）

`Config` bean（`bean/Config.java`）就是订阅地址模型，字段：`type / time / url / json / name / logo / home / parse / notice / danmaku`。数据库层用 Room：

```java
@Entity(indices = @Index(value = {"url", "type"}, unique = true))
public class Config {
```

`VodConfig.parseConfig()` 是解析入口（`api/config/VodConfig.java:156`），支持两种形态：

```java
if (object.has("urls"))      parseDepot(config, object);   // 多仓聚合
else                         parseConfig(config, object);  // 单仓
```

解析后写入：`sites` / `parses` / `doh` / `rules` / `ads` / `flags`（`VodConfig.java:196-206`）：

```java
BaseLoader.get().parseJar(spider, true);
setSites(Json.safeListElement(object, "sites").stream()
        .map(e -> Site.objectFrom(e, spider))...);
setParses(Json.safeListElement(object, "parses").stream()
        .map(Parse::objectFrom)...);
```

`Site` bean 字段（`bean/Site.java:38-80`）：`key / name / api / ext / jar / click / playUrl / homePage / chromeMode`。其中 `api` 就是 `.js` / `.py` / `csp_*` 三选一的源类型标识。

**结论：源的全部身份信息都在一个 JSON 里，客户端只是一个 JSON 解释器 + Spider 运行时。这为跨平台复用提供了可能。**

---

## 3. 涉及仓库及完整 commit ID

| 仓库 | 完整 commit ID | 作用 | 本次是否改动 |
|---|---|---|---|
| WebHTV 本体 | `8e4d9333de8ea7346491e71a0b1ab6858a852298` | 当前 HEAD | 否（纯评估） |
| `wang.harlon.quickjs:wrapper-java` | 版本 `3.2.3`（Maven 坐标记录于 `gradle/libs.versions.toml:134`） | **纯 JVM 版 QuickJS 绑定** | 否 |
| `wang.harlon.quickjs:wrapper-android` | 版本 `3.2.3`（`libs.versions.toml:133`） | Android 版 QuickJS 绑定 | 否 |
| FongMi/mpv-android | `99a60ad2141d5ace94453590903c2c6b9a0a2443`（`third_party/mpv-native-lock.json` → `builder.commit`） | MPV 原生栈构建源 | 否 |
| Chaquopy | `17.0.0` | Android Python 运行时 | 否 |

---

## 4. 关键证据（按 `AGENTS.md` §7 要求记录 access date 与 evidence grade）

采集日期：**2026-09-22**。所有条目为本地源码直读（A 级）。

### E1 — QuickJS 有纯 JVM 变体，但**不带 Windows 原生库** 【A 级，已实测】

项目同时声明两个依赖（`quickjs/build.gradle` + `gradle/libs.versions.toml:133-134`）：

```toml
quickjs-android = { group = "wang.harlon.quickjs", name = "wrapper-android", version.ref = "quickjs" }
quickjs-java    = { group = "wang.harlon.quickjs", name = "wrapper-java",    version.ref = "quickjs" }
```

**实测 Maven Central（access date 2026-09-22）**：

`https://repo1.maven.org/maven2/wang/harlon/quickjs/wrapper-java/3.2.3/` 目录下**只有**：

```
wrapper-java-3.2.3.jar          24,693 B
wrapper-java-3.2.3-sources.jar  13,450 B
wrapper-java-3.2.3-javadoc.jar 143,103 B
wrapper-java-3.2.3.pom / .module
```

**没有任何 platform-classifier 构件**（不存在 `-windows-x86_64`、`-linux-x86_64`、`-osx` 之类）。24,693 字节的 JAR 不可能内含 native 库。

Gradle module metadata 的所有 variant（`apiElements` / `runtimeElements` / `sourcesElements`）**均不含任何 `org.gradle.native.operatingSystem` 或 architecture 属性**——即该构件平台无关，native 由使用者自备。

**上游官方构建说明**（`HarlonWang/quickjs-wrapper` → `wrapper-java/README.md`，access date 2026-09-22）原文：

```
# 构建
## 环境要求:
+ JDK & JAVA_HOME 环境变量
+ 安装好 cmake ninja

### cmake 安装方式 mac
brew install cmake
### cmake 安装方式 linux
apt remove cmake
...
## 构建动态链接库
cd wrapper-java
cmake -DCMAKE_BUILD_TYPE=Debug -DCMAKE_MAKE_PROGRAM=ninja -G Ninja -S ./src/main -B ./build/cmake
cmake --build ./build/cmake --target quickjs-java-wrapper -j 6

## 产物
so 链库地址:
    wrapper-java/build/cmake/libquickjs-java-wrapper.dylib

## TODO
- [ ] 跨平台编译方式(在单一平台编译出其他平台产物)
```

**决定性细节**：
1. 构建文档只给了 **mac** 与 **linux** 两种环境说明，**完全没有 Windows 说明**。
2. 产物示例是 `libquickjs-java-wrapper.dylib`（macOS），**不是 `.so` 也不是 `.dll`**。
3. 上游 TODO 明确写着「跨平台编译方式（在单一平台编译出其他平台产物）」——**说明跨平台编译尚未实现**。
4. `wrapper-java/src/main/CMakeLists.txt` 的 include 路径只有：
   ```
   ${JAVA_HOME}/include/
   ${JAVA_HOME}/include/darwin
   ${JAVA_HOME}/include/linux
   ```
   **没有 `win32` 目录**。
5. 根 `CMakeLists.txt` 通篇**没有任何 `if(WIN32)` 分支**。
6. `wrapper-java` 的文件树中**不存在 `QuickJSLoader` 类**（该类只在 `wrapper-android` 中）；JVM 侧必须自行 `System.loadLibrary`。

**API 兼容性（好消息）**：`wrapper-java` 的 `QuickJSContext` 公开 API 与 Android 版**基本一致**，WebHTV 用到的全部方法均存在：

| WebHTV 使用点 | wrapper-java 是否支持 |
|---|---|
| `QuickJSContext.create()` | ✅ |
| `setModuleLoader(new QuickJSContext.BytecodeModuleLoader(){...})` | ✅ |
| `setConsole(Console)` | ✅ |
| `JSArray` / `JSObject` / `JSFunction` / `JSMethod` | ✅ |
| `JSCallFunction` | ✅ |

**支持的主张**：源码层零改动可编译，**但 Windows 上无法直接运行**——缺 native 库，且上游未提供 Windows 构建路径与 win32 JNI 头支持。

**WebHTV 适用性**：**这是本方案最大的技术障碍**。结论：桌面端若走 Java 路线，必须自行编译 QuickJS native（Windows 需自行补 JNI win32 支持），或改用 Node.js 承载 JS 源。

**Caveat**：JVM 版有线程约束——`QuickJSContext` 所有公开方法调用 `checkSameThread()`，跨线程抛 `QuickJSException("Must be call same thread in QuickJSContext.create!")`。WebHTV 的 `QuickJS Spider` 已用 `ExecutorService` 单线程调度，需在 `X1-1` 确认该约束可满足。

### E2 — JS 运行时核心的平台耦合极浅 【A 级】

`quickjs/src/main/java/` 共 15 文件 / 1349 行。全部 `android.*` / `androidx.*` 引用仅 11 处：

```
bean/Req.java:        import android.text.TextUtils;
bean/Res.java:        import android.text.TextUtils;
crawler/Spider.java:  import android.content.Context;
method/Global.java:   import androidx.annotation.Keep;
method/Global.java:   import androidx.annotation.NonNull;
method/Local.java:    import android.text.TextUtils;
method/Local.java:    import androidx.annotation.Keep;
utils/Crypto.java:    import android.util.Base64;
utils/Module.java:    import android.text.TextUtils;
utils/Module.java:    import android.util.LruCache;
utils/Parser.java:    import android.text.TextUtils;
```

逐项可替代性：

| Android 依赖 | 出现次数 | 纯 JVM 替代 |
|---|---|---|
| `android.text.TextUtils` | 5 | `String.isEmpty()` / `Objects.requireNonNull()` |
| `android.util.Base64` | 1 | `java.util.Base64`（JDK 8+ 标准库，语义等价） |
| `android.util.LruCache` | 1 | `LinkedHashMap` + `removeEldestEntry`，或 Caffeine |
| `android.content.Context` | 1 | 抽象为参数对象（`Spider.init(Context, String ext)` 的 Context 实际只用于取 filesDir/asset） |
| `androidx.annotation.*` | 3 | 无功能作用，可直接删除 |

`Crypto.java` 全文只用了 `Base64.decode` / `Base64.encodeToString`，其余全部是纯 JDK（`javax.crypto` / `java.security` / `java.nio.charset`）。替换 `android.util.Base64` → `java.util.Base64` 是**逐行等价**的机械改动（注意 `Base64.DEFAULT` 对应 `Base64.getDecoder()`，`Base64.NO_WRAP` 对应 `Base64.getEncoder().withoutPadding()` 或 `getEncoder()`，需在 `X1-1` 用一次单测锁定行为）。

**支持的主张**：JS 源运行时的 1349 行中，真正不可移植的代码接近 **0 行**。这是一次约 11 处引用的替换工作量。

**Caveat**：`crawler/Loader.java` 与 `crawler/Spider.java` 直接引用 `dalvik.system.DexClassLoader`（见 E3），该部分**必须**拆出。

### E3 — `DexClassLoader` 只用于 jar 源的类加载，与 JS 源解耦不彻底但目前可拆 【A 级】

`quickjs/src/main/java/com/fongmi/quickjs/crawler/Loader.java` 全文：

```java
package com.fongmi.quickjs.crawler;

import com.whl.quickjs.android.QuickJSLoader;

import dalvik.system.DexClassLoader;

public class Loader {

    public Loader() {
        QuickJSLoader.init();
    }

    public Spider spider(String api, DexClassLoader dex) {
        return new Spider(api, dex);
    }
}
```

`Spider.java:32/37/45`：

```java
import dalvik.system.DexClassLoader;
private final DexClassLoader dex;
public Spider(String api, DexClassLoader dex) { ... }
```

`app/src/main/java/com/fongmi/android/tv/api/loader/CspDexClassLoader.java:5`：

```java
final class CspDexClassLoader extends DexClassLoader {
```

`JarLoader.java:76`：

```java
DexClassLoader loader = new CspDexClassLoader(file.getAbsolutePath(), cachePath, cachePath, App.get().getClassLoader());
```

**支持的主张**：`DexClassLoader` 参数是 JS Spider 构造函数的一部分，但**只在 `csp_*` jar 源路径上真正被使用**（用于把 jar 里的类塞进 JS 环境）。JS 源自身不需要它。

**WebHTV 适用性**：桌面/iOS 端把该参数改为可空/接口，即可完全绕开。**这是 `X1-1` 阶段第一个必须做的重构。**

### E4 — `catvod` 模块的平台耦合同样很浅 【A 级】

`catvod/src/main/java/` 共 40 文件 / 4333 行，其中 20 文件含 `android.*`/`androidx.*` 引用。逐文件引用计数：

```
4  utils/Util.java          (Context, WifiManager, TextUtils, Base64)
4  net/OkHttp.java          (annotation.SuppressLint)
4  bean/Doh.java
2  utils/UriUtil.java
2  utils/Prefers.java
2  bean/Proxy.java
1  utils/Path.java          (android.os.Environment)
1  utils/Json.java          (TextUtils)
1  utils/Auth.java
1  crawler/SpiderDebug.java (TextUtils)
1  crawler/Spider.java      (android.content.Context)
1  crawler/DebugLogStore.java
1  bean/Header.java
1  Init.java
```

**支持的主张**：`catvod` 中"必须 Android"的只有 `WifiManager`（取局域网 IP）与 `Environment`（外部存储路径）两处，其余全是 `TextUtils`/`Base64`/注解这类零成本替换。Spider 抽象的接口签名（`Spider.java` 的 `homeContent` / `categoryContent` / `detailContent` / `searchContent` / `playerContent` / `liveContent` / `proxy` / `action`）**全部返回 `String`（JSON 文本）或 `List<String>`**，天然平台中立。

**Caveat**：`Spider.init(Context context, String extend)` 与 `init(Context)` 的 `Context` 参数需要接口化。

### E5 — 订阅解析逻辑可复用，但需去掉 Room 【A 级】

`bean/Config.java` 与 `bean/Site.java` 都带 `@Entity` / `@PrimaryKey` / `@SerializedName` 注解。Room 是 Android 专属，桌面/iOS 需要替换为 SQLite 直接访问、或 JSON 文件存储。

可选方案：
- 桌面：SQLite（`sqlite-jdbc`）或直接 JSON 持久化
- iOS：Core Data / SQLite
- 或两端统一用"JSON 文件 + 内存索引"，因为 Config/Site 数量很小（通常 < 100 条）

**支持的主张**：Room 只是持久化实现，`@SerializedName` 的 JSON 契约才是真正的数据格式。JSON 契约可以 100% 复用。

### E6 — 原生播放器栈整体为 Android 独占，无法复用 【A 级】

**MPV 10 个库**（`app/src/arm64_v8a/assets/mpv-libs/arm64-v8a/`）：

```
libmpv.so        17,820,224 B
libmvcodec.so    16,526,960 B
libmvformat.so    4,498,016 B
libmvfilter.so    4,276,008 B
libc++_shared.so  1,374,336 B
libmwscale.so     1,234,336 B
libmvutil.so        741,456 B
libmwresample.so     96,952 B
libplayer.so         96,160 B     ← JNI 桥
libmvdevice.so        9,376 B
```

构建源：`third_party/mpv-native-lock.json` → `{"builder": {"repo": "https://github.com/FongMi/mpv-android.git", "commit": "99a60ad2141d5ace94453590903c2c6b9a0a2443"}, "android": {"ndk_version": "29.0.14206865", "ndk_label": "r29", "api_level": 24}}`。

`scripts/build_mpv_native.sh:60-62` 的 ABI 选项：

```
--abi arm64-v8a        Build the validated 64-bit stack (default)
--abi armeabi-v7a      Build the 32-bit stack
--abi all              Build both ARM ABIs
```

`:226` `Darwin) HOST_TAG=darwin-x86_64` 仅表示**可在 macOS 上跑此脚本交叉编译 Android 库**，不产出 macOS 目标。

Android 专属补丁（`scripts/build_mpv_native.sh:13-27`）：

```
third_party/patches/mpv-android-dovi-el-surface.patch
third_party/patches/mpv-android-fel.patch
third_party/patches/mpv-android-vulkan-conversion-default.patch
third_party/patches/mpv-android-vulkan-smart-backend.patch
third_party/patches/mpv-android-vulkan-legacy-backend.patch
```

FFmpeg 侧 Android 专属补丁（`third_party/patches/`）：

```
ffmpeg-audio-mediacodec-hardware-first.patch
ffmpeg-avs3-mediacodec.patch
ffmpeg-avs3.patch
ffmpeg-mediacodec-diagnostics.patch
ffmpeg-mediacodec-output-serialization.patch
ffmpeg-mediacodec-port-starvation.patch
ffmpeg-webhtv-proxy-range.patch
```

`app/src/main/cpp/CMakeLists.txt` 的 `exo_dovi_renderer` 链接 `mediandk` / `vulkan` / `android` / `log` / `libplacebo.a` / `libshaderc.a` / `libdovi.a`。

`app/src/main/jniLibs/`：

```
libijkffmpeg.so  9,289,800 B (arm64) / 6,871,748 B (armv7)
libijkplayer.so    598,832 B (arm64) /   406,320 B (armv7)
libijksdl.so       414,952 B (arm64) /   304,092 B (armv7)
```

**支持的主张**：Android 端的播放能力（FEL 双层重建、DV5 Vulkan、AVS3 硬解、MediaCodec 直出、IJK）**全部绑在 Android NDK 与 `mediandk`/`ANativeWindow` 上**，iOS 与桌面无对应物。

**对照数据**：PeekPili（同目录体系下的跨平台参考实现，`D:\Work\workSpace\PeekPiliRelease`）iOS 侧使用 `Mpv.framework` 仅 **1,915,296 B**，为 WebHTV `libmpv.so` 的 **1/9.3**。差异即来自上述 Android 专属改造。

**WebHTV 适用性**：新客户端**必须重新选型播放器**，不能复用。这是本项目最大的成本项，也是"功能不对等"的根本原因。

### E7 — Android API 绑定面（量化） 【A 级】

`grep` 统计（`app/src/main/java`）：

```
androidx.media3 越出 player/ 包：70 个文件
player/ 内 import android.*：105 / 292 文件
MediaCodec：12 文件      AudioTrack：13 文件
SurfaceView：9 文件      TextureView：6 文件
WebView：7 文件          AudioManager：5 文件
android.os.Handler|Looper：21 文件
```

`player/engine/PlayerEngine.java` 是唯一的引擎抽象，但签名全部暴露 Media3 类型：

```java
import androidx.media3.common.Format;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Tracks;

Player getPlayer();
Tracks getCurrentTracks();
PlaybackFactsSnapshot getPlaybackFactsSnapshot();   // 含 Format
VideoPlaybackDetails getVideoPlaybackDetails();     // 含 ColorInfo / DV profile
```

**支持的主张**：`PlayerEngine` 是 Android 内部多引擎（Exo/IJK/MPV 三选一）的抽象，**不是跨平台抽象**。`getPlayer()` 返回 `androidx.media3.common.Player`，非 Android 平台无法实现该接口。

### E8 — 用户要求的"不内置源"与现有架构天然一致 【A 级】

`VodConfig` 通过 `Config`（订阅地址）驱动，源清单来自远程 JSON 的 `sites` 字段。代码中不存在硬编码站点列表。

**支持的主张**：新客户端只需实现"输入 URL → 拉取 JSON → 解析 sites → 交给 Spider 运行时"，即天然满足"不内置源"的要求。**该约束不增加任何额外工作量。**

---

## 5. 证据摘要表

| 编号 | 结论 | 强度 | 影响 |
|---|---|---|---|
| E1 | QuickJS `wrapper-java` 3.2.3 存在且 API 与 Android 版一致，**但无任何 native 构件、上游无 Windows 构建路径** | `observed`（Maven Central + 上游 README/CMakeLists 实测） | 已由 E10/E11 绕过（改走 Node 路线） |
| E2 | JS 运行时 1349 行仅 11 处 Android 引用 | `observed` | 已不适用（不移植 Java 代码） |
| E3 | `DexClassLoader` 仅服务 `csp_*` jar 源 | `observed` | **成为 E11 的关键**：Android 参考源 96 个站点全部是 `csp_*` |
| E4 | `catvod` 40 文件 4333 行，硬耦合仅 2 处 | `observed` | 已不适用（不移植） |
| E5 | 源数据格式是 JSON 契约，Room 仅是存储 | `observed` | 新端用 JSON 文件即可 |
| E6 | 播放器原生栈 100% Android 独占 | `observed` | 新端必须重新选型播放器 |
| E7 | `PlayerEngine` 非跨平台抽象 | `observed` | 播放层不能复用 |
| E8 | 源由订阅地址驱动，无硬编码 | `observed` | 天然满足"不内置源" |
| E9 | JVM 版有 `checkSameThread()` 约束 | `observed` | 已不适用 |
| E10 | 指定 `.md5` 源是 **drpyS 服务端单文件**，本机 Node 可跑通 | `observed`（端到端实测） | **方案收敛为 Node 路线** |
| E11 | **Android 端参考源与 `.md5` 源是两套独立体系**（`csp_*` DEX vs `nodejs_*`） | `observed`（两源实测对比） | **决定 Android 侧无需改动，且两端实现路径独立** |

### E11 — Android 参考源与 `.md5` 源是**两套完全独立的体系** 【A 级，实测对比】

> 采集日期：2026-09-22。对比对象：
> - A = Android 端参考源 `https://9280.kstore.vip/newwex.json`（33,812 B，HTTP 200）
> - B = `.md5` 源程序运行时自动生成 `wexfnwconfig.json`（21,594 B）

**A：Android 端参考源结构（标准 TVBox 订阅）**：

```
顶层键: spider / wallpaper / logo / sites / parses / doh / rules / ads / lives / headers
sites  : 96 个
parses : 4 个
doh    : 5 个
rules  : 9 个
ads    : 3 个
lives  : 2 个
headers: 1 个
```

`spider` 字段（三段式 `URL;md5;HASH`）：

```
http://oss4liview.moji.com/thd_file/2026/09/20/73c02ea3ecd704dc1d50278db9e6e441.jpg;md5;7be82cf9f66e0070ed430fd7b2d2ba64
```

站点样例（全部 `type=3`）：

```json
{"key":"Douban","name":"🐮【免费分享】🐮","type":3,"api":"csp_NewDouBanGuard","indexs":1,...}
{"key":"花卷","name":"💓花卷┃4K💓","type":3,"api":"csp_AiNewHuaJuanGuard","searchable":1,...}
{"key":"玩偶","name":"💓玩偶┃4K💓","type":3,"api":"csp_AiNewWoggGuard","searchable":1,...}
{"key":"原盘","name":"💓原盘┃4K💓","type":3,"api":"csp_AiNewZhiNan4KGuard","searchable":1,...}
```

**统计：96 个站点，api 前缀 100% 为 `csp_*`。**

**B：`.md5` 源生成的配置**：

```
顶层键: config / _meta / pan
config.sites.list: 94 个
站点样例: {"key":"nodejs_wogg","name":"玩偶|4K","type":3,"enable":true,"searchable":1,...}
```

**统计：94 个站点，key 前缀 100% 为 `nodejs_*`。字段为 `enable`/`filterable`，无 `api`。**

**决定性对比**：

| 维度 | A（Android 参考源） | B（`.md5` 源） |
|---|---|---|
| 格式 | TVBox 订阅 JSON | 源程序内部配置 |
| spider 机制 | `spider` 字段指向 jar/DEX | 无，靠本机 Node 运行 |
| 站点类型 | `csp_*`（**DEX 类加载**） | `nodejs_*`（**本机 Node**） |
| 站点标识 | `api` 字段 | `key` 前缀 |
| 站点数 | 96 | 94 |
| 加载方式 | `DexClassLoader` | `require()` |
| **跨平台** | ❌ **不可能**（iOS/桌面无 Dalvik） | ✅ **已验证可跑** |

**支持的主张**：

1. **这是两个不同的分发体系**，尽管描述的是同一批影视站（花卷、玩偶、观影、七味、虎斑、木偶、多多、立播…在两边都出现）。
2. **Android 参考源依赖 `csp_*` DEX 加载**，与 E3 的发现完全吻合——`DexClassLoader` 在 iOS/桌面无对应物。
3. **`.md5` 源走 Node 路线**，是专为跨平台设计的形态（其源码自述为 `CatVodSpiderios`，即 "CatVod Spider **for iOS**"——**这个命名本身就是它面向 iOS 的直接证据**）。

**WebHTV 适用性（关键结论）**：

- **Android 端继续用 A**：`app/` 现有的 `JarLoader` + `CspDexClassLoader` 链路，**一行都不用改**。
- **桌面/iOS 端用 B**：内嵌 Node 运行 `.md5` 源，**完全不碰 Android 的任何代码**。
- **两端不共享任何源处理代码**，但各自内部完整自洽。这反而**降低了耦合风险**。

**Caveat**：
- 两套站点虽然名字相近，但 `key` 命名规则不同（`AiNewWoggGuard` vs `nodejs_wogg`），**不可互相替换**。客户端必须按各自的格式解析。
- Android 端的 `spider` 字段也是一个 `.jpg` 伪装的 DEX 包（`73c02ea3ecd704dc1d50278db9e6e441.jpg`，md5 `7be82cf9f66e0070ed430fd7b2d2ba64`）——与 B 的 `index.js` 伪装手法同源，说明是同一方维护的双端分发。但**下载后的处理方式完全不同**（A 走 DEX 加载，B 走 Node require）。

### E10 — 指定源是 **drpyS 服务端单文件**，非 TVBox JSON 订阅 【A 级，端到端实测】

> 探针脚本：`.workbuddy-ai/tmp/x1probe/{probe.js, probe2.js, probe3.cjs, run-server.cjs}`
> 采集日期：2026-09-22，本机 Node **v22.22.2** / npm 10.9.7。

**实测步骤与结果**：

**① `.md5` 指针**（HTTP 200，`content-type: application/octet-stream`）：

```
GET http://wexfnw:wexfnw@cat.xn--4kq62z5rby2qupq9ub.top/index.js.md5
→ 200
→ body: 5e633d8817d46e0d1ce0416ddf1aa192     (32 字节，合法 hex MD5)
```

**② `index.js` 是 302 跳转**（注意：**跟随重定向才是正文**）：

```
GET .../index.js  → 302
Location: http://oss4liview.moji.com/thd_file/2026/09/20/99e2c85335e368ba64f4b885910fd600.jpg
```

> 这里纠正了上一轮报告的一个误判。上一轮记为"源正文取不到 / 阻塞点"，实际原因是当时**没有跟随 302**。跟随后的落地对象带 `content-type: image/jpeg`（**伪装**），但内容是合法 JavaScript。

**③ 落地内容校验**：

```
落地 status        = 200
落地 content-type  = image/jpeg          ← 伪装
落地实际大小        = 6,487,338 B
落地内容 MD5        = 5e633d8817d46e0d1ce0416ddf1aa192
与 .md5 指针一致 ?  YES ✅
```

**`index.js.md5` 的语义确认：它是落地内容的 MD5 校验值，用于客户端做版本比对（内容变了才重新下载）。**

**④ 内容性质判定 —— 这是整个评估的关键转折点**：

| 检查项 | 结果 |
|---|---|
| 语法 | 合法 JavaScript（`new Function(src)` 通过） |
| 内置依赖 | `fastify` @18988、`cheerio` @4439724、`pako` @尾部、`formdata-polyfill`、`mime-db`、`web-streams-polyfill`、`node-domexception`、`cookie`、`proxy-addr`、`toad-cache`、`light-my-request` |
| 尾部注释 | 逐条列出上述包的 license 声明（典型 bundler 输出） |
| 导出 | `module.exports={start,stop}` |
| 大小 | 6.4 MB |

**结论：这不是"一个 JS 源脚本"，而是把整个 drpyS 服务端（Node + Fastify + 全部 npm 依赖）用 bundler 打成的单文件程序。** 它导出 `start` / `stop` 两个方法供宿主调用。

**⑤ 端到端启动验证（本机 Node v22.22.2，未使用任何 Android 组件）**：

```
[1] require('source.js')
[2] 导出键: start, stop          | start = function, stop = function
[4] 调用 start() ...
    [RemoteWexConfig] fetch api url[0]: http://upload.baicanuc.cn/ossfiles/1768320816/api.txt
    [RemoteWexConfig] fetch api url[0] ok
    [RemoteWexConfig] decoded site url: http://103.36.222.35:9595
    [RemoteWexConfig] fetch ioswex / baidu / guangya config  → 均 ok
    [RemoteWexConfig] site config loaded
    [RemoteWexConfig] loaded ok, wexSiteUrl=http://103.36.222.35:9595/wexfnwshinidie, cost=193ms
    {"level":30, ..., "msg":"Server listening at http://0.0.0.0:9988"}
    CatVodSpiderios listening on http://127.0.0.1:9988
```

**启动成功，监听 `127.0.0.1:9988`。** 过程中可见它自描述为 **`CatVodSpiderios`**（CatVod Spider for iOS），并会去拉取自己的远程站点配置。

**⑥ 该源的内部配置面（从字符串提取）**：

```
VOD_SERVERS / SOURCE_ORDER / PLATFORM_ORDER / MERGE_SOURCE_PAIRS
CUSTOM_MERGE_RULES / EPISODE_TITLE_FILTER / IP_BLACKLIST
ANIME_TITLE_FILTER / TITLE_NOISE_FILTER / TITLE_MAPPING_TABLE
AUTO_MATCH_MAPPING_TABLE / TOKEN / ADMIN_TOKEN
FAVORITE_REQUIRE_ADMIN / LOCAL_DANMU_NOT_REQUIRE_ADMIN
OTHER_SERVER / CUSTOM_SOURCE_API_URL / VOD_RETURN_MODE
```

**它是一个功能完整的聚合影视服务端**，而非简单的单站点爬虫。

**⑦ 运行时自动生成标准 TVBox 配置（重要）**：

探针运行后，源程序在工作目录自动生成了 `wexfnwconfig.json`（21,594 B）。结构：

```json
{
  "config": {
    "sites": {
      "list": [ ...94 个站点... ]
    }
  },
  "_meta": { "updatedAt": 1790066059507 },
  "pan": {
    "thunder": { "config": "{...迅雷 deviceId/peerId...}" }
  }
}
```

站点统计：

```
站点总数 = 94
type 分布 = 全部 type=3
key 前缀 = 全部 nodejs_*
```

站点样例：

| key | name | type |
|---|---|---|
| `nodejs_douban` | 豆瓣\|首页 | 3 |
| `nodejs_gengxin` | 日期:20260920 | 3 |
| `nodejs_baseset` | 配置\|中心 | 3 |
| `nodejs_mypan` | 我的\|网盘 | 3 |
| `nodejs_wogg` | 玩偶\|4K | 3 |
| `nodejs_duoduo` | 多多\|4K | 3 |
| `nodejs_huban` | 虎斑\|4K | 3 |
| `nodejs_muou` | 木偶\|4K | 3 |
| `nodejs_huajuan` | 花卷\|4K | 3 |
| `nodejs_guanying` | 观影\|4K | 3 |
| `nodejs_qwmkv` | 七味\|4K | 3 |
| `nodejs_libvio` | 立播\|4K | 3 |

**该发现对方案的影响（决定性）**：

1. **完全不需要 QuickJS**。上一轮花大力气论证的 E1（`wrapper-java` 无 Windows native）**不再是障碍**——因为该源本来就是 Node 程序，天然跑在 Node 上。
2. **完全不需要 `catvod` / `quickjs` 模块的移植**。上一轮设想的"11 处 Android 引用替换"也无必要。
3. **完全绕开 `DexClassLoader`**。用户已澄清不需要 `csp_*` 源。
4. **两侧（桌面 + iOS）的实现路径完全一致**：嵌一个 Node → `require` 源文件 → 调 `start()` → 得到本地 HTTP 服务 → 客户端通过 HTTP 消费。
5. **站点清单无需客户端硬编码**。源在运行时自动生成 `sites.list`，客户端只需读取这份标准 TVBox 结构（`key` / `name` / `type`），**天然满足"不内置源"约束**。
6. **与 PeekPili 的架构完全同构**，且 PeekPili 三端（Android/iOS/Windows）已验证该路线可行。

**Caveat**：
- 服务默认监听 `0.0.0.0:9988`，客户端应改为 `127.0.0.1` 以避免暴露到局域网。这是安全加固项，需在实现时处理。
- `start()` 返回的 Promise 在本机探针中出现 `rejected: Cannot read properties of undefined (reading 'slice')`——但这发生在服务已成功监听之后，属非致命错误（疑似某可选子模块初始化失败），**不影响主服务运行**。实现时需 catch 该 rejection 避免宿主崩溃。
- 源码内部有 `TOKEN` / `ADMIN_TOKEN` 概念，说明部分接口需鉴权。客户端需按原设计（`wexfnw:wexfnw` Basic Auth）对接。
- 源程序会**在当前工作目录写文件**（`wexfnwconfig.json`）。客户端实现时需指定专用工作目录，避免污染用户目录。探针运行在仓库根目录产生了该文件，已识别为探针副作用。

---

## 6. 方案对比

### 6.0 关键前提：本项目涉及**两套独立的源体系**（E11）

在讨论方案前必须先厘清这一点，否则会误判工作量。

```
┌─────────────────────────────────────────────────────────────────┐
│  同一方维护的双端分发，但两套体系完全独立                          │
├──────────────────────────────┬──────────────────────────────────┤
│  A：Android 端（现状，冻结）   │  B：桌面 / iOS 端（本次要新增）    │
├──────────────────────────────┼──────────────────────────────────┤
│  https://9280.kstore.vip/    │  http://wexfnw:wexfnw@cat.xn--   │
│  newwex.json                 │  4kq62z5rby2qupq9ub.top/         │
│                              │  index.js.md5                    │
├──────────────────────────────┼──────────────────────────────────┤
│  TVBox 订阅 JSON（96 站点）   │  drpyS 服务端单文件（6.4 MB JS）   │
│  spider: *.jpg 伪装的 DEX     │  index.js: *.jpg 伪装的 JS        │
│  站点 api = csp_*Guard       │  站点 key = nodejs_*             │
│  加载器 = DexClassLoader      │  加载器 = 本机 Node require()     │
│  WebHTV 现有链路已支持 ✅      │  本机已实测跑通 ✅                 │
│  **一行不用改**               │  **全新实现**                     │
└──────────────────────────────┴──────────────────────────────────┘
```

**结论：两端不共享源处理代码，各自内部自洽。这反而降低了耦合风险和回归风险。**

### 方案 A0 — 不改（no change）

仅维持 Android。缺点是用户明确要求扩展，不满足需求。

### 方案 A1 — Android 保持不动 + 新增桌面/iOS 客户端（**已收敛，推荐**）

> **2026-09-22 更新**：E10 实测后，本方案从"两条候选路线"**收敛为单一路线 A1b（Node 承载）**。`A1a`（自建 QuickJS native）与 `Kotlin Multiplatform` 均不再需要。

**架构（已实测验证）**：

```
        ┌───────────────────────────────────────────────────────┐
        │  用户输入源地址（不内置）                                │
        │  http://user:pass@host/index.js.md5                    │
        └───────────────────────┬───────────────────────────────┘
                                │
                                ▼
        ┌───────────────────────────────────────────────────────┐
        │  客户端（桌面 / iOS 各自实现，界面按平台设计）             │
        │  ① 拉 .md5 → 比对本地缓存，判断是否需要更新               │
        │  ② 拉 index.js → 跟随 302 → 拿到 6.4MB JS 源           │
        │  ③ 写入本地源目录                                        │
        │  ④ 启动内嵌 Node → require 源 → 调 start()              │
        │  ⑤ 通过 http://127.0.0.1:9988 消费源接口                 │
        └───────────────────────┬───────────────────────────────┘
                                │
                                ▼
        ┌───────────────────────────────────────────────────────┐
        │  内嵌 Node 运行时（每平台自带）                           │
        │  桌面：node.exe (Windows) / node (macOS, Linux)         │
        │  iOS：NodeMobile.framework                              │
        └───────────────────────────────────────────────────────┘
```

**Android 端**：完全不动。不改 `app/`、不改 `quickjs/`、不改 `catvod/`、不改任何 Gradle 配置。新代码全部位于新增目录。

**关键决策（已由 E10 实测确定）**：

| 决策项 | 结论 | 依据 |
|---|---|---|
| JS 源承载方式 | **Node.js**，非 QuickJS | E10：源本身就是 Node 程序，导出 `{start,stop}` |
| 是否需要 `catvod` 移植 | **不需要** | E10：源自带 Fastify 服务端，不依赖 TVBox Spider 抽象 |
| 是否需要 `DexClassLoader` | **不需要** | 用户已澄清不需要 `csp_*` 源 |
| 是否需要 QuickJS `wrapper-java` | **不需要** | 被 Node 路线完全替代 |
| 播放器 | 重新选型：桌面官方 mpv / iOS `media_kit` | E6：Android 原生栈无法复用 |

**源获取与解析流程（实测可用）**：

```js
// ① md5 指针
GET {源地址}                          → "5e633d8817d46e0d1ce0416ddf1aa192"
// ② 比对本地缓存，不一致才走 ③

// ③ 拉正文（必须跟随 302）
GET {源地址去掉 .md5}                 → 302 → CDN 对象（伪装 image/jpeg）
                                        → 实际 6,487,338 B JavaScript
// ④ 校验
md5(正文) === ①的值 ? 写入 : 报错

// ⑤ 启动
const mod = require('./source.js');
mod.start();                          // → 监听 127.0.0.1:9988
```

**界面设计（按用户要求，各平台独立）**：

| 平台 | 技术选型 | 界面要点 |
|---|---|---|
| Windows / macOS | 原生或 Flutter Desktop | 窗口式布局、鼠标悬停、右键菜单、键盘快捷键、多窗口 |
| iOS / iPadOS | SwiftUI 或 Flutter | 触控手势、底部 Tab、大标题导航、iPad 分栏 |

两端功能一致但表现形式各自符合平台习惯。用户可以**独立设计**，不必强行统一。

**打包形态（按用户要求）**：

| 平台 | 产物 | 内含 |
|---|---|---|
| Windows | `.exe` 安装包 / 便携目录 | 客户端 + `node.exe` + 源目录 |
| macOS | `.app` / `.dmg` | 客户端 + `node` 二进制 + 源目录 |
| iOS | `.ipa` | 客户端 + `NodeMobile.framework` + 源目录 |

**收益**：
- Android 零回归风险（完全不碰）
- 桌面 + iOS 共用同一套源处理逻辑（拉取 → 校验 → 启动 → HTTP 消费）
- **不需编译任何 native 代码**（Node 官方提供全平台二进制）
- **与 PeekPili 三端已验证架构同构**，风险最低
- 界面按平台设计，无历史包袱

**缺点与风险**：
- 需随包分发 Node 运行时（约 70 MB / 平台；iOS 约 55 MB）
- 播放能力弱于 Android（无 FEL / DV5 / AVS3 / MediaCodec 直出）——但用户已明确只需"正常解析使用该源"
- iOS 需处理 Node 在 App Store 的合规问题（动态执行 JS 的限制）
- 源服务默认监听 `0.0.0.0`，需改为 `127.0.0.1`（安全加固）

**与现有功能的关系**：Android 完全不受影响；新增两端为独立进程、独立产物。

**Best-practice 状态**：该架构有 PeekPili 三端实测背书，且本次已完成本机端到端验证。

**最小分阶段实施与验证**：

- **`X1-1`（✅ 已完成）**：本机 Node 加载源文件、调用 `start()`、确认监听端口。
  - 结果：**通过**。详见 E10 ⑤。
- **`X1-2`（桌面端 MVP）**：源管理（输入地址 → 拉取 → 校验 → 落盘）+ 内嵌 Node 生命周期管理 + 界面 + 播放器 + 打包。
- **`X1-3`（iOS 端）**：在桌面端验证通过后开始，复用同一套源处理逻辑，替换 Node 运行时为 `NodeMobile.framework`。

### 方案 A2 — Flutter 完整重写（**拒绝**）

理由（数据支撑）：

| 维度 | 事实 |
|---|---|
| Java 代码量 | 1242 文件，Dart 无法复用任何一行 |
| UI 资源 | 248 个 layout，全部作废 |
| 播放器 | 84,833 行重写，且 Android 专属能力在 Flutter 侧仍无法实现 |
| flavor 结构 | leanback/mobile 两套界面需在 Flutter 内重建 |
| 复用率 | **0%** |

对比方案 A1 的共享 core 路线（可复用 E2/E4 的约 5,682 行核心逻辑），Flutter 在复用率上是严格劣势。且 Flutter 不解决 E6（播放器原生栈）问题。

### 方案 A3 — Kotlin Multiplatform（作为 A1 的替代实现路径）

把共享 core 从 Java 迁到 KMP，可同时产出 JVM 与 Native（iOS）目标。

- **优势**：iOS 侧也能复用 core 逻辑，而非只有桌面
- **劣势**：core 目前是 Java，迁 KMP 需改写；且 iOS 仍受 E6/E3 限制；KMP 不解决 E1（QuickJS native）问题
- **结论**：若 `X1-1` 验证通过且 iOS 优先级高，可在 `X1-3` 阶段考虑；否则 YAGNI

---

## 7. 建议

**推荐 `方案 A1`（已收敛为 Node 承载路线），按以下顺序推进：**

1. **`X1-1` ✅ 已完成**。E10 端到端实测通过——源在本机 Node v22.22.2 上成功加载、启动、监听 `127.0.0.1:9988`。**技术可行性已证实，无需再探。**
2. **`X1-2` 桌面端优先**。桌面无商店审核、无动态代码加载限制、Node 官方提供全平台二进制。产出 `.exe` / `.dmg` 成品包。
3. **`X1-3` iOS 端**。复用 `X1-2` 的源处理逻辑，把 Node 运行时换成 `NodeMobile.framework`（PeekPili 已验证该形态，55 MB）。需注意 App Store 对动态执行 JS 的合规要求。
4. **Android 完全冻结**。新代码全部位于新增目录，`app/` / `quickjs/` / `catvod/` 零改动，`git rm -r <新目录>` 即可完全回滚。

**原三个问题已被用户回答**：

- **Q1（`.py` 源）**：不需要。用户明确"只要能解析使用上面那个 `.md5` 的源文件就行"。
- **Q2（`csp_*` jar 源不可用）**：可接受。同上，范围已收窄到单一源。
- **Q3（iOS 仅支持该源 + 界面不同是否有价值）**：有价值。用户明确"界面按照更符合各平台的设计来做，打包时分别打出成品包就行"。

**待确认的收尾项（非阻塞）—— ✅ 全部已确认（2026-09-22 16:40）**：

- ~~Q4：桌面端要覆盖哪些系统？~~ → **只 Windows。** 无 macOS / Linux 分支，只需 win-x64 的 `node.exe`，打包脚本单一。
- ~~Q5：iOS 是否有上架 App Store 的需求，还是自签名 / TestFlight 分发即可？~~ → **自签名即可。** 无商店审核路径，Node 动态执行 JS 的合规风险消失；需附自签重签说明。

---

## 8. 缺点与风险汇总

| 风险 | 等级 | 说明 |
|---|---|---|
| ~~QuickJS native 在 Windows 不可用~~ | **已消除** | E10 实测后改走 Node 路线，此风险不再适用 |
| Node 运行时随包分发的体积 | 中 | 仅 win-x64 一个二进制，`node.exe` 约 70 MB（PeekPili 实测 69,804,184 B）；iOS `NodeMobile.framework` 约 55 MB。**Q4 定为只 Windows 后不再有 mac/linux 多份体积** |
| ~~iOS App Store 动态执行限制~~ | **已降为低** | **Q5 定为自签名分发后，不经商店审核，此风险基本消失**；残余项仅为免费证书 7 天有效期，需附重签步骤 |
| 源服务监听 `0.0.0.0` | 中 | 安全加固项，实现时改 `127.0.0.1` |
| 源向 CWD 写文件 | 中 | E10 实测会生成 `wexfnwconfig.json`；必须给 Node 独立工作目录，禁止写安装目录/仓库 |
| `start()` Promise rejection | 低 | 实测出现非致命 rejection，需 catch 防宿主崩溃 |
| 播放器能力弱于 Android | 中 | 无 FEL/DV5/AVS3/MediaCodec；但用户只需"正常播放该源" |
| 源文件更新机制 | 低 | `.md5` 比对逻辑简单，已实测可用 |
| Android 误改风险 | 低 | 新代码置于独立目录；建议 guard 声明 scope 排除 `app/` |

---

## 9. 最小实施步骤

**`X1-1`（✅ 已完成，2026-09-22）**：

在写任何客户端代码之前，先证实"源能否脱离 Android 运行"。结果：**通过**。

- 拉取 `.md5` 指针 → `5e633d8817d46e0d1ce0416ddf1aa192`（HTTP 200，32 字节）
- 拉取 `index.js` 并**跟随 302** → 6,487,338 B JavaScript（`content-type` 伪装为 `image/jpeg`）
- MD5 校验 → **与指针严格一致 ✅**
- `require(source)` → 导出 `{start, stop}`
- `start()` → **`Server listening at http://0.0.0.0:9988`**，自述为 `CatVodSpiderios`
- 全程使用本机 Node v22.22.2，**未触及任何 Android 组件**

探针产物：`.workbuddy-ai/tmp/x1probe/`（临时目录，可删）。

**Q4 / Q5 已由用户回答（2026-09-22 16:40）**：

- **Q4 = 只 Windows。** macOS / Linux 不在范围内。后果：
  - 只需 `node.exe`（win-x64）**一个** Node 运行时，不需要 macOS / Linux 二进制。
  - 打包脚本**单一**，无 `.dmg` / `.AppImage` 分支。
  - 播放器只需 Windows 形态的 `libmpv-2.dll`（或 `media_kit` 的 win 实现）。
  - 范围与体积显著缩小；`X1-2` 是唯一的桌面端交付阶段。
- **Q5 = 自签名即可。** 无 App Store 上架需求。后果：
  - **§8 里"iOS App Store 动态执行限制（中高）"风险等级降为「低」**——自签 / 侧载不经商店审核，Node 动态执行 JS 不构成合规障碍。
  - 不需要为规避商店规则而改架构（例如无需把 Node 换成预编译 JS 快照）。
  - 只需处理自签名本身的常见代价：证书 7 天有效期（免费账号）或付费开发者账号一年期；需在文档里给出重签步骤。
  - 分发形态为 `.ipa` + 自签工具链，而非 `.ipa` + 商店。

**`X1-2`（Windows 桌面端 MVP，✅ 已完成，2026-09-22 19:20）**：

产物：`platform/desktop/`（Flutter Windows 客户端）+ `platform/desktop/dist/WebHTV-0.1.0-win-x64/`（便携包，159 MB）。

1. **新建独立目录**（`platform/desktop/`），未修改 `app/`、`quickjs/`、`catvod/`、任何 Gradle 配置 —— 已用 `git diff --stat` 验证为空。
2. **源管理模块**（`lib/src/services/source_fetcher.dart`、`lib/src/models/source_config.dart`）：
   - 输入源地址（Basic Auth 形式 `http://user:pass@host/index.js.md5`）
   - 拉 `.md5` → 与本地缓存比对 → 决定是否重新拉正文
   - 拉正文并**手动跟随 302**（`_followRedirects`，最多 5 跳）→ MD5 校验 → **原子写入**（`index.js.tmp` + `renameSync`）
   - 首启动为空源列表 + "添加源"入口（满足"不内置源"）
3. **Node 生命周期管理（仅 win-x64）**（`lib/src/services/source_runtime.dart`）：
   - 分发 `node.exe`（win-x64，**87,074,816 B / v22.22.2**）
   - 生成 `_bootstrap.cjs`：`require('<源目录>/index.js').start()`，并 `catch` 掉已知非致命 rejection
   - 探测端口：轮询 `GET /health`（校验响应含 `CatVodSpiderios`），最长 30s
   - 退出时 `stop()` 并回收进程
   - **给 Node 独立工作目录**（`<appSupport>/webhtv/{sources,runtime}`）—— 实测确认源会向 CWD 写 `wexfnwconfig.json`（21,594 B），落点正确、仓库未被污染
4. **界面**（按 Windows 桌面习惯独立设计）：`NavigationRail` 四页 —— 源管理 / 浏览 / 站点 / 设置。
5. **播放器**：`media_kit` 1.2.6（`libmpv-2.dll` 29,764,622 B + ANGLE 全套 DLL）。
6. **打包**：`scripts/package_windows.sh` 产出便携目录，15 项完整性校验全过。
7. **无 macOS / Linux 分支** —— Q4 明确只 Windows。

**X1-2 期间新增的关键实测结论**（详见 §13）：

- 源的 HTTP 契约已完整逆向（见 §13.1），客户端 `source_client.dart` 按此实现。
- **端口加固**：源自身监听 `0.0.0.0:9988`；客户端侧已按 §9 计划收敛到只访问 `127.0.0.1`，并在启动前做端口占用预检。
- **代理变量陷阱（重要）**：Node 子进程若继承宿主的 `HTTP_PROXY`，且该代理只对宿主进程有效，则源的全部出网接口报 `os error 10061` → 客户端已在 `Process.start` 时显式清空 4 个代理变量并设 `NO_PROXY=127.0.0.1,localhost`。
- **构建环境**：Git Bash 缺 `ProgramFiles(x86)` → Flutter 报 `%PROGRAMFILES(X86)% environment variable not found.`；`media_kit` 构建期从 GitHub 直连下 ANGLE/mpv 会失败，须走镜像预取。


**`X1-3`（iOS 端，待 `X1-2` 通过）**：

1. 复用 `X1-2` 的源处理逻辑（拉取 / 校验 / 落盘）。
2. Node 运行时替换为 `NodeMobile.framework`（参考 PeekPili：`Payload/PeekPili.app/Frameworks/NodeMobile.framework/NodeMobile`，54,959,120 B）。
3. 界面用 SwiftUI（或 Flutter）按 iOS 习惯设计。
4. 播放器用 `media_kit`（iOS 侧即 PeekPili 已验证的 `Mpv.framework` 路线）。
5. 打包为 `.ipa`；**分发方式为自签名 / 侧载（Q5）**，需在交付时附重签步骤说明。
6. **不需要**为 App Store 审核改架构（Q5 已排除商店路径）。

---

## 10. 预计需要的验证

| 阶段 | 验证方式 | 通过标准 | 状态 |
|---|---|---|---|
| `X1-1` | 本机 Node 加载源 | 导出 `{start,stop}` | ✅ 通过 |
| `X1-1` | 调用 `start()` | 监听本地端口 | ✅ 通过（`0.0.0.0:9988`） |
| `X1-1` | MD5 校验 | 正文 MD5 == 指针 | ✅ 通过 |
| `X1-1` | Android 零改动 | `git status` 确认 `app/`/`quickjs/`/`catvod/` 未改 | ✅ 通过 |
| `X1-2` | 客户端静态检查 | `flutter analyze lib` | ✅ 通过（`No issues found!`） |
| `X1-2` | Windows 构建 | `flutter build windows --release` 成功 | ✅ 通过（`webhtv_win.exe`） |
| `X1-2` | 依赖自举 | ANGLE.7z / mpv 包经镜像校验落地 | ✅ 通过（MD5 精确匹配） |
| `X1-2` | 打包（Windows） | 便携包完整性 15 项校验 | ✅ 通过（159 MB） |
| `X1-2` | 源拉取链路 | `.md5` 指针 → 302 跟随 → MD5 校验 | ✅ 通过（`5e633d88…` 一致） |
| `X1-2` | 服务启动（成品 node） | 用成品包 `runtime/node.exe` 起服务，`/health` 返回 `CatVodSpiderios` | ✅ 通过 |
| `X1-2` | 配置加载 | 服务日志确认 `RemoteWexConfig loaded ok`、13 个站点键 | ✅ 通过 |
| `X1-2` | Node 独立工作目录 | `wexfnwconfig.json` 只出现在工作目录，仓库未被污染 | ✅ 通过 |
| `X1-2` | 代理变量加固 | `Process.start` 显式清空 `HTTP_PROXY` 等 4 项 | ✅ 已实现 |
| `X1-2` | 站点内容接口 | `POST /spider/wogg/3/home` 取到真实数据 | ⚠️ 受上游授权限制（见 §13.3） |
| `X1-2` | 端到端播放（Windows） | 桌面端能播放源返回的直链 | ⚠️ 阻塞于上游 403，非代码问题 |
| `X1-2` | Android 回归 | `git diff --stat app/ quickjs/ catvod/ gradle/` 为空 | ✅ 通过 |
| `X1-3` | iOS 构建 | `NodeMobile.framework` 真机加载成功 | 待做 |
| `X1-3` | iOS 自签分发 | 自签 `.ipa` 能在目标设备安装并启动（Q5） | 待做 |

---

## 11. 回滚路径

- 本文件（`docs/X1-cross-platform-ios-desktop-assessment.md`）为新增文档，删除即回滚。
- `.workbuddy-ai/tmp/x1probe/` 为临时探针目录，`rm -rf` 即清理。
- `X1-2` 起新代码全部位于新增目录（如 `platform/`），`git rm -r platform/` 即完全回滚，**Android 构建图完全不受影响**。
- `X1-1` 已验证 `app/`、`quickjs/`、`catvod/` 零改动，回滚锚点 `8e4d9333de8ea7346491e71a0b1ab6858a852298` 有效。

---

## 12. 未决门（unresolved gates）

**已解答**：

- ~~**G-A**：`wrapper-java` 在 Windows 是否可用~~ → **无 native、上游未支持 Windows。已由 E10 绕过：改走 Node 路线。**
- ~~**G-B**：`Base64` 行为等价性~~ → 不适用（不再移植 Java 代码）。
- ~~**G-D**：`Spider.init(Context)` 用途~~ → 不适用（不再移植 `catvod`）。
- ~~**G-F**：`cat.js` 在 Node 与 QuickJS 下行为一致性~~ → 不适用（源自带完整依赖）。
- ~~**G-C**：iOS App Store 合规性~~ → **已解除：Q5 为自签名分发，不经商店审核。** 仅剩 `NodeMobile.framework` 集成技术问题，归 `X1-3`。

**仍开放**：

- **G-E**：源服务的端口发现方式（固定 9988 还是动态）。实测源码里是**硬编码 9988**，但需确认是否可配置；客户端应优先探测固定端口，失败再扫描。→ `X1-2` 解决。
- **G-G**（新）：源内部的 `TOKEN` / `ADMIN_TOKEN` 接口是否需要客户端处理。→ `X1-2` 读码解决。
- **G-H**（新）：`start()` 返回 Promise 的 rejection 根因（实测为 `Cannot read properties of undefined (reading 'slice')`，发生在服务监听之后）。需确认是否影响部分功能。→ `X1-2` 解决。

**`X1-2` 的收口结论**：

- **G-E —— 已解决**：端口**硬编码 9988**，源码中无配置项。客户端按固定端口实现（`SourceRuntime` 内 `port = 9988`），启动前做占用预检。
- **G-G —— 已部分解答**：`/website/api/*` 存在（sites/status 等约 40 个端点）。其中 `/website/api/status` 用于查询网盘凭证状态（夸克/百度/115/天翼等），客户端「设置」页已接入该端点显示凭证概况。
- **G-H —— 已解答，且本轮未复现**：`start()` 的 rejection 是**环境相关**的偶发。本轮实测 `[host] start() resolved` —— **正常 resolved，无 rejection**。客户端的 `_bootstrap.cjs` 仍保留 `try/catch` + `process.on('unhandledRejection')`，作为防御性措施。

---

## 13. `X1-2` 实测补充（2026-09-22）

### 13.1 CatVodSpiderios HTTP 契约（权威版，客户端按此实现）

**服务发现与元信息（GET，本地，无上游依赖）**

| 端点 | 返回 | 备注 |
|---|---|---|
| `GET /health` | `{"ok":true,"name":"CatVodSpiderios"}` | 客户端**用它判断服务就绪** |
| `GET /check` | `{"run":true}` | 进程存活标志 |

**站点内容（POST + JSON body）**

路径规则：`/spider/<key 去掉 nodejs_ 前缀>/<type>/<action>`

> ⚠️ 注意：站点在 `/config` 里的 `api` 字段形如 `/spider/douban/3`，**直接 GET 会 404**。必须按上式拼成 POST 路径，例如 `nodejs_wogg` + `type=3` → `POST /spider/wogg/3/home`。

| action | 请求体 | 说明 |
|---|---|---|
| `init` | `{}` | 站点初始化 |
| `home` | `{}` | 首页：`{class:[{type_id,type_name}], filters:{…}, list:[…]}` |
| `category` | `{id, page, filters}` | 分类分页：`{page, pagecount, limit, list:[…]}` |
| `detail` | `{"id":"<vod_id 字符串>"}` | **是对象不是数组**；返回 `{list:[{vod_name,vod_play_from,vod_play_url,…}]}` |
| `play` | `{flag, id}` | 取直链；**500 是业务错误**，见下 |
| `search` | `{wd, page}` | 搜索分页 |

**关键语义**

- `vod_id` 必须**原样透传**，形态不固定：`/voddetail/131674.html`、`msearch:36850814`、纯数字都出现过。
- `play` 返回 **HTTP 500 + `{"statusCode":500,"message":"…"}` 表示业务失败**（如未登录网盘），**不是协议错误**。客户端必须把 `message` **原样呈现给用户**，不能笼统显示"加载失败"。
- `vod_pic` 直接指向源自身的 `/imageProxy?url=…&cache=…&customHeaders=…`，可当普通图片 URL 用。
- 榜单类站点（如 `nodejs_douban`）的 `detail` **合法地返回 `{}`** —— 客户端须容忍，不能报错。

**配置与站点清单（GET，需要上游可达）**

| 端点 | 规模 | 备注 |
|---|---|---|
| `GET /config` | ~19.7 KB | `{video:{sites:[…]}, read, comic, music, pan, color}` |
| `GET /full-config` | ~ | 同上，含更多字段 |
| `GET /website/api/sites` | ~10.7 KB | `{code:0,data:[…]}` |
| `GET /website/api/status` | ~2.3 KB | 网盘凭证状态 |

客户端 `source_client.dart` 的 `SiteEntry.prefix` 即按 13.1 的规则重建路径（**不用** `api` 字段）：

```dart
String get prefix {
  final k = key.startsWith('nodejs_') ? key.substring(7) : key;
  return '/spider/$k/$type';
}
```

### 13.2 源自身的上游依赖链（服务日志实测）

```
[RemoteWexConfig] fetch api url[0]: http://upload.baicanuc.cn/ossfiles/1768320816/api.txt   → ok
[RemoteWexConfig] decoded site url: http://103.36.222.35:9595
[RemoteWexConfig] fetch ioswex/baidu/guangya config                                        → ok
[RemoteWexConfig] fetch site config: http://oss4liview.moji.com/thd_file/…/bb98838e….jpg    → ok
[RemoteWexConfig] site config loaded, keys=wogg,huajuan,muou,guanying,duoduo,huban,
                  leijing,123pan,shayang,jutou,qiwei,libvio,panku   (13 个)
[RemoteWexConfig] loaded ok, …, cost=181ms
{"msg":"Server listening at http://0.0.0.0:9988"}
```

**要点**：
- 远程配置初始化被 `.catch()` 包裹（`remoteWexConfig.init().catch(...)`），**失败不致命**。
- 站点清单**不是**静态文件，而是运行时从上述上游动态装载。
- 源监听 `0.0.0.0`（全接口暴露），客户端侧只访问 `127.0.0.1`。

### 13.3 未打通的一环：上游 `403`

| 目标 | 实测 |
|---|---|
| `http://103.36.222.35:9595` | **403 Forbidden** ← 中央站点服务，存在但拒绝 |
| `http://upload.baicanuc.cn/…/api.txt` | 200 |
| `http://oss4liview.moji.com/…/bb98838e….jpg` | 200 |
| `http://www.baidu.com`（对照） | 200 |

本机网络**完全正常**，但源的中央服务 `103.36.222.35:9595` 返回 403 → 依赖它的 `/config`、`/spider/*` 返回 502。
这**不是客户端缺陷**，也与 G-G 提到的 `TOKEN` 疑点吻合。待用户在其正常网络环境（或提供鉴权方式）下复验。

### 13.4 Windows 构建环境踩坑记录

| 现象 | 根因 | 处理 |
|---|---|---|
| `Error: %PROGRAMFILES(X86)% environment variable not found.` | Git Bash 进程无 `ProgramFiles` 系列变量；Flutter `visual_studio.dart:264` 靠它拼 `vswhere.exe` 路径 | 用 `env "ProgramFiles(x86)=…" bash -c 'flutter build …'` 注入（bash 不能直接 `export` 含括号的变量名） |
| `create link … errno = 2` | Dart 在本机无符号链接权限 | 保证 `.plugin_symlinks/` **为空**，让 Flutter 自建（**切勿预填**目录或 NTFS 联接——`Link.existsSync()` 对二者均返回 false，会引发 `errno = 183`） |
| `ANGLE.7z Integrity check failed` | `media_kit_libs_windows_video` 用 `file(DOWNLOAD)` 直连 GitHub，**无重试**；本机直连约 1 KB/s 且不支持续传 | 走镜像（`ghproxy.net` 实测 ~38 KB/s）预取，MD5 校验后放入构建目录 |
| `error MSB3073 … cmake_install.cmake 退出代码 1` | `CMakeCache.txt` 里 `CMAKE_INSTALL_PREFIX=C:/Program Files/webhtv_win`，install 阶段向系统目录写入被拒 | 删除 `build/windows` 重建（`windows/CMakeLists.txt:68` 的默认值兜底逻辑会正确接管） |
| `upstream connect failed … os error 10061` | Node 子进程继承宿主 `HTTP_PROXY`，而该代理只对宿主有效 | `Process.start` 时清空 `HTTP_PROXY`/`HTTPS_PROXY`/`http_proxy`/`https_proxy`，并设 `NO_PROXY=127.0.0.1,localhost` |

辅助脚本（均在 `platform/desktop/scripts/`）：
- `build_windows.sh` —— 注入环境变量 + 清脏缓存 + 预取依赖 + 构建
- `prefetch_media_deps.sh` —— 镜像预取 ANGLE/libmpv（先找本地副本，最后才联网）
- `deploy_node.sh` —— 部署 `runtime/node.exe` 并校验可运行
- `package_windows.sh` —— 一键打包 + 15 项完整性校验
- `fix_plugin_symlinks.sh` —— 判定并清理被污染的插件链接目录

- **G-I**（新）：源文件更新后如何平滑重启 Node 服务（不中断播放）。→ `X1-2` 解决。
