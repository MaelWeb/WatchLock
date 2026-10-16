import json
import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


class PackageLanguageModeTests(unittest.TestCase):
    def test_swift5_is_declared_at_package_level(self):
        result = subprocess.run(
            ["swift", "package", "--package-path", str(ROOT), "dump-package"],
            check=True,
            capture_output=True,
            text=True,
        )
        manifest = json.loads(result.stdout)
        self.assertEqual(
            manifest.get("swiftLanguageVersions"),
            ["5"],
            "Universal Xcode builds need a package-level Swift 5 declaration",
        )
        for target in manifest["targets"]:
            with self.subTest(target=target["name"]):
                language_settings = [
                    setting for setting in target.get("settings", [])
                    if "swiftLanguageMode" in setting["kind"]
                ]
                self.assertEqual(language_settings, [], "Targets should inherit the package language mode")


if __name__ == "__main__":
    unittest.main()
