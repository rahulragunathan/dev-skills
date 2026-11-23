#!/usr/bin/env python3
"""Read one value from the phase record's first table.

Usage:
    git show HEAD:docs/PHASE_RECORD.md | phase-record.py get KEY

The first table outside fenced code is this repository's phase. It must have a
`Key | Value` header and a delimiter row, and two cells in every row; KEY must
appear in it exactly once. A table further down, such as a companion
repository's, is never read. Enclosing backticks are stripped from the key and
the value.

Exit 0 and print the value; exit 1 with the reason on stderr; exit 2 on usage.
"""
import re
import sys

FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
DELIMITER = re.compile(r"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$")


def cells(line: str) -> list[str]:
    inner = line.strip()
    inner = inner[1:] if inner.startswith("|") else inner
    inner = inner[:-1] if inner.endswith("|") else inner
    return [c.strip() for c in inner.split("|")]


def unticked(text: str) -> str:
    """A cell that is one code span, without its backticks; any other cell as it is."""
    whole_span = len(text) > 1 and text[0] == text[-1] == "`" and "`" not in text[1:-1]
    return text[1:-1] if whole_span else text


def first_table(lines: list[str]) -> list[list[str]]:
    fence = None
    for i, line in enumerate(lines):
        m = FENCE.match(line)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not line[m.end():].strip():
                fence = None
            continue
        if m:
            fence = m.group(1)
            continue
        if line.lstrip().startswith("|") and i + 1 < len(lines) and DELIMITER.match(lines[i + 1].strip()):
            if cells(line) != ["Key", "Value"]:
                raise ValueError("the first table is not a Key | Value table")
            rows = []
            for row in lines[i + 2:]:
                if not row.lstrip().startswith("|"):
                    break
                parts = cells(row)
                if len(parts) != 2:
                    raise ValueError(f"a row of the first table does not have two cells: {row.strip()}")
                rows.append([unticked(p) for p in parts])
            return rows
    raise ValueError("the record has no table")


def main(argv: list[str]) -> int:
    if len(argv) != 3 or argv[1] != "get":
        print(__doc__, file=sys.stderr)
        return 2
    key = argv[2]
    # Read everything, so a producer upstream never dies of SIGPIPE.
    lines = sys.stdin.read().splitlines()
    try:
        values = [v for k, v in first_table(lines) if k == key]
    except ValueError as exc:
        print(f"phase-record.py: {exc}", file=sys.stderr)
        return 1
    if len(values) != 1:
        problem = "is missing from" if not values else "appears more than once in"
        print(f"phase-record.py: {key} {problem} the first table", file=sys.stderr)
        return 1
    print(values[0])
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
