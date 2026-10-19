#!/usr/bin/env python3
"""本地化文案维护脚本（FR-15）。

源码里的中文字面量就是键（开发语言 = zh-Hans）：
  - SwiftUI:  Text("中文") / Button("中文") / .help("中文") 等
  - 其他:     String(localized: "中文")

用法：
  python3 Scripts/localization.py check   # 校验：源码键 ↔ en 译文是否一致（CI / 提交前运行）
  python3 Scripts/localization.py sync    # 由源码键重新生成 zh-Hans（恒等映射），并列出 en 缺失 / 多余的键
  python3 Scripts/localization.py missing # 只打印 en 缺失的键（便于补翻译）

提取使用编译器自带的 -emit-localized-strings，格式占位符（%@ / %lld / %.1f）因此与运行时一致，
不靠正则猜类型。英文译文由人工维护在 Resources/Localization/en.lproj/Localizable.strings。
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
LOC_DIR = os.path.join(ROOT, "Resources", "Localization")
EN_FILE = os.path.join(LOC_DIR, "en.lproj", "Localizable.strings")
ZH_FILE = os.path.join(LOC_DIR, "zh-Hans.lproj", "Localizable.strings")
CJK = re.compile(r"[\u4e00-\u9fff]")
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:\.\d+)?(?:ll|l|h)?[@dDuUfFsSxXcC]")


def escape(text):
    return (text.replace("\\", "\\\\").replace('"', '\\"')
            .replace("\n", "\\n").replace("\t", "\\t"))


def unescape(text):
    out, i = [], 0
    while i < len(text):
        c = text[i]
        if c == "\\" and i + 1 < len(text):
            n = text[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


STRING_LINE = re.compile(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$')


def read_strings(path):
    table = {}
    if not os.path.exists(path):
        return table
    with open(path, encoding="utf8") as handle:
        for number, line in enumerate(handle, 1):
            stripped = line.strip()
            if not stripped or stripped.startswith("/*") or stripped.startswith("//"):
                continue
            match = STRING_LINE.match(stripped)
            if not match:
                raise SystemExit(f"{path}:{number}: 无法解析：{stripped[:80]}")
            table[unescape(match.group(1))] = unescape(match.group(2))
    return table


def write_strings(path, table, header):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf8") as handle:
        handle.write(f"/* {header} */\n\n")
        for key in table:
            handle.write(f'"{escape(key)}" = "{escape(table[key])}";\n')


def extract_keys():
    """编译一遍并收集 .stringsdata 里的键；返回按源码顺序去重的 key 列表。"""
    with tempfile.TemporaryDirectory(prefix="wl_loc_") as tmp:
        out_dir = os.path.join(tmp, "out")
        os.makedirs(out_dir)
        command = [
            "swift", "build", "--package-path", ROOT,
            "--scratch-path", os.path.join(tmp, "build"),
            "-Xswiftc", "-emit-localized-strings",
            "-Xswiftc", "-emit-localized-strings-path", "-Xswiftc", out_dir,
        ]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode != 0:
            sys.stderr.write(result.stdout + result.stderr)
            raise SystemExit("编译失败，无法提取文案")
        keys = {}
        for path in sorted(glob.glob(os.path.join(out_dir, "*.stringsdata"))):
            with open(path, encoding="utf8") as handle:
                data = json.load(handle)
            for entries in data.get("tables", {}).get("Localizable", []):
                keys.setdefault(entries["key"], data["source"])
        return list(keys)


def placeholders(text):
    return sorted(PLACEHOLDER.findall(text))


def compare(keys, en):
    cjk_keys = [k for k in keys if CJK.search(k)]
    missing = [k for k in cjk_keys if k not in en]
    obsolete = [k for k in en if k not in keys]
    mismatched = [k for k in cjk_keys if k in en and placeholders(k) != placeholders(en[k])]
    cjk_in_en = [k for k, v in en.items() if CJK.search(v)]
    return missing, obsolete, mismatched, cjk_in_en


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "check"
    if command not in ("check", "sync", "missing"):
        raise SystemExit(__doc__)
    keys = extract_keys()
    en = read_strings(EN_FILE)
    missing, obsolete, mismatched, cjk_in_en = compare(keys, en)

    if command == "sync":
        zh = {k: k for k in keys if CJK.search(k)}
        write_strings(ZH_FILE, zh, "zh-Hans：开发语言，键即译文（由 Scripts/localization.py sync 生成，勿手改）")
        print(f"zh-Hans：写入 {len(zh)} 条")

    if command == "missing":
        for key in missing:
            print(key)
        return

    problems = False
    for title, items in (
        ("en 缺少译文", missing),
        ("en 中有源码已不再使用的键", obsolete),
        ("占位符与源文不一致", mismatched),
        ("en 译文里仍含中文", cjk_in_en),
    ):
        if items:
            problems = True
            print(f"[{title}] {len(items)} 条")
            for item in items[:30]:
                print("  -", item)
    print(f"源码键 {len([k for k in keys if CJK.search(k)])} 条，en 译文 {len(en)} 条")
    if command == "check" and problems:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
