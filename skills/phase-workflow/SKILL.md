---
name: phase-workflow
version: 1.7.0
description: The user's phase-based development process for solo projects — invoke at every phase boundary. Covers plan review, phase start, the seven-step end-of-phase retrospective, the hard gate (per-task commits on a draft PR, marked ready and presented for review), and the post-sign-off merge cycle. Use when a phase is starting, wrapping up, or ready for sign-off.
license: MIT
---

# phase-workflow

Phase-based development for solo projects. One feature branch per phase, branch rules per global CLAUDE.md. **Work is committed per task as it goes, onto a draft pull request opened at phase start.** The PR is the gate: it goes ready-for-review at phase end, and sign-off is what authorizes the merge. Four checkpoints: **plan review** (before the user approves the plan), **phase start** (after approval), **phase end** (retrospective + hand-off), **post-sign-off** (merge cycle).

**The CLIs are best-effort. Running the review is not.** The `/localclaude:review-checkpoint` steps need the `codex` and/or `agy` CLI. **Both missing is the only legitimate reason the step does not run**, and it is stated in writing on the line where the findings table would have gone. One missing CLI is not a skip — the review runs with the other. An installed CLI that fails on quota, auth, timeout or sandbox denial is **partial coverage**, not a skip: the step ran and one reviewer came back empty. `review-checkpoint` is canonical for the wording.

Nothing else exempts the step: not a clean `/code-review`, not a green suite, not a small phase, not the user waiting.

**The phase gate (non-negotiable):** completing phase N never rolls into phase N+1. Present phase N for the user's review and stop. The work at that moment is **committed, pushed, and sitting on a PR marked ready for review** — see §3 step 7 for the checkable state. Nothing merges without sign-off.

**Commit per task; never hold a phase's work in the working tree.** A task lands as one commit once its tests are green and `/simplify` has run. This is a safety rule: the retrospective points `git checkout`, worktree and stash operations at the tree, and `git reflog` recovers what was committed and nothing else.

**The phase's full diff is always one command:** `git diff "origin/$DEFAULT_BRANCH"...HEAD` — three dots, so it reads from the merge base and stays correct as the default branch advances. `git log --oneline "origin/$DEFAULT_BRANCH"..HEAD` lists the phase's commits, and `gh pr diff <n>` shows the same thing in a browser. Per-review-pass scope is `git diff <last-reviewed-sha>..HEAD`.

**What "sign-off" means.** Sign-off is the user approving the *completed* phase's work: "looks good", "approved", "go ahead and commit". Approval to *start* a phase is not sign-off on it. When one message appears to do both — "commit this and start the next phase" — it authorizes the merge cycle for phase N and the *implementation* of N+1, never the commit of N+1. Nothing else is sign-off: not a passing test run, not a positive external review, not your own confidence.

Subagents never commit/push/merge (global CLAUDE.md policy) — all git state changes happen here, in the main agent.

## 1. Plan review (before the user approves)

The plan the user sees is always the **revised** one. Reviewing after approval is too late — the findings arrive when the decision is already made.

1. Draft the plan, **running `/localclaude:design-review plan` as part of it.** Its output — the module table, the expected-change and shared-state lines, and whatever checks fired — fills the **File Structure** section `superpowers:writing-plans` already reserves. This is not an extra step: doing it here means the table reaches the reviewers in step 2 at no extra cost, and the Interface column is the same content `writing-plans` wants in each task's `Interfaces: Consumes / Produces` block, written once at the top instead of scattered.
2. Run `/localclaude:review-checkpoint plan` on the draft (Codex + Gemini).
3. **Revise the plan** to incorporate every finding you verified as having merit.
4. Add the **findings table** to the plan — the canonical format is in `review-checkpoint`. It goes **after the plan itself and before the testing strategy**, so the user reads the approach, then what outside review said about it, then how it will be verified. Every finding gets a row and a disposition; valid findings that are out of scope are filed as `ENH-nn`/`UNK-nn` rather than dropped.
5. Present the whole thing in one pass, whatever the severities. A confirmed Critical does not hold the plan back — the user is in plan mode and can send it back.

