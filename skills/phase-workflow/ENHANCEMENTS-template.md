# Enhancements

Candidate work, highest priority first. [ROADMAP.md](ROADMAP.md) carries the one-line index;
this file carries enough detail to pick an item up without digging.

Each entry has a stable ID — use it in branch names (`feature/enh-01-<slug>`) and in the
CHANGELOG entry that closes it. When an item ships, delete it from here and from the ROADMAP
index; the record lives in [CHANGELOG.md](../CHANGELOG.md). An item dropped rather than built
moves to "Decisions taken and not taken" in [CLAUDE.md](../CLAUDE.md). IDs are never reused.

## Priority

Priority is about value, not urgency. Effort is a rough estimate — a session, or days.

| Level | Means |
| ------- | ------- |
| **High** | Closes a gap hit during real use. |
| **Medium** | Worth doing when the area is already open. Removes a sharp edge or a duplication. |
| **Low** | Tidying. Do it while passing through. |

---

<a id="enh-01"></a>

## ENH-01 — `<title>`

**Priority:** `<level>` · **Effort:** `<~hours / ~days>`
**Where:** [file.py](../file.py) — `def the_function_to_change(` · **Regression net:** `tests/test_<x>.py`

### What it is

<the change, in a paragraph or two>

### Why it matters

<the gap it closes or the duplication it removes — concrete, in the project's domain terms>

### Notes for the work

<approach, the constraints that would trip someone up, invariants to preserve, and related
IDs worth bundling into the same pass>
