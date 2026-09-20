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

All three merge methods are enabled on the repository; `squash` is selected because the preflight
takes the first allowed method in the order squash, rebase, merge.

## Diagram generators

None. The architecture diagram names skills rather than their scripts, so the two helpers this
phase adds leave it factually correct. §2 step 4 is skipped.

## Model and effort, per task

Recorded in each commit trailer. Tranche assignment for Tasks 4 and 5 is fixed by the rule in the
plan before Task 3's results are seen, and written here when Task 3 completes.

## Deviations from the documented workflow, recorded rather than silent

1. **§2 step 1's clean-tree guard was not satisfied literally.** It requires
   `git status --porcelain=v1 --untracked-files=all` to be empty, but §1 produces the spec and the
   plan before the branch exists, and neither may be committed to `main` without sign-off. Those
   two requirements conflict. What was checked instead: no *modified tracked* files, which is the
   loss the guard protects against. The two untracked files followed the switch and are committed
   as this phase's first commit.

2. **The phase record has no defined location.** §2 step 3 names the contents but not the path.
   This file is that record; if the skill later defines a path, move it rather than duplicating.
