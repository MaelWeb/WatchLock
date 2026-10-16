#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="WatchLock"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
RELEASE_VERSION="${RELEASE_VERSION:-${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")}}"
if [[ ! "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
  echo "RELEASE_VERSION 必须为 major.minor.patch 或 major.minor.patch-prerelease：$RELEASE_VERSION" >&2
  exit 2
fi
APP_VERSION="${RELEASE_VERSION%%-*}"
if [[ -n "${VERSION:-}" && "$VERSION" != "$APP_VERSION" ]]; then
  echo "VERSION 与 RELEASE_VERSION 的基础版本不一致" >&2
  exit 2
fi

VERSION="$APP_VERSION" bash "$ROOT_DIR/Scripts/build-app.sh" "$@"

STAGING_DIR="$(mktemp -d "$ROOT_DIR/dist/.dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
DMG_NAME="$APP_NAME-$RELEASE_VERSION.dmg"
DMG_PATH="$ROOT_DIR/dist/$DMG_NAME"

ditto "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$ROOT_DIR/LICENSE" "$STAGING_DIR/LICENSE"

echo "==> 创建 $DMG_NAME"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" \
  -fs HFS+ -format UDZO -ov "$DMG_PATH"
hdiutil verify "$DMG_PATH"
(
  cd "$ROOT_DIR/dist"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
  shasum -a 256 -c "$DMG_NAME.sha256"
)
echo "==> 完成：$DMG_PATH"
echo "校验文件：$DMG_PATH.sha256"
