#!/usr/bin/env python3
"""Write one Results row into a pressure-test scenario file, by column name.

Both times a round's results were written by hand, a regex or an index matched
the wrong column and silently overwrote provenance: round 2 put condition text
into the skill column, round 3 put notes into the condition column. Neither was
caught by counting matches, because the count was right.

This addresses the cause rather than the instance. Columns are addressed by
their header text, every named column must exist, and the row is verified after
writing.

Usage:
    write_results.py <scenario.md> --run "With skill (round 3)" \
        --set "Model ID=\\`claude-opus-5\\`" --set "Date=2026-09-08" ...

    write_results.py <scenario.md> --show          print the table as name: value

Exit 0 on success, 1 on refusal. Nothing is written unless every check passes.
"""
from __future__ import annotations

import argparse
import pathlib
import sys


def split_row(line: str) -> list[str]:
    """Cells of a markdown table row, without the outer empties."""
    return [c.strip() for c in line.rstrip("\n").split("|")[1:-1]]


def join_row(cells: list[str]) -> str:
    return "| " + " | ".join(cells) + " |\n"


def find_table(lines: list[str]) -> tuple[int, list[str]]:
    """Index of the header line under '## Results', and its column names."""
    try:
        start = next(i for i, l in enumerate(lines) if l.strip() == "## Results")
    except StopIteration:
        sys.exit("no '## Results' section")
    for i in range(start, len(lines)):
        if lines[i].lstrip().startswith("| Run |"):
            return i, split_row(lines[i])
    sys.exit("no results table under '## Results'")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario", type=pathlib.Path)
    ap.add_argument("--run", help="value of the Run column identifying the row")
    ap.add_argument("--set", action="append", default=[], metavar="COLUMN=VALUE")
    ap.add_argument("--show", action="store_true")
    args = ap.parse_args()

    if not args.scenario.is_file():
        sys.exit(f"not a file: {args.scenario}")
    lines = args.scenario.read_text().splitlines(keepends=True)
    hdr_i, headers = find_table(lines)

    if args.show:
        for line in lines[hdr_i + 2:]:
            if not line.lstrip().startswith("|"):
                break
            for name, val in zip(headers, split_row(line)):
                print(f"{name}: {val}")
            print("---")
        return 0

    if not args.run:
        sys.exit("--run is required unless --show is given")

    updates: dict[str, str] = {}
    for pair in args.set:
        if "=" not in pair:
            sys.exit(f"--set needs COLUMN=VALUE, got: {pair}")
        col, val = pair.split("=", 1)
        col = col.strip()
        if col not in headers:
            sys.exit(f"no such column: {col!r}; columns are {headers}")
        if col in updates:
            sys.exit(f"column named twice: {col!r}")
        updates[col] = val
    if "|" in "".join(updates.values()):
        sys.exit("a cell value may not contain '|' — it would split the row")

    run_i = headers.index("Run")
    target = None
    for i in range(hdr_i + 2, len(lines)):
        if not lines[i].lstrip().startswith("|"):
            break
        cells = split_row(lines[i])
        if len(cells) == len(headers) and cells[run_i] == args.run:
            target = i
            break
    if target is None:
        sys.exit(f"no row whose Run column is {args.run!r}")

    cells = split_row(lines[target])
    for col, val in updates.items():
        cells[headers.index(col)] = val
    new_line = join_row(cells)

    # Verify before writing: the row must still have exactly the right shape,
    # and every column not named must be byte-identical to what was there.
    check = split_row(new_line)
    if len(check) != len(headers):
        sys.exit(f"refusing: row would have {len(check)} cells, table has {len(headers)}")
    before = split_row(lines[target])
    for i, name in enumerate(headers):
        if name not in updates and check[i] != before[i]:
            sys.exit(f"refusing: column {name!r} changed but was not named")

    lines[target] = new_line
    args.scenario.write_text("".join(lines))
    print(f"updated {len(updates)} column(s) in row {args.run!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
