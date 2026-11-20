"""The roadmap machinery moved from phase-workflow to project-docs; nothing may still point at the old paths."""

import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# Built from parts so this file does not name the paths it forbids.
OLD = "phase-" + "workflow/"
MOVED = [OLD + name for name in (
    "roadmap.py",
    "ROADMAP-template.md",
    "KNOWN_ISSUES-template.md",
    "ENHANCEMENTS-template.md",
    "OPEN_QUESTIONS-template.md",
    "tests/roadmap.bats",
)]
# CHANGELOG and dated plans and specs record history, which keeps the old names.
HISTORY = ("CHANGELOG.md", "docs/superpowers/plans/", "docs/superpowers/specs/")


def offending():
    tracked = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z"],
        check=True, capture_output=True, text=True,
    ).stdout.split("\0")
    hits = []
    for rel in filter(None, tracked):
        if rel.startswith(HISTORY):
            continue
        try:
            text = (ROOT / rel).read_text()
        except (UnicodeDecodeError, FileNotFoundError):
            continue
        hits += [f"{rel}: {old}" for old in MOVED if old in text]
    return hits


class MovedPathsTest(unittest.TestCase):
    def test_no_old_roadmap_paths(self):
        self.assertEqual(offending(), [])


if __name__ == "__main__":
    unittest.main()
