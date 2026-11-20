# Phase record

**The phase in flight, and nothing else.** Written at `phase-workflow` §2 step 3, preserved across
sessions, and read back at §4 for `MERGE_METHOD`. Later checks do not replace it: it pins what was
decided at phase start so a repository setting changed mid-phase cannot silently alter the merge.

This file is **overwritten** at each phase start, never appended. Accumulated records would be the
phase ledger the roadmap rules forbid — the release history is the phase history. When no phase is
in flight the body is the single line `No phase in flight.`

---

## project-docs and September's rules

| Key | Value |
| --- | --- |
| `ORIGIN_URL` | `git@github.com:rahulragunathan/dev-skills.git` |
| `ORIGIN_PUSH_URL` | `git@github.com:rahulragunathan/dev-skills.git` |
| `REPO` | `rahulragunathan/dev-skills` |
| `DEFAULT_BRANCH` | `main` |
| `PHASE_BRANCH` | `feature/project-docs` |
| `MERGE_METHOD` | `squash` |
| Branched from | `origin/main` at `d42d5e0` |
| Started | 2026-11-20 |
| `PR` | recorded at the gate |
| Release | v2.1.0 |

All three merge methods are enabled on the repository; `squash` is selected because the preflight
takes the first allowed method in the order squash, rebase, merge.

The dev-setup standards change lands in a second PR in that repository, signed off at the same
gate and merged after this one.
