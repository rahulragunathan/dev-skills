#!/usr/bin/env python3
"""Rank the Gemini models `agy models` lists, best reviewer first.

Reads `agy models` output on stdin and prints up to three distinct model ids,
space-separated. Prints an empty line when no model qualifies; the caller
treats that as "no Gemini reviewer", never as an empty loop.

Orchestrator models, efforts below medium (low, minimal, none) and ultra,
which delegates the work, are never offered. The rest rank, most significant first:
  1. version, newest first;
  2. a full model before a light tier (flash, lite);
  3. effort: high, the user's default, then xhigh, then medium, then anything
     else, a missing effort suffix included: the id is the only way to tell
     agy the effort, so an id without one runs at whatever agy defaults to;
  4. family, by FAMILIES, with an unlisted family after every listed one;
  5. model id, so the order never depends on how agy printed the list.
"""
from __future__ import annotations

import re
import sys

# The user's ranking of Gemini families, strongest first.
FAMILIES = ("carbon", "argon", "neon", "hydrogen")
LIGHT_TIERS = {"flash", "lite"}
# The rank of each effort suffix; anything else ranks after these.
EFFORT_RANK = {"high": 0, "xhigh": 1, "medium": 2}
# Never offered: below a review's floor, or (ultra) delegating the work.
EXCLUDED = ("low", "minimal", "none", "ultra")
VERSION = re.compile(r"\d+(?:\.\d+)*")


def version_key(version: str) -> tuple[int, ...]:
    """Newest first, with 4 read as 4.0.0 so that 4.1 sorts above it."""
    parts = [int(n) for n in version.split(".")]
    return tuple(-n for n in parts + [0] * (4 - len(parts)))


def rank(model: str) -> tuple:
    words = model.split("-")[1:]
    version = words.pop(0) if words and VERSION.fullmatch(words[0]) else None
    effort = EFFORT_RANK.get(words[-1] if words else "", len(EFFORT_RANK))
    family = next((FAMILIES.index(w) for w in words if w in FAMILIES), len(FAMILIES))
    return (
        (0, version_key(version)) if version else (1, ()),
        1 if LIGHT_TIERS & set(words) else 0,
        effort,
        family,
        model,
    )


def ladder(lines) -> list[str]:
    ids = [line.split()[0] for line in lines if line.strip()]
    usable = {m for m in ids if m.startswith("gemini-")
              and "orchestrator" not in m and m.rsplit("-", 1)[-1] not in EXCLUDED}
    return sorted(usable, key=rank)[:3]


if __name__ == "__main__":
    print(" ".join(ladder(sys.stdin)))
