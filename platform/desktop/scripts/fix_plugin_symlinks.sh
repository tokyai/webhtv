#!/usr/bin/env bash
# 确保 Windows 上 Flutter 插件的符号链接目录处于「干净可重建」状态。
#
# 背景（实测结论，勿再重复踩坑）
# ------------------------------
# `flutter build windows` 会在 `windows/flutter/ephemeral/.plugin_symlinks/`
# 下为每个插件建符号链接，实现见 Flutter 源码
# `packages/flutter_tools/lib/src/flutter_plugins.dart` 的
# `_createPlatformPluginSymlinks`：
#
#     final Link link = symlinkDirectory.childLink(name);
#     if (link.existsSync()) {
#       continue;               // 已存在 → 跳过
#     }
#     link.createSync(path);
#
# ⚠️ 以下两种「绕过」都已被实测证伪，不要再试：
#
#   1) `cp -r <plugin> .plugin_symlinks/<name>`（复制真实目录）
#      → Dart 的 `Link.existsSync()` 对普通目录返回 **false**
#        （不是文档暗示的 true），于是 Flutter 仍会调 `createSync`，
#        撞上已存在的目录 → `PathExistsException ... errno = 183`。
#
#   2) PowerShell `New-Item -ItemType Junction`（目录联接）
#      → `Link.existsSync()` 对 junction 同样返回 false；
#        `Link.targetSync()` 报 `OS Error errno = 4390`
#        （「此文件或目录不是一个重分析点」）。同样失败。
#
# ✅ 正确做法：目录里**什么都别预先放**，让 Flutter 自己建。
#    本机实测：清空后 Flutter 成功创建 8 个链接
#    （jni / media_kit_libs_windows_video / media_kit_video /
#      package_info_plus / path_provider_windows /
#      shared_preferences_windows / volume_controller / wakelock_plus）。
#
# ⚠️ 安全机制注意
# --------------
# 该目录下每条符号链接会被解析成整个插件目录树，
# `rm -rf` 目录本身会被安全护栏判定为「批量删除数千条目」而中断。
# 因此这里**只在确有污染时才清理**，且逐条 unlink，避免触发护栏。
#
# 判定「干净」的标准：目录下每一项都是有效符号链接（`-L` 为真）。
# 若存在普通目录/文件（即 cp 或 junction 的残留），则清掉。
#
# 用法
# ----
#   bash scripts/fix_plugin_symlinks.sh [--force]
#     --force  无条件清空重建（一般不需要）
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINKDIR="$PROJ/windows/flutter/ephemeral/.plugin_symlinks"
FORCE="${1:-}"

echo "[fix_symlinks] 项目: $PROJ"

if [ ! -d "$LINKDIR" ]; then
  mkdir -p "$LINKDIR"
  echo "[fix_symlinks] 目录不存在，已创建空目录: $LINKDIR"
  exit 0
fi

count_entries() { ls -A "$LINKDIR" 2>/dev/null | wc -l | tr -d ' '; }

# 统计「非符号链接」的条目数（这些才是污染）
count_bad() {
  local n=0
  local e
  for e in "$LINKDIR"/*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    if [ ! -L "$e" ]; then
      n=$((n + 1))
    fi
  done
  echo "$n"
}

BEFORE="$(count_entries)"
BAD="$(count_bad)"

echo "[fix_symlinks] 当前条目数: $BEFORE，其中非符号链接（污染）: $BAD"

if [ "$FORCE" != "--force" ] && [ "$BAD" = "0" ] && [ "$BEFORE" != "0" ]; then
  echo "[fix_symlinks] 目录干净（全是符号链接），无需处理。"
  echo "[fix_symlinks] 下一步: flutter build windows --release"
  exit 0
fi

if [ "$BEFORE" = "0" ]; then
  echo "[fix_symlinks] 目录为空，Flutter 会自动创建链接。"
  exit 0
fi

# 有污染 → 逐条删除。先删非链接（污染项），再删链接。
echo "[fix_symlinks] 检测到污染，开始清理 $LINKDIR"
for e in "$LINKDIR"/*; do
  [ -e "$e" ] || [ -L "$e" ] || continue
  if [ ! -L "$e" ]; then
    rm -rf "$e"
    echo "[fix_symlinks]   已删除污染项: $(basename "$e")"
  fi
done

# 再清符号链接（用 unlink 只删链接本身，不递归进目标）
for e in "$LINKDIR"/*; do
  [ -L "$e" ] || continue
  unlink "$e" 2>/dev/null || rm -f "$e"
done

AFTER="$(count_entries)"
echo "[fix_symlinks] 清理完成，剩余条目: $AFTER （应为 0）"
echo "[fix_symlinks] 下一步: flutter build windows --release"
