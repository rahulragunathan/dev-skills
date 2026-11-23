#!/usr/bin/env python3
"""Scan the committed dependency files for known vulnerabilities, with osv-scanner.

Usage:
    dependency-scan.py [--root DIR] [--offline]

It reads only what is committed at HEAD, from an export of its regular files, so
an untracked or ignored file, an untracked osv-scanner.toml and a symlink's
target cannot change the verdict. A tracked osv-scanner.toml is honoured, and
the output names what it ignores. Each supported file is scanned on its own,
so its own exit status counts. Nothing is installed: lockfiles are read as
they are.

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
import tarfile
import tempfile

# The lockfiles osv-scanner reads exactly, by ecosystem. requirements*.txt is
# best effort: the scanner skips any line that is not pinned.
LOCKFILES = {
    "npm": ("package-lock.json", "pnpm-lock.yaml", "yarn.lock"),
    "python": ("uv.lock", "poetry.lock", "Pipfile.lock", "pdm.lock"),
    "cargo": ("Cargo.lock",),
    "go": ("go.mod",),
    "ruby": ("Gemfile.lock",),
    "php": ("composer.lock",),
    "gradle": ("gradle.lockfile",),
}
REQUIREMENTS = "requirements*.txt"
# A manifest that declares dependencies needs a lockfile of its ecosystem in its
# folder or a folder above it, or the versions it runs with are unknown.
MANIFESTS = {"package.json": "npm", "Cargo.toml": "cargo", "Gemfile": "ruby",
             "composer.json": "php", "pyproject.toml": "python"}
PINNED = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*(\[[^\]]*\])?\s*===?\s*[^\s;,]+\s*(;.*)?$")
IGNORED_ID = re.compile(r'^\s*id\s*=\s*"([^"]+)"', re.M)
INSTALL_HINT = "brew install osv-scanner (dev-setup's bootstrap.sh installs it)"


def export_head(root: pathlib.Path, into: pathlib.Path) -> None:
    """Regular files committed at HEAD, nothing else: no symlink is followed."""
    archive = subprocess.run(["git", "-c", "core.fsmonitor=false", "-C", str(root), "archive", "HEAD"],
                             capture_output=True)
    if archive.returncode != 0:
        raise RuntimeError(archive.stderr.decode(errors="replace").strip() or "git archive failed")
    with tempfile.TemporaryFile() as tar_bytes:
        tar_bytes.write(archive.stdout)
        tar_bytes.seek(0)
        with tarfile.open(fileobj=tar_bytes) as tar:
            for member in tar.getmembers():
                parts = pathlib.PurePosixPath(member.name).parts
                if not member.isreg() or member.name.startswith("/") or ".." in parts:
                    continue
                target = into.joinpath(*parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as src, open(target, "wb") as dst:
                    shutil.copyfileobj(src, dst)


def folder_of(rel: str) -> str:
    return rel.rsplit("/", 1)[0] + "/" if "/" in rel else ""


def declares_dependencies(name: str, text: str) -> bool:
    """A tooling-only manifest, such as a pyproject.toml holding ruff settings, has none."""
    try:
        if name == "package.json":
            data = json.loads(text)
            return any(data.get(k) for k in ("dependencies", "devDependencies", "optionalDependencies"))
        if name == "composer.json":
            return bool(json.loads(text).get("require"))
    except (ValueError, AttributeError):
        return True              # unreadable: assume it does, so a gap is not hidden
    if name == "pyproject.toml":
        project = re.search(r"^dependencies\s*=\s*\[\s*[^\]\s]", text, re.M)
        poetry = re.search(r"^\[tool\.poetry(?:\.group\.\w+)?\.dependencies\]\s*\n(.*?)(?=^\[|\Z)",
                           text, re.M | re.S)
        return bool(project) or bool(poetry and any(
            line.strip() and not line.strip().startswith(("#", "python"))
            for line in poetry[1].splitlines()))
    return True


def unpinned(text: str) -> list[str]:
    """Requirement lines without an exact version, which the scanner skips silently."""
    out = []
    for line in text.splitlines():
        line = line.split(" #", 1)[0].strip()
        if line and not line.startswith(("#", "-")) and not PINNED.match(line):
            out.append(line)
    return out


def findings_in(stdout: str, rel: str) -> list[str]:
    results = json.loads(stdout).get("results", []) if stdout.strip() else []
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
            export_head(root, tree)
        except RuntimeError as exc:
            print(f"cannot read HEAD of {root}: {exc}")
            return 2
        files = sorted(p.relative_to(tree).as_posix() for p in tree.rglob("*") if p.is_file())
        names = {rel: rel.rsplit("/", 1)[-1] for rel in files}
        lockfiles = {rel: eco for rel in files for eco, known in LOCKFILES.items() if names[rel] in known}
        lockfiles.update({rel: "python" for rel in files if fnmatch.fnmatch(names[rel], REQUIREMENTS)})

        gaps, findings, failed = [], [], []
        for rel in files:
            eco = MANIFESTS.get(names[rel])
            if not eco or not declares_dependencies(names[rel], (tree / rel).read_text(errors="replace")):
                continue
            if not any(e == eco and folder_of(rel).startswith(folder_of(f)) for f, e in lockfiles.items()):
                gaps.append(f"NOT SCANNED {rel}: declares dependencies and has no lockfile")
        for rel in files:
            if names[rel] == "osv-scanner.toml":
                ids = IGNORED_ID.findall((tree / rel).read_text(errors="replace"))
                print(f"{rel} ignores {', '.join(ids) if ids else 'nothing'}")

        if not lockfiles:
            print("\n".join(gaps) if gaps else "no supported dependency files")
            return 3 if gaps else 0
        scanner = shutil.which("osv-scanner")
        if not scanner:
            print(f"osv-scanner is not installed — {INSTALL_HINT}")
            for line in gaps:
                print(line)
            return 2

        scanned = 0
        for rel in sorted(lockfiles):
            requirements = fnmatch.fnmatch(names[rel], REQUIREMENTS)
            if requirements:
                gaps += [f"NOT SCANNED {rel}: {line} is not pinned"
                         for line in unpinned((tree / rel).read_text(errors="replace"))]
            # The parser prefix keeps a colon in the path from being read as one.
            parser = "requirements.txt" if requirements else names[rel]
            cmd = [scanner, "scan", "source", "--format", "json", "--no-resolve",
                   *(["--offline"] if offline else []), "-L", f"{parser}:{tree / rel}"]
            run = subprocess.run(cmd, capture_output=True, text=True, cwd=tree)
            if run.returncode == 128:
                gaps.append(f"NOT SCANNED {rel}: no packages found")
                continue
            if run.returncode not in (0, 1):
                err = " ".join(run.stderr.split())[-300:]
                failed.append(f"osv-scanner failed on {rel} (exit {run.returncode}): {err}")
                continue
            try:
                findings += findings_in(run.stdout, rel)
            except (ValueError, AttributeError):
                failed.append(f"osv-scanner gave unreadable output for {rel}")
                continue
            scanned += 1
        for line in failed + findings + gaps:
            print(line)
        if not (failed or findings):
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