## 2. Phase start (plan approved)

1. **Detect the default branch, then create and publish the phase branch.** Never hardcode `main`. `origin/HEAD` is set by `git clone` but not by `git remote add`, hence the fallback. **Every later section re-runs this block** — a shell variable does not survive between invocations.

   ```bash
   DEFAULT_BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')"
   [ -n "$DEFAULT_BRANCH" ] || DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)"
   [ -n "$DEFAULT_BRANCH" ] || { echo "cannot determine the default branch — ask before continuing" >&2; exit 1; }
   git switch -c "feature/<slug>" --no-track "origin/$DEFAULT_BRANCH" && git push -u origin "feature/<slug>"
   ```

   **This is the only place a phase branch is created.**
2. **Open the PR as a draft, now.** It exists for the whole phase, accumulates the per-task commits, and gives the user a live comprehensive diff at any moment rather than only at the gate.

   ```bash
   gh pr create --draft --base "$DEFAULT_BRANCH" --head "feature/<slug>" \
     --title "<phase name>" --body-file <file>
   ```

   A draft PR cannot be merged, which is the point: the branch is visible and reviewable from the first commit while the merge stays gated on sign-off. Body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

   **This does not conflict with "open a PR only when I explicitly ask."** That rule guards against surprise PRs on work the user has not approved. This one opens *after* plan approval, as a draft, and lands nothing.
3. **Read the repo's merge settings now, not at merge time.** The PR is the landing path on every repo, so branch protection no longer decides *how* a phase lands — only whether the merge needs review approval, which sign-off covers anyway. What still varies is the merge method: `--squash` is rejected by a repo that allows only merge commits, and the remote branch survives unless someone deletes it.

   ```bash
   gh api repos/{owner}/{repo} --jq '{squash: .allow_squash_merge, rebase: .allow_rebase_merge, merge: .allow_merge_commit, autodelete: .delete_branch_on_merge}'
   ```

   Record these with the phase. §4 reads them; it never rediscovers them. No `gh`, or the call fails? Record `unknown` and ask at §4 rather than guessing a method.

4. **Land the plan's diagram generators.** `design-review` builds them into the scratchpad at §1, because §1 runs before this branch exists, and the plan's front matter records their filenames. Copy **every** generator the plan recorded into `docs/` as this phase's first task **and commit it**. That commit is the baseline `design-review phase` compares against at §3 step 2. Skip this step entirely when the plan recorded none, which is the no-`drawio` path.
5. Seed/refresh `ROADMAP.md`, `KNOWN_ISSUES.md`, `ENHANCEMENTS.md`, and `OPEN_QUESTIONS.md` under `docs/` from the templates next to this file, if the project doesn't have them.
6. **`/simplify`'s primary home is the TDD refactor step**, not the retrospective — the *refactor while green* beat of each red-green-refactor cycle, where the diff is one feature and the tests that just passed re-validate whatever it rewrites. §3 step 2 then runs it as a sweep for cross-feature duplication no single refactor step could see. A big haul there means the refactor steps were skipped.
7. Adopting this workflow on an existing project with no in-flight branch? Run `/localclaude:review-checkpoint repo` first — it reviews the current state and seeds `docs/KNOWN_ISSUES.md`, `docs/ENHANCEMENTS.md`, and `docs/OPEN_QUESTIONS.md`, with their ROADMAP pointer rows, before phase 1 is planned.

## 3. Phase end — retrospective (before hand-off)

**Seven steps, in this order, every one of them.** The retrospective starts once the phase's last task is done and the suite is green — that is its trigger, not a request from the user. Each step produces an artifact, and you do not reach the gate at step 7 without all of them. Findings from every step land in the roadmap files — `docs/ROADMAP.md` plus `KNOWN_ISSUES.md` / `ENHANCEMENTS.md` / `OPEN_QUESTIONS.md` — not just chat.

