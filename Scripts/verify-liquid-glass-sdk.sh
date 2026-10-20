#!/usr/bin/env bash
# 校验发布产物是否会采用系统的 Liquid Glass 材质。
#
# 依据（Apple 官方文档）：
#   - 《Adopting Liquid Glass》：用最新 SDK 构建，标准组件（含 popover）才自动采用新材质。
#   - 《UIDesignRequiresCompatibility》：设为 YES 会强制退回旧外观，仅供临时过渡，
#     未设置或 NO 才是链接最新 SDK 时的默认（采用新设计）。
#
# 用法：Scripts/verify-liquid-glass-sdk.sh dist/WatchLock.app
# 退出码：0 通过；1 不满足（链接了旧 SDK，或带了退回旧外观的键）。
set -euo pipefail

APP="${1:?用法: $0 <WatchLock.app>}"
BIN="$APP/Contents/MacOS/WatchLock"
PLIST="$APP/Contents/Info.plist"
MIN_SDK_MAJOR=26

[ -f "$BIN" ] || { echo "找不到可执行文件：$BIN" >&2; exit 1; }
[ -f "$PLIST" ] || { echo "找不到 Info.plist：$PLIST" >&2; exit 1; }

fail=0

# 每个架构都要检查（Universal 包里 arm64 与 x86_64 各有一份 LC_BUILD_VERSION）。
archs="$(lipo -archs "$BIN")"
for arch in $archs; do
  sdk="$(otool -arch "$arch" -l "$BIN" | awk '/LC_BUILD_VERSION/{f=1} f&&$1=="sdk"{print $2; exit}')"
  if [ -z "$sdk" ]; then
    echo "[$arch] 读不到 LC_BUILD_VERSION 的 sdk 字段" >&2
    fail=1
    continue
  fi
  major="${sdk%%.*}"
  if [ "$major" -lt "$MIN_SDK_MAJOR" ]; then
    echo "[$arch] 链接的 SDK 为 ${sdk}，低于 ${MIN_SDK_MAJOR}：不会采用系统 Liquid Glass 材质" >&2
    fail=1
  else
    echo "[$arch] 链接 SDK ${sdk}（>= ${MIN_SDK_MAJOR}）"
  fi
done

# 兼容键不得为 YES。取不到（未设置）是预期的默认。
if value="$(plutil -extract UIDesignRequiresCompatibility raw "$PLIST" 2>/dev/null)"; then
  case "$value" in
    true|1|YES|yes)
      echo "Info.plist 设置了 UIDesignRequiresCompatibility=${value}：会强制退回旧外观" >&2
      fail=1
      ;;
    *) echo "UIDesignRequiresCompatibility=${value}（不影响）" ;;
  esac
else
  echo "UIDesignRequiresCompatibility 未设置（默认，采用系统新设计）"
fi

exit "$fail"
