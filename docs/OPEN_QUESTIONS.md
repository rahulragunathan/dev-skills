# Open Questions

Things not yet settled, decisions first. [ROADMAP.md](ROADMAP.md) carries the one-line index;
this file carries the reasoning.

These are not work items. Each is a decision waiting to be made, a gap in what the tests
prove, or a risk knowingly carried. An entry that turns out to describe defined wrong
behavior with a known fix is a bug — move it to [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

Each entry has a stable ID. When one is settled it leaves this file: into the code plus a
CHANGELOG entry if it changed anything, into KNOWN_ISSUES or ENHANCEMENTS if it became work,
or into "Decisions taken and not taken" in [AGENTS.md](../AGENTS.md) if the answer was to do
nothing. IDs are never reused.

## Kind

`roadmap.py check` reads these levels from the template bundled with `project-docs`, and
refuses any other Kind, and checks that open questions follow its row order. In a project's own
copy this table is for reading: editing it changes nothing.

| Kind | Means |
| ------ | ------- |
| **Decision** | The code does something defensible, but nobody has chosen whether it is right. Asks for an answer. |
| **Verification** | The behavior is probably correct and nothing proves it. Asks for a test, or a deliberate acceptance. |
| **Risk** | Known, understood, accepted for now. Asks for nothing until circumstances change. |

---

<a id="unk-04"></a>

## UNK-04 — Does an undefined input-format check bound a shared cache's keys?

**Kind:** Decision
**Where:** [s02-lifetime-surface.md](../skills/design-review/tests/s02-lifetime-surface.md) — `Fail an unbounded`

S02 Lifetime fails "an unbounded shared cache". The fixture's `taxonomy.category_for` cache is
keyed by SKU prefixes from merchant files. Some designs keep that cache unbounded and say the
prefix is format-checked first, without defining the format. A defined format, such as three
uppercase letters, bounds the keys; an undefined one does not show a bound.

Graders split on this argument. The round-7 correction failed with-skill replicate 3 for it. In
round 9 the graders failed with-skill replicate 3 for it, but passed baseline replicate 2, whose
design differs mainly by naming a `normalise_prefix` function. S02 Lifetime tallies depend on
the answer.

**What Settles It:** choose one reading and write it into the S02 Lifetime condition: either a
key bound must be stated (a maxsize, a finite key set or a defined format), or a named
normalisation step is enough. The reworded condition changes the condition hash, so the affected rows would need
re-grading against it.

**Source:** claude-opus-5 — round-9 grading, 2026-09-14.

---

<a id="unk-05"></a>

## UNK-05 — What drives repeat review findings?

**Kind:** Verification
**Where:** [external-review/SKILL.md](../skills/external-review/SKILL.md) — `in code an earlier fix of this review wrote`

External review often needs several passes, and later passes keep finding problems. It is not
known how many of the findings in a narrow pass are in code the previous pass's fixes wrote, and
how many are documentation drift those fixes caused.

**What Settles It:** the per-pass counts the review record now keeps, read across a few phases.
If most later findings sit in fix code, the fix step needs more care. A narrow pass never reviews
untouched code, so these counts cannot say what a first pass missed; that would need a separate
full-scope sample.

**Source:** gpt-6.2-sol:max, gpt-6.2-astra:max — plan review, project-docs phase, 2026-11-20;
narrowed after gpt-6.2-astra:max — phase review pass 1, 2026-11-22.
