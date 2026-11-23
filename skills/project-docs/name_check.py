#!/usr/bin/env python3
"""Check that the names a project's Markdown docs mention still exist.

Advisory: it lists what it cannot find, and each item is fixed or marked with
`<!-- name-check: ignore NAME ... -->` on the line above. It cannot catch a
false claim, and it never runs a program it reads about: a flag is checked
against the source of the repo script that owns it, and flags of external
tools are not checked at all.

Usage:
    name_check.py [--root DIR] [FILE ...]

Exit 0 when nothing is missing, 1 when something is, 2 on a usage error or a
root that is not a git repository.
"""
from __future__ import annotations

import argparse
import collections
import fnmatch
import os
import pathlib
import re
import shutil
import subprocess
import sys
import urllib.parse

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from roadmap import FILES, FRAGMENT, LINK, SECRET_NAMES, credential_shaped, fenced_lines  # noqa: E402,F401

Finding = collections.namedtuple("Finding", "path line kind name reason")

INTERPRETERS = {"python3", "python", "bash", "sh", "node"}
ID = re.compile(rf"({'|'.join(FILES)})-\d+")
# An ID is declared by its entry's anchor in a detail file, or named in CHANGELOG.
ID_ANCHOR = re.compile(rf"""<a\s+id=["']((?:{'|'.join(FILES).lower()})-\d+)["']""")
ID_WORD = re.compile(rf"(?<![\w-])(?:{'|'.join(FILES)})-\d+(?![\w-])")
FLAG = re.compile(r"(--[A-Za-z0-9][\w-]*)(=\S*)?")
BARE = re.compile(r"[A-Za-z][\w.+-]*")
# A trailing line, range, symbol or line-anchor suffix: `x.py:12`, `x.py::test`.
SUFFIX = re.compile(r"(::[\w.\[\]-]+|:\d+(-\d+)?|#L\d+(-L?\d+)?)$")
NOT_A_PATH = set("$~<>*{}|;()[]")
SCHEME = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*:")
QUOTE = re.compile(r"^\s*(>\s?)+")
IGNORE = re.compile(r"<!--\s*name-check:\s*ignore\s+(.+?)\s*-->")
REFDEF = re.compile(r"^ {0,3}\[[^\]]+\]:\s*<?([^\s>]+)>?")
HEADING = re.compile(r"^ {0,3}#{1,6}\s+(.*?)\s*#*\s*$")
HTML_ID = re.compile(r"""\b(?:id|name)=["']([^"']+)["']""")
DETAIL_FILES = {prefix: f"docs/{name}" for prefix, name in FILES.items()}


class NotARepo(Exception):
    pass


def in_scope(rel: str) -> bool:
    """Current docs only. CHANGELOG, dated plans and specs record history;
    templates link to the layout they are set up into, not to their neighbours;
    and Markdown under a tests/ folder is test input, except its README."""
    name = rel.rsplit("/", 1)[-1]
    test_input = "tests" in rel.split("/")[:-1] and name != "README.md"
    return (rel.endswith(".md") and name != "CHANGELOG.md" and not name.endswith("-template.md")
            and not test_input
            and not rel.startswith(("docs/superpowers/plans/", "docs/superpowers/specs/")))


def flag_name(word: str) -> str | None:
    m = FLAG.fullmatch(word)
    return m[1] if m else None


