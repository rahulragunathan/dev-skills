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
refuses any other Kind. It does not check the order of open questions. In a project's own copy this table is for reading: editing it changes nothing.

| Kind | Means |
| ------ | ------- |
| **Decision** | The code does something defensible, but nobody has chosen whether it is right. Asks for an answer. |
| **Verification** | The behavior is probably correct and nothing proves it. Asks for a test, or a deliberate acceptance. |
| **Risk** | Known, understood, accepted for now. Asks for nothing until circumstances change. |

---

<a id="unk-01"></a>

## UNK-01 — <the question, as a question>

**Kind:** <Decision | Verification | Risk>
**Where:** [file.py](../file.py)

<what the code does now, and why it is unsettled>

**What settles it:** <the decision to make, the test to write, or — for a Risk — the
circumstances that would make this worth revisiting>
