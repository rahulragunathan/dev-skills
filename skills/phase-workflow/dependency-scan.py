#!/usr/bin/env python3
"""Scan the committed dependency files for known vulnerabilities, with osv-scanner.

Usage:
    dependency-scan.py [--root DIR] [--offline]

It reads only the dependency files committed at HEAD, blob by blob from git's
tree (so export-ignore attributes drop nothing, and no other file is copied
out), so an untracked or ignored file and an untracked osv-scanner.toml cannot
change the verdict. A committed symlink is never followed; one named like a
dependency file is a coverage gap. A requirements file is never handed to the
scanner as it is. Its lines are joined and its comments removed as pip does, and
the scanner gets only the lines pinned to one exact version of a valid name, as
name==version. Every other line (an include, a range, an editable, an option the
scan does not know, or a variable) is reported as a gap by its number, and a file
that is not UTF-8 is a gap as a whole. Every output line has its control
characters escaped. A tracked osv-scanner.toml is passed to the scanner by name, so one it
cannot load fails the scan, and the output names what it can suppress. Each
supported file is scanned on its own, so its own exit status counts. Nothing is
installed: lockfiles are read as they are.

Package names and versions, never source, go to the OSV database (api.osv.dev);
a private package name can still identify an internal service. --offline uses a
local database downloaded beforehand instead, and fails without one.

Output: the commit scanned, a FINDING line per advisory group (its first id, its other ids and
aliases, the package, the version, the file) and per vulnerability no group lists, a NOT SCANNED line per coverage gap, then a
summary.

Exit 0 every file scanned and clean, or nothing to scan; 1 findings; 2 the
scanner is missing or failed; 3 coverage gaps only. Findings and gaps are always
printed; the status is the worst of 2, then 1, then 3.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import pathlib
import re
import shlex
import shutil
import subprocess
import tempfile

# The lockfiles osv-scanner reads exactly, by ecosystem. requirements*.txt is
# best effort: only its exactly pinned lines are scanned, and the rest are gaps.
LOCKFILES = {
    "npm": ("package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lock"),
    "python": ("uv.lock", "poetry.lock", "Pipfile.lock", "pdm.lock"),
    "cargo": ("Cargo.lock",),
    "go": ("go.mod",),
    "ruby": ("Gemfile.lock",),
    "php": ("composer.lock",),
    "gradle": ("gradle.lockfile",),
    "dart": ("pubspec.lock",),
    "elixir": ("mix.lock",),
    "nuget": ("packages.lock.json",),
}
REQUIREMENTS = "requirements*.txt"
# A manifest that declares dependencies needs a lockfile of its ecosystem in its
# folder or a folder above it, or the versions it runs with are unknown.
MANIFESTS = {"package.json": "npm", "Cargo.toml": "cargo", "Gemfile": "ruby",
             "composer.json": "php", "pyproject.toml": "python", "pubspec.yaml": "dart"}
# A pin the scan vouches for: a PEP 508 name, optional extras, == and one version (with pip's
# optional trailing comma), as bare text or in parentheses, then an optional non-empty marker.
# ASCII only, as the grammars are. Each part is matched once, so a long malformed line costs
# linear time.
_EXTRA = r"[A-Za-z0-9][A-Za-z0-9._-]*"
# No two whitespace runs can meet: each optional part carries its own trailing space.
PINNED = re.compile(r"^(?P<name>[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)"
                    rf"(?:\s*\[\s*(?:{_EXTRA}(?:\s*,\s*{_EXTRA})*\s*)?\])?\s*"
                    r"(?:==\s*(?P<bare>[^\s;()=*$,]+)\s*(?:,\s*)?"
                    r"|\(\s*==\s*(?P<paren>[^\s;()=*$,]+)\s*(?:,\s*)?\)\s*)"
                    r"(?:;\s*\S.*)?$", re.ASCII)
# PEP 440's public and local versions; a leading v is allowed and dropped.
VERSION = re.compile(r"^v?((?:\d+!)?\d+(?:\.\d+)*(?:[-_.]?(?:a|b|rc|alpha|beta|pre|preview|c)[-_.]?\d*)?"
                     r"(?:-\d+|[-_.]?(?:post|rev|r)[-_.]?\d*)?(?:[-_.]?dev[-_.]?\d*)?(?:\+[a-z0-9]+(?:[-_.][a-z0-9]+)*)?)$",
                     re.I | re.ASCII)
# PEP 263's declaration, which pip honours in a requirements file's first two lines.
CODING = re.compile(rb"^[ \t\f]*#.*?coding[:=][ \t]*([-\w.]+)", re.M)
# The algorithms pip's hash checking accepts, and pip's KEY=VALUE for config settings.
HASH = re.compile(r"^(?:sha256|sha384|sha512):[0-9a-fA-F]+$", re.ASCII)
CONFIG_SETTING = re.compile(r"^[^=\s]+=", re.ASCII)
# Longer option text than any real index URL or hash list is not tokenized at all.
OPTIONS_LIMIT = 4096
# pip's own rules (req_file.py): a comment starts at a # that begins the line or follows
# whitespace, and only a whole-line comment stops a trailing backslash joining the next line.
# pip writes the first as (^|\s+)#.*$; one \s matches the same text without its quadratic cost.
COMMENT = re.compile(r"(^|\s)#.*$")
WHOLE_LINE_COMMENT = re.compile(r"^\s*#")
# Options pip reads on a line of their own that name no package and fetch nothing the scan
# would miss, and the options a pin may carry that change no package. Any other option,
# abbreviations included, is a gap. Each value option maps to the pattern its value must fit.
GLOBAL_FLAGS = {"--no-index", "--pre", "--prefer-binary", "--require-hashes"}
GLOBAL_VALUES = dict.fromkeys(("-i", "--index-url", "--extra-index-url", "-f", "--find-links",
                               "--trusted-host", "--only-binary", "--no-binary"))
PIN_VALUES = {"--hash": HASH, "--config-settings": CONFIG_SETTING}
IGNORED_ID = re.compile(r"""(?<![\w-])id\s*=\s*(?:"([^"]+)"|'([^']+)')""")
OVERRIDE = re.compile(r"^\s*\[\[\s*PackageOverrides\s*\]\]|PackageOverrides\s*=", re.M)
INSTALL_HINT = "brew install osv-scanner"


