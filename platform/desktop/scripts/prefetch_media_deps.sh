#!/usr/bin/env bash
# 预取 media_kit_windows_video 的两个构建期压缩包（走 GitHub 镜像）。
#
# 为什么必须预取
# --------------
# `media_kit_libs_windows_video-1.0.11/windows/CMakeLists.txt` 里有一对
# `download_and_verify()` 调用，用 `file(DOWNLOAD)` 直连 GitHub releases：
#
#   LIBMPV_URL  = https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z
#   LIBMPV_MD5  = a832ef24b3a6ff97cd2560b5b9d04cd8
#   ANGLE_URL   = https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z
#   ANGLE_MD5   = e866f13e8d552348058afaafe869b1ed
#
# 本机实测：
#   * GitHub 直连 ~1 KB/s，且**不支持 Range 续传**（`curl -C -` 报 exit=56，
#     文件大小不再增长），4.8 MB 的 ANGLE.7z 反复截断。
#   * 沙箱内的 bash 完全没有外网（所有 host 返回 HTTP=000）。
#   * 镜像可用，实测 `ghproxy.net` 平均 ~38 KB/s，2m13s 拉完 ANGLE.7z，
#     MD5 与期望值精确匹配。
#
# `file(DOWNLOAD)` **没有任何重试**，下不全就直接：
#   CMake Error ... ANGLE.7z Integrity check failed, please try to re-build project again.
#
# CMake 的跳过逻辑（读源码得到，很关键）
# -------------------------------------
#   download_and_verify(url, md5, archive):
#     if (EXISTS archive) { 算 MD5；不匹配就 REMOVE }
#     if (NOT EXISTS archive) { DOWNLOAD ...; 校验 }
#
#   check_directory_exists_and_not_empty(${ANGLE_SRC} ...)
#   → 只要求 `${CMAKE_BINARY_DIR}/ANGLE` 目录**非空**
#
# 所以「压缩包 MD5 正确」+「解压目录非空」两者齐备时，CMake 完全不会联网。
# 本脚本就把这两件事都准备好。
#
# 用法
# ----
#   bash scripts/prefetch_media_deps.sh
# 需要在 `flutter build windows` 之前运行（build_windows.sh 会自动调用）。
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ⚠️ 构建目录陷阱
# ---------------
# 全局有 `flutter config --build-dir=build_c`，但实测在 env 注入的子 shell
# 里未必生效，`flutter build windows` 会**回落到默认的 `build/`**。
# 构建日志里 CMake 报的路径就是权威答案：
#     D:/.../platform/desktop/build/windows/x64/mpv-dev-....7z
# 所以这里**两个目录都铺一份**，谁在生效都不会漏。
DESTS=(
  "$PROJ/build/windows/x64"
  "$PROJ/build_c/windows/x64"
)

# 镜像前缀列表，按实测速度排序（gh.llkk.cc 实测 502，已剔除）
MIRRORS=(
  "https://ghproxy.net/"
  "https://gh-proxy.com/"
  "https://ghfast.top/"
)

LIBMPV="mpv-dev-x86_64-20230924-git-652a1dd.7z"
LIBMPV_URL_GH="https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/${LIBMPV}"
LIBMPV_MD5="a832ef24b3a6ff97cd2560b5b9d04cd8"

ANGLE="ANGLE.7z"
ANGLE_URL_GH="https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z"
ANGLE_MD5="e866f13e8d552348058afaafe869b1ed"

mkdir -p "${DESTS[@]}"

# 下载暂存目录（先校验 MD5，通过后再铺到各构建目录）
DEST="$PROJ/.deps-cache"
mkdir -p "$DEST"

# md5_of <file> → 32 位小写 hex
md5_of() {
  md5sum "$1" 2>/dev/null | awk '{print $1}'
}

# fetch <文件名> <github 原始 URL> <期望 MD5>
#
# 查找顺序（重要：**先找现成的，最后才联网**）
#   1. 各候选构建目录里已有的（build/windows/x64、build_c/windows/x64）
#   2. 下载缓存 .deps-cache/
#   3. 依次尝试各镜像下载
# 命中任一处的 MD5 校验通过即返回，绝不重复下载。
fetch() {
  local name="$1" gh_url="$2" want="$3"
  local out="$DEST/$name"
  local got d src

  # --- 阶段 1：扫描已有副本（构建目录 + 缓存）---
  for d in "${DESTS[@]}" "$DEST"; do
    if [ -f "$d/$name" ]; then
      got="$(md5_of "$d/$name" || true)"
      if [ "$got" = "$want" ]; then
        echo "[prefetch] $name 已在 $d 找到且 MD5 匹配，跳过下载"
        # 统一回填到缓存目录，供后续铺开
        if [ "$d" != "$DEST" ]; then
          cp -f "$d/$name" "$out"
        fi
        return 0
      else
        echo "[prefetch] $d/$name 存在但 MD5 不匹配（$got），删除"
        rm -f "$d/$name"
      fi
    fi
  done

  # --- 阶段 2：联网下载 ---
  echo "[prefetch] $name 本地没有可用副本，开始下载"
  for m in "${MIRRORS[@]}"; do
    local url="${m}${gh_url}"
    echo "[prefetch] 尝试镜像: $m"
    # --fail 让 4xx/5xx 直接失败；镜像对不存在的资源常返回 502
    if curl -L --fail --retry 3 --retry-all-errors --connect-timeout 20 \
            --max-time 900 -o "$out" "$url" 2>/dev/null; then
      got="$(md5_of "$out" || true)"
      if [ "$got" = "$want" ]; then
        echo "[prefetch] $name 下载成功，MD5 匹配 ($got)"
        return 0
      fi
      echo "[prefetch] $name 下载完成但 MD5 不匹配（得到 $got），换下一个镜像"
      rm -f "$out"
    else
      echo "[prefetch] $name 经该镜像下载失败，换下一个"
      rm -f "$out"
    fi
  done

  echo "[prefetch] 错误: $name 所有镜像均失败（期望 MD5 $want）" >&2
  echo "[prefetch] 请手动下载并放置到: $out" >&2
  return 1
}

fetch "$ANGLE"  "$ANGLE_URL_GH"  "$ANGLE_MD5"
fetch "$LIBMPV" "$LIBMPV_URL_GH" "$LIBMPV_MD5"

# 把校验通过的包铺到两个候选构建目录（顺带清掉可能残留的 0 字节坏包）
for d in "${DESTS[@]}"; do
  # 清掉 0 字节残file：CMake 会算 MD5（空文件= d41d8c...），发现不匹配后
  # 自个儿 REMOVE 再 DOWNLOAD —— 那一步正是会卡住的地方，提前清理掉。
  find "$d" -maxdepth 1 -name "*.7z" -size 0 -delete 2>/dev/null || true
  for f in "$ANGLE" "$LIBMPV"; do
    if [ -f "$DEST/$f" ] && [ ! -f "$d/$f" ]; then
      cp "$DEST/$f" "$d/$f"
      echo "[prefetch] 已铺到 $d/$f"
    fi
  done
done

echo "[prefetch] 依赖就绪（ANGLE + libmpv），CMake 将跳过下载、直接解压。"
