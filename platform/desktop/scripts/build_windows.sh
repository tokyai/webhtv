#!/usr/bin/env bash
# 在 Windows/PortableGit 环境下构建 WebHTV 桌面端（Windows）。
#
# 为什么需要这个包装脚本
# ----------------------
# 1) **环境变量缺失（致命）**
#    Flutter 的 `visual_studio.dart` 靠 `%PROGRAMFILES(X86)%` 拼
#    `vswhere.exe` 的路径；拿不到就直接 `throwToolExit`：
#        Error: %PROGRAMFILES(X86)% environment variable not found.
#    PortableGit 启动的 bash 进程里，`ProgramFiles` / `ProgramFiles(x86)`
#    / `ProgramW6432` 等变量**一个都没有**（实测 `env | grep -c ProgramFiles` = 0）。
#    又因为变量名含括号和反斜杠，bash 里不能直接 `export`：
#        bash: export: `ProgramFiles(x86)=...': not a valid identifier
#    所以必须用 `env "NAME=VAL" ... bash -c` 这种形式注入。
#
# 2) **reg.exe / wmic.exe 被安全策略拉黑（非致命）**
#    `flutter doctor` 会调 `reg query ...\Microsoft SDKs\Windows\v10.0`
#    和 `wmic os get Caption`。这两个程序在本机安全中心的程序黑名单里，
#    报 "PROGRAM BLOCKED BY SECURITY POLICY"，且**不可从命令行放行**。
#    影响范围：只影响 `flutter doctor` 的**体检显示**，不影响实际构建
#    （构建走 CMake → MSVC，不依赖这两次查询）。
#    因此本脚本**直接构建，不跑 doctor**。
#
# 3) **符号链接**
#    构建前清空 `windows/flutter/ephemeral/.plugin_symlinks`，
#    理由见 scripts/fix_plugin_symlinks.sh 的注释（三种踩坑记录）。
#
# 4) **ANGLE.7z / libmpv 构建期下载（易失败）**
#    `media_kit_libs_windows_video` 的 CMake 用 `file(DOWNLOAD)` 从 GitHub
#    拉两个包，无重试。GitHub 直连在本机约 1 KB/s 且会截断，
#    必须走镜像预取（见 scripts/prefetch_media_deps.sh）。
#    下载后校验 MD5，不匹配就 FATAL_ERROR。
#
# 用法
# ----
#   bash scripts/build_windows.sh            # release
#   bash scripts/build_windows.sh debug      # debug
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-release}"

case "$MODE" in
  release|debug) ;;
  *) echo "[build] 未知模式: $MODE（应为 release 或 debug）" >&2; exit 2 ;;
esac

echo "[build] 项目: $PROJ"
echo "[build] 模式: $MODE"

# --- 第 1 步：确保插件链接目录干净（Flutter 会自己重建）---
bash "$PROJ/scripts/fix_plugin_symlinks.sh"

# --- 第 2 步：清理脏 CMake 缓存（关键！）---
#
# 症状
# ----
#   构建到最后一步 `INSTALL.vcxproj` 失败：
#     error MSB3073: 命令 "cmake.exe -DBUILD_TYPE=Release -P cmake_install.cmake" 已退出，代码为 1
#   `cmake_install.cmake` 里所有 `file(INSTALL DESTINATION ...)` 都指向
#     C:/Program Files/webhtv_win
#   → 往系统目录写，非管理员必然失败。
#
# 根因
# ----
#   `windows/CMakeLists.txt:68` 的兜底逻辑：
#     if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
#       set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
#     endif()
#   只在 prefix 仍是「默认值」时才改写成 bundle 目录。
#   一旦 CMakeCache.txt 里被写成 C:/Program Files/webhtv_win
#   （实测发生过），`INITIALIZED_TO_DEFAULT` 为假 → 兜底被跳过 → install 炸。
#
# 处理
# ----
#   删除 `$BUILD_ROOT/windows`（纯中间产物，不含用户数据），
#   并把已校验的 .7z 依赖包搬回原位，避免重新联网下载。
BUILD_ROOT="$PROJ/build"
DEPS_CACHE="$PROJ/.deps-cache"
KEEP=""
if [ -d "$BUILD_ROOT/windows/x64" ]; then
  for f in ANGLE.7z mpv-dev-x86_64-20230924-git-652a1dd.7z; do
    if [ -f "$BUILD_ROOT/windows/x64/$f" ]; then
      mkdir -p "$DEPS_CACHE"
      cp "$BUILD_ROOT/windows/x64/$f" "$DEPS_CACHE/$f"
      KEEP="$KEEP $f"
    fi
  done