| Step | Artifact it must produce |
| --- | --- |
| 1. Confidence check | a written answer, and the extra tests it directed |
| 2. `design-review phase` → `/simplify` → `/code-review high` | the module table plus whatever fired, or the line saying nothing did; and a re-run green suite |
| 3. Test-validity audit | a verdict per test added or changed this phase |
| 4. Documentation pass | the doc diffs and the drift-check report |
| 5. External review loop | a coverage line per pass, plus a findings table wherever the count is non-zero |
| 6. Post-fix drift re-check | confirmation that every filing has its ROADMAP row |
| 7. Gate | the hand-off: PR ready for review, phase diff, findings |

### Red flags — every one of these means the retrospective has not run

| Thought | Reality |
| --- | --- |
| "All the tasks are done and the tests are green, so I can hand off" | Green is the retrospective's *entry* condition, not its output. |
| "`/code-review` found nothing, so an external pass would find nothing" | Different models with different blind spots. That is the entire point of step 5. |
| "The user is waiting — I'll offer the external review instead of running it" | Offering is skipping. It is a step, not a suggestion. |
| "This phase was small / it's just docs" | Size is not a listed exemption. Only *both* CLIs missing is, and only in writing. |
| "The structure is obvious, I'll skip the table" | The table is what makes it obvious to someone who was not in the conversation. It is also what the external reviewers read. |
| "I'll run the review after they sign off" | Sign-off is a decision made *on* the findings. After is too late. |
| "The tests pass, so they test the right thing" | Passing is what a test does when the bug is absent *and* when the test is vacuous. Step 3 is what tells them apart. |

1. **Confidence check:** explicitly answer "what am I least confident about right now?" (untested edge cases, quota/API assumptions, auth corners) and use it to direct extra tests/verification.
2. **Consolidation & simplification analysis** of the codebase as it now stands. Run **`/localclaude:design-review phase` first, then `/simplify`, then `/code-review high`** — in that order.
   - **That order, not the reverse.** Each pass must read the shape the one before it left: `design-review` moves responsibilities, `/simplify` rewrites, and `/code-review` is the correctness pass over everything that moved.
   - **Invoke it; do not restate its questions here.** The rubric lives in `design-review`; a second copy is a second edit site.
   - **Re-run the test suite after `/simplify`.** It rewrites code after the phase's green bar was established, and step 7 hands the user a diff to sign off on. Green is re-earned and reported, never assumed.
   - **Simpler, not shorter.** Reject any simplification that nests ternaries, trades readability for fewer lines, folds unrelated concerns into one function, or deletes an abstraction that was organising the code. Explicit beats compact.
   - **Always type the level.** `/code-review` with no level reuses the last one you typed *in any project*, so an unstated level silently inherits from an unrelated session.
   - `high` at the gate — the code is about to merge and ship in a release, so a missed bug costs more than a false one, and step 5's triage already handles uncertain findings. `medium` for mid-phase spot checks, where a short actionable list beats a triage pass. Not `ultra`: it's user-triggered and billed, and step 5 already covers that breadth.
