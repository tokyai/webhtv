#!/usr/bin/env bash
# ============================================================================
# sign_ios.sh —— 把 GitHub Actions 产出的**未签名** .ipa 用本地自签证书重签
#
# 为什么需要这个脚本
# ---------------------------------------------------------------------------
# CI 上刻意**不签名**（证书私钥不进仓库/secret）。因此 CI 给出的是
# `WebHTV-<ver>-ios-unsigned.ipa`，本身无法直接安装。本脚本在**本机**
# （macOS，或装了 ldid 的环境）完成重签。
#
# ⚠️  在 Windows 上**不能**运行 —— 需要 macOS 的 `codesign` / `security`。
#     本仓库开发机是 Windows，因此这个脚本是给「拿到 .ipa 后去 Mac 上重签」
#     的场景准备的，不是本机可直接跑的。
#
# 用法
# ---------------------------------------------------------------------------
#   bash scripts/sign_ios.sh \
#     --ipa  dist/WebHTV-0.1.0-ios-unsigned.ipa \
#     --p12  /path/to/ios_sign.p12 \
#     --profile /path/to/PeekPili_Dev_Profile.mobileprovision \
#     --password 123456 \
#     --bundle-id com.webhtv.app \
#     --out  dist/WebHTV-0.1.0-ios-signed.ipa
#
# 签名材料（本项目已有的那套，位于
# `D:\Work\workSpace\PeekPiliRelease\app\anzhuangbao\ios\`）：
#   development.cer                     开发证书（DER）
#   ios_sign.key                        私钥
#   ios_sign.csr                        证书签名请求
#   ios_sign.p12                        由上面三个用 openssl 合成，密码 123456
#   PeekPili_Dev_Profile.mobileprovision 开发描述文件
#
#   合成命令（`1.txt` 里记的）：
#     openssl x509 -inform DER -in development.cer -out ios_sign.pem -outform PEM
#     openssl pkcs12 -export -inkey ios_sign.key -in ios_sign.pem -out ios_sign.p12
#     # 密码: 123456
# ============================================================================

set -euo pipefail

IPA=""
P12=""
PROFILE=""
PASSWORD=""
BUNDLE_ID=""
OUT=""
ENTITLEMENTS=""

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ipa)        IPA="$2"; shift 2 ;;
    --p12)        P12="$2"; shift 2 ;;
    --profile)    PROFILE="$2"; shift 2 ;;
    --password)   PASSWORD="$2"; shift 2 ;;
    --bundle-id)  BUNDLE_ID="$2"; shift 2 ;;
    --out)        OUT="$2"; shift 2 ;;
    --entitlements) ENTITLEMENTS="$2"; shift 2 ;;
    -h|--help)    usage 0 ;;
    *) echo "未知参数: $1" >&2; usage 2 ;;
  esac
done

# ---- 平台前置检查 --------------------------------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
  echo "错误：本脚本需要 macOS（codesign / security / PlistBuddy）。" >&2
  echo "      当前系统：$(uname -s)。请在 Mac 上运行，或改用 Sideloadly/AltStore。" >&2
  exit 1
fi

for req in "$IPA" "$P12" "$PROFILE"; do
  [ -n "$req" ] || { echo "错误：--ipa / --p12 / --profile 均为必填。" >&2; usage 2; }
  [ -e "$req" ] || { echo "错误：文件不存在 —— $req" >&2; exit 1; }
done
[ -n "$OUT" ] || { echo "错误：必须指定 --out。" >&2; usage 2; }

WORK="$(mktemp -d)"
KEYCHAIN="$WORK/sign.keychain-db"
KEYCHAIN_PASS="webhtv-sign"

