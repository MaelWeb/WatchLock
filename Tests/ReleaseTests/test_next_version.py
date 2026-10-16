import importlib.util
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("next_version", ROOT / "Scripts" / "next-version.py")
VERSION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERSION)


class NextVersionTests(unittest.TestCase):
    def test_patch_increment(self):
        self.assertEqual(VERSION.next_version(["v0.4.0"], "patch", "0.1.0"), "0.4.1")

    def test_minor_resets_patch(self):
        self.assertEqual(VERSION.next_version(["v0.4.9"], "minor", "0.1.0"), "0.5.0")

    def test_major_resets_minor_and_patch(self):
        self.assertEqual(VERSION.next_version(["v0.4.9"], "major", "0.1.0"), "1.0.0")

    def test_numeric_order_not_lexical_or_creation_order(self):
        tags = ["v0.9.9", "v1.10.0", "v1.2.0", "v1.9.99"]
        self.assertEqual(VERSION.next_version(tags, "patch", "0.1.0"), "1.10.1")

    def test_prerelease_and_unrelated_tags_are_ignored(self):
        tags = ["v9.0.0-beta.1", "v8.0.0+build", "release-7.0.0", "v1.2", "v01.2.3", "v0.4.0"]
        self.assertEqual(VERSION.next_version(tags, "patch", "0.1.0"), "0.4.1")

    def test_initial_version_is_used_without_stable_tags(self):
        self.assertEqual(VERSION.next_version(["v5.0.0-beta.1"], "patch", "0.1.0"), "0.1.1")
        self.assertEqual(VERSION.next_version([], "minor", "0.1.0"), "0.2.0")
        self.assertEqual(VERSION.next_version([], "major", "0.1.0"), "1.0.0")

    def test_invalid_initial_version_is_rejected(self):
        for version in ("invalid", "0.1", "00.1.0", "0.1.0-beta.1", "../0.1.0"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                VERSION.next_version([], "patch", version)

    def test_invalid_bump_is_rejected(self):
        with self.assertRaises(ValueError):
            VERSION.next_version(["v0.4.0"], "auto", "0.1.0")

    def test_rerun_reuses_annotated_tag_for_same_commit(self):
        tags = [("v0.4.1", "tag", "commit-a", "WatchLock release (run 42)")]
        self.assertEqual(VERSION.reusable_version(tags, "42", "commit-a"), "0.4.1")

    def test_other_run_and_lightweight_tags_are_not_reused(self):
        tags = [("v0.4.1", "tag", "commit-a", "WatchLock release (run 41)"),
                ("v0.4.2", "commit", "", "WatchLock release (run 42)")]
        self.assertIsNone(VERSION.reusable_version(tags, "42", "commit-a"))
        self.assertIsNone(VERSION.reusable_version(tags, None, "commit-a"))

    def test_rerun_commit_mismatch_is_rejected(self):
        tags = [("v0.4.1", "tag", "commit-b", "WatchLock release (run 42)")]
        with self.assertRaises(ValueError):
            VERSION.reusable_version(tags, "42", "commit-a")

    def test_duplicate_run_tags_are_rejected(self):
        tags = [("v0.4.1", "tag", "commit-a", "WatchLock release (run 42)"),
                ("v0.4.2", "tag", "commit-a", "WatchLock release (run 42)")]
        with self.assertRaises(ValueError):
            VERSION.reusable_version(tags, "42", "commit-a")

    def test_invalid_run_id_is_rejected(self):
        with self.assertRaises(ValueError):
            VERSION.reusable_version([], "../42", "commit-a")

    def test_resolver_reads_git_tags_and_plist(self):
        with tempfile.TemporaryDirectory(dir=ROOT) as directory:
            repo = Path(directory)
            (repo / "Resources").mkdir()
            with (repo / "Resources" / "Info.plist").open("wb") as handle:
                plistlib.dump({"CFBundleShortVersionString": "0.1.0"}, handle)
            result = subprocess.CompletedProcess([], 0, "v0.4.0\tcommit\t\tmessage\n")
            with patch.object(VERSION.subprocess, "run", return_value=result) as run:
                self.assertEqual(VERSION.resolve_version(repo, "patch"), "0.4.1")
            self.assertEqual(run.call_args.args[0][:3], ["git", "-C", str(repo)])

    def test_resolver_reuses_run_tag_without_reading_plist(self):
        tags = subprocess.CompletedProcess([], 0, "v0.4.1\ttag\tcommit-a\tWatchLock release (run 42)\n")
        head = subprocess.CompletedProcess([], 0, "commit-a\n")
        with patch.object(VERSION.subprocess, "run", side_effect=[tags, head]):
            self.assertEqual(VERSION.resolve_version(Path("missing-repo"), "patch", "42"), "0.4.1")


if __name__ == "__main__":
    unittest.main()
