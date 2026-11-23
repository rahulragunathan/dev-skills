#!/usr/bin/env python3
"""Set up, close or check the roadmap files.

Closing an entry means deleting it from its detail file and removing its
pointer row from the index. Done by hand it has destroyed content twice in
this repository: a slice from an anchor to end of file took three unrelated
entries with it, and markdownlint passed on the result because the damage was
well-formed, just shorter.

So this does not slice. It parses the file into entries, drops exactly the one
named, and then requires every surviving entry to be byte-identical to what it
was. Counting is not enough — a count can be right while the content is wrong.

It never loses a concurrent edit: `close` keeps the bytes it read and refuses
if either file changed before it replaces them, and a rollback restores a file
only while it still holds what `close` wrote. A window of one read to one rename
remains against an editor that ignores all of this; nothing narrower is possible
without a lock every editor honours. Line endings and trailing whitespace are the
file's own: the closed entry's bytes are cut out and nothing else is rewritten.

Usage:
    roadmap.py check [--docs DIR]
    roadmap.py close KI-15 [--docs DIR]
    roadmap.py init [--docs DIR]

Exit 0 on success, 1 on refusal. Nothing is written unless every check passes.
"""
from __future__ import annotations

import argparse
import collections
import fnmatch
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
WHERE_AT = re.compile(r'(?:^\s*|\*\*[^*\n]+:\*\*[^\n]*·\s*)(\*\*Where:\*\*)')
WHERE_LIKE = re.compile(r'^\s*(?:[-+*]\s+|\d+[.)]\s+)?\*\*Where(?::\*\*|\*\*:)')
Ref = collections.namedtuple("Ref", "target fragment")
# The rated fields of each kind of entry, in sort-key order. Their levels are
# not listed here: they are read from the templates bundled beside this file.
FIELDS = {"KI": ["Severity", "Likelihood"], "ENH": ["Priority"], "UNK": ["Kind"]}
TEMPLATES = pathlib.Path(__file__).resolve().parent
# The credential-shaped names external-review's capture.sh withholds; a test
# keeps the two lists equal. check never opens a cited file of this shape, and
# name_check.py imports the same screen.
SECRET_NAMES = ("*.env", "*.env.*", "*.pem", "*.key", "*.p12", "*.pfx", "*.crt", "*id_rsa*",
                "*id_ed25519*", "*id_ecdsa*", "*.pypirc", "*credentials*", "*.netrc", "*.npmrc",
                "*.sqlite", "*.sqlite3")
# Each index section and the table header it must hold, so blank files never pass.
SECTIONS = {"KI": "## Known Issues", "ENH": "## Enhancements", "UNK": "## Open Questions"}


def credential_shaped(rel: str) -> bool:
    """The rule capture.sh applies: the path or any folder above it matches."""
    path = rel.lower()
    while path:
        if any(fnmatch.fnmatch(path, p) for p in SECRET_NAMES):
            return True
        path = path.rsplit("/", 1)[0] if "/" in path else ""
    return False


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


def entry_spans(text: str) -> dict[str, tuple[int, int]]:
    """{entry-id: (start, end)} in `text`.

    An entry starts at its `<a id="...">` anchor and runs to the next one, or
    to end of file. The separator line before an anchor belongs to the entry
    that follows it, so removing an entry removes its separator too and never
    leaves a doubled or orphaned rule. An anchor inside a fenced example is
    example text, not an entry.
    """
    fenced = fenced_lines(text)
    anchors = [m for m in re.finditer(r'^<a id="([a-z]+-\d+)"></a>\s*$', text, re.M)
               if not fenced[text.count("\n", 0, m.start())]]
    spans: dict[str, tuple[int, int]] = {}
    for i, m in enumerate(anchors):
        start = _entry_start(text, m)
        end = (_entry_start(text, anchors[i + 1]) if i + 1 < len(anchors)
               else len(text))
        eid = m.group(1).upper()
        if eid in spans:
            fail(f"refusing: {eid} appears twice in the detail file")
        spans[eid] = (start, end)
    return spans


def split_entries(text: str) -> tuple[str, dict[str, str]]:
    """Return (header, {entry-id: body}). The header ends exactly where the first
    entry begins: computing that boundary by a second rule once left prose
    belonging to neither slice, so it vanished on the next write."""
    spans = entry_spans(text)
    if not spans:
        return text, {}
    first_start = min(s for s, _ in spans.values())
    return text[:first_start], {eid: text[s:e] for eid, (s, e) in spans.items()}


