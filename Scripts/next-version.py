#!/usr/bin/env python3
import argparse
import plistlib
import re
import subprocess
import sys
from pathlib import Path


VERSION_PATTERN = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
TAG_PATTERN = re.compile(r"v" + VERSION_PATTERN)


def next_version(tags, bump, initial_version):
    if bump not in ("patch", "minor", "major"):
        raise ValueError("发布类型必须为 patch、minor 或 major")
    versions = []
    for tag in tags:
        match = TAG_PATTERN.fullmatch(tag)
        if match:
            versions.append(tuple(int(part) for part in match.groups()))
    if versions:
        major, minor, patch = max(versions)
    else:
        match = re.fullmatch(VERSION_PATTERN, initial_version)
        if not match:
            raise ValueError("初始版本必须为 major.minor.patch，且不能包含前导零")
        major, minor, patch = (int(part) for part in match.groups())
    if bump == "major":
        major, minor, patch = major + 1, 0, 0
    elif bump == "minor":
        minor, patch = minor + 1, 0
    else:
        patch += 1
    return f"{major}.{minor}.{patch}"


def reusable_version(tag_info, run_id, commit):
    if not run_id:
        return None
    if not re.fullmatch(r"[1-9][0-9]*", run_id):
        raise ValueError("run-id 必须为正整数")
    message = f"WatchLock release (run {run_id})"
    matches = [row for row in tag_info if row[1] == "tag" and row[3] == message]
    if len(matches) > 1:
        raise ValueError("同一次流水线对应多个版本标签，拒绝自动发布")
    if not matches:
        return None
    tag, _, target, _ = matches[0]
    if not TAG_PATTERN.fullmatch(tag) or target != commit:
        raise ValueError("已有流水线标签的版本或目标提交不匹配，拒绝覆盖")
    return tag[1:]


def resolve_version(repo, bump, run_id=None):
    result = subprocess.run(
        ["git", "-C", str(repo), "for-each-ref",
         "--format=%(refname:strip=2)%09%(objecttype)%09%(*objectname)%09%(contents:subject)",
         "refs/tags"],
        check=True, capture_output=True, text=True,
    )
    tag_info = [line.split("\t", 3) for line in result.stdout.splitlines()]
    if run_id:
        commit = subprocess.run(
            ["git", "-C", str(repo), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        version = reusable_version(tag_info, run_id, commit)
        if version:
            return version
    with (repo / "Resources" / "Info.plist").open("rb") as handle:
        initial_version = plistlib.load(handle)["CFBundleShortVersionString"]
    return next_version((row[0] for row in tag_info), bump, initial_version)


def main():
    parser = argparse.ArgumentParser(description="从最高稳定版本标签递增版本；无标签时读取 Info.plist")
    parser.add_argument("bump", choices=("patch", "minor", "major"))
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--run-id", help="重跑时复用本次流水线已创建的标签")
    args = parser.parse_args()
    try:
        print(resolve_version(args.repo, args.bump, args.run_id))
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print(f"无法计算发布版本：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
