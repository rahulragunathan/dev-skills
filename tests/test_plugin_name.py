"""The plugin's name lives in the manifests and the README, so renaming it is a small edit."""

import json
import re
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
}


def plugin_name():
    return json.loads((ROOT / ".claude-plugin/plugin.json").read_text())["name"]


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
        market = json.loads((ROOT / ".claude-plugin/marketplace.json").read_text())
        self.assertEqual([p["name"] for p in market["plugins"]], [plugin_name()])


if __name__ == "__main__":
    unittest.main()
