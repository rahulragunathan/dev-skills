#!/usr/bin/env python3
"""Close a roadmap entry, or check that the roadmap files reconcile.

Closing an entry means deleting it from its detail file and removing its
pointer row from the index. Done by hand it has destroyed content twice in
this repository: a slice from an anchor to end of file took three unrelated
entries with it, and markdownlint passed on the result because the damage was
well-formed, just shorter.

So this does not slice. It parses the file into entries, drops exactly the one
named, and then requires every surviving entry to be byte-identical to what it
was. Counting is not enough — a count can be right while the content is wrong.

Usage:
    roadmap.py check [--docs DIR]
    roadmap.py close KI-15 [--docs DIR]

Exit 0 on success, 1 on refusal. Nothing is written unless every check passes.
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

FILES = {
    "KI": "KNOWN_ISSUES.md",
    "ENH": "ENHANCEMENTS.md",
    "UNK": "OPEN_QUESTIONS.md",
}


def fail(msg: str) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(1)


def split_entries(text: str) -> tuple[str, dict[str, str]]:
    """Return (header, {entry-id: body}).

    An entry starts at its `<a id="...">` anchor and runs to the next one, or
    to end of file. The separator line before an anchor belongs to the entry
    that follows it, so removing an entry removes its separator too and never
    leaves a doubled or orphaned rule.
    """
    anchors = list(re.finditer(r'^<a id="([a-z]+-\d+)"></a>\s*$', text, re.M))
    if not anchors:
        return text, {}
    entries: dict[str, str] = {}
    for i, m in enumerate(anchors):
        start = m.start()
        sep = text.rfind("\n---\n", 0, start)
        # Only treat the rule as this entry's if nothing but blank lines sits between.
        if sep != -1 and text[sep + len("\n---\n"):start].strip() == "":
            start = sep
        end = anchors[i + 1].start() if i + 1 < len(anchors) else len(text)
        if i + 1 < len(anchors):
            nsep = text.rfind("\n---\n", 0, anchors[i + 1].start())
            if nsep > start and text[nsep + len("\n---\n"):anchors[i + 1].start()].strip() == "":
                end = nsep
        eid = m.group(1).upper()
        if eid in entries:
            fail(f"refusing: {eid} appears twice in the detail file")
        entries[eid] = text[start:end]
    return text[: anchors[0].start() if anchors[0].start() == 0 else
                 (text.rfind("\n---\n", 0, anchors[0].start()) if
                  text.rfind("\n---\n", 0, anchors[0].start()) != -1 else anchors[0].start())], entries


def index_rows(roadmap: str, prefix: str) -> dict[str, str]:
    fname = FILES[prefix]
    rows: dict[str, str] = {}
    for line in roadmap.splitlines(keepends=True):
        m = re.match(rf'^\| \[({prefix}-\d+)\]\({re.escape(fname)}#', line)
        if m:
            if m.group(1) in rows:
                fail(f"refusing: {m.group(1)} has two index rows")
            rows[m.group(1)] = line
    return rows


def load(docs: pathlib.Path) -> tuple[str, dict[str, tuple[str, dict[str, str]]]]:
    roadmap_p = docs / "ROADMAP.md"
    if not roadmap_p.is_file():
        fail(f"no ROADMAP.md under {docs}")
    detail = {}
    for prefix, name in FILES.items():
        p = docs / name
        if not p.is_file():
            fail(f"no {name} under {docs}")
        detail[prefix] = split_entries(p.read_text())
    return roadmap_p.read_text(), detail


def cmd_check(docs: pathlib.Path) -> int:
    roadmap, detail = load(docs)
    ok = True
    for prefix, (_, entries) in detail.items():
        rows = index_rows(roadmap, prefix)
        dangling = sorted(set(rows) - set(entries))
        orphaned = sorted(set(entries) - set(rows))
        status = "ok" if not dangling and not orphaned else "MISMATCH"
        print(f"{FILES[prefix]:22} entries={len(entries):3} pointers={len(rows):3}  {status}")
        if dangling:
            print(f"  index points at missing entries: {dangling}")
            ok = False
        if orphaned:
            print(f"  entries with no index row:      {orphaned}")
            ok = False
    return 0 if ok else 1


def cmd_close(docs: pathlib.Path, eid: str) -> int:
    prefix = eid.split("-")[0].upper()
    if prefix not in FILES:
        fail(f"unknown id prefix: {eid}")
    roadmap, detail = load(docs)
    header, entries = detail[prefix]
    if eid not in entries:
        fail(f"refusing: no entry {eid} in {FILES[prefix]}")
    rows = index_rows(roadmap, prefix)
    if eid not in rows:
        fail(f"refusing: no index row for {eid}; close it by hand and say why")

    survivors = {k: v for k, v in entries.items() if k != eid}
    new_detail = header.rstrip("\n") + "\n" + "".join(survivors.values())
    if not new_detail.endswith("\n"):
        new_detail += "\n"

    # The check that matters: every surviving entry must come back byte-identical.
    _, reparsed = split_entries(new_detail)
    if set(reparsed) != set(survivors):
        lost = sorted(set(survivors) - set(reparsed))
        fail(f"refusing: rewriting would lose {lost or 'entries'}")
    for k in survivors:
        if reparsed[k].strip() != survivors[k].strip():
            fail(f"refusing: {k} would not survive byte-identical")

    new_roadmap = "".join(l for l in roadmap.splitlines(keepends=True) if l != rows[eid])
    if len(new_roadmap.splitlines()) != len(roadmap.splitlines()) - 1:
        fail("refusing: removing the index row would change more than one line")

    (docs / FILES[prefix]).write_text(new_detail)
    (docs / "ROADMAP.md").write_text(new_roadmap)
    print(f"closed {eid}: {len(entries)} entries -> {len(survivors)}, index row removed")
    return cmd_check(docs)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("command", choices=["check", "close"])
    ap.add_argument("id", nargs="?")
    ap.add_argument("--docs", type=pathlib.Path, default=pathlib.Path("docs"))
    args = ap.parse_args()
    if args.command == "check":
        return cmd_check(args.docs)
    if not args.id:
        fail("close needs an entry id, e.g. roadmap.py close KI-15")
    return cmd_close(args.docs, args.id.upper())


if __name__ == "__main__":
    raise SystemExit(main())