def _cells(line: str) -> list[str]:
    """The cells of one Markdown table row, stripped."""
    return [c.strip() for c in line.strip().split("|")[1:-1]]


def index_rows(roadmap: str, prefix: str) -> dict[str, dict]:
    """{entry-id: {"line": the row, "anchor": what the link actually targets}}.

    The anchor is kept because comparing displayed IDs alone let a row point at
    a heading that does not exist: the table looked reconciled and the link
    went nowhere.
    """
    rows: dict[str, dict] = {}
    headers = []
    lines = roadmap.splitlines(keepends=True)
    for line, fenced in zip(lines, fenced_lines(roadmap)):
        if fenced:
            continue
        cells = _cells(line)
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
            shown = link[1] if link else cells[0]
            if shown != eid:
                fail(f"refusing: an index row displays {shown}, not {eid}: " + line.strip())
            rows[eid] = {"line": line, "anchor": link[3] if link else "",
                         "filename": link[2] if link else "",
                         "cells": dict(zip(headers, cells))}

    return rows


def load_scales(template_dir: pathlib.Path) -> dict[str, dict[str, list[str]]]:
    """{prefix: {field: [levels, best first]}}, read from each template's scale table.

    The scale tables in the templates are the one source of the levels: a row
    added or moved there changes what `check` accepts, with no second copy here.
    """
    scales: dict[str, dict[str, list[str]]] = {}
    for prefix, fields in FIELDS.items():
        name = FILES[prefix].replace(".md", "-template.md")
        lines = (template_dir / name).read_text().splitlines()
        scales[prefix] = {}
        for field in fields:
            try:
                start = lines.index(f"## {field}")
            except ValueError:
                fail(f"refusing: no {field} scale in {name}")
            rows, in_table = [], False
            for line in lines[start + 1:]:
                # The table belongs to this section: never take the next one's.
                if line.startswith("## "):
                    break
                if line.startswith("|"):
                    in_table = True
                    rows.append(line)
                elif in_table:
                    break
            # Skip the header and delimiter rows; a level is the bold first cell.
            levels = [_cells(r)[0].strip("*").strip() for r in rows[2:]]
            if not levels:
                fail(f"refusing: the {field} scale in {name} is empty")
            repeated = sorted(lv for lv, n in collections.Counter(levels).items() if n > 1)
            if repeated:
                fail(f"refusing: the {field} scale in {name} repeats {repeated}")
            scales[prefix][field] = levels
    return scales


def reconcile(docs: pathlib.Path, proposed: dict[str, str] | None = None):
    """Check the index against the detail files. `proposed` replaces a file's
    text in memory, so a change can be reconciled before anything is written."""
    proposed = proposed or {}
    def text_of(name):
        return proposed[name] if name in proposed else (docs / name).read_text()

    roadmap = text_of("ROADMAP.md")
    scales = load_scales(TEMPLATES)
    ok, problems = True, []
    for problem in structure_problems(roadmap, {n: text_of(n) for n in FILES.values()}):
        problems.append(problem); ok = False
    for prefix, name in FILES.items():
        detail_text = text_of(name)
        _, entries = split_entries(detail_text)
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
        fields = FIELDS[prefix]
        ratings = {}
        for eid, body in entries.items():
            ratings[eid] = {}
            for field in fields:
                match = re.search(r'\*\*' + field + r':\*\*\s*([^\n·]+)', body)
                val = match[1].strip() if match else ""
                ratings[eid][field] = val
                if eid in rows and (not val or rows[eid]["cells"].get(field) != val):
                    problems.append(f"  rating mismatch: {eid} {field}"); ok = False
                if val and val not in scales[prefix][field]:
                    problems.append(f"  unknown {field}: {eid} ({val})"); ok = False
            if eid in rows:
                for label, ours, theirs in mirrored(prefix, eid, body, rows[eid]):
                    if ours != theirs:
                        problems.append(f"  mismatch: {eid} {label}"); ok = False
        # Open questions too: the template orders them by Kind.
        for label, ids in [("detail", entries), ("index", rows)]:
            # An unknown level is reported above, so order only the known ones.
            keys = [tuple(scales[prefix][f].index(ratings[e][f]) for f in fields)
                    for e in ids if e in ratings
                    and all(ratings[e][f] in scales[prefix][f] for f in fields)]
            if keys != sorted(keys):
                problems.append(f"  rating order invalid: {label}"); ok = False
        if wrong:
            detail = [f"{e} -> #{rows[e]['anchor']}" for e in wrong]
            problems.append(f"  index rows pointing at the wrong anchor: {detail}"); ok = False
    return ok, problems