class Repo:
    def __init__(self, root: pathlib.Path):
        self.root = root.resolve()
        # core.fsmonitor names a program git would run while reading the index.
        out = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", str(self.root),
                              "ls-files", "-z"], capture_output=True, text=True)
        if out.returncode != 0:
            raise NotARepo(f"not a git repository: {root}")
        self.tracked = [p for p in out.stdout.split("\0") if p]
        self.tops = {p.split("/", 1)[0] for p in self.tracked}
        self.basenames = {p.rsplit("/", 1)[-1] for p in self.tracked}
        self._text: dict[str, str | None] = {}
        self._anchors: dict[str, set[str]] = {}
        self._code: str | None = None
        # A declaration is a visible anchor in its own detail file, not an example.
        self.ids = {m[1].upper() for prefix, f in DETAIL_FILES.items()
                    for line in visible_lines(self.text(f) or "")
                    for m in [ID_ANCHOR.match(blank_spans(line))]
                    if m and m[1].upper().startswith(prefix + "-")}
        self.ids |= set(ID_WORD.findall(self.text("CHANGELOG.md") or ""))

    def inside(self, rel: str) -> bool:
        """True when the path, with every symlink on the way resolved, is in the root.
        A tracked symlink to a folder elsewhere does not make what is under it ours."""
        full = os.path.realpath(os.path.join(self.root, rel))
        return full == str(self.root) or full.startswith(str(self.root) + os.sep)

    def present(self, rel: str) -> bool:
        """Inside the root and on disk; a symlink counts without being followed."""
        return self.inside(rel) and os.path.lexists(os.path.join(self.root, rel))

    def text(self, rel: str) -> str | None:
        """A file's text, or None for anything the check must not open: a
        symlink, a non-regular or binary file, a credential-shaped path, or a
        path outside the root."""
        if rel not in self._text:
            self._text[rel] = self._read(rel)
        return self._text[rel]

    def _read(self, rel: str) -> str | None:
        path = self.root / rel
        # Any symlink on the way, not only the last one, could lead to a
        # credential-shaped folder under a harmless name.
        if (not self.inside(rel) or credential_shaped(rel)
                or os.path.realpath(path) != os.path.abspath(path) or not path.is_file()):
            return None
        try:
            data = path.read_bytes()
        except OSError:
            return None
        if b"\0" in data[:8192]:
            return None
        return data.decode("utf-8", errors="replace")

    def code(self) -> str:
        """The text of every readable tracked file that is not Markdown, which
        is where a subcommand a doc names would be defined."""
        if self._code is None:
            self._code = "\n".join(self.text(p) or "" for p in self.tracked if not p.endswith(".md"))
        return self._code

    def anchors(self, rel: str) -> set[str]:
        if rel not in self._anchors:
            found: set[str] = set()
            seen: collections.Counter[str] = collections.Counter()
            for line in visible_lines(self.text(rel) or ""):
                m = HEADING.match(line)
                if m:
                    slug = slugify(m[1])
                    found.add(f"{slug}-{seen[slug]}" if seen[slug] else slug)
                    seen[slug] += 1
                found.update(HTML_ID.findall(blank_spans(line)))
            self._anchors[rel] = found
        return self._anchors[rel]


def blank_spans(line: str) -> str:
    """The line with code spans blanked, so an example is not read as markup
    and the columns of everything else stay where they were."""
    return FRAGMENT.sub(lambda m: " " * len(m[0]), line)


def slugify(heading: str) -> str:
    """GitHub's heading anchor: link text kept, punctuation dropped, spaces to hyphens."""
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", heading).lower()
    text = "".join(c for c in text if c.isalnum() or c in " -_")
    return text.replace(" ", "-")


def visible_lines(text: str) -> list[str]:
    """The document's lines with fenced blocks and HTML comments blanked, so
    line numbers still match. Fences inside blockquotes count too, which is why
    the quote markers are stripped before roadmap.py's fence tracker reads them.
    Ignore directives survive."""
    lines = text.splitlines()
    fenced = fenced_lines("\n".join(QUOTE.sub("", line) for line in lines))
    out, comment = [], False
    for line, in_fence in zip(lines, fenced):
        if in_fence:
            out.append("")
            continue
        # Comment markers are found with code spans blanked out, so a
        # backticked `<!--` is text, not the start of a comment.
        masked = blank_spans(line)
        if comment:
            end = masked.find("-->")
            if end < 0:
                out.append("")
                continue
            comment, line, masked = False, line[end + 3:], masked[end + 3:]
        if not IGNORE.search(masked):
            while (start := masked.find("<!--")) >= 0:
                end = masked.find("-->", start + 4)
                if end < 0:
                    line, comment = line[:start], True
                    break
                line, masked = line[:start] + line[end + 3:], masked[:start] + masked[end + 3:]
        out.append(line)
    return out


def path_token(token: str) -> str | None:
    """The path a backticked token names, or None when it is not path-shaped."""
    token = SUFFIX.sub("", token)
    if (not token or "/" not in token or token.startswith("/") or "//" in token
            or SCHEME.match(token) or NOT_A_PATH & set(token)):
        return None
    return token


def locate(repo: Repo, token: str | None, doc_dir: str) -> str | None:
    """The repo-relative path a path token means, or None when it does not read
    as a path here. A path must start at `.`, `..`, a folder beside the doc or a
    top-level entry, which keeps `N/A`, `origin/main` or an example like
    `auth/token.py` from being taken for one. It resolves from the doc's folder
    first, then from the root."""
    if not token:
        return None
    first = token.split("/", 1)[0]
    from_doc = os.path.normpath(os.path.join(doc_dir, token))
    if first in (".", "..") or repo.present(os.path.join(doc_dir, first)):
        if repo.present(from_doc) or first not in repo.tops:
            return from_doc
    if first in repo.tops:
        return os.path.normpath(token)
    return None


