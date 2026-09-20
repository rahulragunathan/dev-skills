#!/usr/bin/env python3
"""List Bats assertions and whether another command follows in their test.

Usage:
    python3 bats_assertions.py <file.bats>...

Test declarations and top-level functions delimit bodies; braces do not.
Heredoc content is skipped before looking for either boundaries or assertions.
Exit 0 on success, 1 when an input cannot be read or parsed.
"""
from __future__ import annotations

import argparse
from collections import deque
import pathlib
import re
import sys

TEST_START = re.compile(
    r'''^[ \t]*@test[ \t]+(?:"(?P<double>(?:\\.|[^"\\])*)"|'''
    r"'(?P<single>[^']*)')[ \t]+\{[ \t]*(?:#.*)?$"
)
TEST_LINE = re.compile(r"^[ \t]*@test(?:[ \t]|$)")
FUNCTION_START = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*[ \t]*\([ \t]*\)[ \t]*\{")

# Add assertion idioms here. Each pattern matches the start of a command.
ASSERTION_PATTERNS = {
    "[[ ]]": re.compile(r"^\[\[(?:\s|$)"),
}

# Consume quoted strings and escapes before interpreting shell punctuation.
# This keeps quoted semicolons and heredoc-looking text inside their command.
SHELL_PART = re.compile(
    r"""'[^']*' | "(?:\\.|[^"\\])*" | \\.
    | (?P<comment>(?<![^\s;|&])\#.*)
    | (?P<heredoc>(?<!<)<<(?!<)(?P<tabs>-?)[ \t]*
        (?:'(?P<single>[^']+)' | "(?P<double>[^"]+)"
        | (?P<bare>[^\s'";|&<>()]+)))
    | (?P<separator>;)
    """,
    re.X,
)


def fail(msg: str) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(1)


def split_commands(line: str) -> tuple[list[str], list[tuple[str, bool]]]:
    """Split command separators outside quotes and collect heredoc delimiters."""
    commands, heredocs = [], []
    start = 0
    for match in SHELL_PART.finditer(line):
        if match.group("comment") is not None:
            line = line[:match.start()]
            break
        if match.group("heredoc") is not None:
            delimiter = match.group("single") or match.group("double") or match.group("bare")
            heredocs.append((delimiter, bool(match.group("tabs"))))
        elif match.group("separator") is not None:
            command = line[start:match.start()].strip()
            if command:
                commands.append(command)
            start = match.end()
    command = line[start:].strip()
    if command:
        commands.append(command)
    return commands, heredocs


def test_rows(name: str, body: list[tuple[int, str]]) -> list[tuple[int, str, str]]:
    """Classify assertions after removing the test's trailing closing line."""
    if body and body[-1][1].strip() == "}":
        body = body[:-1]
    commands = [(number, command) for number, line in body
                for command in split_commands(line)[0]]
    return [(number, name, "final" if index == len(commands) - 1 else "mid")
            for index, (number, command) in enumerate(commands)
            if any(pattern.match(command) for pattern in ASSERTION_PATTERNS.values())]


def parse(text: str) -> list[tuple[int, str, str]]:
    """Return (line, test name, position) rows without interpreting brace depth."""
    rows = []
    name = None
    body = []
    pending = deque()
    for number, line in enumerate(text.splitlines(), 1):
        if pending:
            delimiter, strip_tabs, _ = pending[0]
            candidate = line.lstrip("\t") if strip_tabs else line
            if candidate == delimiter:
                pending.popleft()
            continue

        commands, heredocs = split_commands(line)
        pending.extend((delimiter, strip_tabs, number)
                       for delimiter, strip_tabs in heredocs)
        test = TEST_START.match(line)
        if TEST_LINE.match(line) and test is None:
            raise ValueError(f"line {number}: malformed @test declaration")
        if test or FUNCTION_START.match(line):
            if name is not None:
                rows.extend(test_rows(name, body))
            name = (test.group("double") if test.group("double") is not None
                    else test.group("single")) if test else None
            body = []
        elif name is not None and commands:
            body.append((number, line))

    if pending:
        delimiter, strip_tabs, opened = pending[0]
        raise ValueError(f"line {opened}: unterminated heredoc {delimiter!r}")
    if name is not None:
        rows.extend(test_rows(name, body))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", metavar="file.bats")
    args = parser.parse_args()
    # Collect before printing: a later file that fails to parse must not leave
    # a partial inventory on stdout for a caller to act on.
    output = []
    for filename in args.files:
        try:
            rows = parse(pathlib.Path(filename).read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError) as exc:
            fail(f"{filename}: {exc}")
        output.extend(f"{filename}\t{line}\t{name}\t{position}"
                      for line, name, position in rows)
    for row in output:
        print(row)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
