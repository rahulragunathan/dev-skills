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
import collections
import os
import tempfile
import shutil
import pathlib
import re
import sys
import signal

FILES = {
    "KI": "KNOWN_ISSUES.md",
    "ENH": "ENHANCEMENTS.md",
    "UNK": "OPEN_QUESTIONS.md",
}
FENCE = re.compile(r'^ {0,3}(`{3,}|~{3,})(.*)$')
LINK = re.compile(
    r'\[[^\[\]\n]*\]\(\s*(?:<([^<>\n]*)>|([^()<>\s]*))'
    r'(?:\s+(?:"[^"]*"|\'[^\']*\'|\([^()]*\)))?\s*\)')
LOOSE = re.compile(r'\]\s*\(')
FRAGMENT = re.compile(r'(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)', re.S)
FIELD = re.compile(r'\*\*[^*\n]+:\*\*')
LINE_ANCHOR = re.compile(r'#L\d+')
WHERE = "**Where:**"
Ref = collections.namedtuple("Ref", "target fragment")


def fail(msg: str) -> None:
    print(msg, file=sys.stderr)
    raise SystemExit(1)


def _entry_start(text: str, anchor) -> int:
    """Where an entry begins: at its separator rule when only blank lines sit
    between the two, otherwise at the anchor itself. One rule, one place, so
    the header slice and the entry slice can never disagree about it."""
    start = anchor.start()
    sep = text.rfind("\n---\n", 0, start)
    if sep != -1 and text[sep + len("\n---\n"):start].strip() == "":
        return sep
    return start


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
        start = _entry_start(text, m)
        end = (_entry_start(text, anchors[i + 1]) if i + 1 < len(anchors)
               else len(text))
        eid = m.group(1).upper()
        if eid in entries:
            fail(f"refusing: {eid} appears twice in the detail file")
        entries[eid] = text[start:end]
    # The header ends exactly where the first entry begins. Computing that
    # boundary twice, by two different rules, left prose between the last rule
    # and the first anchor belonging to neither slice — so it vanished on the
    # next write.
    first_start = min(_entry_start(text, m) for m in [anchors[0]])
    return text[:first_start], entries


def index_rows(roadmap: str, prefix: str) -> dict[str, dict]:
    """{entry-id: {"line": the row, "anchor": what the link actually targets}}.

    The anchor is kept because comparing displayed IDs alone let a row point at
    a heading that does not exist: the table looked reconciled and the link
    went nowhere.
    """
    rows: dict[str, dict] = {}
    headers = []
    for line in roadmap.splitlines(keepends=True):
        cells = [c.strip() for c in line.strip().split("|")[1:-1]]
        if cells and cells[0] == "ID":
            headers = cells
        m = re.match(rf'^\|\s*\[?({prefix}-\d+)\b', line)
        if m:
            if not line.rstrip().endswith("|") or not headers or len(cells) != len(headers):
                fail("refusing: malformed index row: " + line.strip())
            eid = m.group(1)
            if eid in rows:
                fail(f"refusing: {eid} has two index rows")
            link = re.fullmatch(r'\[([^]]+)\]\(([^#)]+)#([^)]*)\)', cells[0])
            rows[eid] = {"line": line, "anchor": link[3] if link else "",
                         "filename": link[2] if link else "",
                         "cells": dict(zip(headers, cells))}

    return rows


def reconcile(docs: pathlib.Path, proposed: dict[str, str] | None = None):
    """Check the index against the detail files. `proposed` replaces a file's
    text in memory, so a change can be reconciled before anything is written."""
    proposed = proposed or {}
    def text_of(name):
        return proposed[name] if name in proposed else (docs / name).read_text()

    roadmap = text_of("ROADMAP.md")
    ok, problems = True, []
    for prefix, name in FILES.items():
        _, entries = split_entries(text_of(name))
        rows = index_rows(roadmap, prefix)
        dangling = sorted(set(rows) - set(entries))
        orphaned = sorted(set(entries) - set(rows))
        wrong = sorted(e for e in set(rows) & set(entries)
                       if rows[e]["anchor"] != e.lower())
        destinations = [e for e in rows if rows[e]["filename"] != name]
        status = "ok" if not (dangling or orphaned or wrong or destinations) else "MISMATCH"
        problems.append(f"{name:22} entries={len(entries):3} pointers={len(rows):3}  {status}")
        if dangling:
            problems.append(f"  index points at missing entries: {dangling}"); ok = False
        if orphaned:
            problems.append(f"  entries with no index row:      {orphaned}"); ok = False
        if destinations:
            problems.append(f"  wrong destination: {destinations}"); ok = False
        fields = {"KI": ["Severity", "Likelihood"], "ENH": ["Priority"], "UNK": ["Kind"]}[prefix]
        ratings = {}
        for eid, body in entries.items():
            ratings[eid] = {}
            for field in fields:
                match = re.search(r'\*\*' + field + r':\*\*\s*([^\n·]+)', body)
                val = match[1].strip() if match else ""
                ratings[eid][field] = val
                if eid in rows and (not val or rows[eid]["cells"].get(field) != val):
                    problems.append(f"  rating mismatch: {eid} {field}"); ok = False
        ranks = {"Critical": 0, "High": 1, "Medium": 2, "Low": 3,
                 "Almost always": 0, "Likely": 1, "Rare": 2}
        if prefix != "UNK":
            for label, ids in [("detail", entries), ("index", rows)]:
                keys = [tuple(ranks.get(ratings[e][f], 99) for f in fields)
                        for e in ids if e in ratings]
                if keys != sorted(keys) or any(99 in k for k in keys):
                    problems.append(f"  rating order invalid: {label}"); ok = False
        if wrong:
            detail = [f"{e} -> #{rows[e]['anchor']}" for e in wrong]
            problems.append(f"  index rows pointing at the wrong anchor: {detail}"); ok = False
    return ok, problems