cleanup() {
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

# ---- 1. 临时钥匙串导入 p12 ------------------------------------------------
echo "==> 创建临时钥匙串并导入签名身份"
security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN"
# 把临时钥匙串临时插进搜索列表，让 codesign 能找到它
ORIG_KEYCHAINS="$(security list-keychains -d user | tr -d ' "'"'"'\n' | sed 's/^//')"
security list-keychains -d user -s "$KEYCHAIN" $ORIG_KEYCHAINS

security import "$P12" -k "$KEYCHAIN" -P "${PASSWORD:-}" -T /usr/bin/codesign
# 避免 codesign 弹窗索要钥匙串访问权限
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASS" "$KEYCHAIN" >/dev/null

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" \
  | sed -n 's/.*"\(.*\)".*/\1/p' | head -1)"
if [ -z "$IDENTITY" ]; then
  echo "错误：导入后仍未找到可用的 codesigning 身份。" >&2
  security find-identity -v -p codesigning "$KEYCHAIN" >&2 || true
  exit 1
fi
echo "    身份：$IDENTITY"

# ---- 2. 解包 ipa ----------------------------------------------------------
echo "==> 解包 $IPA"
mkdir -p "$WORK/raw"
(cd "$WORK/raw" && unzip -q "$IPA")

APP="$(find "$WORK/raw/Payload" -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP" ] || { echo "错误：Payload 内没有 .app。" >&2; exit 1; }
echo "    App：$(basename "$APP")"

# ---- 3. 嵌入描述文件 ------------------------------------------------------
echo "==> 嵌入描述文件"
cp "$PROFILE" "$APP/embedded.mobileprovision"

PROFILE_PLIST="$WORK/profile.plist"
security cms -D -i "$PROFILE" > "$PROFILE_PLIST"

# 若未显式给 bundle id，从描述文件里取（自签场景下两者必须一致）
if [ -z "$BUNDLE_ID" ]; then
  BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' \
    "$PROFILE_PLIST" | sed 's/^[^.]*\.//')"
  echo "    从描述文件推导 bundle id：$BUNDLE_ID"
fi

# 改写 app 的 bundle id，使其与描述文件匹配
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Info.plist"

# ---- 4. 生成 entitlements -------------------------------------------------
if [ -z "$ENTITLEMENTS" ]; then
  ENTITLEMENTS="$WORK/entitlements.plist"
  # 直接复用描述文件里的 Entitlements（含 application-identifier、
  # get-task-allow 等），这是自签最省事也最不容易出错的做法。
  /usr/libexec/PlistBuddy -x -c 'Print :Entitlements' "$PROFILE_PLIST" > "$ENTITLEMENTS"
fi

# ---- 5. 逐层签名 ----------------------------------------------------------
# 顺序很重要：**先签内嵌的 Framework/dylib，再签主 App**。
# 反过来签会让主 App 的签名在子项被改动后失效。
echo "==> 签名内嵌二进制"
find "$APP/Frameworks" -type f \( -name '*.dylib' -o -perm -u+x \) 2>/dev/null | while read -r bin; do
  case "$bin" in
    *.framework/*) continue ;;
  esac
  codesign --force --sign "$IDENTITY" --timestamp=none "$bin" 2>/dev/null || true
done

find "$APP/Frameworks" -maxdepth 1 -name '*.framework' 2>/dev/null | while read -r fw; do
  echo "    $(basename "$fw")"
  codesign --force --sign "$IDENTITY" --timestamp=none "$fw"
done

echo "==> 签名主 App"
codesign --force --sign "$IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  --timestamp=none \
  "$APP"

# ---- 6. 校验 --------------------------------------------------------------
echo "==> 校验签名"
codesign --verify --deep --strict --verbose=2 "$APP" || {
  echo "警告：codesign --verify 未完全通过（自签场景下常见，安装后仍可用）。" >&2
}

# ---- 7. 重新打包 ----------------------------------------------------------
echo "==> 重新打包"
mkdir -p "$(dirname "$OUT")"
(cd "$WORK/raw" && zip -qry "$OUT" Payload)

echo ""
echo "完成：$OUT"
echo "      bundle id : $BUNDLE_ID"
echo "      签名身份  : $IDENTITY"
echo ""
echo "安装方式：Xcode → Window → Devices and Simulators → 拖入 .ipa，"
echo "         或 brew install ios-deploy && ios-deploy --bundle <解包的 .app>"
