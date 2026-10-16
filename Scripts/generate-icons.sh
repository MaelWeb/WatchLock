#!/usr/bin/env bash
# 从品牌主图生成应用图标资源
#
# 用法：
#   ./Scripts/generate-icons.sh
#
# 产物（进 git，构建时不再依赖本机的图像工具）：
#   Resources/AppIcon.icns   应用图标（Dock / Finder / 关于窗口）
#
# 主图来源（AI 生成，如需重做请覆盖后重跑本脚本）：
#   docs/logo/AppIcon-master.png   1024 圆角方形 + 渐变底 + 白色 w 锁形
#
# 说明：菜单栏状态图标不走位图资源，由 `UI/Design/MenuBarIcon.swift` 用代码绘制。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="$ROOT_DIR/docs/logo/AppIcon-master.png"
OUT_ICNS="$ROOT_DIR/Resources/AppIcon.icns"

[[ -f "$MASTER" ]] || { echo "缺少主图：$MASTER" >&2; exit 1; }

python3 - "$MASTER" "$OUT_ICNS" <<'PY'
import shutil, subprocess, sys, tempfile
from pathlib import Path
from PIL import Image

master, out_icns = map(Path, sys.argv[1:3])
tmp = Path(tempfile.mkdtemp())
iconset = tmp / "AppIcon.iconset"
iconset.mkdir()

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

print(f"已生成 {out_icns.name}")
shutil.rmtree(tmp, ignore_errors=True)
PY

echo "==> 完成"
echo "    $(du -h "$OUT_ICNS" | cut -f1)  $OUT_ICNS"