def _fenced_lines(text: str) -> list[bool]:
    """Keep nested, shorter fences from hiding the references after a block.

    Only the opening character repeated at least as many times, followed by
    whitespace alone, closes the block. Backticks in an info string instead
    make the apparent opening fence ordinary text.
    """
    flags, opened = [], None
    for line in text.splitlines():
        match = FENCE.match(line)
        if opened is None:
            if match and (match[1][0] == "~" or "`" not in match[2]):
                opened = match[1]
            flags.append(opened is not None)
        else:
            flags.append(True)
            if (match and match[1][0] == opened[0]
                    and len(match[1]) >= len(opened) and not match[2].strip(" \t")):
                opened = None
    return flags


def _where_field(lines: list[str]) -> str:
    """Wrapped links and fragments belong to the same field, not to its body.

    Stopping at paragraph and field boundaries prevents later examples from
    supplying a missing fragment for an earlier citation.
    """
    for i, line in enumerate(lines):
        line = line.lstrip()
        if not line.startswith(WHERE):
            continue
        out = [line]
        for nxt in lines[i + 1:]:
            if not nxt.strip() or nxt.lstrip().startswith(("**", "#", "|")):
                break
            out.append(nxt)
        return " ".join(out)
    return ""


def _references(field: str) -> list[Ref]:
    """Unrecognised links must be findings, never silently missing references.

    Code spans can themselves contain markdown; mask them while identifying
    links and field boundaries, then bind each fragment to its preceding link.
    """
    syntax = FRAGMENT.sub(lambda m: " " * len(m[0]), field)
    stop = FIELD.search(syntax, len(WHERE))
    if stop:
        field, syntax = field[:stop.start()], syntax[:stop.start()]
    matches = [m for m in LINK.finditer(field) if syntax[m.start()] == "["]
    remaining = list(syntax)
    for match in matches:
        remaining[match.start():match.end()] = " " * (match.end() - match.start())
    if LOOSE.search("".join(remaining)):
        raise ValueError("a link in this Where field is not in the accepted reference form")

    refs = []
    for i, match in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(field)
        span = FRAGMENT.search(field, match.end(), end)
        fragment = span[2] if span else None
        # Markdown trims one padding space at each end, except for all-space
        # spans. Compare the quoted code, not the delimiter padding.
        if (fragment and fragment.startswith(" ") and fragment.endswith(" ")
                and fragment.strip(" ")):
            fragment = fragment[1:-1]
        destination = match[1] if match[1] is not None else match[2]
        target = destination.partition("#")[0]
        refs.append(Ref(target, fragment))
    return refs


