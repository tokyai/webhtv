#!/usr/bin/env bash
# 一键打包 Windows 成品便携包。
#
# 用法：bash scripts/package_windows.sh
#
# 产出：dist/WebHTV-<版本>-win-x64/  可直接拷贝到任意 Windows 机器运行
#
# 步骤：
#   1. flutter build windows --release
#   2. 部署 node.exe 到 runtime/
#   3. 组装 dist 目录
#   4. 校验产物完整性
set -euo pipefail

PROJ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJ"

VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version: *//; s/+.*//')"
echo "=========================================="
echo " WebHTV Windows 打包"
echo " 版本: $VERSION"
echo "=========================================="

echo ""
echo "[1/4] 编译 release 版本…"
# ⚠️ 必须走 build_windows.sh：
#   1) 它注入 ProgramFiles(x86) 等变量，否则 Flutter 报
#      "%PROGRAMFILES(X86)% environment variable not found." 直接退出；
#   2) 它会清空 .plugin_symlinks、预取 ANGLE/mpv 依赖、
#      并在检测到脏 CMAKE_INSTALL_PREFIX 时清理 build/windows。
bash scripts/build_windows.sh release

echo ""
echo "[2/4] 部署 Node 运行时…"
bash scripts/deploy_node.sh release

echo ""
echo "[3/4] 组装发布目录…"
SRC="build/windows/x64/runner/Release"
DST="dist/WebHTV-${VERSION}-win-x64"
STAGE="dist/.stage-WebHTV-${VERSION}-win-x64"

# ⚠️ 关键：**先在临时目录组装，全部成功后再替换正式目录**。
#
# 为什么不能直接 `rm -rf "$DST" && cp`：
#   1) 若目标目录被占用（例如用户正开着 WebHTV，其 `data/app.so` 被 mmap），
#      删除可能**部分成功** —— 留下一个被清空一半、又被填充一半的残缺目录；
#      用户双击它就会「源服务未启动」（实测踩过的坑）。
#   2) 安全删除层可能中途拦截 `rm -rf`，脚本若继续执行同样产生残缺。
# 先组装到 STAGE 可保证：要么完整替换、要么完全不碰正式目录。
rm -rf "$STAGE" 2>/dev/null || true
mkdir -p "$STAGE"
cp -r "$SRC"/* "$STAGE/"

# 把 CMake BINARY_NAME（webhtv_win.exe）改成对用户友好的 WebHTV.exe
if [ -f "$STAGE/webhtv_win.exe" ]; then
  mv "$STAGE/webhtv_win.exe" "$STAGE/WebHTV.exe"
  echo "    -> 可执行文件已重命名: WebHTV.exe"
fi

# 清掉运行时残留：GPU 驱动（libGLESv2/vulkan-1）初始化时会创建
# 空的 "NVIDIA Corporation" 目录，不属于交付内容。
# 覆写一次能保证它是干净的。
find "$STAGE" -maxdepth 1 -type d -name "NVIDIA Corporation" -exec rm -rf {} + 2>/dev/null || true

# 附一份使用说明
cat > "$STAGE/使用说明.txt" <<'EOF'
WebHTV — Windows 桌面客户端
============================

【这是什么】

  一个通过"添加源地址"来收看的播放客户端。
  本程序不内置任何播放源，所有内容均需你自己提供源地址。

【快速开始】

  1. 双击 WebHTV.exe 启动
  2. 首次启动会停在「源管理」页（因为还没有源）
  3. 点击「添加源地址」，填入你的源地址，例如：
         http://用户名:密码@主机/index.js.md5
  4. 程序会自动下载源、校验 MD5、并在本机启动它
  5. 切到「浏览」页即可看到站点内容

【关于播放】

  部分源的播放链路依赖网盘账号（夸克 / 百度 / 115 / 天翼 等）。
  如果播放时提示"请先去配置中心登录"，这是源本身的提示，不是故障。
  请先在「设置」页查看凭证状态，按源提供的配置方式登录网盘后再重试。

【目录说明】

  runtime\node.exe        本机 Node 运行时（源服务由它承载）
  data\  <用户目录>       源文件与运行数据（不在本目录，见「设置」页）

【端口】

  源服务固定使用本机 9988 端口。
  程序退出时会自动回收源服务；若异常退出（崩溃/强杀），
  源服务会在约 15 秒内自行退出，不会长期占用端口。
  仅当端口被**其它程序**占用时才会提示，按提示释放即可。

【卸载】

  直接删除本目录即可。
  用户数据位于 %APPDATA%\com.webhtv\webhtv_win\webhtv，
  如需彻底清理可一并删除（程序「设置」页会显示确切路径）。
EOF

echo "    -> $STAGE"

echo ""
echo "[4/4] 校验产物…"
FAIL=0
# 必需项：exe + node 运行时 + Flutter 运行时 + AOT 产物 + 播放栈
for f in \
  "WebHTV.exe" \
  "runtime/node.exe" \
  "flutter_windows.dll" \
  "data/app.so" \
  "libmpv-2.dll" \
  "libEGL.dll" \
  "libGLESv2.dll" \
  "d3dcompiler_47.dll" \
  "vk_swiftshader.dll" \
  "vulkan-1.dll" \
  "zlib.dll" \
  "media_kit_video_plugin.dll" \
  "media_kit_libs_windows_video_plugin.dll" \
  "volume_controller_plugin.dll" \
  "data/icudtl.dat" \
; do
  if [ -e "$STAGE/$f" ]; then
    printf "    [OK] %-42s %10s 字节\n" "$f" "$(stat -c%s "$STAGE/$f" 2>/dev/null || echo '?')"
  else
    printf "    [缺失] %s\n" "$f"
    FAIL=1
  fi
done

if [ "$FAIL" = "1" ]; then
  echo ""
  echo "错误：必需文件缺失，**不会**替换正式发布目录。" >&2
  echo "      已保留组装现场: $STAGE（可手工检查）" >&2
  exit 1
fi

# ---- 原子替换：校验通过后才动正式目录 ----
#
# 若正式目录被占用（用户开着 App），`rm -rf` 可能只删掉一部分。
# 这里先尝试整体改名移走（快且原子），失败再退回逐项删除；
# 无论哪种失败都**明确报错**，不留残缺目录冒充成品。
if [ -e "$DST" ]; then
  BACKUP="dist/.prev-$(date +%H%M%S).bak"
  if mv "$DST" "$BACKUP" 2>/dev/null; then
    echo "    -> 旧目录已移走: $BACKUP"
    rm -rf "$BACKUP" 2>/dev/null || echo "    (提示：$BACKUP 未能删除，可手工清理)"
  else
    echo "错误：无法移走旧目录 $DST（可能被占用）。" >&2
    echo "      请先关闭正在运行的 WebHTV，再重新打包。" >&2
    echo "      本次组装结果保留在: $STAGE" >&2
    exit 1
  fi
fi
mv "$STAGE" "$DST"
echo "    -> 已发布: $DST"

SIZE="$(du -sh "$DST" | cut -f1)"
echo ""
echo "=========================================="
echo " 打包完成"
echo " 目录: $DST"
echo " 体积: $SIZE"
echo "=========================================="
echo ""
echo "该目录可直接拷贝到其它 Windows 机器运行，无需安装。"