def wanted(name: str) -> bool:
    """A file the scan reads: a lockfile, a requirements file, a manifest, the scanner's config."""
    return (any(name in known for known in LOCKFILES.values()) or fnmatch.fnmatch(name, REQUIREMENTS)
            or name in MANIFESTS or name == "osv-scanner.toml")


def export_head(root: pathlib.Path, commit: str, into: pathlib.Path) -> list[str]:
    """Write the dependency files committed at `commit` into `into`, and nothing else;
    return the paths of committed symlinks with those names, which are never followed."""
    git = ["git", "-c", "core.fsmonitor=false", "-C", str(root)]
    tree = subprocess.run([*git, "ls-tree", "-r", "-z", commit], capture_output=True)
    if tree.returncode != 0:
        raise RuntimeError(tree.stderr.decode(errors="replace").strip() or "git ls-tree failed")
    links = []
    for record in filter(None, tree.stdout.split(b"\0")):
        meta, _, path = record.partition(b"\t")
        mode, kind, sha = meta.decode().split()
        rel = path.decode("utf-8", errors="surrogateescape")
        parts = pathlib.PurePosixPath(rel).parts
        if not wanted(parts[-1] if parts else ""):
            continue
        if mode == "120000":
            links.append(rel)
            continue
        if kind != "blob" or rel.startswith("/") or ".." in parts:
            continue
        blob = subprocess.run([*git, "cat-file", "blob", sha], capture_output=True)
        if blob.returncode != 0:
            raise RuntimeError(f"cannot read {rel} at {commit}")
        target = into.joinpath(*parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(blob.stdout)
    return links


def folder_of(rel: str) -> str:
    return rel.rsplit("/", 1)[0] + "/" if "/" in rel else ""


def declares_dependencies(name: str, text: str) -> bool:
    """A tooling-only manifest, such as a pyproject.toml holding ruff settings, has none."""
    try:
        if name == "package.json":
            data = json.loads(text)
            return any(data.get(k) for k in ("dependencies", "devDependencies",
                                             "optionalDependencies", "peerDependencies"))
        if name == "composer.json":
            data = json.loads(text)
            return bool(data.get("require") or data.get("require-dev"))
    except (ValueError, AttributeError):
        return True              # unreadable: assume it does, so a gap is not hidden
    if name == "pyproject.toml":
        project = re.search(r"^\s*dependencies\s*=\s*\[\s*[^\]\s]", text, re.M)
        groups = re.search(r"^\[(?:dependency-groups|project\.optional-dependencies)\]\s*\n\s*[\w-]+\s*=", text, re.M)
        tables = re.finditer(r"^\[tool\.poetry(?:\.group\.[^\].]+)?\.dependencies\]\s*\n(.*?)(?=^\[|\Z)",
                             text, re.M | re.S)
        return bool(project) or bool(groups) or any(
            line.strip() and not line.strip().startswith("#")
            and not re.match(r"python\s*=", line.strip())
            for table in tables for line in table[1].splitlines())
    if name == "pubspec.yaml":
        return bool(re.search(r"^(?:dev_)?dependencies:\s*\n[ \t]+\S", text, re.M))
    return True


def logical_lines(text: str) -> list[tuple[int, str]]:
    """pip's join_lines and ignore_comments: (first line number, line) for each requirement."""
    out, start, parts = [], None, []
    for number, line in enumerate(text.splitlines(), 1):
        if line.endswith("\\") and not WHOLE_LINE_COMMENT.match(line):
            start = start or number
            parts.append(line.strip("\\"))
            continue
        if WHOLE_LINE_COMMENT.match(line):
            line = " " + line         # as pip does, so the comment is removed below
        out.append((start or number, "".join(parts + [line]))); start, parts = None, []
    if parts:
        out.append((start, "".join(parts)))
    stripped = [(n, COMMENT.sub("", line).strip()) for n, line in out]
    return [(n, line) for n, line in stripped if line]


def names(token: str, short: str, long: str) -> bool:
    """Whether pip could read `token` as option `short`/`long`: the short form with its value
    attached, or the long form or an abbreviation of it."""
    flag = token.partition("=")[0]
    return (token.startswith(short) and not token.startswith("--")) or (len(flag) > 3 and long.startswith(flag))


def option_gap(tokens: list[str], flags: set[str], values: dict) -> str | None:
    """Why these option tokens stop the scan vouching for the line, or None. Known options
    are matched whole first, so --require-hashes is never read as --requirement."""
    pending = None                      # the value option whose value comes next
    for token in tokens:
        if pending is not None:
            if values[pending] and not values[pending].match(token):
                return "has an option the scan does not read"
            pending = None
            continue
        flag, eq, value = token.partition("=")
        if flag in flags and not eq:
            continue
        if flag in values:
            if eq and values[flag] and not values[flag].match(value):
                return "has an option the scan does not read"
            pending = None if eq else flag
            continue
        if names(token, "-r", "--requirement") or names(token, "-c", "--constraint"):
            return "includes another file, not followed"
        if names(token, "-e", "--editable"):
            return "is not pinned (editable)"
        return "has an option the scan does not read"
    return "has an option the scan does not read" if pending else None


def requirements_text(data: bytes) -> tuple[str | None, str]:
    """The file as pip would decode it, or None and why. Only UTF-8, with or without a BOM,
    is read: replacing a byte could move a line boundary pip sees."""
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    elif data.startswith((b"\xff\xfe", b"\xfe\xff")):
        return None, "not UTF-8"
    declared = CODING.search(b"\n".join(data.split(b"\n")[:2]))
    if declared and declared[1].decode("ascii").lower().replace("_", "-") not in ("utf-8", "utf8"):
        return None, "declares an encoding other than UTF-8"
    try:
        return data.decode("utf-8"), ""
    except UnicodeDecodeError:
        return None, "not UTF-8"


def read_requirements(text: str) -> tuple[list[str], list[str]]:
    """(the pins to scan, as name==version, and the gaps by line number). Lines are joined,
    commented and split into requirement and options as pip does; anything the scan cannot
    vouch for is a gap. A line is named by number, never by its text, since a URL
    requirement can carry a credential."""
    pins, gaps = [], []
    for number, line in logical_lines(text):
        # pip's break_args_options: the requirement runs up to the first word starting "-".
        words = line.split(" ")
        cut = next((i for i, w in enumerate(words) if w.startswith("-")), len(words))
        requirement, options = " ".join(words[:cut]).strip(), " ".join(words[cut:])
        if not requirement and "${" in line:
            # pip expands it before reading the options, so it can hold an include.
            gaps.append(f"line {number} has a version or variable the scan cannot use")
            continue
        try:
            if len(options) > OPTIONS_LIMIT:
                raise ValueError("too long")
            tokens = shlex.split(options)
        except ValueError:
            gaps.append(f"line {number} has an option the scan does not read")
            continue
        if requirement:
            why = option_gap(tokens, set(), PIN_VALUES)
        else:
            why = option_gap(tokens, GLOBAL_FLAGS, GLOBAL_VALUES)
        if why or not requirement:
            if why:
                gaps.append(f"line {number} {why}")
            continue
        pin = PINNED.match(requirement)
        version = VERSION.match((pin["bare"] or pin["paren"]) if pin else "")
        if not pin:
            gaps.append(f"line {number} is not pinned")
        elif not version or "${" in line:
            gaps.append(f"line {number} has a version or variable the scan cannot use")
        else:
            pins.append(f"{pin['name']}=={version[1]}")
    return pins, gaps


def readable(value) -> bool:
    """A string fit for one line of the report: not blank, no control characters."""
    return isinstance(value, str) and bool(value.strip()) and value.isprintable()


def shown(line: str) -> str:
    """A report line with every non-printable character escaped, so repository text such as
    a path holding a line break cannot forge another line."""
    return "".join(c if c.isprintable() else repr(c)[1:-1] for c in line)


def findings_in(stdout: str, rel: str) -> tuple[list[str], list[str]]:
    """(the FINDING lines in osv-scanner's JSON, the parts it could not read). What cannot be
    read is named as such, and everything else is still reported."""
    results = json.loads(stdout).get("results") if stdout.strip() else None
    if not isinstance(results, list):
        return [], ["no results list"]
    out, errors = [], []
    for result in results:
        # Every result names its packages, each with a name and a version, as the recorded answers do.
        if not isinstance(result, dict) or not isinstance(result.get("packages"), list):
            errors.append("a result without packages")
            continue
        for pkg in result["packages"]:
            rows, problems = package_findings(pkg, rel)
            out += rows; errors += problems
    return out, errors


def listed(pkg: dict, key: str):
    """The list at `key`; absent or null is empty, any other type is None."""
    value = pkg.get(key)
    return [] if value is None else value if isinstance(value, list) else None


def package_findings(pkg, rel: str) -> tuple[list[str], list[str]]:
    """(one row per advisory group, its other ids and aliases in brackets, and one per
    vulnerability no group lists; what could not be read). A bad group or vulnerability is
    an error of its own and the rest of the package is still reported."""
    p = pkg.get("package") if isinstance(pkg, dict) else None
    if not isinstance(p, dict) or not readable(p.get("name")) or not readable(p.get("version")):
        return [], ["a package without a name and version"]
    groups, vulns = listed(pkg, "groups"), listed(pkg, "vulnerabilities")
    rows, errors, grouped = [], [], set()
    if groups is None or vulns is None:
        errors.append("a package whose groups or vulnerabilities are not lists")
    for group in groups or []:
        ids = group.get("ids") if isinstance(group, dict) else None
        aliases = group.get("aliases") if isinstance(group, dict) else None
        aliases = [] if isinstance(group, dict) and aliases is None else aliases   # Go writes an empty slice as null
        if not (isinstance(ids, list) and ids and isinstance(aliases, list)
                and all(readable(i) for i in ids + aliases)):
            errors.append("a group without usable ids")
            continue
        grouped |= set(ids) | set(aliases)
        rows.append((ids[0], sorted(set(ids[1:] + aliases) - {ids[0]})))
    for vuln in vulns or []:
        vid = vuln.get("id") if isinstance(vuln, dict) else None
        if not readable(vid):
            errors.append("a vulnerability without a usable id")
        elif vid not in grouped:
            rows.append((vid, [])); grouped.add(vid)
    return ([f"FINDING {first} ({', '.join(rest)}) {p['name']} {p['version']} {rel}" for first, rest in rows],
            errors)


def say(line: str) -> None:
    """Print one report line; every line passes through shown(), whatever text it holds."""
    print(shown(line))


def scan(root: pathlib.Path, offline: bool) -> int:
    with tempfile.TemporaryDirectory(prefix="dependency-scan-") as tmp:
        tree = pathlib.Path(tmp) / "head"
        tree.mkdir()
        head = subprocess.run(["git", "-C", str(root), "rev-parse", "--verify", "HEAD^{commit}"],
                              capture_output=True, text=True)
        if head.returncode != 0:
            say(f"cannot read HEAD of {root}")
            return 2
        commit = head.stdout.strip()
        say(f"scanned commit {commit}")
        try:
            links = export_head(root, commit, tree)
        except (RuntimeError, OSError) as exc:
            say(f"cannot read {commit} of {root}: {exc}")
            return 2
        files = sorted(p.relative_to(tree).as_posix() for p in tree.rglob("*") if p.is_file())
        names = {rel: rel.rsplit("/", 1)[-1] for rel in files}
        lockfiles = {rel: eco for rel in files for eco, known in LOCKFILES.items() if names[rel] in known}
        requirements = {rel for rel in files if fnmatch.fnmatch(names[rel], REQUIREMENTS)}
        lockfiles.update({rel: "python" for rel in requirements})

        gaps, findings, failed = [], [], []
        for rel in links:
            gaps.append(f"NOT SCANNED {rel}: a symlink, not read")
        for rel in files:
            eco = MANIFESTS.get(names[rel])
            if not eco or not declares_dependencies(names[rel], (tree / rel).read_text(errors="replace")):
                continue
            if not any(e == eco and folder_of(rel).startswith(folder_of(f)) for f, e in lockfiles.items()):
                gaps.append(f"NOT SCANNED {rel}: declares dependencies and has no lockfile")
        for rel in files:
            if names[rel] == "osv-scanner.toml":
                text = (tree / rel).read_text(errors="replace")
                what = [a or b for a, b in IGNORED_ID.findall(text)]
                what += ["a package override"] * len(OVERRIDE.findall(text))
                say(f"{rel} can suppress findings: {', '.join(what) if what else 'nothing recognised'}")

        if not lockfiles:
            for line in gaps or ["no supported dependency files"]:
                say(line)
            return 3 if gaps else 0
        scanner = shutil.which("osv-scanner")
        if not scanner:
            say(f"osv-scanner is not installed — {INSTALL_HINT}")
            for line in gaps:
                say(line)
            return 2

        scanned = 0
        for rel in sorted(lockfiles):
            source = tree / rel
            if rel in requirements:
                # The scanner gets only the checked pins, so it can follow no include. They
                # replace the exported copy in place, beside any osv-scanner.toml it obeys.
                text, why = requirements_text(source.read_bytes())
                if text is None:
                    gaps.append(f"NOT SCANNED {rel}: {why}, not read")
                    continue
                pins, lines = read_requirements(text)
                gaps += [f"NOT SCANNED {rel}: {line}" for line in lines]
                if not pins:
                    gaps.append(f"NOT SCANNED {rel}: no pinned requirement")
                    continue
                source.write_text("\n".join(pins) + "\n")
            # The parser prefix keeps a colon in the path from being read as one.
            parser = "requirements.txt" if rel in requirements else names[rel]
            # The scanner reads only the config in the file's own folder, and drops one it
            # cannot load without failing; named, a config it cannot load stops the scan.
            config = source.parent / "osv-scanner.toml"
            cmd = [scanner, "scan", "source", "--format", "json", "--no-resolve",
                   *(["--offline"] if offline else []),
                   *(["--config", str(config)] if config.is_file() else []), "-L", f"{parser}:{source}"]
            # Its stderr is never read (it can quote a token), so it is never decoded either.
            run = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, cwd=tree)
            if run.returncode == 128:
                gaps.append(f"NOT SCANNED {rel}: no packages found")
                continue
            if run.returncode not in (0, 1):
                # Its own text is not copied out: it can quote a signed URL or a token.
                failed.append(f"osv-scanner failed on {rel} (exit {run.returncode}); rerun it by hand to see why")
                continue
            try:
                # Strict: a byte replaced in the JSON could pass for a readable advisory id.
                found, unreadable = findings_in(run.stdout.decode("utf-8"), rel)
            except (ValueError, AttributeError, TypeError):   # UnicodeDecodeError is a ValueError
                found, unreadable = [], ["not JSON"]
            if unreadable:
                failed.append(f"osv-scanner gave unreadable output for {rel}")
                findings += found
                continue
            if run.returncode == 1 and not found:
                # Exit 1 means it found something; an answer we cannot read is not clean.
                failed.append(f"osv-scanner reported vulnerabilities but none could be read for {rel}")
                continue
            findings += found
            scanned += 1
        for line in failed + findings + gaps:
            say(line)
        if scanned and not (failed or findings):
            say(f"{scanned} file{'' if scanned == 1 else 's'} scanned: no known vulnerabilities")
        return 2 if failed else 1 if findings else 3 if gaps else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", type=pathlib.Path, default=pathlib.Path("."))
    ap.add_argument("--offline", action="store_true", help="use a local database; never the network")
    args = ap.parse_args()
    return scan(args.root.resolve(), args.offline)


if __name__ == "__main__":
    raise SystemExit(main())
