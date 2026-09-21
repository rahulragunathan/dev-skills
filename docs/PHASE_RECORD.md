# Phase record

**The phase in flight, and nothing else.** Written at `phase-workflow` §2 step 3, preserved across
sessions, and read back at §4 for `MERGE_METHOD`. Later checks do not replace it: it pins what was
decided at phase start so a repository setting changed mid-phase cannot silently alter the merge.

This file is **overwritten** at each phase start, never appended. Accumulated records would be the
phase ledger the roadmap rules forbid — the release history is the phase history. When no phase is
in flight the body is the single line `No phase in flight.`

---

## Mini phase — reference integrity

| Key | Value |
| --- | --- |
| `ORIGIN_URL` | `git@github.com:rahulragunathan/localclaude.git` |
| `ORIGIN_PUSH_URL` | `git@github.com:rahulragunathan/localclaude.git` |
| `REPO` | `rahulragunathan/localclaude` |
| `DEFAULT_BRANCH` | `main` |
| `PHASE_BRANCH` | `feature/reference-integrity` |
| `MERGE_METHOD` | `squash` |
| Branched from | `origin/main` at `bcf5473` |
| Started | 2026-09-21 |
| `PR` | recorded here once §2 step 2 opens it |
| Release | v1.12.0 |
| `APPROVED_SHA` | the PR head at sign-off — see **Gate** below |

All three merge methods are enabled on the repository; `squash` is selected because the preflight
takes the first allowed method in the order squash, rebase, merge.

## Scope

Two items filed *during* phase 1, both instruments rather than fixes, both taken before phase 2
because the remaining phases would otherwise be measured with them.

| Item | What it is |
| --- | --- |
| ENH-30 | Anchor roadmap references to a greppable fragment, and make `roadmap.py check` verify it |
| KI-52 | Measure whether mid-test `[[ ]]` vacuity differs between bash 3.2.57 and bash 5 |

**Plan:** `docs/superpowers/plans/2026-09-21-mini-phase-reference-integrity.md`.

## Diagram generators

None. The architecture diagram names skills rather than their scripts, so new functions inside
`roadmap.py` leave it factually correct. §2 step 4 is skipped, as in phase 1.

## Decisions taken at phase start

1. **A fragment is required per file link, not per entry.** 89 fragments across 71 entries; 38
   point inside the five in-scope skills or the repo root and 51 outside them. Both external
   reviewers attacked the per-entry reading independently as a false green: one verified fragment
   would certify an entry citing three files. Chosen by the user over the 71-fragment and
   59-fragment readings, with those costs measured and presented.
2. **Two exemptions, both forced by real entries.** A link whose target is a directory is an
   existence-only reference and takes no fragment (`ENH-04`, `ENH-07`). A fragment cannot contain a
   backtick, so `ENH-27` picks a different distinctive string from the file it cites.
3. **bash 5 is installed on the host** with `brew install bash`, authorised by the user at phase
   start. It lands at `$(brew --prefix)/bin/bash` and leaves `/bin/bash` untouched.

## Model and effort, per task

Recorded in each commit trailer. Astra (`gpt-6-astra`) writes the production diff; Claude writes
the red test first.

## Deviations from the documented workflow, recorded rather than silent

1. **The plan was drafted outside the repository.** `codex-root.sh` refuses any untracked file, so
   §1's external review cannot run while the plan sits in `docs/superpowers/plans/`. It was
   drafted and reviewed in `~/.claude/plans/` and moved in as this phase's first commit. Filed as
   a finding — the two documents are consistent and neither says this.

## Findings from executing the workflow

Filed properly in Task 5; recorded here as they are found.

| ID | Finding |
| --- | --- |
| — | The documented 0-`mid` gate in `phase-workflow/SKILL.md` cannot fail: a scanner failure prints nothing, which reads as clean. Confirmed by running it against a missing file. |
| — | §1's plan review cannot run with the plan inside the repo (deviation 1 above). |

## External review, plan pass

**Full coverage** — `Codex gpt-6-astra (max) 11 · Gemini gemini-3.1-pro-high 8 · 4 overlapping →
15 unique findings`. Single chunk of 60,399 characters; `bundle contains 1 of 1 files; 0 withheld,
0 excluded`. Both reviewers answered at their top rung, and neither authored the plan, so the
author-disqualification rule phase 1 added did not apply.

All 17 rows incorporated. The two that changed the phase:

- **The interpreter comparison was not one.** Task 2 selected bash with `PATH`, and
  `/opt/homebrew/bin` precedes `/bin` on this machine, so after the install both arms would have
  run bash 5, agreed, and produced "not host-dependent" from a single interpreter. Each arm now
  invokes its bash on the bats script directly and reads `BASH_VERSION` from inside the run.
- **One verified fragment concealed every other reference in its entry.** Found independently by
  both reviewers, and the reason decision 1 above went to the strict reading.

## Gate

Recorded at §3 step 7.

## Evidence state

S01 to S07 design-review evidence is untouched so far. `design-review/SKILL.md` is not in this
phase's scope; `phase-workflow/SKILL.md` is, so **S07's with-skill rows expire again** when Task 2
or Task 5 edits it. S07's round-9 row is already marked **Expired** from phase 1 and re-gathering
stays blocked on KI-48, so the mark does not change — but the hash does, and Task 5 records it.
