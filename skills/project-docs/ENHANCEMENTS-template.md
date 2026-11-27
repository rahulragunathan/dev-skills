# Enhancements

Candidate work, highest priority first. [ROADMAP.md](ROADMAP.md) carries the one-line index;
this file carries enough detail to pick an item up without digging.

Each entry has a stable ID — use it in branch names (`feature/enh-01-<slug>`) and in the
CHANGELOG entry that closes it. How an entry enters, ships or is dropped is in
[ROADMAP.md](ROADMAP.md).

## Priority

`roadmap.py check` reads these levels, in row order, from the template bundled with
`project-docs`. In a project's own copy this table is for reading: editing it changes nothing.

Priority is about value, not urgency. Effort is a rough estimate — a session, or days.

| Level | Means |
| ------- | ------- |
| **High** | Closes a gap hit during real use. |
| **Medium** | Worth doing when the area is already open. Removes a sharp edge or a duplication. |
| **Low** | Tidying. Do it while passing through. |

---

<a id="enh-01"></a>

## ENH-01 — `<title>`

**Priority:** <High | Medium | Low> · **Effort:** <~hours / ~days>
**Where:** [file.py](../file.py) — `def the_function_to_change(` · **Regression Net:** `tests/test_<x>.py`

### What It Is

<the change, in a paragraph or two>

### Why It Matters

<the gap it closes or the duplication it removes — concrete, in the project's domain terms>

### Steps To Reproduce

<numbered steps that show the behaviour, for an entry that describes one. Delete this section
otherwise.>

### Notes For The Work

<approach, the constraints that would trip someone up, invariants to preserve, and related
IDs worth bundling into the same pass>