def structure_problems(roadmap: str, details: dict[str, str]) -> list[str]:
    """What a set-up from the templates always has: a title in each file, and in
    the index a section with a pointer table for each kind of entry."""
    problems = []
    lines = roadmap.splitlines()
    for prefix, heading in SECTIONS.items():
        if heading not in lines:
            problems.append(f"  structure: ROADMAP.md has no '{heading}' section"); continue
        section = lines[lines.index(heading) + 1:]
        section = section[:next((i for i, l in enumerate(section) if l.startswith("## ")), len(section))]
        if not any(_cells(l)[:1] == ["ID"] for l in section if l.startswith("|")):
            problems.append(f"  structure: '{heading}' in ROADMAP.md has no pointer table")
    for name, text in [("ROADMAP.md", roadmap), *details.items()]:
        if not any(l.startswith("# ") for l in text.splitlines()):
            problems.append(f"  structure: {name} has no title")
    return problems


def _title_key(title: str) -> str:
    # An index row may capitalise the first letter of a title the detail heading keeps lower case.
    return title[:1].lower() + title[1:]


def mirrored(prefix: str, eid: str, body: str, row: dict) -> list[tuple[str, str, str]]:
    """(label, detail value, index value) for each field the index mirrors besides ratings."""
    heading = re.search(rf'^## {eid} — (.*?)\s*$', body, re.M)
    pairs = [("title", _title_key(heading[1]) if heading else "",
              _title_key(list(row["cells"].values())[1]) if len(row["cells"]) > 1 else "")]
    if prefix == "ENH":
        effort = re.search(r'\*\*Effort:\*\*\s*([^\n·]+)', body)
        pairs.append(("Effort", effort[1].strip() if effort else "", row["cells"].get("Effort", "")))
    return pairs


