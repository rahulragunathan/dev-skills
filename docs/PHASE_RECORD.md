# Phase record

**The phase in flight, and nothing else.** Written at `phase-workflow` §2 step 3, preserved across
sessions, and read back at §4 for `MERGE_METHOD`. Later checks do not replace it: it pins what was
decided at phase start so a repository setting changed mid-phase cannot silently alter the merge.

This file is **overwritten** at each phase start, never appended. Six accumulated records would be
the phase ledger the roadmap rules forbid — the release history is the phase history. When no
phase is in flight the body is the single line `No phase in flight.`

---

## Phase 1 — gate integrity

| Key | Value |
| --- | --- |
| `ORIGIN_URL` | `git@github.com:rahulragunathan/localclaude.git` |
| `ORIGIN_PUSH_URL` | `git@github.com:rahulragunathan/localclaude.git` |
| `REPO` | `rahulragunathan/localclaude` |
| `DEFAULT_BRANCH` | `main` |
| `PHASE_BRANCH` | `feature/gate-integrity` |
| `MERGE_METHOD` | `squash` |
| Branched from | `origin/main` at `356afac` |
| Started | 2026-09-20 |
| `PR` | [#5](https://github.com/rahulragunathan/localclaude/pull/5) |
| Release | v1.11.0 |
| `APPROVED_SHA` | the PR head at sign-off — see **Gate** below |

All three merge methods are enabled on the repository; `squash` is selected because the preflight
takes the first allowed method in the order squash, rebase, merge.

## Diagram generators

None. The architecture diagram names skills rather than their scripts, so the two helpers this
phase adds leave it factually correct. §2 step 4 is skipped.

## Model and effort, per task

Recorded in each commit trailer.

### Tranche assignment — fixed 2026-09-20, before any conversion

Rule from the plan, applied to the committed inventory: sort suites by mid-test count descending,
ties alphabetical by path, assign alternately starting with Tranche A.

| # | Suite | Mid | Tranche |
| --- | --- | ---: | --- |
| 1 | `design-review/tests/evidence.bats` | 17 | A |
| 2 | `external-review/tests/preflight.bats` | 14 | B |
| 3 | `phase-workflow/tests/phase-git.bats` | 10 | A |
| 4 | `design-review/tests/grade_batch.bats` | 8 | B |
| 5 | `claude-setup/tests/install-standards.bats` | 5 | A |
| 6 | `design-review/tests/write_results.bats` | 5 | B |
| 7 | `claude-setup/tests/install-link.bats` | 2 | A |
| 8 | `design-review/tests/grade.bats` | 2 | B |
| 9 | `external-review/tests/codex-root.bats` | 2 | A |
| 10 | `design-review/tests/rollup.bats` | 1 | B |
| 11 | `external-review/tests/capture.bats` | 1 | A |
| 12 | `phase-workflow/tests/roadmap.bats` | 1 | B |

**Tranche A — `gpt-6-astra` at `medium`:** 6 suites, 37 assertions.
**Tranche B — `gpt-6-astra` at `max`:** 6 suites, 31 assertions.

The arms are not equal: alternating over a descending list with these counts gives A six more
assertions than B. That is the rule as written, applied without adjustment after seeing the
numbers. It is one more reason the comparison is descriptive only.

## Deviations from the documented workflow, recorded rather than silent

1. **§2 step 1's clean-tree guard was not satisfied literally.** It requires
   `git status --porcelain=v1 --untracked-files=all` to be empty, but §1 produces the spec and the
   plan before the branch exists, and neither may be committed to `main` without sign-off. Those
   two requirements conflict. What was checked instead: no *modified tracked* files, which is the
   loss the guard protects against. The two untracked files followed the switch and are committed
   as this phase's first commit.

2. **The phase record has no defined location.** §2 step 3 names the contents but not the path.
   This file is that record; if the skill later defines a path, move it rather than duplicating.

## Findings from executing the workflow

Filed properly in Task 9; recorded here as they are found.

| ID | Finding |
| --- | --- |
| KI-53 | zsh applies its `:r` history modifier to `"$DEFAULT_BRANCH:refs/..."` in §2 step 1, mangling the refspec. One occurrence, `SKILL.md:57`. Bracing fixes it. |
| KI-54 | "The phase record" had three consumers and no defined path. Resolved by `docs/PHASE_RECORD.md`; the skill wording still needs the edit. |
| — | ROADMAP's Status section still describes the previous programme's phase 2. Task 9 updates it. |

## Notes carried out of the tasks

**Astra disputed a test in Task 2, and was right.** The fixture copied
`verify_assertions.sh` into a scratch repository while the prompt required it to resolve
`mutation-restore.sh` as a sibling; both could not hold. It changed nothing and reported the
conflict, which is the dispute path the plan specifies. The fixture now runs the script from its
real home with the scratch repo as the working directory.

**Bats rewrites `@test` lines inside heredocs.** A fixture written inline with
`cat > f.bats <<'EOF'` arrives as `bats_test_function --description ... -- test_x;test_x() {`,
not as the source it was meant to be. Verified directly. Both suites' fixtures are therefore real
files under `tests/fixtures/`, never heredocs. Codex raised this as F-23 during plan review; it
was fixed for Task 1 and reintroduced in Task 2 before being caught.

**Two mutations this phase were false reds**, caught only by checking which line failed rather
than the exit status:

- Task 1: disabling the heredoc skip made the script raise "unterminated heredoc" and exit 1.
  The test failed, but on the status check rather than the named row-count assertion. Mutating
  heredoc *detection* instead gave the red at the named line.
- Task 2: the first audit passed with nothing failing, which exposed that test 3 never reached
  the output-inspection code at all — `mutation-restore.sh`'s own restore check was refusing
  first. Tests 4 and 5 were added to reach it, and both are proven by mutation.

The running count of test-side defects is four, against none in Astra's production code. The
split was argued on Astra's weakness being unpinned code; the evidence so far is that the
reviewer's weakness is fixtures, and the arbiter is the mutation check rather than either
author's care.

## Gate

| | |
| --- | --- |
| Presented | 2026-09-21 |
| `APPROVED_SHA` | the head of PR #5 at sign-off, read with `gh pr view 5 --json headRefOid` |
| Tests | 326 passing, 0 failing, across the four in-scope skills |
| Gates | `roadmap.py check` clean · markdownlint clean · 0 `mid` assertions |
| External review | **Partial coverage** — Codex disqualified as the diff's author under this phase's own new rule; `gemini-3.8-flash-high` the only independent reviewer |

§4 loads `MERGE_METHOD` from this table and resolves `APPROVED_SHA` from the recorded `PR`.

**The record cannot hold its own commit's SHA.** Writing a value here changes the commit it
describes, and amending regresses without end. What survives a session is the PR number, and the
gate has already verified that the PR head, `origin/<branch>` and local `HEAD` are the same commit
— so resolving the SHA from the PR is exact, not a convenience. Sign-off binds to that head; an
edit afterwards moves it and means re-requesting review.

## What the phase did

All nine planned tasks, plus four defects found while executing the workflow.

| Closed | KI-45, KI-46, KI-53, KI-54, UNK-02 |
| --- | --- |
| Filed | KI-47 to KI-52, ENH-28, ENH-29 |

KI-53 and KI-54 were found by running the workflow rather than reading it: zsh read
`$DEFAULT_BRANCH:refs/...` as a `:r` history modifier and broke the phase-start fetch, and "the
phase record" had three consumers and no defined path. This file is the answer to the second.

## Review outcomes

Six findings fixed in phase, two filed, four rejected with reasons, one partly rejected. The two
that would have shipped:

- **`git cherry` is wrong in both directions** — found by the flash-tier reviewer at plan time.
  KI-46's own notes recommended it and claimed it "verified both ways"; that verification used a
  one-commit branch.
- **`verify_assertions.sh` reported `GREEN` for an operator inside a quoted literal** — found by
  the same reviewer at the gate. `GREEN` licenses deleting an assertion.

**Two process failures of mine, recorded because they are repeatable.** I truncated an
alphabetically-ordered diff for external review, so the reviewer saw only `docs/` and produced
twelve findings about code it never read — every checkable one wrong, including a Critical
claiming the KI-46 fix could never fire. And a test of mine forced a worse design: asserting that
`SKILL.md` mentions a flag pushed a local-only utility into the merge cycle, giving §4 two
deletion mechanisms until it was reverted.

## What the authorship split actually showed

Astra wrote the production diffs; Claude wrote the tests. The split was argued from ENH-26 and
KI-37 — Astra's weakness being fixes that work but are not pinned. That is not what happened.

Astra's logic was sound in every task. Its two defects were an undeclared environment dependency
and a diagnostic that named the wrong cause, both "right at the site shown, wrong at the edge".
Claude's defects were all test-side and numbered around ten: fixtures that never reached the code,
assertions satisfied by the wrong text, multiline reasoning three separate times, `$output`
clobbered by a later `run`, two review findings already accepted into the plan and then
reintroduced in code, and one test that forced a bad design.

**Astra disputed a Claude test three times and was right every time.** That is the half of the
split that paid, and it is mutual review rather than compensation for one party's weakness — the
spec has been corrected to say so.

**The arbiter was neither author.** It was the mutation check plus reading *which line* a red came
from. Two mutations this phase were false reds. One test passed on HEAD because the production
code's own error message contained the string it grepped for, which no mutation can detect.

`verify_assertions.sh` gave three false verdicts in total — exit status alone meant `RED`, a
disjunction meant `GREEN`, an ambiguous line meant `GREEN`. All three were fixed the same way:
refuse rather than guess. A tool whose job is judging tests kept judging on insufficient evidence,
and its `REFUSED` path turned out to be where the correctness lives.
