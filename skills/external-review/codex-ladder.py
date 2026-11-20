#!/usr/bin/env python3
"""Rank the Codex models in Codex's model cache, best reviewer first.

Prints up to three `slug:effort` rungs, space-separated. Exits 1 with no output
when the cache is missing or not JSON; the caller treats that as "no Codex
reviewer".

Only models the cache lists as visible are offered. They rank newest version
first, then by family, by FAMILIES, with an unlisted family after every listed
one, then by slug. The cache's own `priority` is not used: it is OpenAI's
default pick, not a capability rank. Each rung takes the model's highest
supported effort other than `ultra`, which delegates work to other models.

Usage:
    codex-ladder.py [CACHE]    (default ~/.codex/models_cache.json)
"""
from __future__ import annotations

import json
import pathlib
import re
import sys

# The user's ranking of OpenAI families, strongest first.
FAMILIES = ("astra", "sol", "terra", "luna")
# Lowest to highest. `ultra` is left out on purpose: it delegates the work.
EFFORTS = ("none", "minimal", "low", "medium", "high", "xhigh", "max")
VERSION = re.compile(r"\d+(?:\.\d+)*")


def version_key(version: str) -> tuple[int, ...]:
    """Newest first, with 4 read as 4.0.0 so that 4.1 sorts above it."""
    parts = [int(n) for n in version.split(".")]
    return tuple(-n for n in parts + [0] * (4 - len(parts)))


def rank(slug: str) -> tuple:
    words = slug.split("-")
    version = next((w for w in words if VERSION.fullmatch(w)), None)
    family = next((FAMILIES.index(w) for w in words if w in FAMILIES), len(FAMILIES))
    return (
        (0, version_key(version)) if version else (1, ()),
        family,
        slug,
    )


def ladder(models: list[dict]) -> list[str]:
    rungs = []
    for m in sorted((m for m in models if m.get("visibility") == "list"), key=lambda m: rank(m["slug"])):
        supported = [e.get("effort") for e in m.get("supported_reasoning_levels", [])]
        efforts = [e for e in EFFORTS if e in supported]
        if efforts:
            rungs.append(f"{m['slug']}:{efforts[-1]}")
    return rungs[:3]


def main() -> int:
    path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "~/.codex/models_cache.json").expanduser()
    try:
        models = json.loads(path.read_text())["models"]
    except (OSError, ValueError, KeyError, TypeError):
        return 1
    print(" ".join(ladder(models)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