def fenced_lines(text: str) -> list[bool]:
    """Keep nested, shorter fences from hiding the references after a block.

    Only the opening character repeated at least as many times, followed by
    whitespace alone, closes the block. Backticks in an info string instead
    make the apparent opening fence ordinary text.

    Second fence tracker, after skills/design-review/tests/write_results.py; only
    this one rejects backtick fences with backticks in their info strings.
    Two stay separate under the rule of three; a third occurrence creates a shared home.
    name_check.py imports this one rather than adding a third.
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
        # The field starts its line, or follows another field after a `·`:
        # `**Priority:** Low · **Where:** …`. Inside a list item it is malformed.
        m = WHERE_AT.search(line)
        if not m:
            continue
        out = [line[m.start(1):]]
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
    # Balanced code spans are masked; any remaining backtick is unpaired and
    # may have caused a link to be swallowed by the preceding span.
    if "`" in syntax:
        raise ValueError("unbalanced backticks in this Where field")
    matches = [m for m in LINK.finditer(field) if syntax[m.start()] == "["]
    remaining = list(syntax)
    for match in matches:
        remaining[match.start():match.end()] = " " * (match.end() - match.start())
    # Shortcut references like [x.sh] are ambiguous with bracketed prose and out of scope.
    if "][" in syntax or LOOSE.search("".join(remaining)):
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
        if not target:
            raise ValueError("a link in this Where field has an empty target")
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
                     for line, fenced in zip(body.splitlines(), fenced_lines(body))]
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
                if any(WHERE_LIKE.match(line) for line in lines):
                    findings.append(f"  {eid}: malformed Where field")
                elif not eid.startswith("UNK"):
                    # Known issues and enhancements always say where they live (KI-56).
                    findings.append(f"  {eid}: no Where field")
                continue
            try:
                refs = _references(field)
            except ValueError as exc:
                findings.append(f"  {eid}: {exc}")
                continue
            if not refs:
                findings.append(f"  {eid}: empty Where field")
            for ref in refs:
                if re.match(r'[A-Za-z][A-Za-z0-9+.-]*:', ref.target):
                    continue
                if ref.target.startswith("/"):
                    # Cite repository files relative to the docs folder, so the link works anywhere.
                    findings.append(f"  {eid}: absolute path: {ref.target}")
                    continue
                try:
                    path = (docs / ref.target).resolve()
                    named = os.path.normpath(os.path.join(docs.name, ref.target))
                    if not path.is_relative_to(docs.parent):
                        findings.append(f"  {eid}: cited path outside repository: {ref.target}")
                    elif not path.exists():
                        findings.append(f"  {eid}: cited path missing: {ref.target}")
                    elif path.is_dir():
                        if ref.fragment is not None:
                            findings.append(f"  {eid}: fragment on a directory link: {ref.target}")
                    elif not path.is_file():
                        findings.append(f"  {eid}: cited path is not a file: {ref.target}")
                    elif (credential_shaped(named)
                          or credential_shaped(str(path.relative_to(docs.parent)))):
                        findings.append(f"  {eid}: refusing to read a credential-shaped file: {ref.target}")
                    elif path.is_relative_to(docs) and path.suffix == ".md":
                        # A doc in docs/ is cited for its existence; source there needs a fragment.
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
                        occurrences = contents[path].count(ref.fragment)
                        if occurrences == 0:
                            findings.append(f"  {eid}: fragment absent from {ref.target}: {ref.fragment}")
                        elif occurrences > 1:
                            findings.append(f"  {eid}: fragment occurs more than once in {ref.target}: {ref.fragment}")
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
    # A third pass over these files makes roadmap.py a module with its own
    # directory, not a fourth function.
    ok, problems = reconcile(docs)
    refs_ok, refs_problems = verify_references(docs)
    for line in problems + refs_problems:
        print(line)
    return 0 if (ok and refs_ok) else 1


def read_document(path: pathlib.Path) -> tuple[bytes, str, bool]:
    """(the bytes on disk, the text with LF line ends, whether the file uses CRLF)."""
    raw = path.read_bytes()
    crlf = b"\r\n" in raw
    if crlf and b"\n" in raw.replace(b"\r\n", b""):
        fail(f"refusing: {path.name} mixes CRLF and LF line endings; close it by hand")
    return raw, raw.decode("utf-8").replace("\r\n", "\n"), crlf


def encode(text: str, crlf: bool) -> bytes:
    return (text.replace("\n", "\r\n") if crlf else text).encode("utf-8")


def cmd_close(docs: pathlib.Path, eid: str) -> int:
    prefix = eid.split("-")[0].upper()
    if prefix not in FILES:
        fail(f"unknown id prefix: {eid}")
    load(docs)          # refuses early if a file is missing or malformed
    name = FILES[prefix]
    detail_raw, detail, detail_crlf = read_document(docs / name)
    index_raw, roadmap, index_crlf = read_document(docs / "ROADMAP.md")
    spans = entry_spans(detail)
    if eid not in spans:
        fail(f"refusing: no entry {eid} in {name}")
    rows = index_rows(roadmap, prefix)
    if eid not in rows:
        fail(f"refusing: no index row for {eid}; close it by hand and say why")

    # Cut the entry's bytes out and touch nothing else, so the file keeps its own
    # whitespace and its final newline, or lack of one.
    start, end = spans[eid]
    new_detail = detail[:start] + detail[end:]
    added_newline = detail.endswith("\n") and not new_detail.endswith("\n")
    if added_newline:
        new_detail += "\n"

    # The check that matters: every surviving entry must come back byte-identical.
    entries = {k: detail[s:e] for k, (s, e) in spans.items()}
    survivors = {k: v for k, v in entries.items() if k != eid}
    _, reparsed = split_entries(new_detail)
    if set(reparsed) != set(survivors):
        lost = sorted(set(survivors) - set(reparsed))
        fail(f"refusing: rewriting would lose {lost or 'entries'}")
    last = max(survivors, key=lambda k: spans[k][0]) if survivors else None
    for k in survivors:
        expected = survivors[k] + ("\n" if added_newline and k == last else "")
        if reparsed[k] != expected:
            fail(f"refusing: {k} would not survive byte-identical")

    new_roadmap = "".join(l for l in roadmap.splitlines(keepends=True)
                          if l != rows[eid]["line"])
    if len(new_roadmap.splitlines()) != len(roadmap.splitlines()) - 1:
        fail("refusing: removing the index row would change more than one line")

    # Reconcile the proposed documents before writing either. Writing first and
    # checking after meant a refusal happened with the edits already on disk,
    # and a failure on the second write left the first one changed.
    proposed = {name: new_detail, "ROADMAP.md": new_roadmap}
    ok, problems = reconcile(docs, proposed)
    if not ok:
        for line in problems:
            print(line, file=sys.stderr)
        fail(f"refusing: closing {eid} would leave the roadmap inconsistent")

    install_documents(docs, {name: encode(new_detail, detail_crlf),
                             "ROADMAP.md": encode(new_roadmap, index_crlf)},
                      {name: detail_raw, "ROADMAP.md": index_raw})
    print(f"closed {eid}: {len(entries)} entries -> {len(survivors)}, index row removed")
    return 0


def install_documents(docs: pathlib.Path, proposed: dict[str, bytes],
                      expected: dict[str, bytes]) -> None:
    """Replace each document with its proposed bytes, or change nothing.

    `expected` is what was read: a file that no longer holds it was edited
    meanwhile, and nothing is replaced. A rollback restores a file only while it
    still holds what was installed; one edited since is left as it is, and the
    originals are kept for inspection.
    """
    # Keep recovery copies outside the tree. Each replacement is staged beside
    # its destination so os.replace stays atomic even across filesystem devices.
    recovery = pathlib.Path(tempfile.mkdtemp(prefix="roadmap-"))
    landed: dict[str, bytes] = {}
    retain_recovery = False
    rolling_back = False

    def replace_from(source, destination):
        fd, staged = tempfile.mkstemp(prefix=".roadmap-", dir=destination.parent)
        os.close(fd)
        candidate = pathlib.Path(staged)
        try:
            shutil.copy2(source, candidate)
            os.replace(candidate, destination)
        finally:
            candidate.unlink(missing_ok=True)

    def interrupted(signum, frame):
        # Once rollback has begun, a signal waits for it to finish.
        if not rolling_back:
            raise KeyboardInterrupt(f"signal {signum}")

    previous = {}
    try:
        previous = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGINT, signal.SIGTERM)}
        for name, body in proposed.items():
            shutil.copy2(docs / name, recovery / (name + ".original"))
            (recovery / name).write_bytes(body)
            shutil.copymode(docs / name, recovery / name)
        changed = [n for n in proposed if (docs / n).read_bytes() != expected[n]]
        if changed:
            fail(f"refusing: {', '.join(changed)} changed since it was read; nothing closed")
        for name in proposed:
            replace_from(recovery / name, docs / name)
            landed[name] = proposed[name]
    except BaseException as exc:
        rolling_back = True
        if isinstance(exc, SystemExit):
            raise
        for sig in previous:
            signal.signal(sig, signal.SIG_IGN)
        kept = []
        try:
            for name in reversed(list(landed)):
                if (docs / name).read_bytes() == landed[name]:
                    replace_from(recovery / (name + ".original"), docs / name)
                else:
                    kept.append(name)
        except BaseException:
            retain_recovery = True
            fail(f"rollback failed; originals retained at {recovery}")
        if kept:
            retain_recovery = True
            fail(f"installation failed: {exc}; {', '.join(kept)} changed after close wrote it, so it "
                 f"was left as it is; originals retained at {recovery}")
        fail(f"installation failed; originals restored: {exc}")
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
        if not retain_recovery:
            shutil.rmtree(recovery)


def cmd_init(docs: pathlib.Path) -> int:
    """Create whichever roadmap files are missing, from the templates without
    their example entries, so a fresh set-up passes `check`. An existing file,
    or a symlink in its place, is never touched, and a file that appears while
    this runs is left to whoever made it. On failure, or on SIGINT or SIGTERM,
    it removes what it made and only that: each file it still owns, by inode,
    and each folder it created. A file whose identity it could not read is not
    removed, since another writer may have replaced it, and the message names it."""
    names = ["ROADMAP.md", *FILES.values()]
    if os.path.lexists(docs) and not docs.is_dir():
        fail(f"refusing: {docs} exists and is not a folder")
    missing = [n for n in names if not os.path.lexists(docs / n)]
    if not missing:
        print("nothing to set up")
        return 0
    bodies = {}
    for name in missing:
        text = (TEMPLATES / name.replace(".md", "-template.md")).read_text()
        if name == "ROADMAP.md":
            examples = set()
            for prefix in FILES:
                examples |= {r["line"] for r in index_rows(text, prefix).values()}
            text = "".join(l for l in text.splitlines(keepends=True) if l not in examples)
        else:
            text = split_entries(text)[0].rstrip("\n") + "\n"
        bodies[name] = text

    fired = []

    def interrupted(signum, frame):
        # Raise once; a signal after that, or once rollback has begun for any
        # failure, must not interrupt the rollback.
        if not fired:
            fired.append(signum)
            raise KeyboardInterrupt(f"signal {signum}")

    made_dirs = []                      # deepest last
    created: list[list] = []            # [path, (dev, ino) or None]
    signals = {signal.SIGINT, signal.SIGTERM}
    previous = {}

    def guarded(step):
        # Signals wait while a folder or file is made and recorded, so nothing
        # exists on disk that the rollback does not know about. The caller's
        # own mask is restored afterwards, not cleared.
        mask = signal.pthread_sigmask(signal.SIG_BLOCK, signals)
        try:
            step()
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, mask)

    def make_folder(folder):
        try:
            folder.mkdir()
            made_dirs.append(folder)
        except FileExistsError:
            if not folder.is_dir():
                raise
            # Another init made it; it is theirs, so ours to use, not remove.

    def make_file(path, text):
        # O_EXCL refuses any existing entry, a dangling symlink included, so
        # nothing that appeared since the check above is replaced.
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o666)  # the umask decides
        except FileExistsError:
            return
        entry = [path, None]
        created.append(entry)
        try:
            st = os.fstat(fd)
            entry[1] = (st.st_dev, st.st_ino)
            with os.fdopen(fd, "w") as f:
                fd = None
                f.write(text)
        finally:
            if fd is not None:
                os.close(fd)

    try:
        previous = {sig: signal.signal(sig, interrupted) for sig in signals}
        for folder in [*reversed(docs.parents), docs]:
            if not os.path.lexists(folder):
                guarded(lambda folder=folder: make_folder(folder))
        for name, text in bodies.items():
            guarded(lambda name=name, text=text: make_file(docs / name, text))
    except BaseException as exc:
        fired.append("rollback")        # from here a signal changes nothing
        for sig in previous:
            signal.signal(sig, signal.SIG_IGN)
        left, unconfirmed = [], []
        for path, ident in created:
            if ident is None:
                # Made here, but its identity was never read: another writer may
                # have replaced it since, so it is left in place and reported.
                unconfirmed.append(str(path))
                continue
            try:
                st = os.lstat(path)
                if (st.st_dev, st.st_ino) == ident:
                    path.unlink()
            except FileNotFoundError:
                pass
            except OSError:
                left.append(str(path))
        for folder in reversed(made_dirs):
            try:
                folder.rmdir()
            except OSError:
                left.append(str(folder))  # someone else's file is in it now
        skipped = (f"; removal skipped for {', '.join(unconfirmed)}: could not confirm it is ours, "
                   "so inspect it before retrying") if unconfirmed else ""
        if left:
            fail(f"refusing: set-up failed: {exc}; could not remove {', '.join(left)}{skipped}")
        if skipped:
            fail(f"refusing: set-up failed: {exc}{skipped}")
        fail(f"refusing: set-up failed, nothing of ours left behind: {exc}")
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)
    for path, _ in created:
        print(f"created {path}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    # --docs may come before or after the subcommand.
    ap.add_argument("--docs", type=pathlib.Path, default=pathlib.Path("docs"))
    commands = ap.add_subparsers(dest="command", required=True)
    for name in ("check", "close", "init"):
        sub = commands.add_parser(name)
        if name == "close":
            sub.add_argument("id", help="the entry to close, e.g. KI-15")
        sub.add_argument("--docs", type=pathlib.Path, default=argparse.SUPPRESS)
    args = ap.parse_args()
    if args.command == "check":
        return cmd_check(args.docs)
    if args.command == "init":
        return cmd_init(args.docs)
    return cmd_close(args.docs, args.id.upper())


if __name__ == "__main__":
    raise SystemExit(main())