3. **Test-validity audit.** A test that passes whether or not the bug exists is worse than no test: it is a false green that the CHANGELOG then cites as evidence. Reading a test does not reveal this. The only proof a test discriminates is having watched it fail for the reason you claim.

   Audit **every test this phase added or changed**. Each one must satisfy both:

   - **A stated failure condition** — what, specifically, would make this test fail. Not "it tests the parser": *"it fails if a `<script>` survives sanitization"*. Where the test closes a tracked issue it carries the ID (`test_ki_07_...`, or a `# KI-07` docstring line) so the audit is a lookup rather than a hunt. **Most tests have no ID** — a fresh feature has nothing to point at — and that is fine. The ID is a convenience when it exists; the stated failure condition is the requirement, always.
   - **A fixture that carries the property under test.** Assert this *before* asserting on the outcome. No amount of breaking production code will fail a test whose input never had the property: a quote-escaping test needs a quote in its input, a timezone test needs a non-UTC account.
   - **Evidence of a red state** — either the TDD red-step observation from earlier in the phase, or a **mutation check** run now.

   **Mutate, don't revert.** Break the specific behaviour the test names, in place, and confirm the test fails on the named assertion. Reverting the whole fix is coarser and has a hole: `git stash push` without `-u` leaves a newly added file in the tree, so the "reverted" code is still there and the test is falsely certified.

   **The task is committed before you mutate it, so git holds the original.** That is the whole
   safety mechanism, and it is why per-task commits exist. `git checkout --` restores from the
   index, which under this workflow *is* the task's finished state.

   ```bash
   git diff --quiet && git diff --cached --quiet \
     || { echo "TREE DIRTY — commit the task before auditing it"; exit 1; }

   # --- edit <file> now: break exactly the behaviour the failure condition names ---

   set +e; .venv/bin/python -m pytest <the test> -x; rc=$?; set -e

   git checkout -- "<file>"
   git diff --quiet || { echo "RESTORE FAILED — inspect before continuing"; exit 1; }

   [ $rc -ne 0 ] || { echo "NOT A RED — it passed with the behaviour broken; the test does not discriminate"; exit 1; }
   .venv/bin/python -m pytest <the test>              # must pass again
   ```

   **The clean-tree guard is the precondition, not decoration** — `git checkout --` is safe only
   because the file's committed content is what it restores. `set +e` around pytest is required:
   under `errexit` a bare `cmd; rc=$?` exits before the assignment and leaves the mutation in
   place.

   **A red that is an import error, a collection error, or a fixture failure does not count.** It has to be the assertion named in the failure condition. A false red is worth exactly as much as no check, and it is the easier of the two to mistake for success.

   **When the behaviour cannot be broken in place** — it lives in a dependency, or the fix was a deletion — use a worktree off the base, where the fix is absent by construction:

   ```bash
   PY="$PWD/.venv/bin/python"                      # the base env; a fresh worktree has no .venv
   WT="$(mktemp -d)"
   git worktree add "$WT/audit" "<base>"               || { echo "WORKTREE ADD FAILED"; exit 1; }
   mkdir -p "$WT/audit/$(dirname "<path to the test>")" || { echo "MKDIR FAILED"; exit 1; }
   cp -p "<test file>" "$WT/audit/<path to the test>"   || { echo "COPY FAILED"; exit 1; }
   ( cd "$WT/audit" && "$PY" -m pytest "<the test>" )   # must fail ON THE NAMED ASSERTION
   git worktree remove --force "$WT/audit"; rmdir "$WT"
   ```

   **Check every setup command; none of them is safe to assume.** A `git worktree add` that fails — the base is already checked out in another worktree, most often — is followed by a `mkdir -p` that creates the directory anyway. Pytest then runs in a bare directory, or against the phase's own code, and the red it produces proves nothing.

   **`$PY` is absolute on purpose**, and this is the one place the relative-venv convention does not apply: the interpreter belongs to the base checkout, and a fresh worktree has no `.venv` because it is a gitignored symlink. Two limits on reusing it — an editable install can resolve imports back to the original checkout rather than the worktree, and it holds the phase's own dependency versions, so it cannot reproduce a behaviour that lives in an older dependency. Where either applies, build a throwaway env inside the worktree instead.

   **`--force` on removal is required.** The copied test file makes the tree dirty, and a plain `git worktree remove` refuses and strands the worktree.

   Copy the **test** across, never the fix. For a test that *documents* an open issue rather than closing one, verify it is genuinely `xfail`/`skip` with the issue ID attached and not quietly passing.

   A test that fails the audit is fixed or deleted — never carried — and any issue it claimed to close does not move to CHANGELOG until a test that does discriminate exists. Report the audit as a line per test; a phase where every test passed the audit says so explicitly.
