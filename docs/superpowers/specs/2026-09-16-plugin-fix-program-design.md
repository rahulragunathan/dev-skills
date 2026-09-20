# Fix program for five localclaude skills

**Date:** 2026-09-16
**Status:** drafted, awaiting review
**Scope:** `claude-setup`, `design-review`, `external-review`, `phase-workflow`, `project-env`

## Goal

Close 28 open roadmap items across five skills, in an order that makes each fix verifiable by
the time it is made. Astra writes the production diffs. Claude writes the tests and holds the
gate.

## Ordering principle

**Instruments before measurements.** Three items in this set are instruments used to judge every
other fix, and two of them are broken now:

- KI-45 — 78 mid-test `[[ ]]` assertions never fire, so a green suite proves less than its count
  suggests.
- KI-46 — the phase cleanup guard misfires on every squash-merged branch, and this program runs
  six merge cycles.
- The design-review grading cluster decides what round 9's grades mean, so it must land before
  anything is re-graded.

Nothing is measured with an instrument that has not been repaired.

## The phases

| # | Phase | Items | Release |
| --- | ------- | ------- | --------- |
| 1 | Gate integrity | KI-45, KI-46, plus three skill gaps found while planning | patch |
| 2 | design-review grading correctness | KI-36, KI-37, KI-38, KI-39, KI-41, KI-42, KI-44, ENH-26, ENH-14 | minor |
| 3 | design-review methodology and scenarios | UNK-04, ENH-19, ENH-22 to ENH-25, KI-47 to KI-51 (new, below) | minor |
| 4 | external-review | KI-43, ENH-15, ENH-21, ENH-12 | minor |
| 5 | claude-setup | ENH-27, ENH-11 | minor |
| 6 | project-env | ENH-10, and the bats harness it needs first | minor |
| spike | ENH-18 | interpreter versus isolated subprocess | lands nothing |

### Why phase 1 bundles KI-45 and KI-46

They share a file. KI-46's fix touches `phase-git.bats`, one of the suites KI-45 rewrites.
Both are also the same defect class: a check that does not check. KI-45's assertions never fire;
KI-46's guard fires wrongly every time.

### Three skill gaps found while planning

These block the program rather than sit in it, so they are phase 1 work:

1. **The Codex ladder cannot express effort as a rung.** `external-review`'s `codex_ladder()`
   emits slugs only. The real ladder is a ladder of (slug, effort) pairs. The Gemini ladder
   beside it already ranks by effort, so the asymmetry is unintended.
2. **`gpt-5.6-sol` and `gpt-6-astra` are tied at priority 1.** Sorting is stable, so rung 1
   resolves to file order in the cache, not to rank. The ladder cannot name a specific model.
3. **`external-review` has no rule for a reviewer that authored the diff.** It handles only the
   Claude-reviewing-Claude direction. This program needs the other direction from day one.

Two CHANGELOG claims are stale and get corrected in the same phase: the ladder does not "top out
at `gpt-6-astra`" (nothing in the cache ranks it above Sol), and "every listed model supports low
through max" is wrong for `gpt-5.6-luna` and `gpt-5.5`.

### Deferred, with reasons

- **ENH-16** changes the grading report JSON and needs a migration of historical artifacts.
  Doing that while round-9 rows are being re-graded is the wrong moment.
- **ENH-20** (mutation audits in a disposable checkout) is a day of work on the gate this
  program leans on hardest. Worth doing, but not while that gate is in use.

## How each phase runs

### Per task

1. Claude names the failure condition and writes the red test.
2. Claude runs it and confirms it fails for that reason.
3. Astra implements the minimal fix against that test.
4. Claude runs the suite.
5. Claude runs the mutation check with `mutation-restore.sh`, per phase-workflow §3 step 3.
6. `/simplify` at the refactor step, then re-run the suite.
7. Commit on the phase branch, recording the model slug and effort.

**Test and fix have different authors on purpose.** The documented failure mode for Astra in this
repo is not bad code, it is unpinned code: ENH-26 records a fix whose hunk can be reverted with
the suite still green, and KI-37 records a fix applied to uncached packets only. Both are
test-shaped failures.

**This is not a merit argument for Claude writing tests.** KI-45 is 78 assertions Claude wrote
that never fire. The arbiter is the mutation check, which trusts neither author: it requires
watching the test fail for its named reason. That is why phase 1 comes first. Until KI-45 lands,
no red observed in a `.bats` suite is worth anything.

### Per phase

