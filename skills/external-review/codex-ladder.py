#!/usr/bin/env python3
"""Rank the Codex models in Codex's model cache, best reviewer first.

Prints up to three distinct `slug:effort` rungs, space-separated. Exits 1 with
no output when the cache is missing, not JSON or has no list of models; the
caller treats that as "no Codex reviewer". A malformed entry is skipped.

Only models the cache lists as visible are offered. They rank by family, by
FAMILIES, with an unlisted family after every listed one; then newest version
first (the number after `gpt`; anything else ranks last); then by slug. The
model comes first, then its effort. The cache's own `priority` is not used: it is OpenAI's
default pick, not a capability rank. Each rung runs at `high`, the user's
default, or where the model lacks it at the first of EFFORTS it supports.
Another effort is used only when the user asks for it.

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
# The effort each rung runs at: the first of these the model supports. High is
# the user's default. Nothing below medium is a review, and `ultra` is left out
# on purpose: it delegates the work to other models.
EFFORTS = ("high", "xhigh", "max", "medium")
VERSION = re.compile(r"\d+(?:\.\d+)*")
SLUG = re.compile(r"[a-z0-9][a-z0-9.-]*")


def version_key(version: str) -> tuple[int, ...]:
    """Newest first, with 4 read as 4.0.0 so that 4.1 sorts above it."""
    parts = [int(n) for n in version.split(".")]
    return tuple(-n for n in parts + [0] * (4 - len(parts)))


def rank(slug: str) -> tuple:
    words = slug.split("-")
    # The version is the word after `gpt` (gpt-6.2-sol); in o3-2025-04-16 the
    # numbers are a date, and such a model ranks after every versioned one.
    version = words[1] if words[0] == "gpt" and len(words) > 1 and VERSION.fullmatch(words[1]) else None
    family = next((FAMILIES.index(w) for w in words if w in FAMILIES), len(FAMILIES))
    return (
        family,
        (0, version_key(version)) if version else (1, ()),
        slug,
    )


def usable(m) -> bool:
    """A listed model entry with a well-formed slug; anything else is skipped, not fatal."""
    return (isinstance(m, dict) and m.get("visibility") == "list"
            and isinstance(m.get("slug"), str) and SLUG.fullmatch(m["slug"]) is not None)


def ladder(models: list) -> list[str]:
    # A slug listed more than once offers every effort any of its entries does.
    supported: dict[str, set] = {}
    for m in filter(usable, models):
        levels = m.get("supported_reasoning_levels")
        efforts = {e.get("effort") for e in levels if isinstance(e, dict)} if isinstance(levels, list) else set()
        supported.setdefault(m["slug"], set()).update(efforts)
    rungs = []
    for slug, efforts in supported.items():
        effort = next((e for e in EFFORTS if e in efforts), None)
        if effort:
            rungs.append((rank(slug), f"{slug}:{effort}"))
    return [rung for _, rung in sorted(rungs)][:3]


def main() -> int:
    path = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "~/.codex/models_cache.json").expanduser()
    try:
        models = json.loads(path.read_text())["models"]
    except (OSError, ValueError, KeyError, TypeError):
        return 1
    if not isinstance(models, list):
        return 1
    rungs = ladder(models)
    print(" ".join(rungs))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
