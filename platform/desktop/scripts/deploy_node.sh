#!/usr/bin/env bash
# 把 node.exe 部署到已构建产物中，使其可以独立运行。
#
# 用法：bash scripts/deploy_node.sh [构建模式]
#   构建模式：debug（默认）| release
#
# 背景：应用需要一个本机 Node 运行时来承载 drpyS 源服务。
#       node.exe 体积较大（约 83 MB），不放进 Flutter assets
#       （会拖慢热重载），而是在构建后复制到产物目录的 runtime/ 下。
set -euo pipefail

MODE="${1:-debug}"
PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$PROJ/build/windows/x64/runner/$([ "$MODE" = "release" ] && echo Release || echo Debug)"
NODE_SRC="$PROJ/assets/runtime/node.exe"

echo "[deploy_node] 项目目录: $PROJ"
echo "[deploy_node] 构建模式: $MODE"
echo "[deploy_node] 产物目录: $BUNDLE"

if [ ! -d "$BUNDLE" ]; then
  echo "[deploy_node] 错误：产物目录不存在。请先运行 flutter build windows --$MODE" >&2
  exit 1
fi

if [ ! -f "$NODE_SRC" ]; then
  echo "[deploy_node] assets/runtime/node.exe 不存在，尝试从系统 PATH 获取…" >&2
  SYS_NODE="$(command -v node || true)"
  if [ -z "$SYS_NODE" ]; then
    echo "[deploy_node] 错误：找不到 node.exe。请手动放置到 assets/runtime/node.exe" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$NODE_SRC")"
  cp "$SYS_NODE" "$NODE_SRC"
  echo "[deploy_node] 已从 $SYS_NODE 复制"
fi

mkdir -p "$BUNDLE/runtime"
cp "$NODE_SRC" "$BUNDLE/runtime/node.exe"
echo "[deploy_node] 已部署: $BUNDLE/runtime/node.exe ($(stat -c%s "$BUNDLE/runtime/node.exe") 字节)"

# 校验 node 可运行
"$BUNDLE/runtime/node.exe" --version >/dev/null \
  && echo "[deploy_node] node 运行时校验通过" \
  || { echo "[deploy_node] 错误：部署的 node.exe 无法运行" >&2; exit 1; }

echo "[deploy_node] 完成"