One cycle is an `external-review phase` pass over the accumulated diff, reviewed by Claude and
Gemini. Astra authored the diff, so it is not a reviewer for it. Every finding is verified and
given a disposition in one table.

**Three cycles is a ceiling, not a quota.** Stop when a cycle returns no verified findings. Then
the retrospective, then the PR is marked ready.

Everything that reaches origin goes through Claude. Astra may commit its own task. It never
pushes, merges, tags, or touches the default branch.

### When Astra disputes a test

The test's named failure condition is the contract. A dispute goes into the findings table with a
disposition like any other finding, and escalates to the user. Neither author overrides the other.

## Model selection and provenance

Probed on 2026-09-16: `gpt-6-astra` accepts `medium`, `high` and `max`. The session logs record
the effort actually used, so this is confirmed rather than inferred. The ChatGPT app's "Medium"
ceiling is a UI presentation, not a CLI entitlement.

`ultra` exists above `max` and is not used. It delegates tasks automatically, so the diff may not
come from the model recorded against it, which defeats the provenance rule below.

| Rung | For |
| ------ | ----- |
| `gpt-6-astra` at `max` | Judgment no test pins: phase 2 interpreter semantics, all of phase 3, the ENH-18 spike, ENH-15, ENH-21 |
| `gpt-6-astra` at `medium` | Pinned, bounded fixes: phase 1 conversions, KI-46, KI-40, KI-43, KI-44, phase 5 |
| `gpt-5.6-sol` at `medium` | Budget fallback only, recorded as such |

**Record the slug and effort on every commit.** Provenance is already load-bearing: KI-37 and
ENH-26 cite "Astra's F-06" and "Astra's F-02" by name. If some of those diffs came from another
model or another rung, that record misleads a later reader.

If Astra becomes usage-constrained mid-phase, drop to Sol and record the switch. A rung change
that is not in the record is the same failure as the effort default.

## Phase 1 calibration

Phase 1 converts 78 near-identical assertions. Run one tranche at `medium` and one at `max`, and
the mutation check yields a per-tranche defect count on near-identical work. That sets the rung
rule for phases 2 to 6 on evidence rather than on a guess about which tasks are hard. It costs
nothing extra, because the conversions have to happen either way.

Fix the tranche split and the assignment before the first conversion, not after seeing results.

## Decisions carried in

- **UNK-02 — closed.** No test in this repo can be shown to discriminate from git history alone.
  The mutation check replaces the need for historical evidence. Delete from `OPEN_QUESTIONS.md`
  and the ROADMAP index; add one row to "Decisions taken and not taken" in `CLAUDE.md` so it is
  not re-filed later.
- **UNK-04 — the stricter reading.** A key bound must be stated: a maxsize, a finite key set, or
  a defined format. A named normalisation step is not enough. This rewords the S02 Lifetime
  condition, which changes the condition hash and expires the affected rows. They are re-graded
  in phase 3, after phase 2 fixes KI-37. Re-grading against a tool that keeps a replaced slot's
  old grade would bake the defect in.

## Astra's review of round 9

Dispatched and returned 2026-09-16, `gpt-6-astra` at `max`. Archived with its prompt and a
provenance record at
`Claude-Projects/Project Artifacts/Plugins/localclaude/astra-evidence-review-2026-09-16/`.

Three of its highest-impact claims were checked independently against the artifacts before this
section was written. All three hold.

### What it confirms

**UNK-04 lands exactly where predicted, and the effect is the opposite of the worry.** Astra
re-judged all 12 retained Lifetime judgements over 10 distinct answers. One answer flips:
baseline replicate 2, packets `bdf39ade` and `c2bc587a`. S02 Lifetime becomes 4/5 in both arms.
The apparent with-skill disadvantage that motivated the question disappears.

