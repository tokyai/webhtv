# 统一 CI 打包（一次触发，全平台产出）

> 状态：**已实施**。任务族 `X1-unified-ci`。
> 创建：2026-09-22。

---

## 1. 一句话说明

在 GitHub Actions 里**手动触发一个 workflow**，它会并行构建
**Android 手机端 + Android TV 端 + Windows 便携包 + iOS 未签名包**，
最后汇总成**一个** GitHub Release。

```
GitHub → Actions → "Release All Platforms" → Run workflow → Run
```

所有参数都可以留空。

---

## 2. 怎么用

### 2.1 打全部平台（默认）

`Actions → Release All Platforms → Run workflow`，`platforms` 保持 `all`。

产出（一个 Release 里全部齐备）：

| 平台 | 文件 | 说明 |
|---|---|---|
| Android | `*mobile*arm64-v8a*.apk` | 手机端 64 位 |
| Android | `*mobile*armeabi-v7a*.apk` | 手机端 32 位 |
| Android | `*leanback*arm64-v8a*.apk` | TV 端 64 位 |
| Android | `*leanback*armeabi-v7a*.apk` | TV 端 32 位 |
| Android | `<同上 4 个>.json` | 每个 APK 的更新清单（含 sha256） |
| Windows | `WebHTV-<ver>-win-x64.zip` | 便携包，解压即用 |
| Windows | `WebHTV-<ver>-win-x64.tar.gz` | 同上，保留 Unix 可执行位 |
| iOS | `WebHTV-<ver>-ios-unsigned.ipa` | **未签名**，需自行重签 |

### 2.2 只打部分平台

`platforms` 下拉里可选 `android` / `windows` / `ios` 或两两组合。

### 2.3 只验证某一个平台的构建（不发布）

直接跑对应的 `Build XXX (reusable)` workflow。它只构建，产物在
该次运行的 Artifacts 里，**不会**创建 Release。

### 2.4 参数说明

| 参数 | 留空时 | 说明 |
|---|---|---|
| `platforms` | `all` | 要构建哪些平台 |
| `release_tag` | `v<Android versionName>-yyyyMMddHHmm` | 留空则用当前时间生成 |
| `release_channel` | `auto`（`fongmi-sync` 分支 → beta） | 决定 tag 是否带 `-beta`、是否 pre-release |
| `release_notes` | 自动生成一段说明 | 换行写 `\n` |
| `prerelease` | `false`（beta 通道自动 `true`） | 标记为预发布 |
| `sync_cnb` | `false` | 同步产物到 CNB Release |
| `publish_oci` | `true` | 把 APK 发布为 OCI 制品（需配置变量与密钥） |

---

## 3. 结构

```
.github/workflows/
├── release-all.yml        ← 【统一入口】手动触发这里
├── build-android.yml      ← 可复用单元：4 个 APK + 更新清单
├── build-windows.yml      ← 可复用单元：便携包 zip/tar.gz
├── build-ios.yml          ← 可复用单元：未签名 ipa
└── cnb-release-sync.yml   ← 独立工具：把已有 Release 补同步到 CNB
```

执行流程：

```
prepare (ubuntu)              解析版本号 / tag / 通道 / 要构建哪些平台
   │
   ├── android (ubuntu)  ┐
   ├── windows (win)     ├─ 三平台**并行**，各跑各的 runner
   └── ios     (macos-14)┘
   │
publish (ubuntu)              下载全部 artifact → 建 Release → OCI → CNB 同步
```

### 3.1 为什么拆成「构建单元 + 统一发布」

**构建单元只上传 artifact，不各自建 Release。** 否则一次触发会打出 3 个
割裂的 Release，用户还得自己四处找齐同一批产物。发布统一由 `publish`
job 完成，保证「一次触发 = 一个 Release = 全部平台」。

### 3.2 为什么三个构建并行

三个平台需要的 runner 完全不同（ubuntu / windows / macos），没有依赖关系，
并行能把总时长压到「最慢的那个平台」而不是「三者之和」。

