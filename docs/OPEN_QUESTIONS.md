# Open Questions

Things not yet settled, decisions first. [ROADMAP.md](ROADMAP.md) carries the one-line index;
this file carries the reasoning.

These are not work items. Each is a decision waiting to be made, a gap in what the tests
prove, or a risk knowingly carried. An entry that turns out to describe defined wrong
behavior with a known fix is a bug — move it to [KNOWN_ISSUES.md](KNOWN_ISSUES.md).

Each entry has a stable ID. When one is settled it leaves this file: into the code plus a
CHANGELOG entry if it changed anything, into KNOWN_ISSUES or ENHANCEMENTS if it became work,
or into "Decisions taken and not taken" in [CLAUDE.md](../CLAUDE.md) if the answer was to do
nothing. IDs are never reused.

## Kind

| Kind | Means |
| ------ | ------- |
| **Decision** | The code does something defensible, but nobody has chosen whether it is right. Asks for an answer. |
| **Verification** | The behavior is probably correct and nothing proves it. Asks for a test, or a deliberate acceptance. |
| **Risk** | Known, understood, accepted for now. Asks for nothing until circumstances change. |

---

<a id="unk-02"></a>

## UNK-02 — No test in this repo can be shown to discriminate from git history alone

**Kind:** Risk
**Where:** [tests/](../skills/claude-toggle-backend/tests/)

The repository's history begins with implementation and tests already together, at the
initial import of v1.8.0. There is therefore no commit at which a test existed and its
implementation did not, so no test's red state can be recovered from history. The explicit
repo-id and forced-port tests compare against constants supplied by the test itself, though
they do still exercise real transformations.

This is a limitation of the history, not a defect in any particular test. Eight specific
discrimination failures were found by reading the tests rather than the history, and those
are filed as KI-09, KI-10, KI-11, KI-12, KI-23, KI-24, KI-25 and KI-26.

All eight sit in `claude-toggle-backend`, which is being rebuilt, so they will be answered by
new tests rather than by repairs to these. The entry still applies: the rebuild's tests will
also be written alongside their implementation, so their red state will not be recoverable
from history either.

**What settles it:** nothing, and nothing needs to. The mutation check adopted in
`phase-workflow` §3 step 3 replaces the need for historical evidence — it breaks the named
behaviour in the production code now and confirms the test fails on the named assertion,
which works regardless of what the history contains. This entry exists so the absence of
historical evidence is not mistaken later for evidence of absence.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.
