"""The plugin's name lives in the manifests and the README, so renaming it is a small edit."""

import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# CHANGELOG records past releases under the name they shipped with; a rename never edits it.
ALLOWED = {
    ".claude-plugin/plugin.json",
    ".claude-plugin/marketplace.json",
    "README.md",
    "CHANGELOG.md",
    # The phase record holds the repository identity the merge cycle reads back.
    "docs/PHASE_RECORD.md",
}


def plugin_name():
    return json.loads((ROOT / ".claude-plugin/plugin.json").read_text())["name"]


def marketplace():
    return json.loads((ROOT / ".claude-plugin/marketplace.json").read_text())


def files_naming(name):
    tracked = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z"],
        check=True, capture_output=True, text=True,
    ).stdout.split("\0")
    word = re.compile(rf"(?<![\w-]){re.escape(name)}(?![\w-])")
    hits = []
    for rel in filter(None, tracked):
        try:
            text = (ROOT / rel).read_text()
        except (UnicodeDecodeError, FileNotFoundError):
            continue
        if word.search(text):
            hits.append(rel)
    return hits


class PluginNameTest(unittest.TestCase):
    def test_name_appears_only_in_allowed_files(self):
        stray = sorted(set(files_naming(plugin_name())) - ALLOWED)
        self.assertEqual(stray, [], f"plugin name '{plugin_name()}' found outside {sorted(ALLOWED)}")

    def test_marketplace_lists_the_plugin_by_its_manifest_name(self):
        market = marketplace()
        self.assertEqual([p["name"] for p in market["plugins"]], [plugin_name()])


class ReleaseVersionTest(unittest.TestCase):
    def test_manifest_version_is_the_newest_changelog_release(self):
        # Fails if a release is prepared in CHANGELOG while plugin.json keeps
        # the old version, which is the one the installer reads (ENH-35).
        heading = re.search(r"^## \[(\d+\.\d+\.\d+)\]", (ROOT / "CHANGELOG.md").read_text(), re.M)
        self.assertIsNotNone(heading, "CHANGELOG.md has no release heading")
        manifest = json.loads((ROOT / ".claude-plugin/plugin.json").read_text())["version"]
        self.assertEqual(manifest, heading[1])


class DrawioSkillNameTest(unittest.TestCase):
    def test_drawio_is_named_as_the_plugin_skill(self):
        # Fails if a skill or doc still points at the loose drawio skill's install path, or
        # names "the drawio skill" instead of the plugin's drawio:create-diagram.
        docs = [*ROOT.glob("skills/*/SKILL.md"), ROOT / "README.md", ROOT / "AGENTS.md",
                ROOT / "docs/ARCHITECTURE.md", ROOT / "docs/build_architecture.py"]
        bare = re.compile(r"(?i)(`drawio` skill|the drawio skill|drives the drawio skill)")
        for path in docs:
            text = path.read_text()
            rel = path.relative_to(ROOT)
            self.assertNotIn("~/.claude/skills/drawio", text, f"{rel} names the old path")
            self.assertIsNone(bare.search(text), f"{rel} names a bare drawio skill")


class ManifestValidTest(unittest.TestCase):
    def test_marketplace_entry_carries_no_version(self):
        # Fails if marketplace.json gains a version, a second source that can hide a bump.
        market = marketplace()
        self.assertNotIn("version", market["plugins"][0])

    def test_claude_validates_both_manifests(self):
        # Fails if Claude Code rejects either manifest.
        claude = shutil.which("claude")
        if not claude:
            self.skipTest("claude is not installed")
        for name in ("plugin.json", "marketplace.json"):
            with self.subTest(name):
                run = subprocess.run(
                    [claude, "plugin", "validate", str(ROOT / ".claude-plugin" / name)],
                    capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=120,
                )
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

# Below every test class, so a direct run collects them all (KI-73).
if __name__ == "__main__":
    unittest.main()