---

## 4. 关键实现细节

### 4.1 tag 由 Android 版本号派生

沿用既有约定 —— 历史 Release 的 tag 都是 `v<Android versionName>-<时间戳>`。
桌面端与 iOS 的版本号（`pubspec.yaml` 的 `0.1.0+1`）**只用于产物文件名**，
不进 tag。

理由：客户端更新检查（`*.json` 清单）依赖 tag 与 Android 版本号对齐，
改掉会破坏已有的更新链路。

### 4.2 Windows：为什么走 CI 要额外处理

`platform/desktop/scripts/*.sh` 是**为本地开发机（PortableGit）写的**，
里面的补丁在 `windows-latest` runner 上大多是无害的幂等操作，因此**刻意
复用同一条路径** —— 避免「本地能出包、CI 出不了」的分叉。

逐个说明：

| 脚本 | 本地需要它的原因 | 在 runner 上 |
|---|---|---|
| `fix_plugin_symlinks.sh` | 本机没有创建符号链接的权限 | 空操作（目录本就干净） |
| `prefetch_media_deps.sh` | GitHub 直连约 1 KB/s 且会截断 | 真的会去下，但脚本失败不中断，CMake 自身有兜底 |
| 环境变量注入（`ProgramFiles` 等） | PortableGit 环境里一个都没有 | 变量本就有，注入只是覆盖成同值 |

**唯一的真问题**是 `deploy_node.sh` 需要 `assets/runtime/node.exe`，
而该文件被 `.gitignore` 忽略（87 MB 不适合入库）。

解法：workflow 里**从官方源下载指定版本的 Node**，并校验版本号与本地一致：

```yaml
NODE_VERSION: "22.22.2"
URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-win-x64.zip"
# 下载后 ./assets/runtime/node.exe --version 必须等于 v22.22.2
```

**为什么不从 runner PATH 取**：runner 预装的 Node 版本会随镜像更新而变，
打进包里的运行时版本就不可复现了。源服务（drpyS）对 Node 版本有实际要求，
因此锁死版本。

### 4.3 Windows：zip 为什么用 Python 而不是 `Compress-Archive`

包内有 `使用说明.txt`（中文名）。PowerShell 的 `Compress-Archive`
按 ANSI 代码页写 zip 条目名，Windows PowerShell 5.1 下**必然乱码**，
pwsh 7 也不保证。

改用 Python 的 `zipfile` —— 它会显式写 **UTF-8 标志位**（general purpose
bit 11），在 Windows 资源管理器与各大解压工具里都能正确还原。

CI 里还带**打包后自检**：读回 zip、跑 `testzip()`、断言能找到
`使用说明.txt`，并确认 `WebHTV.exe` / `runtime/node.exe` / `data/app.so`
/ `libmpv-2.dll` 都在。

**本地实测**（用真实的 161 MB 产物跑过一次）：

```
zip 完成: WebHTV-0.1.0-win-x64.zip (63.5 MB)
tar.gz 完成: WebHTV-0.1.0-win-x64.tar.gz (63.3 MB)
zip 条目数: 30，中文文件名可正确读取
  OK  WebHTV.exe
  OK  runtime/node.exe
  OK  data/app.so
  OK  libmpv-2.dll
```

### 4.4 iOS：三道前置检查

iOS 构建失败往往要到很久之后（链接阶段甚至运行期）才暴露，很难排查。
因此把检查提前：

1. **vendored pod 文件齐全性**（最前面，几秒出结论）
   `NodeWrapper.c`、`NodeMobile.framework/NodeMobile` 等 7 个文件逐个确认，
   并打印大小。
2. **NodeMobile 架构** —— `lipo -archs` 必须含 `arm64`。
3. **`Podfile.lock` 里有 `flutter_node`** —— 确认 vendored pod 真的挂上了。

打包后再验：`Runner.app/Frameworks/NodeMobile.framework` 必须存在
（缺了源服务起不来，直接失败）；`Info.plist` 的 ATS / 方向 / 后台音频
三项缺失只告警不阻断。

