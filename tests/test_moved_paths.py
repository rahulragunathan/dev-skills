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
HISTORY_DIRS = ("docs/superpowers/plans/", "docs/superpowers/specs/")


def offending():
    tracked = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z"],
        check=True, capture_output=True, text=True,
    ).stdout.split("\0")
    hits = []
    for rel in filter(None, tracked):
        if rel == "CHANGELOG.md" or rel.startswith(HISTORY_DIRS):
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

    def test_the_files_are_at_their_new_paths_only(self):
        # Fails if a file moves back, which the reference scan above cannot see.
        new = [p.replace(OLD, "project-docs/") for p in MOVED]
        self.assertEqual([p for p in MOVED if (ROOT / "skills" / p).exists()], [])
        self.assertEqual([p for p in new if not (ROOT / "skills" / p).exists()], [])


if __name__ == "__main__":
    unittest.main()