fi

if [ -f "$BUILD_ROOT/windows/x64/CMakeCache.txt" ]; then
  if grep -q 'CMAKE_INSTALL_PREFIX:PATH=C:/Program Files' \
        "$BUILD_ROOT/windows/x64/CMakeCache.txt" 2>/dev/null; then
    echo "[build] 检测到脏 CMAKE_INSTALL_PREFIX，清理 build/windows 重建"
    rm -rf "$BUILD_ROOT/windows"
    mkdir -p "$BUILD_ROOT/windows/x64"
    for f in $KEEP; do
      cp "$DEPS_CACHE/$f" "$BUILD_ROOT/windows/x64/$f"
      echo "[build]   依赖包已恢复: $f"
    done
  else
    echo "[build] CMakeCache 正常，跳过清理"
  fi
fi

# --- 第 3 步：预取 media_kit 构建期依赖（ANGLE + libmpv）---
#
# 必须在「清理脏缓存」之后：清理会删掉 build/windows，连带删掉已放好的 .7z。
# 预取脚本会把包铺到 build/windows/x64 与 build_c/windows/x64 两处，
# 谁在生效都不会漏。
#
# 失败不中断：若本地/缓存里已有校验通过的包，CMake 自身也会跳过下载；
# 只有确实一个可用副本都没有时才需要网络。
if [ -f "$PROJ/scripts/prefetch_media_deps.sh" ]; then
  if ! bash "$PROJ/scripts/prefetch_media_deps.sh"; then
    echo "[build] 警告: 依赖预取未完全成功。" >&2
    echo "[build] 若 CMake 仍报 'Integrity check failed'，说明本地无可用副本，" >&2
    echo "[build] 请手动下载 ANGLE.7z (MD5 e866f13e8d552348058afaafe869b1ed)" >&2
    echo "[build] 与 mpv-dev-x86_64-20230924-git-652a1dd.7z (MD5 a832ef24b3a6ff97cd2560b5b9d04cd8)" >&2
    echo "[build] 放入 $PROJ/.deps-cache/ 后重试。" >&2
  fi
fi

# --- 第 4 步：注入 Windows 环境变量并构建 ---
echo "[build] 注入 Windows 环境变量并调用 flutter build windows --$MODE"
cd "$PROJ"

env \
  "ProgramFiles=C:\\Program Files" \
  "ProgramFiles(x86)=C:\\Program Files (x86)" \
  "ProgramW6432=C:\\Program Files" \
  "CommonProgramFiles=C:\\Program Files\\Common Files" \
  "CommonProgramFiles(x86)=C:\\Program Files (x86)\\Common Files" \
  bash -c "cd \"$PROJ\" && flutter build windows --$MODE"

# 产物目录：实际落在默认的 build/（见文件头关于 build-dir 的说明），
# 不要写死 build_c —— 那会误导使用者。
case "$MODE" in
  release) OUTDIR="build/windows/x64/runner/Release" ;;
  debug)   OUTDIR="build/windows/x64/runner/Debug" ;;
esac

# --- 第 5 步：部署 Node 运行时 ---
#
# **必须做**：应用依赖 runtime/node.exe 承载 drpyS 源服务。缺了它，
# 源服务子进程起不来，所有搜索/首页/播放全部失败（界面表现为
# 「聚合搜索 0 结果」，但端口探测又像是通的，极难定位）。
#
# 历史上这步只在 `package_windows.sh`（打包 Release）里做，导致
# **Debug 产物永远缺 node.exe** —— 本地调试跑 Debug 时必然踩这个坑。
# 现在统一由本脚本负责，两种模式都不会漏。
if [ -f "$PROJ/scripts/deploy_node.sh" ]; then
  if ! bash "$PROJ/scripts/deploy_node.sh" "$MODE"; then
    echo "[build] 错误: Node 运行时部署失败。应用将无法启动源服务。" >&2
    echo "[build] 请确认 assets/runtime/node.exe 存在，或系统 PATH 中有 node。" >&2
    exit 1
  fi
else
  echo "[build] 警告: 找不到 scripts/deploy_node.sh，产物将缺少 runtime/node.exe" >&2
fi

echo "[build] 完成。产物: $PROJ/$OUTDIR/"
if [ -f "$PROJ/$OUTDIR/webhtv_win.exe" ]; then
  echo "[build]   可执行文件: $OUTDIR/webhtv_win.exe"
fi
