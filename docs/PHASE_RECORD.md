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
`Almost always` spelling; the KI template gains Path and Area fields and a Steps To Reproduce section, the ENH template an
optional Steps To Reproduce, and both title-case headings; external-review's rubric, triage, tables, blocking rule, loop and gate follow; phase-workflow
points at the rule. The phase-end `/code-review high` found eight findings, triaged under the new
rule: none blocks, six are filed as KI-97 to KI-102, and two are accepted. ENH-40 records making
Path required. `/security-review` could not run, since the session's working directory is not
this repository.

A follow-up on the same PR, after the first gate at `acce93a` and on your request, closed the policy
gaps the review filed (KI-97 to KI-101, KI-103 to KI-108), removed the Happy Path line, opened each
keyed note with Blocking or Non-Blocking and its Disposition, fixed KI-111, and brought the roadmap
files to one casing and shape (KI-110). Passes 4 and 5 reviewed it; pass 4's one blocking finding
(the fixture's clone kept `origin`) was fixed, and the rest were filed. Passes 6 to 9 reviewed only
the rule that lets a reviewer's confirmed fix to the release's bookkeeping docs land without another
pass. You chose to fix the findings of passes 6 to 8; pass 9 found no blocking finding, and its
findings were filed as KI-121 to KI-126. You then chose to fix KI-122 to KI-126. Pass 10 reviewed
those fixes and found no blocking finding; its findings are filed as KI-127 to KI-132. You then
chose to fix KI-127, the regressions in the post-review check. Pass 11 reviewed that fix and found
no blocking finding; its findings are filed as KI-133 to KI-136.

The final follow-up pinned Git operations, confined reproduction steps, corrected triage and shortened the review loop. ENH-44 tracks the S02 condition edit and re-grading.
