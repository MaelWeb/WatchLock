#!/usr/bin/env bash
# 从应用图标源文件导出文档用的图片
#
# 用法：
#   ./Scripts/generate-icons.sh
#
# 唯一源：Resources/AppIcon.icon（Icon Composer 文档，可直接用 Icon Composer.app 打开编辑）
#   Assets/background.png   背景图层：1024 铺满、不透明的对角渐变
#   Assets/glyph.png        前景图层：白色锁形，透明底
#   icon.json               图层顺序 / 玻璃高光 / 阴影等
#
# 为什么这样拆（Apple HIG · App icons）：macOS 26 起图标由系统统一遮罩并生成高光，
# 设计稿应提供「方形、未遮罩」的图层；背景图层必须铺满且不透明；不要自己画圆角、阴影或留白。
# 打进 App 的 Assets.car / 回退 icns 由 build-app.sh 调 actool 现编，不入库。
#
# 本脚本只导出文档用的两张图：
#   docs/logo/AppIcon-master.png        1024 平面母版：背景 + 锁形直接合成，铺满、不透明、无圆角无留白
#   docs/ui-design/AppIcon-master.png   同上（设计稿 HTML 引用，用 CSS border-radius 模拟圆角）
#   docs/logo/AppIcon.png               512 系统效果图（ictool 渲染：系统圆角 + Liquid Glass 高光），README 展示用
#
# 说明：菜单栏状态图标不走位图资源，由 `UI/Design/MenuBarIcon.swift` 用代码绘制。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_DIR="$ROOT_DIR/Resources/AppIcon.icon"
MASTER="$ROOT_DIR/docs/logo/AppIcon-master.png"
MASTER_COPY="$ROOT_DIR/docs/ui-design/AppIcon-master.png"
PREVIEW="$ROOT_DIR/docs/logo/AppIcon.png"

ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
[[ -d "$ICON_DIR" ]] || { echo "缺少图标源：$ICON_DIR" >&2; exit 1; }
[[ -x "$ICTOOL" ]] || { echo "找不到 ictool（需要 Xcode 26 自带的 Icon Composer）：$ICTOOL" >&2; exit 1; }

python3 - "$ICON_DIR" "$MASTER" "$MASTER_COPY" <<'PY'
import sys
from pathlib import Path
from PIL import Image

icon_dir, *outs = map(Path, sys.argv[1:])
bg = Image.open(icon_dir / "Assets/background.png").convert("RGBA")
glyph = Image.open(icon_dir / "Assets/glyph.png").convert("RGBA")
assert bg.size == glyph.size == (1024, 1024), "图层必须是 1024×1024"
assert min(bg.getchannel("A").getdata()) == 255, "背景图层必须完全不透明（HIG：背景铺满且不透明）"
master = Image.alpha_composite(bg, glyph).convert("RGB")
for out in outs:
    master.save(out, optimize=True)
    print(f"已导出 {out}")
PY

"$ICTOOL" "$ICON_DIR" --export-image --output-file "$PREVIEW" \
  --platform macOS --rendition Default --width 512 --height 512 --scale 1 >/dev/null
echo "已导出 $PREVIEW"

echo "==> 完成"