**ENH-25 is not a hypothetical.** Astra guessed the arm blind on 14 answers and got 14/14, and
7/7 in each arm. Two answers disclose loading in their own text ("I read the design-review skill
file once, as instructed"), and excluding those still leaves 12/12. One informed reader on a
small sample cannot estimate general recoverability, but it settles the question the packets were
supposed to answer: removing the arm label did not conceal the arm.

### New defects, needing IDs

These are not restatements of ENH-22 to ENH-25. Proposed IDs follow the highest in use.

**KI-47 — grading packets omit information their conditions require.** The grader prompt says
"everything you need is in the packet below this prompt." No packet carries the scenario prompt,
and none of the 84 carries S05's banned-word list, which its Rule 4 grades against. Verified
independently: 0/84 packets contain the list, and `scenarios/s05-report-form.md` does. Two
graders said so in their own judgements. Severity High: it applies to every packet in the round.

**KI-48 — S07's with-skill arm is handed the answer to the condition it is graded on.**
`loaded-phase-workflow.md:167` supplies `local = now` and `local = now.astimezone(timezone.utc)`
as the host-independent mutations. S07 condition 2b at lines 41-44 grades whether the answer
picks exactly those. Verified independently. The with-skill 5/5 versus baseline 2/5 on Mutation
choice measures recall of a worked example supplied minutes earlier, not mutation reasoning.
Severity High: it invalidates a comparison already quoted in the results tables.

**KI-49 — the headline tally mixes two skills.** S07 loads `phase-workflow`, stated at
`s07-process-rules.md:5` and verified. The combined 33/35 versus 21/35 is therefore not a
design-review result. The design-review-only subtotal is 28/30 versus 19/30.

**KI-50 — S05's fixture contradicts itself.** Its final decisions say two modules "each copy the
exact `taxes.round_line_tax` implementation" and then that they "will call
`taxes.round_line_tax` at that same per-line stage." An answer cannot report a final state that
is not self-consistent, so the scenario cannot cleanly separate deficient reporting from a
reasonable challenge to the fixture.

**KI-51 — rejected grading attempts are not retained.** Agreement is computed over retained
accepted attempts only. For one S02 condition the documented history holds three votes implying
1/3 agreement, while the retained pair contributes 1/1. The rejected verdict is also the one
matching the settled UNK-04 reading. This is adjacent to ENH-24 but distinct: ENH-24 is about
denominators, this is about discarded evidence.

### Grade corrections beyond UNK-04

Astra fails S05 Rule 4 for baseline replicates 4 and 5, where the recorded graders passed them by
reasoning that Rule 1 already covered the same text. The grading instruction says "Grade each
listed condition on its own." The same heading produced a Rule 4 failure in baseline replicate 1,
so the rule was applied inconsistently within the round. S05 Rule 4 becomes 0/5 baseline against
5/5 with-skill.

### What it says about agreement

40/40 agreement, but 26 of those 40 comparisons are on conditions with no observed failure
anywhere in the sample. Astra also identifies at least two agreeing pairs that are jointly wrong.
Filtering cannot lower a perfect fraction; it only shows how little evidence remains under it.
The mechanical-inflation hypothesis in ENH-24 is **not** supported for this round: all 84 packets
record "Conditions the harness already failed: none."

### Consequence for the programme

Phase 3 grows and its order is now fixed: correct the grading materials (KI-47), then settle the
scenario defects (KI-48, KI-50), then re-grade, then decide ENH-22 to ENH-25. Re-grading before
KI-47 is fixed would repeat the round with the same missing inputs.

No new evidence round is dispatched until phase 3 closes. Astra's closing point stands: these are
requirements for stronger evidence, not grounds to discard the artifacts already held.

## Open items

Three decisions taken while the user was away, recorded here to be overturned rather than
discovered:

1. **KI-45 scope is the four in-scope suites.** 123 of the repo's 145 `[[` lines sit in
   `claude-setup`, `design-review`, `external-review` and `phase-workflow`. The remaining 22 are
   in the held `claude-toggle-backend`, `local-models` and `drive-backup` suites, which the
   ROADMAP places outside current work. Those 22 stay recorded in KI-45 and the entry stays open
   at reduced scope.

2. **The 78 mutation checks get a harness, not 78 manual runs.** KI-45 asks that each conversion
   be confirmed by making it false once and watching its test fail. At §3 step 3 rigour that is
   78 mutation runs, and it is the single largest cost in this program. Proposal: write a script
   that negates each converted assertion in place, runs its test, and asserts a red on the named
   assertion, emitting one results table. That turns 78 manual checks into one reviewable
   artifact. The script is itself production code and gets a test first. If it proves unsound,
   fall back to manual runs on a sample and say so in the phase record rather than claiming 78.

3. **`project-env` has no test suite.** ENH-10 changes env naming and needs a migration in
   `standardize-*-envs.sh`, a script that can move real virtualenvs. The harness is built before
   the behaviour changes, which is why phase 6 is last and why its effort estimate of ~2 hours is
   wrong.

## What this design does not cover

- The exact wording of the five new entries below, and whether any is rated differently once
  the user reads the report.
- Any new evidence round. No evidence is gathered and no grading is run until phase 3 closes.
- The backup cluster and the held rebuild work, which remain phase 2 of the separate roadmap
  programme and are untouched here.
