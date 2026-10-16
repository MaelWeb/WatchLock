#!/usr/bin/env bash
# 从品牌主图生成应用图标资源
#
# 用法：
#   ./Scripts/generate-icons.sh
#
# 产物（都进 git，构建时不再依赖本机的图像工具）：
#   Resources/AppIcon.icns          应用图标（Dock / Finder / 关于窗口）
#   Resources/MenuBarTemplate.png   菜单栏模板图标（黑色 + alpha，系统自动适配深色模式）
#
# 主图来源（AI 生成，如需重做请覆盖后重跑本脚本）：
#   docs/logo/AppIcon-master.png        1024 圆角方形 + 渐变底 + 白色 w 锁形
#   docs/logo/MenuBarTemplate-source.png 单色 w 锁形（浅底黑字或透明底黑字均可）
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="$ROOT_DIR/docs/logo/AppIcon-master.png"
TEMPLATE_SRC="$ROOT_DIR/docs/logo/MenuBarTemplate-source.png"
OUT_ICNS="$ROOT_DIR/Resources/AppIcon.icns"
OUT_TEMPLATE="$ROOT_DIR/Resources/MenuBarTemplate.png"

[[ -f "$MASTER" ]] || { echo "缺少主图：$MASTER" >&2; exit 1; }
[[ -f "$TEMPLATE_SRC" ]] || { echo "缺少菜单栏图源：$TEMPLATE_SRC" >&2; exit 1; }

python3 - "$MASTER" "$TEMPLATE_SRC" "$OUT_ICNS" "$OUT_TEMPLATE" <<'PY'
import shutil, subprocess, sys, tempfile
from pathlib import Path
from PIL import Image

master, template_src, out_icns, out_template = map(Path, sys.argv[1:5])
tmp = Path(tempfile.mkdtemp())
iconset = tmp / "AppIcon.iconset"
iconset.mkdir()

# --- AppIcon.icns ---
# macOS 需要的尺寸（含 @2x）。主图已经是 1024，统一用 LANCZOS 缩放。
sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (64, 1), (128, 1), (128, 2),
         (256, 1), (256, 2), (512, 1), (512, 2)]
src = Image.open(master).convert("RGBA")
for px, scale in sizes:
    side = px * scale
    name = f"icon_{px}x{px}{'@2x' if scale == 2 else ''}.png"
    src.resize((side, side), Image.LANCZOS).save(iconset / name)
# 1024（App Store / 高 DPI 用）
src.resize((1024, 1024), Image.LANCZOS).save(iconset / "icon_512x512@2x.png")
subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out_icns)], check=True)

# --- 菜单栏模板图标 ---
# 模板图必须是「黑色 + alpha」：系统按 alpha 着色，浅色/深色模式下自动反色。
# AI 出图可能是「白底黑字」也可能是「透明底黑字」，这里统一归一化：
#   覆盖率 = 1 - min(R,G,B)（白→0，黑→1），用它当 alpha，RGB 全置黑。
from PIL import ImageChops

# 44pt（菜单栏 @2x 的实际像素为 22×2）
tpl = Image.open(template_src).convert("RGBA").resize((44, 44), Image.LANCZOS)
a = tpl.getchannel("A")
# 先按原 alpha 合成到白底：这样「透明底黑字」和「白底黑字」两种情况归一。
white = Image.new("RGBA", tpl.size, (255, 255, 255, 255))
flattened = Image.alpha_composite(white, tpl).convert("RGB")
r, g, b = flattened.split()
# 覆盖率 = 1 - min(R,G,B)：白底→0（透明），黑字→1（不透明）
darkest = ImageChops.darker(ImageChops.darker(r, g), b)
alpha = ImageChops.invert(darkest)
if a.getextrema() != (255, 255):
    alpha = ImageChops.multiply(alpha, a)  # 原图已标注透明的保持透明
black = Image.new("L", tpl.size, 0)
Image.merge("RGBA", (black, black, black, alpha)).save(out_template)

print(f"已生成 {out_icns.relative_to(out_icns.parents[2])} 与 {out_template.name}")
shutil.rmtree(tmp, ignore_errors=True)
PY

echo "==> 完成"
echo "    $(du -h "$OUT_ICNS" | cut -f1)  $OUT_ICNS"
echo "    $(du -h "$OUT_TEMPLATE" | cut -f1)  $OUT_TEMPLATE"
