#!/usr/bin/env python3
"""Scan the committed dependency files for known vulnerabilities, with osv-scanner.

Usage:
    dependency-scan.py [--root DIR] [--offline]

It reads only the dependency files committed at HEAD, blob by blob from git's
tree (so export-ignore attributes drop nothing, and no other file is copied
out), so an untracked or ignored file and an untracked osv-scanner.toml cannot
change the verdict. A committed symlink is never followed; one named like a
dependency file is a coverage gap. A requirements file that includes another
file is a gap and is not scanned, since the scanner would follow the include
wherever it points. A tracked osv-scanner.toml is honoured, and the output
names what it can suppress. Each supported file is scanned on its own, so its
own exit status counts. Nothing is installed: lockfiles are read as they are.

Package names and versions, never source, go to the OSV database (api.osv.dev);
a private package name can still identify an internal service. --offline uses a
local database downloaded beforehand instead, and fails without one.

Output: a FINDING line per advisory group (its first id, its aliases, the
package, the version, the file), a NOT SCANNED line per coverage gap, then a
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
import shutil
import subprocess
import tempfile

# The lockfiles osv-scanner reads exactly, by ecosystem. requirements*.txt is
# best effort: the scanner skips any line that is not pinned.
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
             "composer.json": "php", "pyproject.toml": "python"}
PINNED = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*(\[[^\]]*\])?\s*===?\s*[^\s;,\\*]+\s*(;.*)?$")
INCLUDE = re.compile(r"^\s*(-r|-c|--requirement|--constraint)(\s|=)")
# pip-compile --generate-hashes adds options and continuation lines after a pin.
OPTIONS = re.compile(r"\s+--[\w-]+(=\S*)?|\s*\\$")
IGNORED_ID = re.compile(r"""(?<![\w-])id\s*=\s*(?:"([^"]+)"|'([^']+)')""")
OVERRIDE = re.compile(r"^\s*\[\[\s*PackageOverrides\s*\]\]|PackageOverrides\s*=", re.M)
USERINFO = re.compile(r"(://)[^/@\s]+@")
INSTALL_HINT = "brew install osv-scanner"


def wanted(name: str) -> bool:
    """A file the scan reads: a lockfile, a requirements file, a manifest, the scanner's config."""
    return (any(name in known for known in LOCKFILES.values()) or fnmatch.fnmatch(name, REQUIREMENTS)
            or name in MANIFESTS or name == "osv-scanner.toml")


def export_head(root: pathlib.Path, into: pathlib.Path) -> list[str]:
    """Write the dependency files committed at HEAD into `into`, and nothing else;
    return the paths of committed symlinks with those names, which are never followed."""
    git = ["git", "-c", "core.fsmonitor=false", "-C", str(root)]
    tree = subprocess.run([*git, "ls-tree", "-r", "-z", "HEAD"], capture_output=True)
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
            raise RuntimeError(f"cannot read {rel} at HEAD")
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
        poetry = re.search(r"^\[tool\.poetry(?:\.group\.[^\].]+)?\.dependencies\]\s*\n(.*?)(?=^\[|\Z)",
                           text, re.M | re.S)
        return bool(project) or bool(groups) or bool(poetry and any(
            line.strip() and not line.strip().startswith("#")
            and not re.match(r"python\s*=", line.strip())
            for line in poetry[1].splitlines()))
    return True


def unpinned(text: str) -> list[int]:
    """Numbers of the requirement lines without an exact version, which the scanner
    skips silently. Lines are named by number: a URL requirement can carry a credential."""
    out = []
    for number, line in enumerate(text.splitlines(), 1):
        line = OPTIONS.sub("", line.split(" #", 1)[0]).strip()
        if not line or line.startswith("#") or INCLUDE.match(line):
            continue
        if line.startswith("-") and not line.startswith(("-e", "--editable")):
            continue                      # other pip options name no package
        if not PINNED.match(line):
            out.append(number)
    return out


