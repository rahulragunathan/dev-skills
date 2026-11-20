#!/usr/bin/env python3
"""Rank the Gemini models `agy models` lists, best reviewer first.

Reads `agy models` output on stdin and prints up to three model ids,
space-separated. Prints an empty line when no model qualifies; the caller
treats that as "no Gemini reviewer", never as an empty loop.

Orchestrator models and `-low` rungs are never offered. The rest rank, most
significant first:
  1. version, newest first;
  2. a full model before a light tier (flash, lite);
  3. review grade (xhigh, high) before medium, and medium before anything
     else, a missing effort suffix included: the id is the only way to tell
     agy the effort, so an id without one runs at whatever agy defaults to;
  4. family, by FAMILIES, with an unlisted family after every listed one;
  5. effort, xhigh before high.
"""
from __future__ import annotations

import re
import sys

# The user's ranking of Gemini families, strongest first.
FAMILIES = ("carbon", "argon", "neon", "hydrogen")
LIGHT_TIERS = {"flash", "lite"}
# (grade, tie-break) for each effort suffix; anything else is grade 2.
EFFORT_RANK = {"xhigh": (0, 0), "high": (0, 1), "medium": (1, 0)}
VERSION = re.compile(r"\d+(?:\.\d+)*")


def version_key(version: str) -> tuple[int, ...]:
    """Newest first, with 4 read as 4.0.0 so that 4.1 sorts above it."""
    parts = [int(n) for n in version.split(".")]
    return tuple(-n for n in parts + [0] * (4 - len(parts)))


def rank(model: str) -> tuple:
    words = model.split("-")[1:]
    version = words.pop(0) if words and VERSION.fullmatch(words[0]) else None
    grade, tie = EFFORT_RANK.get(words[-1] if words else "", (2, 0))
    family = next((FAMILIES.index(w) for w in words if w in FAMILIES), len(FAMILIES))
    return (
        (0, version_key(version)) if version else (1, ()),
        1 if LIGHT_TIERS & set(words) else 0,
        grade,
        family,
        tie,
    )


def ladder(lines) -> list[str]:
    ids = [line.split()[0] for line in lines if line.strip()]
    usable = [m for m in ids if m.startswith("gemini-")
              and "orchestrator" not in m and not m.endswith("-low")]
    return sorted(usable, key=rank)[:3]


if __name__ == "__main__":
    print(" ".join(ladder(sys.stdin)))
