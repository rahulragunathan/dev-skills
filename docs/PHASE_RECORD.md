# Phase record

**The phase in flight, and nothing else.** Written at `phase-workflow` §2 step 3, preserved across
sessions, and read back at §4 for `MERGE_METHOD`. Later checks do not replace it: it pins what was
decided at phase start so a repository setting changed mid-phase cannot silently alter the merge.

This file is **overwritten** at each phase start, never appended. Accumulated records would be the
phase ledger the roadmap rules forbid — the release history is the phase history. When no phase is
in flight the body is the single line `No phase in flight.`

---

## Dependable helpers

| Key | Value |
| --- | --- |
| `ORIGIN_URL` | `git@github.com:rahulragunathan/dev-skills.git` |
| `ORIGIN_PUSH_URL` | `git@github.com:rahulragunathan/dev-skills.git` |
| `REPO` | `rahulragunathan/dev-skills` |
| `DEFAULT_BRANCH` | `main` |
| `PHASE_BRANCH` | `bugfix/dependable-helpers` |
| `MERGE_METHOD` | `squash` |
| Branched from | `origin/main` at `277e9ed` |
| Started | 2026-11-23 |
| `PR` | 10 |
| Release | v2.2.0 |

All three merge methods are enabled on the repository; `squash` is selected because the preflight
takes the first allowed method in the order squash, rebase, merge.

The plan lives outside the repository, in `~/.claude/plans/2026-11-23-helpers-fix-plan.md`. The
companion repository, dev-setup, ships 1.2.0 from `feature/standards-change-report` in this
phase.
