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
    # An empty cell is one space, not two. "|  |" trips markdownlint's compact
    # table style, and a table the linter rejects is a table nobody re-reads.
    return "|" + "|".join(f" {c} " if c else " " for c in cells) + "|\n"


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
    ap.add_argument("--add", action="store_true",
                    help="append a new row instead of updating an existing one")
    ap.add_argument("--add-column", metavar="NAME",
                    help="append a column, empty in every existing row")
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

    if args.add_column:
        name = args.add_column.strip()
        if not name:
            sys.exit("--add-column needs a name")
        if "|" in name or "\n" in name or "\r" in name:
            sys.exit("a column name may not contain '|' or a line break")
        if name in headers:
            sys.exit(f"refusing: a column named {name!r} already exists")

        end = hdr_i + 2
        while end < len(lines) and lines[end].lstrip().startswith("|"):
            end += 1
        before = [split_row(l) for l in lines[hdr_i + 2:end]]

        lines[hdr_i] = join_row(headers + [name])
        lines[hdr_i + 1] = join_row(["---"] * (len(headers) + 1))
        for i in range(hdr_i + 2, end):
            lines[i] = join_row(split_row(lines[i]) + [""])

        # Every existing cell must survive in place. A column added by hand
        # shifts the row by one and the damage reads as well-formed markdown.
        after = [split_row(l) for l in lines[hdr_i + 2:end]]
        if len(after) != len(before):
            sys.exit("refusing: the row count changed")
        for old_cells, new_cells in zip(before, after):
            if new_cells[:-1] != old_cells or new_cells[-1] != "":
                sys.exit("refusing: an existing cell moved or changed")
        if len(split_row(lines[hdr_i])) != len(split_row(lines[hdr_i + 1])):
            sys.exit("refusing: header and separator would disagree")

        args.scenario.write_text("".join(lines))
        print(f"added column {name!r} to {len(after)} row(s)")
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
    # A newline ends the row early and leaves its remainder outside the table,
    # which markdownlint will not flag because what is left is still well formed.
    if any(("\n" in v) or ("\r" in v) for v in updates.values()):
        sys.exit("a cell value may not contain a line break — it would end the row")

    # A duplicate Run value makes every later update ambiguous, and the writer
    # resolves the ambiguity by silently taking the first match.
    if "Run" in updates:
        run_col = headers.index("Run")
        for i in range(hdr_i + 2, len(lines)):
            if not lines[i].lstrip().startswith("|"):
                break
            cells = split_row(lines[i])
            if len(cells) == len(headers) and cells[run_col] == updates["Run"] \
                    and cells[run_col] != args.run:
                sys.exit(f"refusing: a row for {updates['Run']!r} already exists")

    run_i = headers.index("Run")

    if args.add:
        end = hdr_i + 2
        while end < len(lines) and lines[end].lstrip().startswith("|"):
            if split_row(lines[end])[run_i] == args.run:
                sys.exit(f"refusing: a row for {args.run!r} already exists; "
                         f"drop --add to update it")
            end += 1
        cells = ["" for _ in headers]
        cells[run_i] = args.run
        for col, val in updates.items():
            cells[headers.index(col)] = val
        new_line = join_row(cells)
        if len(split_row(new_line)) != len(headers):
            sys.exit("refusing: the new row would not match the table's shape")
        before_rows = lines[hdr_i + 2:end]
        lines.insert(end, new_line)
        # The rows already there are the record; adding to it must not touch them.
        after_rows = [l for l in lines[hdr_i + 2:end]]
        if after_rows != before_rows:
            sys.exit("refusing: adding the row would change an existing one")
        args.scenario.write_text("".join(lines))
        print(f"added row {args.run!r} with {len(updates)} column(s) set")
        return 0

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
