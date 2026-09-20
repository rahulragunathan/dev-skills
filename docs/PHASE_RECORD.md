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
