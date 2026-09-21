#!/usr/bin/env python3
"""List Bats assertions as load-bearing (final) or unguarded before more commands (mid).

Usage:
    python3 bats_assertions.py <file.bats>...

Test declarations and top-level functions delimit bodies; braces do not.
Heredoc content is skipped before looking for either boundaries or assertions.
An explicit trailing ``|| false`` makes an assertion final wherever it sits.
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
    r"'(?P<single>[^']*)')[ \t]+\{(?P<body>.*)$"
)
TEST_LINE = re.compile(r"^[ \t]*@test(?:[ \t]|$)")
FUNCTION_START = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*[ \t]*\([ \t]*\)[ \t]*\{")

# Add assertion idioms here. Each pattern matches the start of a command.
ASSERTION_PATTERNS = {
    "[[ ]]": re.compile(r"^\[\[(?:\s|$)"),
}
EXPLICIT_FAILURE = re.compile(r"\]\]\s*\|\|\s*false$")

# Consume quoted strings and escapes before interpreting shell punctuation.
# This keeps quoted semicolons and heredoc-looking text inside their command.
SHELL_PART = re.compile(
    r"""'[^']*' | "(?:\\.|[^"\\])*" | \\.
    | (?P<comment>(?<![^\s;|&])\#.*)
    | (?P<arithmetic>\$?\(\() | (?P<paren>[()])
    | (?P<heredoc>(?<!<)<<(?!<)(?P<tabs>-?)[ \t]*
        (?:'(?P<single>[^']+)' | "(?P<double>[^"]+)"
        | (?P<bare>[^\s'";|&<>()]+)))
    | (?P<separator>;)
    """,
    re.X,
)


def split_commands(line: str) -> tuple[list[str], list[tuple[str, bool]]]:
    """Split command separators outside quotes and collect heredoc delimiters."""
    commands, heredocs = [], []
    start = 0
    arithmetic_depth = 0
    for match in SHELL_PART.finditer(line):
        if match.group("arithmetic") is not None:
            arithmetic_depth += 2
            continue
        if arithmetic_depth:
            # In arithmetic, << shifts a value; it does not open a heredoc.
            if match.group("paren") == "(":
                arithmetic_depth += 1
            elif match.group("paren") == ")":
                arithmetic_depth -= 1
            continue
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
    """Classify assertions after removing the test's trailing closing brace."""
    logical_body = []
    continued = False
    for number, line in body:
        if continued:
            number, previous = logical_body.pop()
            line = previous + line
        continued = line.endswith("\\")
        logical_body.append((number, line[:-1] if continued else line))
    commands = [(number, command) for number, line in logical_body
                for command in split_commands(line)[0]]
    if commands and commands[-1][1] == "}":
        commands = commands[:-1]
    return [(number, name, "final" if index == len(commands) - 1
             or EXPLICIT_FAILURE.search(command) else "mid")
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
            body = [(number, test.group("body"))] if test else []
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
    # Keep successful files in argument order and report every failure.
    output = []
    failed = False
    for filename in args.files:
        try:
            rows = parse(pathlib.Path(filename).read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError) as exc:
            print(f"{filename}: {exc}", file=sys.stderr)
            failed = True
            continue
        output.extend(f"{filename}\t{line}\t{name}\t{position}"
                      for line, name, position in rows)
    for row in output:
        print(row)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
