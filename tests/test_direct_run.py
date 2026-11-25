"""test_plugin_name.py must test the release when it is run as a script, not only under discovery."""

import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parent.parent


def fixture_repo(tmp: pathlib.Path, manifest_version: str, changelog: str) -> pathlib.Path:
    """A git repository holding a copy of test_plugin_name.py and the files it reads."""
    (tmp / "tests").mkdir()
    (tmp / ".claude-plugin").mkdir()
    shutil.copy(ROOT / "tests/test_plugin_name.py", tmp / "tests/test_plugin_name.py")
    (tmp / ".claude-plugin/plugin.json").write_text(json.dumps({"name": "fixture-plugin", "version": manifest_version}))
    (tmp / ".claude-plugin/marketplace.json").write_text(json.dumps({"plugins": [{"name": "fixture-plugin"}]}))
    (tmp / "CHANGELOG.md").write_text(changelog)
    for args in (["init", "-q"], ["add", "-A"]):
        subprocess.run(["git", "-C", str(tmp), *args], check=True)
    return tmp


def run_directly(repo: pathlib.Path) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(repo / "tests/test_plugin_name.py")],
                          capture_output=True, text=True, cwd=repo)


class DirectRunTest(unittest.TestCase):
    def test_release_test_runs_when_the_file_runs_directly(self):
        # Fails if the release test is defined after unittest.main(), so a direct run skips it (KI-73).
        with tempfile.TemporaryDirectory() as tmp:
            repo = fixture_repo(pathlib.Path(tmp), "1.0.0", "# Changelog\n\n## [1.1.0] - 2026-11-23\n")
            result = run_directly(repo)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertIn("test_manifest_version_is_the_newest_changelog_release", result.stderr)

    def test_missing_release_heading_fails_as_an_assertion(self):
        # Fails if a CHANGELOG with no release heading raises TypeError instead of failing the test.
        with tempfile.TemporaryDirectory() as tmp:
            repo = fixture_repo(pathlib.Path(tmp), "1.0.0", "# Changelog\n\n## [Unreleased]\n")
            result = run_directly(repo)
            self.assertEqual(result.returncode, 1, result.stderr)
            self.assertNotIn("TypeError", result.stderr)
            self.assertIn("no release heading", result.stderr)


if __name__ == "__main__":
    unittest.main()
