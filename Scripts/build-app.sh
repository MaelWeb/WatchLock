#!/usr/bin/env bash
# 构建并打包 WatchLock.app
#
# 用法：
#   ./Scripts/build-app.sh                     # release 构建 + 无沙箱（默认，本地真机测试）
#   ./Scripts/build-app.sh --debug             # debug 构建
#   ./Scripts/build-app.sh --sandbox           # 打开 App 沙箱（上架/沙箱兼容性对照）
#   ./Scripts/build-app.sh --no-sandbox        # 关闭 App 沙箱（显式）
#   SIGN_IDENTITY="Apple Development: ..." ./Scripts/build-app.sh
#
# 签名：未指定时自动选本机的 Developer ID Application / Apple Development 证书，
# 都没有才退回 ad-hoc（ad-hoc 每次打包授权都会失效，见下方 detect_identity 注释）。
#
# 为什么默认无沙箱：锁屏依赖外部命令与 Apple Events（osascript ⌃⌘Q、pmset），
# 沙箱下 System Events 会以 -600「应用程序没有运行」失败，本机真机测试需要关掉。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_CONFIG="release"
SANDBOX_MODE="no-sandbox"

for arg in "$@"; do
  case "$arg" in
    --debug) BUILD_CONFIG="debug" ;;
    --sandbox) SANDBOX_MODE="sandbox" ;;
    --no-sandbox) SANDBOX_MODE="no-sandbox" ;;
    *)
      echo "未知参数：$arg" >&2
      exit 2
      ;;
  esac
done

APP_NAME="WatchLock"
BUILD_DIR="$ROOT_DIR/.build/${BUILD_CONFIG}"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"

# 签名身份优先级：显式 SIGN_IDENTITY > 本机已有的稳定证书 > ad-hoc。
#
# 为什么不能一直用 ad-hoc：ad-hoc 签名的 designated requirement 是二进制哈希（cdhash），
# 每次重新打包都会变；而「辅助功能」「蓝牙」等 TCC 授权就是按它绑定的，
# 于是每次打包后旧授权全部失效（设置里看着还勾着，实际已不生效），
# 锁屏就会反复报「osascript 不允许发送按键 (1002)」。
# 用同一张证书签名，designated requirement 稳定，授权可以跨打包保留。
detect_identity() {
  local list prefix match
  list="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  for prefix in "Developer ID Application" "Apple Development"; do
    match="$(printf '%s\n' "$list" | sed -n "s/.*\"\(${prefix}:[^\"]*\)\".*/\1/p" | head -n 1 || true)"
    if [[ -n "$match" ]]; then
      printf '%s' "$match"
      return 0
    fi
  done
  return 0
}
SIGN_IDENTITY="${SIGN_IDENTITY:-$(detect_identity)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ENTITLEMENTS_SRC="$ROOT_DIR/Resources/WatchLock.entitlements"
ENTITLEMENTS="$ENTITLEMENTS_SRC"

echo "==> 构建 ($BUILD_CONFIG, $SANDBOX_MODE)"
swift build --package-path "$ROOT_DIR" -c "$BUILD_CONFIG"

BIN="$BUILD_DIR/$APP_NAME"
if [[ ! -f "$BIN" ]]; then
  echo "未找到产物：$BIN" >&2
  exit 1
fi

if [[ "$SANDBOX_MODE" == "no-sandbox" ]]; then
  # 从基线 entitlements 中剥离沙箱相关键，写入临时文件供签名使用。
  ENTITLEMENTS="$(mktemp "${TMPDIR:-/tmp}/watchlock.entitlements.XXXXXX").plist"
  python3 - "$ENTITLEMENTS_SRC" "$ENTITLEMENTS" <<'PY'
import plistlib, sys
source, destination = sys.argv[1], sys.argv[2]
with open(source, "rb") as handle:
    data = plistlib.load(handle)
for key in ("com.apple.security.app-sandbox",
            "com.apple.security.files.user-selected.read-write"):
    data.pop(key, None)
with open(destination, "wb") as handle:
    plistlib.dump(data, handle)
PY
  trap 'rm -f "$ENTITLEMENTS"' EXIT
fi

echo "==> 组装 $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ENTITLEMENTS" "$APP_DIR/Contents/Resources/WatchLock.entitlements"

# 品牌图标资源（由 Scripts/generate-icons.sh 生成，已入库）
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
if [[ -f "$ROOT_DIR/Resources/MenuBarTemplate.png" ]]; then
  cp "$ROOT_DIR/Resources/MenuBarTemplate.png" "$APP_DIR/Contents/Resources/MenuBarTemplate.png"
fi

echo "==> 签名 ($SIGN_IDENTITY)"
codesign --force --deep --sign "$SIGN_IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  --options runtime "$APP_DIR"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "    注意：当前是 ad-hoc 签名，每次打包 cdhash 都会变，辅助功能 / 蓝牙授权会随之失效。"
  echo "    本机没有可用的签名证书时可忽略；有证书请用 SIGN_IDENTITY=\"Apple Development: ...\" 指定。"
else
  echo "    稳定签名：辅助功能 / 蓝牙授权可跨重新打包保留（换签名身份后需重新授权一次）。"
fi

echo "==> 生效的 entitlements"
if codesign -d --entitlements :- "$APP_DIR" 2>/dev/null | grep -q "app-sandbox"; then
  echo "    已启用 App 沙箱"
else
  echo "    未启用 App 沙箱（osascript / pmset 等外部命令可正常调用）"
fi

echo "==> 完成：$APP_DIR"
echo "提示：首次运行需要在「系统设置 → 隐私与安全性 → 蓝牙」授予蓝牙权限。"
