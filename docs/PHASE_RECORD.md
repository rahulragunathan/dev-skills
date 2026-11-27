# Phase record

**The phase in flight, and nothing else.** Written at `phase-workflow` §2 step 3, preserved across
sessions, and read back at §4 for `MERGE_METHOD`. Later checks do not replace it: it pins what was
decided at phase start so a repository setting changed mid-phase cannot silently alter the merge.

This file is **overwritten** at each phase start, never appended. Accumulated records would be the
phase ledger the roadmap rules forbid — the release history is the phase history. When no phase is
in flight the body is the single line `No phase in flight.`

---

## Review triage

| Key | Value |
| --- | --- |
| `ORIGIN_URL` | `git@github.com:rahulragunathan/dev-skills.git` |
| `ORIGIN_PUSH_URL` | `git@github.com:rahulragunathan/dev-skills.git` |
| `REPO` | `rahulragunathan/dev-skills` |
| `DEFAULT_BRANCH` | `main` |
| `PHASE_BRANCH` | `feature/review-triage` |
| `MERGE_METHOD` | `squash` |
| Branched from | `origin/main` at `0096e33` |
| Started | 2026-11-26 |
| `PR` | 13 |
| Release | v2.3.0 |

`squash` is selected because the preflight takes the first allowed method in the order squash,
rebase, merge.

The plan lives outside the repository, in `~/.claude/plans/2026-11-26-triage-plan.md`, with its
design beside it (`2026-11-26-triage-design.md`).

What the phase did: `roadmap.py` checks optional Path and Area fields and accepts the old
`Almost always` spelling; the KI and ENH templates gain Path, Area and Steps To Reproduce in title
case; external-review's rubric, triage, tables, blocking rule, loop and gate follow; phase-workflow
points at the rule. The phase-end `/code-review high` found eight findings, triaged under the new
rule: none blocks, six are filed as KI-97 to KI-102, and two are accepted. ENH-40 records making
Path required. `/security-review` could not run, since the session's working directory is not
this repository.