4. **Documentation pass — holistic, not delta.** Check every doc against the code *as it now stands*, fixing drift from earlier phases too:
   - **README.md** — setup and usage; rewrite clean-slate when stale.
   - **docs/ARCHITECTURE.md** — **records and explains every diagram the project has**, one short section each saying what it depicts and when to regenerate it, not a bare embed. Regenerate each one with the `drawio` skill and compare against the generator committed at §2 (commit the `.drawio` source, generator script, and rendered PNG). **Drift-check the generator, not the PNG** — its box and edge labels are string literals naming modules and files, so they drop into the identifier check below, while a PNG is opaque to it. Catch a stale render mechanically: regenerate, then `git status`; if the PNG changes it was already out of date with its own source.
   - **CHANGELOG.md** — this phase's user-visible changes, appended to `[Unreleased]` under Added/Changed/Fixed/Removed. Never edit a released section. Every entry here is *moved* out of ROADMAP and its supporting file, not copied. Decide the version now (minor for additive work, patch for fixes and docs, major for a break) and put it in the hand-off; the release is cut and tagged after sign-off, in the merge cycle.
   - **KNOWN_ISSUES.md / ENHANCEMENTS.md / OPEN_QUESTIONS.md** — every finding triaged out of steps 1–3 gets a full entry in the right one and a pointer row in ROADMAP, not a one-liner in ROADMAP alone. Getting these current *before* step 5 is what lets the external reviewers be told what is already tracked, so they stop re-deriving the backlog. Rate it when you write it; an unrated item is an untriaged item. Re-check the ordering, and re-check the filing: a question that has become a defined bug moves to KNOWN_ISSUES.
   - **Location** — root keeps README.md, CLAUDE.md, CHANGELOG.md, LICENSE; every other doc lives in `docs/`. If a doc is at root that shouldn't be, `git mv` it so the rename is tracked, then fix every inbound link.
   - **Current-state rule:** every doc except CLAUDE.md, **CHANGELOG.md** and the roadmap files (`ROADMAP.md`, `KNOWN_ISSUES.md`, `ENHANCEMENTS.md`, `OPEN_QUESTIONS.md`) documents only what the code *is*. CHANGELOG is exempt because describing removed features is most of a changelog's job; the rule as it stood forbade exactly that — no "what we didn't build", no rejected alternatives, no removed features. Decisions-not-taken that future developers/agents must know go in the **project CLAUDE.md** only.
   - **Project CLAUDE.md** — updated to match the code as it actually is, plus those awareness notes.
   - **Docs about this project that live outside its repo.** A repo nested inside a container folder is usually described by that folder's own `README.md` and `CLAUDE.md` — a plugin inside a marketplace folder, a skill inside a synced skills folder. Those drift exactly like the in-repo docs and are missed exactly because they are one level up. Sweep them in the same pass: the skill list, the command table, the bundled-script list, anything naming a count.

     **They will not show up in `git status`.** The container folder is often not a git repo at all, so edits to it are invisible to the phase diff and to step 7's gate check. **Name them explicitly in the hand-off** — path and what changed — or the user signs off on a diff that does not contain them.
   - **Code comments** — read the comments in every file this phase touched. Delete comments describing removed behavior, fix ones the code outgrew, add a why-comment where the logic is non-obvious. Comments say *why*, not *what*.
   - **Drift check** — for each doc and comment, verify the identifiers, file paths, commands, flags, and config keys it names still exist. Report what you found, not only what you fixed.
   - **Style** — every doc follows the global writing standard (Simplified Technical English, Zinsser: clarity, simplicity, brevity, humanity). Rewrite bloated prose you pass through, including text from earlier phases.
   - **docs/ROADMAP.md + the three supporting files** — follow the templates' vocabulary and sections exactly (say **"Done"**, never "Implemented"). ROADMAP rows stay pointers; detail belongs in the supporting file. Verify every ID appears in both, that the ratings agree, and that both files are ordered by rating descending. ROADMAP's phase note moves to "no phase in flight" *only after* sign-off (§4) — at hand-off it still says this phase is in progress.