def includes(text: str) -> list[int]:
    return [n for n, line in enumerate(text.splitlines(), 1) if INCLUDE.match(line)]


def masked(text: str) -> str:
    return USERINFO.sub(r"\1***@", text)


def findings_in(stdout: str, rel: str) -> list[str]:
    """The FINDING lines in osv-scanner's JSON; ValueError for anything not shaped as its answer."""
    results = json.loads(stdout).get("results") if stdout.strip() else None
    if not isinstance(results, list):
        raise ValueError("no results list")
    out = []
    for result in results:
        for pkg in result.get("packages", []):
            p = pkg.get("package", {})
            # One row per advisory group: its ids and aliases name one vulnerability.
            for group in pkg.get("groups", []):
                ids = group.get("ids") or ["?"]
                aliases = sorted(set(group.get("aliases", [])) - {ids[0]})
                out.append(f"FINDING {ids[0]} ({', '.join(aliases)}) {p.get('name')} {p.get('version')} {rel}")
    return out


def scan(root: pathlib.Path, offline: bool) -> int:
    with tempfile.TemporaryDirectory(prefix="dependency-scan-") as tmp:
        tree = pathlib.Path(tmp) / "head"
        tree.mkdir()
        try:
            links = export_head(root, tree)
        except (RuntimeError, OSError) as exc:
            print(f"cannot read HEAD of {root}: {exc}")
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
                print(f"{rel} can suppress findings: {', '.join(what) if what else 'nothing recognised'}")

        if not lockfiles:
            for line in gaps or ["no supported dependency files"]:
                print(line)
            return 3 if gaps else 0
        scanner = shutil.which("osv-scanner")
        if not scanner:
            print(f"osv-scanner is not installed — {INSTALL_HINT}")
            for line in gaps:
                print(line)
            return 2

        scanned = 0
        for rel in sorted(lockfiles):
            if rel in requirements:
                text = (tree / rel).read_text(errors="replace")
                included = includes(text)
                if included:
                    # The scanner would follow the include wherever it points, outside HEAD too.
                    gaps.append(f"NOT SCANNED {rel}: line {included[0]} includes another file")
                    continue
                gaps += [f"NOT SCANNED {rel}: line {n} is not pinned" for n in unpinned(text)]
            # The parser prefix keeps a colon in the path from being read as one.
            parser = "requirements.txt" if rel in requirements else names[rel]
            cmd = [scanner, "scan", "source", "--format", "json", "--no-resolve",
                   *(["--offline"] if offline else []), "-L", f"{parser}:{tree / rel}"]
            run = subprocess.run(cmd, capture_output=True, text=True, cwd=tree)
            if run.returncode == 128:
                gaps.append(f"NOT SCANNED {rel}: no packages found")
                continue
            if run.returncode not in (0, 1):
                err = masked(" ".join(run.stderr.split()))[-300:]
                failed.append(f"osv-scanner failed on {rel} (exit {run.returncode}): {err}")
                continue
            try:
                found = findings_in(run.stdout, rel)
            except (ValueError, AttributeError, TypeError):
                failed.append(f"osv-scanner gave unreadable output for {rel}")
                continue
            if run.returncode == 1 and not found:
                # Exit 1 means it found something; an answer we cannot read is not clean.
                failed.append(f"osv-scanner reported vulnerabilities but none could be read for {rel}")
                continue
            findings += found
            scanned += 1
        for line in failed + findings + gaps:
            print(line)
        if scanned and not (failed or findings):
            print(f"{scanned} file{'' if scanned == 1 else 's'} scanned: no known vulnerabilities")
        return 2 if failed else 1 if findings else 3 if gaps else 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--root", type=pathlib.Path, default=pathlib.Path("."))
    ap.add_argument("--offline", action="store_true", help="use a local database; never the network")
    args = ap.parse_args()
    return scan(args.root.resolve(), args.offline)


if __name__ == "__main__":
    raise SystemExit(main())
