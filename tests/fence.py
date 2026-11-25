"""Select one ```bash fence from a SKILL.md by its `# fence: <name>` marker line.

The suites that execute documented fences used to pick them by a substring of
their code, so rewriting a fence silently broke the selector. A marker names the
fence's purpose, and exactly one fence may carry it.

Usage: fence.py <SKILL.md> <name>    prints the fence body; exit 1 unless one matches
"""
import pathlib
import re
import sys

FENCE = re.compile(r'^([ \t]*)```bash\n(.*?)^\1```', re.S | re.M)


def fence(skill, name: str) -> str:
    text = pathlib.Path(skill).read_text()
    found = [m.group(2) for m in FENCE.finditer(text)
             if m.group(2).lstrip().startswith(f"# fence: {name}\n")]
    if len(found) != 1:
        raise SystemExit(f"fence.py: {len(found)} fences marked '{name}' in {skill}")
    return found[0]


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    sys.stdout.write(fence(sys.argv[1], sys.argv[2]))
