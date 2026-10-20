"""发布配置的静态约束：保证产物会采用系统的 Liquid Glass 材质。

依据（Apple 官方文档）：
- 《Adopting Liquid Glass》：用最新 SDK 构建，标准组件（含 popover）才自动采用新材质。
- 《UIDesignRequiresCompatibility》：设为 YES 会强制退回旧外观，仅供临时过渡。
"""
import plistlib
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"
INFO_PLIST = ROOT / "Resources" / "Info.plist"
BUILD_APP = ROOT / "scripts" / "build-app.sh"
VERIFY_SCRIPT = ROOT / "scripts" / "verify-liquid-glass-sdk.sh"


class LiquidGlassReleaseTests(unittest.TestCase):
    def test_build_job_runs_on_a_macos_26_or_newer_runner(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        # 只看 build 作业：release 作业跑在 ubuntu 上，与 SDK 无关。
        build_block = text.split("jobs:", 1)[1].split("\n  release:", 1)[0]
        labels = re.findall(r"^\s*runs-on:\s*(\S+)", build_block, flags=re.MULTILINE)
        self.assertEqual(len(labels), 1, f"build 作业应只有一个 runs-on：{labels}")
        match = re.fullmatch(r"macos-(\d+)(?:-.+)?", labels[0])
        self.assertIsNotNone(match, f"build 作业必须是 macOS runner：{labels[0]}")
        self.assertGreaterEqual(
            int(match.group(1)), 26,
            "runner 低于 macos-26 会链接旧 SDK，App 不会采用系统 Liquid Glass 材质",
        )

    def test_workflow_verifies_linked_sdk_after_building(self):
        text = WORKFLOW.read_text(encoding="utf-8")
        build_at = text.index("build-dmg.sh")
        verify_at = text.index("verify-liquid-glass-sdk.sh")
        self.assertLess(build_at, verify_at, "SDK 校验必须在构建之后执行")
        self.assertTrue(VERIFY_SCRIPT.exists())

    def test_compatibility_key_is_not_forced_on(self):
        # 键「缺省」才是链接最新 SDK 时的默认；设为 YES 会强制退回旧外观。
        for path in (INFO_PLIST, BUILD_APP):
            with self.subTest(path=path.name):
                content = path.read_text(encoding="utf-8")
                self.assertNotIn(
                    "UIDesignRequiresCompatibility", content,
                    "不要设置该键：它会让系统按旧 SDK 外观渲染，等于放弃玻璃材质",
                )

    def test_deployment_target_stays_compatible_with_older_macos(self):
        # 升级 SDK 不等于抬高最低系统：macOS 14/15 用户仍要能运行（外观保持旧样式）。
        with INFO_PLIST.open("rb") as handle:
            plist = plistlib.load(handle)
        major = int(str(plist["LSMinimumSystemVersion"]).split(".")[0])
        self.assertLessEqual(major, 14, "最低系统被抬高会让旧系统用户无法升级")


if __name__ == "__main__":
    unittest.main()