def verify_references(docs: pathlib.Path) -> tuple[bool, list[str]]:
    """Index agreement cannot reveal references whose cited source has drifted.

    Unfenced entry text cannot carry line anchors. In the Where field, each
    file link outside docs needs its own fragment; document links and directories
    carry only an existence claim. Collect findings so reconciliation cannot
    hide them.
    """
    ok, problems = True, []
    docs = docs.resolve()
    contents: dict[pathlib.Path, str] = {}
    for name in FILES.values():
        findings = []
        _, entries = split_entries((docs / name).read_text())
        for eid, body in entries.items():
            # Keep a boundary where a fence was, rather than joining a field
            # before the example to unrelated text after it.
            lines = ["" if fenced else line
                     for line, fenced in zip(body.splitlines(), _fenced_lines(body))]
            # Line anchors are banned throughout the entry. Parse links only
            # to retain their destination in the diagnostic, not to limit scope.
            text = "\n".join(lines)
            links = list(LINK.finditer(text))
            for anchor in LINE_ANCHOR.finditer(text):
                finding = f"  {eid}: line anchor {anchor[0]}"
                for link in links:
                    group = 1 if link[1] is not None else 2
                    if link.start(group) <= anchor.start() < link.end(group):
                        target, marker, suffix = link[group].partition("#")
                        finding = f"  {eid}: line anchor {marker + suffix} on {target}"
                        break
                findings.append(finding)
            field = _where_field(lines)
            if not field:
                continue
            try:
                refs = _references(field)
            except ValueError as exc:
                findings.append(f"  {eid}: {exc}")
                continue
            for ref in refs:
                if "://" in ref.target:
                    continue
                try:
                    path = (docs / ref.target).resolve()
                    if not path.exists():
                        findings.append(f"  {eid}: cited path missing: {ref.target}")
                    elif path.is_dir():
                        if ref.fragment is not None:
                            findings.append(f"  {eid}: fragment on a directory link: {ref.target}")
                    elif not path.is_file():
                        findings.append(f"  {eid}: cited path is not a file: {ref.target}")
                    elif path.is_relative_to(docs):
                        continue
                    elif ref.fragment is None:
                        findings.append(f"  {eid}: file link with no fragment: {ref.target}")
                    # This floor rejects degenerate fragments (spaces, fi, do, {),
                    # but else/then/pass/next still pass. Distinctiveness needs
                    # human judgement when converting citations.
                    elif sum(not c.isspace() for c in ref.fragment) < 4:
                        findings.append(f"  {eid}: fragment too weak to verify: {ref.target}")
                    else:
                        if path not in contents:
                            contents[path] = path.read_text()
                        if ref.fragment not in contents[path]:
                            findings.append(f"  {eid}: fragment absent from {ref.target}: {ref.fragment}")
                except (OSError, UnicodeError) as exc:
                    findings.append(f"  {eid}: cannot read cited path {ref.target}: {exc}")
        if findings:
            ok = False
        status = "INVALID" if findings else "verified"
        problems.append(f"{name:22} references {status}")
        problems.extend(findings)
    return ok, problems


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
    load(docs)          # refuses early if a file is missing or malformed
    ok, problems = reconcile(docs)
    refs_ok, refs_problems = verify_references(docs)
    for line in problems + refs_problems:
        print(line)
    return 0 if (ok and refs_ok) else 1


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

    new_roadmap = "".join(l for l in roadmap.splitlines(keepends=True)
                          if l != rows[eid]["line"])
    if len(new_roadmap.splitlines()) != len(roadmap.splitlines()) - 1:
        fail("refusing: removing the index row would change more than one line")

    # Reconcile the proposed documents before writing either. Writing first and
    # checking after meant a refusal happened with the edits already on disk,
    # and a failure on the second write left the first one changed.
    proposed = {FILES[prefix]: new_detail, "ROADMAP.md": new_roadmap}
    ok, problems = reconcile(docs, proposed)
    if not ok:
        for line in problems:
            print(line, file=sys.stderr)
        fail(f"refusing: closing {eid} would leave the roadmap inconsistent")

    install_documents(docs, proposed)
    print(f"closed {eid}: {len(entries)} entries -> {len(survivors)}, index row removed")
    return 0


def install_documents(docs: pathlib.Path, proposed: dict[str, str]) -> None:
    # Keep recovery copies outside the tree. Each replacement is staged beside
    # its destination so os.replace stays atomic even across filesystem devices.
    recovery = pathlib.Path(tempfile.mkdtemp(prefix="localclaude-roadmap-"))
    installed = []
    retain_recovery = False

    def replace_from(source, destination):
        fd, name = tempfile.mkstemp(prefix=".roadmap-", dir=destination.parent)
        os.close(fd)
        candidate = pathlib.Path(name)
        try:
            shutil.copy2(source, candidate)
            os.replace(candidate, destination)
        finally:
            candidate.unlink(missing_ok=True)

    def interrupted(signum, frame):
        raise KeyboardInterrupt(f"signal {signum}")

    previous = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        for name, body in proposed.items():
            shutil.copy2(docs / name, recovery / (name + ".original"))
            (recovery / name).write_text(body)
            shutil.copymode(docs / name, recovery / name)
        for name in proposed:
            installed.append(name)
            replace_from(recovery / name, docs / name)
    except BaseException as exc:
        # A second signal must not interrupt rollback of the first one.
        for sig in previous:
            signal.signal(sig, signal.SIG_IGN)
        try:
            for name in reversed(installed):
                original = recovery / (name + ".original")
                if (docs / name).read_bytes() != original.read_bytes():
                    replace_from(original, docs / name)
        except BaseException:
            retain_recovery = True
            fail(f"rollback failed; originals retained at {recovery}")
        fail(f"installation failed; originals restored: {exc}")
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        if not retain_recovery:
            shutil.rmtree(recovery)


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