5. **External review loop:** `/localclaude:review-checkpoint phase` (Codex + Gemini). **`review-checkpoint` is canonical for the loop** — passes, the blocking pause, the cap, the disposition vocabulary and the filing rules are defined there; do not restate them. What is phase-specific:
   - **It runs after the docs pass.** The rubric asks for doc-vs-code contradictions, so stale docs spend findings on drift step 4 would have repaired anyway.
   - **A findings table for every pass that ran appears at the gate** (step 7), or the written line naming what was unavailable. That artifact is how a skipped review is caught.
   - Any test written to close a finding here goes through step 3's audit before the loop moves on. A fix landing without a discriminating test is how the next phase inherits this one's bug.
6. **Post-fix drift re-check — narrow, not another holistic pass.** If step 5's fixes moved a module, the diagrams are back in scope: regenerate and compare. Step 5 changed code after step 4 declared the docs true. Re-check only what those fixes touched: the docs and code comments the changed files invalidate, and the CHANGELOG entries whose claims moved. Then confirm every filing from every pass has both its full entry and its ROADMAP pointer row, with ratings that agree. Report what you found, not only what you fixed.
7. **Present to the user and stop** — the phase gate.
   - **Include a findings table per review pass** from step 5, in `review-checkpoint`'s canonical format, with the phase-mode disposition vocabulary. Chat-only — never written to a per-phase review file. It exists so the user can see every finding and pull any deferred one back into this phase before signing off.
   - **Do not merge.** The merge is the post-sign-off action; it happens in §4 and nowhere else. Committing and pushing are not — those happened per task, throughout the phase.
   - **The gate has two checkable states.** First, **the work is committed, pushed, and on a PR marked ready for review** — every one of those is a fact git or `gh` will answer, none is self-attested:

     ```bash
     git diff --quiet && git diff --cached --quiet || echo "UNCOMMITTED WORK — commit it before the gate"
     git log --oneline "origin/$DEFAULT_BRANCH"..HEAD          # the phase's commits; must not be empty
     git status -sb | head -1                                  # must not say [ahead N] — push first
     gh pr ready <n> && gh pr view <n> --json isDraft,state --jq '{draft: .isDraft, state: .state}'
     ```

     Give the user the phase diff command in the hand-off — `git diff "origin/$DEFAULT_BRANCH"...HEAD`, three dots — and the PR link. That is the comprehensive view of everything the phase did, and it is stable as the default branch advances. Second, **the review artifact exists on disk**, not only in the hand-off. The hand-off carries a **coverage line for every pass — always, whatever happened** — naming each reviewer, the exact model that ran, and its outcome: a finding count, `clean`, the error verbatim, or `not installed`. A findings table accompanies it wherever the count is non-zero. **Cite the reviewer output files that back it**, per pass, with byte counts: `review-checkpoint` writes `<scratchpad>/codex_<mode>_p<n>.txt` and `gemini_<mode>_p<n>.txt`, so a missing or empty file means that reviewer produced nothing and the coverage line has to say so. No coverage line means step 5 did not happen and you are not at the gate yet.

     **A coverage line, not a table, because a table cannot cover every outcome.** A pass where both reviewers ran and returned nothing has no findings to tabulate, no missing CLI to report as a skip, and no error to quote — and the older wording called that a review that never happened.

     **And a file, not just the hand-off.** The first state asks git a question and git answers. Without the files this one asks the agent's own message whether it contains a table, which the agent that skipped step 5 satisfies by writing one. A path with a byte count is the same class of evidence as `git status`. It is not unfakeable; it stops being pure self-attestation.
   - **Name the merge method** recorded at §2 step 3, or say it is `unknown` and needs a decision. §4 uses it verbatim and the wrong one is rejected.
   - **End the hand-off with the state:** "Uncommitted on `<branch>`, awaiting your sign-off to commit." If that sentence isn't true, don't write it — report what actually happened.
   - **Any edit while waiting for sign-off is a new commit on the PR, named in a follow-up message.** Re-request review unless it is a typo. The control is visibility, not category — no edit is too small to name.

## 4. Post-sign-off merge cycle

Sign-off — as defined at the top of this file — is the only trigger. Once it comes, run the whole cycle without re-asking.