### 4.5 部分平台失败时的行为

`publish` job 用 `if: always() && needs.prepare.result == 'success'`。

含义：**某个平台构建失败不会拖垮其它平台已构建好的产物**。
若 Windows 挂了，Android 与 iOS 照样发布；失败的平台会在 job summary
里标注 `::warning`，并在 Step Summary 表格里显示其结果。

但有个硬门槛：**一个可交付产物都没有时直接失败**，不会建空的 Release。
另外若 Android 参与了构建，**APK 数与清单数必须相等**（每个 APK 一份
`*.json`），不齐则中止 —— 这能拦住「APK 打出来了但清单生成失败」
这种半成品发布。

### 4.6 OCI 描述符回填

OCI 发布成功后，`Merge OCI descriptors into manifests` 步骤会把
OCI 描述符写回对应的 `*.json` 更新清单（供客户端做 OCI 拉取）。

回填时会**校验描述符的 size 与本地 APK 一致**，不一致直接失败 ——
防止清单指向一个错误的制品。

---

## 5. 与旧 workflow 的关系

| 旧文件 | 处理 | 原因 |
|---|---|---|
| `android-release.yml` | **已删除** | 逻辑完整迁入 `build-android.yml`（构建）+ `release-all.yml`（发布）。保留会造成同一逻辑两份维护 |
| `ios-release.yml` | **已删除** | 由 `build-ios.yml` 取代（并加强了前置检查） |
| `cnb-release-sync.yml` | **保留** | 独立的补同步工具，与统一流程不冲突 |

迁移时**逐项核对过旧 Android workflow 的 12 个能力点**，确认全部到位：

```
verify_mpv_native_assets        build-android OK
testMobileArm64_v8aDebugUnitTest  build-android OK
sdkmanager                      build-android OK
assembleMobileArm64             build-android OK
assembleMobileArmeabi           build-android OK
assembleLeanbackArm64           build-android OK
assembleLeanbackArmeabi         build-android OK
Configure release signing       build-android OK
publish-oci-apks                release-all   OK
sync-cnb-release                release-all   OK
oci-metadata                    release-all   OK
Generate update manifests       build-android OK
```

---

## 6. 校验记录（2026-09-22）

**能做的验证**（本机 Windows，无法跑 macOS/runner）：

| 检查项 | 结果 |
|---|---|
| 5 个 workflow YAML 语法 | ✅ 全部合法 |
| `workflow_call` 引用路径存在性 | ✅ 3/3 |
| 可复用 workflow 的 `inputs` 契约（必填/未声明） | ✅ 3/3 OK |
| artifact 名 —— 上传方 vs 下载方 | ✅ `platform-{android,windows,ios}` |
| `prepare` 的 outputs 声明 vs `if` 条件引用 | ✅ 3/3 |
| outputs 在步骤里真实写入 `GITHUB_OUTPUT` | ✅ 3/3 |
| 旧 Android workflow 12 个能力点迁移 | ✅ 12/12 |
| Windows 打包脚本实测（真实 161 MB 产物） | ✅ zip 63.5 MB / tar.gz 63.3 MB，中文名正常 |

**未验证**（受环境限制）：

- **workflow 未在 GitHub 上真实跑过。** 本机是 Windows，无法执行
  macOS job；也无法在本地模拟 runner。YAML 语法、引用、inputs 契约、
  artifact 名、outputs 链路都做了静态校验，但**真实运行结果未知**。
- **首次跑之前请确认这些仓库配置**：
  - Secrets：`RELEASE_KEYSTORE_BASE64`、`RELEASE_KEY_ALIAS`、
    `RELEASE_STORE_PASSWORD`（Android 签名必需，缺了报明确错误）
  - Secrets：`CNB_TOKEN`（仅 `sync_cnb` 时需要）
  - Variables：`OCI_REPOSITORY` + Secrets `OCI_USERNAME` / `OCI_TOKEN`
    （仅 `publish_oci` 时有效，缺了会跳过并告警）