def check_doc(repo: Repo, rel: str) -> list[Finding]:
    findings: list[Finding] = []
    doc_dir = os.path.dirname(rel)
    ignored: set[str] = set()
    for number, line in enumerate(visible_lines(repo.text(rel) or ""), 1):
        here, ignored = ignored, set()
        # The directive must sit outside a code span; the names it lists may be
        # backticked, so they are read from the same place in the raw line.
        directive = IGNORE.search(blank_spans(line))
        if directive:
            raw = IGNORE.match(line, directive.start())
            ignored = set(raw[1].replace("`", " ").split()) if raw else set()
            continue
        found: list[tuple] = []
        scripts, lone_flags = [], []
        for m in FRAGMENT.finditer(line):
            words = m[2].split()
            if not words:
                continue
            if len(words) > 1:
                script = check_command(repo, words, doc_dir, found)
                if script:
                    scripts.append(script)
            elif ID.fullmatch(words[0]):
                if words[0] not in repo.ids:
                    found.append(("id", words[0], ""))
            elif flag := flag_name(words[0]):
                lone_flags.append(flag)
            else:
                path = locate(repo, path_token(words[0]), doc_dir)
                if path and not repo.inside(path):
                    found.append(("path", words[0], "outside the repository"))
                elif path and not repo.present(path):
                    found.append(("path", words[0], ""))
        # A lone flag is checked only against a repo script named on the same line.
        for flag in lone_flags:
            if scripts and not any(defines(repo.text(s), flag) for s in scripts):
                found.append(("flag", flag, ""))

        prose = blank_spans(line)
        targets = [m[1] or m[2] for m in LINK.finditer(prose)]
        ref = REFDEF.match(prose)
        if ref:
            targets.append(ref[1])
        for target in targets:
            found.extend(check_link(repo, target, rel, doc_dir))
        findings += [Finding(rel, number, *f) for f in found if f[1] not in here]
    return findings


def check_command(repo, words, doc_dir, found) -> str | None:
    """A command span: its program must exist, and a repo script's flags must
    appear in its source. Returns the script it names, if any. Anything that
    does not look like a command is prose and is not checked."""
    first = words[0]
    script = locate(repo, path_token(first), doc_dir)
    args = words[1:]
    if not script and first in INTERPRETERS:
        operand = locate(repo, path_token(words[1]), doc_dir)
        if operand:
            first, script, args = words[1], operand, words[2:]
    if not script:
        if (BARE.fullmatch(first) and words[1].startswith("--") and not shutil.which(first)
                and first not in repo.basenames
                and not re.search(rf"(?<![\w-]){re.escape(first)}(?![\w-])", repo.code())):
            found.append(("command", first, ""))
        return None
    if not repo.inside(script):
        found.append(("command", first, "outside the repository"))
        return None
    if not repo.present(script):
        found.append(("command", script, ""))
        return None
    source = repo.text(script)
    for word in args:
        flag = flag_name(word)
        if flag and not defines(source, flag):
            found.append(("flag", flag, ""))
    return script


def defines(source: str | None, flag: str) -> bool:
    """The flag appears whole in the script: --format is not --format-long."""
    return bool(source) and re.search(rf"(?<![\w-]){re.escape(flag)}(?![\w-])", source) is not None


def check_link(repo, target, rel, doc_dir) -> list[tuple]:
    if not target or SCHEME.match(target):
        return []
    path, _, anchor = urllib.parse.unquote(target).partition("#")
    path = path.split("?", 1)[0]
    # A leading / is resolved from the repository root, as GitHub does.
    base = "" if path.startswith("/") else doc_dir
    full = os.path.normpath(os.path.join(base, path.lstrip("/"))) if path else rel
    if not repo.inside(full):
        return [("link", target, "outside the repository")]
    if not repo.present(full):
        return [("link", target, "")]
    if anchor and full.endswith(".md") and anchor not in repo.anchors(full):
        return [("anchor", target, "")]
    return []


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", type=pathlib.Path, default=pathlib.Path("."))
    ap.add_argument("files", nargs="*", help="docs to check, relative to the root")
    args = ap.parse_args()
    try:
        repo = Repo(args.root)
    except NotARepo as exc:
        print(exc, file=sys.stderr)
        return 2
    named = [os.path.normpath(f) for f in args.files]
    unknown = [f for f in named if f not in repo.tracked or not f.endswith(".md")]
    if unknown:
        print(f"not a tracked Markdown file: {', '.join(unknown)}", file=sys.stderr)
        return 2
    unreadable = [f for f in named if repo.text(f) is None]
    if unreadable:
        print(f"cannot read: {', '.join(unreadable)}", file=sys.stderr)
        return 2
    docs = [f for f in (named or repo.tracked) if in_scope(f)]
    skipped = [f for f in docs if repo.text(f) is None]
    docs = [f for f in docs if f not in skipped]
    findings = [f for rel in docs for f in check_doc(repo, rel)]
    for f in findings:
        print(f"{f.path}:{f.line}: missing {f.kind} {f.name}" + (f" — {f.reason}" if f.reason else ""))
    if skipped:
        # The rest was checked, but the run is incomplete: say so, and fail as one.
        print(f"cannot read: {', '.join(skipped)} (not checked)", file=sys.stderr)
        return 2
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