**One path.** The PR already exists as a draft from §2 step 2 and went ready for review at the
gate, so there is nothing to open and no landing path to choose. Sign-off authorizes the merge —
and only the merge.

1. **Cut the release.** The items are already in `[Unreleased]` — §3 step 4 moved them there and deleted them from ROADMAP and their supporting file, and doing it twice is how one of them gets lost. This step is the release mechanics only: rename `[Unreleased]` to `## [<version>] - <date> — <phase name>`, open a fresh empty `[Unreleased]` above it, and add the compare link under the `## Reference` heading at the foot of the file. Update ROADMAP's phase note.
2. **Commit and push** that release commit to the phase branch. It appears on the PR like any other.
3. **Wait for required checks:** `gh pr checks <n> --watch`. A failing check or a blocking required review ends the cycle here — report it and stop. Don't push fixes through a gate the user hasn't seen.
4. **Merge with the method §2 step 3 recorded** — exactly one of `--squash`, `--rebase`, `--merge`. The wrong one is rejected. Add `--delete-branch` unless `delete_branch_on_merge` is already on, or nothing cleans up the remote branch. If §2 recorded `unknown`, ask rather than guessing.

   ```bash
   gh pr merge <n> --<squash|rebase|merge> --delete-branch
   ```

5. **Confirm the merge actually completed, then tag the SHA it produced.** Do not tag the default branch's tip.

   ```bash
   gh pr view <n> --json state,mergeCommitSha --jq '{state: .state, sha: .mergeCommitSha}'
   ```

   **`state` must read `MERGED`.** `gh pr merge` can *enqueue* a PR on a repo with a merge queue and return success without merging anything, and even a completed merge can be followed by someone else's commit before you pull — so the default branch tip is not reliably this release. `mergeCommitSha` is, on all three methods: squash and rebase merges write a new commit that appears nowhere on the branch, and this field names it.

   ```bash
   SHA="$(gh pr view <n> --json mergeCommitSha --jq .mergeCommitSha)"
   [ -n "$SHA" ] && [ "$SHA" != "null" ] || { echo "NOT MERGED — stop; do not tag"; exit 1; }
   git fetch origin && git tag "v<version>" "$SHA" && git push origin "v<version>"
   ```

   The `&&` chain matters: a failed fetch must stop the tag, or the tag names a pre-merge commit.
6. **Clean up:** run the user's `git-clean-local-branches` alias. Step 4 already removed the remote branch.

Then stop. The next phase's branch is created at phase start (§2 step 1) — never here.

**`git reset --hard` appears nowhere in this workflow; do not add it.** Where a reset is genuinely required, branch first (`git branch backup/<phase>-$(date +%s)`) or use `git reset --keep`, which refuses rather than discarding.

## Roadmap file rules (summary — templates are canonical)

- Fixed vocabulary: **Done** (never "Implemented"), consistent status terms throughout.
- `docs/ROADMAP.md` is future-tense and index-level only. Exactly these sections: **Status** (prose, plus a short note on the phase in flight or planned — often none), **Known Issues**, **Enhancements**, and **Open Questions** — three pointer tables, no prose. Confidence-check findings land in Open Questions.
- No `Resolved` section and no `Notes` section. Shipped work belongs in CHANGELOG.md; standing limitations belong in ARCHITECTURE.md or the project CLAUDE.md.
- **No phase ledger.** A phase ends by cutting a CHANGELOG release whose heading names it, so the release history is the phase history. ROADMAP records only what is in flight or planned. Version by what the phase did: minor for additive work, patch for fixes and docs, major for a break.
- The rating in a ROADMAP row mirrors the supporting file, which is authoritative. The drift check verifies they agree, that ordering is descending, and that every ID appears in both.
- Completed items are deleted from both files, not annotated in place.
- An entry filed from an external review carries a provenance line naming the model ids that found it — `Source: gpt-5.6-sol, gemini-3.1-pro-high — phase review, phase 4` — never the CLI name, so the attribution survives without a separate review store.
