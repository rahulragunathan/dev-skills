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

<a id="unk-01"></a>

## UNK-01 — Should the phase gate be "unpushed" rather than "uncommitted"?

**Kind:** Decision
**Where:** [phase-workflow/SKILL.md](../skills/phase-workflow/SKILL.md) §3 step 7, §4

The gate is defined as uncommitted work: at hand-off `git status` shows the phase's changes
as modified or untracked, and `git log origin/main..HEAD` shows no new commits. Sign-off then
authorises commit, push and landing.

That definition rules out `superpowers:subagent-driven-development`, which is built on
per-task subagent commits. Three of its mechanisms are commit-range based and none of them
degrade gracefully: `scripts/review-package PLAN_FILE BASE HEAD` diffs a commit range to
build each task's review, the ledger records SHAs per task and is the documented crash
recovery map, and the implementer subagent is specified to return its commits as its result.
Instructing a subagent to skip committing removes the substrate the rest of the skill runs
on, which is why the two kept colliding in practice.

The alternative considered on 2026-09-05 was to redefine the gate as **unpushed**: at
hand-off the branch has commits, the tree is clean, and nothing has reached origin. Sign-off
would then authorise push and landing rather than commit and landing. The protection the gate
actually provides — nothing leaves the machine and nothing lands without approval — survives
that change intact, and on a squash-merge repository the intermediate commits disappear at
merge anyway.

It was rejected to keep the gate stable, and parallel implementation now runs through
`superpowers:dispatching-parallel-agents` instead: one implementer per module from the plan's
module table, returning changed files and test results without committing. The known cost is
that task N's diff against `origin/main` contains tasks 1 to N-1, since nothing is committed
in between, so review noise grows through a phase. The mitigation in use is to review per
module by path rather than by diff range, which the module table makes possible.

**What settles it:** running several phases with parallel implementation under the current
gate and seeing whether per-module path review holds up. If review noise becomes the thing
that slows a phase down, the unpushed gate is the change that fixes it, and this entry records
the reasoning so the argument does not have to be rebuilt.

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

**What settles it:** nothing, and nothing needs to. The mutation check adopted in
`phase-workflow` §3 step 3 replaces the need for historical evidence — it breaks the named
behaviour in the production code now and confirms the test fails on the named assertion,
which works regardless of what the history contains. This entry exists so the absence of
historical evidence is not mistaken later for evidence of absence.

**Source:** gpt-5.6-sol — repo review, 2026-09-05.
