#!/usr/bin/env python3
"""Rank the Gemini models `agy models` lists, best reviewer first.

Reads `agy models` output on stdin and prints up to three model ids, one per
model class, space-separated. Prints an empty line when no model qualifies; the
caller treats that as "no Gemini reviewer", never as an empty loop.

The model class comes first, then the effort: the user's rule. A class is the
id without its effort suffix (gemini-4-neon for gemini-4-neon-high). Classes
rank, most significant first:
  1. family, by FAMILIES, with an unlisted family (older lines such as flash
     or lite included) after every listed one;
  2. version, newest first;
  3. class name, so the order never depends on how agy printed the list.
Each class is offered once, at the first of PREFERENCE it has: high, the
default; then the suffix-less id, which the review loop runs with
`--effort high`; then xhigh; then medium. Orchestrator models, efforts below
medium (low, minimal, none) and ultra, which delegates the work, are never
offered. Another effort is used only when the user asks for it.
"""
from __future__ import annotations

import re
import sys

# The user's ranking of Gemini families, strongest first.
FAMILIES = ("carbon", "argon", "neon", "hydrogen")
# Within a class, the variant to run: "" is the suffix-less id.
PREFERENCE = ("high", "", "xhigh", "medium")
EFFORTS = {"high", "xhigh", "medium", "low", "minimal", "none", "ultra"}
VERSION = re.compile(r"\d+(?:\.\d+)*")


def version_key(version: str) -> tuple[int, ...]:
    """Newest first, with 4 read as 4.0.0 so that 4.1 sorts above it."""
    parts = [int(n) for n in version.split(".")]
    return tuple(-n for n in parts + [0] * (4 - len(parts)))


def split(model: str) -> tuple[str, str]:
    """(class, effort suffix), with "" for an id that carries no effort."""
    head, _, last = model.rpartition("-")
    return (head, last) if last in EFFORTS else (model, "")


def rank(model_class: str) -> tuple:
    words = model_class.split("-")[1:]
    version = words.pop(0) if words and VERSION.fullmatch(words[0]) else None
    family = next((FAMILIES.index(w) for w in words if w in FAMILIES), len(FAMILIES))
    return (
        family,
        (0, version_key(version)) if version else (1, ()),
        model_class,
    )


def ladder(lines) -> list[str]:
    ids = {line.split()[0] for line in lines if line.strip()}
    variants: dict[str, dict[str, str]] = {}
    for m in ids:
        if m.startswith("gemini-") and "orchestrator" not in m:
            model_class, effort = split(m)
            variants.setdefault(model_class, {})[effort] = m
    rungs = []
    for model_class in sorted(variants, key=rank):
        pick = next((variants[model_class][e] for e in PREFERENCE if e in variants[model_class]), None)
        if pick:
            rungs.append(pick)
    return rungs[:3]


if __name__ == "__main__":
    print(" ".join(ladder(sys.stdin)))
