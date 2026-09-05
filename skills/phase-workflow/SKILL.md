---
name: phase-workflow
version: 1.7.0
description: The user's phase-based development process for solo projects — invoke at every phase boundary. Covers the plan review (external review of the drafted plan, incorporated and tabled before the user approves it), phase start, the seven-step end-of-phase retrospective (confidence check, /simplify then /code-review, test-validity audit that reverts each fix to prove its test discriminates, holistic documentation pass with drift check, an external review loop of up to three review→fix passes each pausing on a dispositioned findings table, post-fix drift re-check), the hard phase gate (present uncommitted work for user sign-off and STOP — never commit, never roll into the next phase), and the post-sign-off merge cycle (cut the CHANGELOG release → commit → push → land → tag → branch cleanup), landing by local merge or by pull request when the default branch is protected. Use when a phase is starting, wrapping up, ready for hand-off/sign-off, or when the user says "phase done", "retrospective", "wrap up the phase", or "start phase N".
license: MIT
---

# phase-workflow

Phase-based development for solo projects. One feature branch per phase, branch rules per global CLAUDE.md. A phase lands by local merge, or by pull request where the default branch is protected (§4). Four checkpoints: **plan review** (before the user approves the plan), **phase start** (after approval), **phase end** (retrospective + hand-off), **post-sign-off** (merge cycle).

**The CLIs are best-effort. Running the review is not.** The `/localclaude:review-checkpoint` steps below need the `codex` and/or `agy` CLI. If only one is installed, the review runs with that reviewer; **if neither is, skip the review and carry on** — say so on the line where the findings table would have gone, so a missing table is never mistaken for a clean review. A missing CLI never blocks a phase.

A missing CLI is the **only** legitimate reason the step does not run, and it must be stated in writing. Nothing else qualifies: not a clean `/code-review`, not a green suite, not a small phase, not the user waiting. Don't re-run §3 step 2's `/code-review` to fill the gap — it already ran, and it shares the blind spots of the model that wrote the code; the outside opinion is what's missing, so record that rather than papering over it.

**The phase gate (non-negotiable):** completing phase N never rolls into phase N+1. Present phase N for the user's review and stop. The work at that moment is **uncommitted** — see §3 step 7 for the checkable state.

**What "sign-off" means.** Sign-off is the user approving the *completed* phase's work: "looks good", "approved", "go ahead and commit". Approval to *start* a phase is not sign-off on it. When one message appears to do both — "commit this and start the next phase" — it authorizes the merge cycle for phase N and the *implementation* of N+1, never the commit of N+1. Nothing else is sign-off: not a passing test run, not a positive external review, not your own confidence.

Subagents never commit/push/merge (global CLAUDE.md policy) — all git state changes happen here, in the main agent, at these checkpoints.

## 1. Plan review (before the user approves)

The plan the user sees is always the **revised** one. Reviewing after approval is too late — the findings arrive when the decision is already made.

1. Draft the plan.
2. Run `/localclaude:review-checkpoint plan` on the draft (Codex + Gemini).
3. **Revise the plan** to incorporate every finding you verified as having merit.
4. Add the **findings table** to the plan — the canonical format is in `review-checkpoint`. It goes **after the plan itself and before the testing strategy**, so the user reads the approach, then what outside review said about it, then how it will be verified. Every finding gets a row and a disposition; valid findings that are out of scope are filed as `ENH-nn`/`UNK-nn` rather than dropped.
5. Present the whole thing in one pass, whatever the severities. A confirmed Critical does not hold the plan back — the user is in plan mode and can send it back.

## 2. Phase start (plan approved)

1. Create + publish the phase branch (`git switch -c feature/<slug> --no-track origin/main`, then `git push -u origin <branch>`). **This is the only place a phase branch is created.**
2. **Settle the landing path now, not at merge time.** Branch protection is knowable the moment the branch exists. Discover it in §4 instead and the cycle fails at its last step, after the release is cut, committed and pushed, with a merge commit sitting on local `main` that only `git reset --hard origin/main` removes — the one command that destroys work when you get it wrong.

   ```bash
   gh api "repos/{owner}/{repo}/branches/main/protection" --silent 2>/dev/null && echo protected || echo unprotected
   ```

   A 404 (`unprotected`) means §4 **path A**. Anything else means **path B**. No `gh`, or the call errors for another reason? `git log --merges origin/main` coming back empty on a repo with real history means the default branch is linear and almost certainly enforced that way — take path B.

   On path B, read the repo's merge settings in the same breath. Each one is its own way to fail: `--squash` is rejected by a repo that allows only merge commits, and the remote branch survives the merge unless someone deletes it.

   ```bash
   gh api repos/{owner}/{repo} --jq '{squash: .allow_squash_merge, rebase: .allow_rebase_merge, merge: .allow_merge_commit, autodelete: .delete_branch_on_merge}'
   ```

   Record the path and these settings with the phase. §4 reads them; it never rediscovers them.
3. Seed/refresh `ROADMAP.md`, `KNOWN_ISSUES.md`, `ENHANCEMENTS.md`, and `OPEN_QUESTIONS.md` under `docs/` from the templates next to this file, if the project doesn't have them.
4. **`/simplify`'s primary home is the TDD refactor step**, not the retrospective — the *refactor while green* beat of each red-green-refactor cycle, where the diff is one feature and the tests that just passed re-validate whatever it rewrites. §3 step 2 then runs it as a sweep for cross-feature duplication no single refactor step could see. A big haul there means the refactor steps were skipped.
5. Adopting this workflow on an existing project with no in-flight branch? Run `/localclaude:review-checkpoint repo` first — it reviews the current state and seeds `docs/KNOWN_ISSUES.md`, `docs/ENHANCEMENTS.md`, and `docs/OPEN_QUESTIONS.md`, with their ROADMAP pointer rows, before phase 1 is planned.

## 3. Phase end — retrospective (before hand-off)

**Seven steps, in this order, every one of them.** The retrospective starts once the phase's last task is done and the suite is green — that is its trigger, not a request from the user. Each step produces an artifact, and you do not reach the gate at step 7 without all of them. Findings from every step land in the roadmap files — `docs/ROADMAP.md` plus `KNOWN_ISSUES.md` / `ENHANCEMENTS.md` / `OPEN_QUESTIONS.md` — not just chat.

| Step | Artifact it must produce |
| --- | --- |
| 1. Confidence check | a written answer, and the extra tests it directed |
| 2. `/simplify` → `/code-review high` | a re-run green suite |
| 3. Test-validity audit | a verdict per test added or changed this phase |
| 4. Documentation pass | the doc diffs and the drift-check report |
| 5. External review loop | a findings table per pass, **or** the written skip line |
| 6. Post-fix drift re-check | confirmation that every filing has its ROADMAP row |
| 7. Gate | the hand-off, uncommitted |

### Red flags — every one of these means the retrospective has not run

| Thought | Reality |
| --- | --- |
| "All the tasks are done and the tests are green, so I can hand off" | Green is the retrospective's *entry* condition, not its output. |
| "`/code-review` found nothing, so an external pass would find nothing" | Different models with different blind spots. That is the entire point of step 5. |
| "The user is waiting — I'll offer the external review instead of running it" | Offering is skipping. It is a step, not a suggestion. |
| "This phase was small / it's just docs" | Size is not a listed exemption. Only a missing CLI is, and only in writing. |
| "I'll run the review after they sign off" | Sign-off is a decision made *on* the findings. After is too late. |
| "The tests pass, so they test the right thing" | Passing is what a test does when the bug is absent *and* when the test is vacuous. Step 3 is what tells them apart. |

1. **Confidence check:** explicitly answer "what am I least confident about right now?" (untested edge cases, quota/API assumptions, auth corners) and use it to direct extra tests/verification.
2. **Consolidation & simplification analysis** of the codebase as it now stands — modularity, security, code reuse, maintainability, simplicity. Run **`/simplify` first, then `/code-review high`**.
   - **That order, not the reverse.** `/simplify` applies its fixes to the working tree; `/code-review` only reports. Simplifying first means the correctness pass reads the code's final shape. Reviewing first leaves simplify's own edits with no correctness pass except the external one at step 5.
   - **Re-run the test suite after `/simplify`.** It rewrites code after the phase's green bar was established, and step 7 hands the user a diff to sign off on. Green is re-earned and reported, never assumed.
   - **Simpler, not shorter.** Reject any simplification that nests ternaries, trades readability for fewer lines, folds unrelated concerns into one function, or deletes an abstraction that was organising the code. Explicit beats compact.
   - **Always type the level.** `/code-review` with no level reuses the last one you typed *in any project*, so an unstated level silently inherits from an unrelated session.
   - `high` at the gate — the code is about to merge and ship in a release, so a missed bug costs more than a false one, and step 5's triage already handles uncertain findings. `medium` for mid-phase spot checks, where a short actionable list beats a triage pass. Not `ultra`: it's user-triggered and billed, and step 5 already covers that breadth.
3. **Test-validity audit.** A test that passes whether or not the bug exists is worse than no test: it is a false green that the CHANGELOG then cites as evidence. Reading a test does not reveal this. The only proof a test discriminates is having watched it fail for the reason you claim.

   Audit **every test this phase added or changed**. Each one must satisfy both:

   - **A stated failure condition** — what, specifically, would make this test fail. Not "it tests the parser": *"it fails if a `<script>` survives sanitization"*. Where the test closes a tracked issue it carries the ID (`test_ki_07_...`, or a `# KI-07` docstring line) so the audit is a lookup rather than a hunt. **Most tests have no ID** — a fresh feature has nothing to point at — and that is fine. The ID is a convenience when it exists; the stated failure condition is the requirement, always.
   - **Evidence of a red state** — either the TDD red-step observation from earlier in the phase, or a revert check run now.

   ```bash
   git stash push -- <files holding the fix>
   .venv/bin/python -m pytest <the test> -x     # must fail ON THE ASSERTION
   git stash pop
   .venv/bin/python -m pytest <the test>         # must pass
   git status --porcelain                        # identical to before — step 7 depends on this
   ```

   **A red that is an import error, a collection error, or a fixture failure does not count.** It has to be the assertion named in the failure condition. A false red is worth exactly as much as no check, and it is the easier of the two to mistake for success.

   For a fix spanning many files, run the check in a throwaway `git worktree` off the base instead, so the phase's uncommitted tree is never touched. For a test that *documents* an open issue rather than closing one, verify it is genuinely `xfail`/`skip` with the issue ID attached and not quietly passing.

   A test that fails the audit is fixed or deleted — never carried — and any issue it claimed to close does not move to CHANGELOG until a test that does discriminate exists. Report the audit as a line per test; a phase where every test passed the audit says so explicitly.
4. **Documentation pass — holistic, not delta.** Check every doc against the code *as it now stands*, fixing drift from earlier phases too:
   - **README.md** — setup and usage; rewrite clean-slate when stale.
   - **docs/ARCHITECTURE.md** — explains the system; regenerate the embedded diagram with the `drawio` skill whenever structure changed (commit the `.drawio` source, generator script, and rendered PNG).
   - **CHANGELOG.md** — this phase's user-visible changes, appended to `[Unreleased]` under Added/Changed/Fixed/Removed. Never edit a released section. Every entry here is *moved* out of ROADMAP and its supporting file, not copied. Decide the version now (minor for additive work, patch for fixes and docs, major for a break) and put it in the hand-off; the release is cut and tagged after sign-off, in the merge cycle.
   - **KNOWN_ISSUES.md / ENHANCEMENTS.md / OPEN_QUESTIONS.md** — every finding triaged out of steps 1–3 gets a full entry in the right one and a pointer row in ROADMAP, not a one-liner in ROADMAP alone. Getting these current *before* step 5 is what lets the external reviewers be told what is already tracked, so they stop re-deriving the backlog. Rate it when you write it; an unrated item is an untriaged item. Re-check the ordering, and re-check the filing: a question that has become a defined bug moves to KNOWN_ISSUES.
   - **Location** — root keeps README.md, CLAUDE.md, CHANGELOG.md, LICENSE; every other doc lives in `docs/`. If a doc is at root that shouldn't be, `git mv` it so the rename is tracked, then fix every inbound link.
   - **Current-state rule:** every doc except CLAUDE.md and the roadmap files (`ROADMAP.md`, `KNOWN_ISSUES.md`, `ENHANCEMENTS.md`, `OPEN_QUESTIONS.md`) documents only what the code *is* — no "what we didn't build", no rejected alternatives, no removed features. Decisions-not-taken that future developers/agents must know go in the **project CLAUDE.md** only.
   - **Project CLAUDE.md** — updated to match the code as it actually is, plus those awareness notes.
   - **Code comments** — read the comments in every file this phase touched. Delete comments describing removed behavior, fix ones the code outgrew, add a why-comment where the logic is non-obvious. Comments say *why*, not *what*.
   - **Drift check** — for each doc and comment, verify the identifiers, file paths, commands, flags, and config keys it names still exist. Report what you found, not only what you fixed.
   - **Style** — every doc follows the global writing standard (Simplified Technical English, Zinsser: clarity, simplicity, brevity, humanity). Rewrite bloated prose you pass through, including text from earlier phases.
   - **docs/ROADMAP.md + the three supporting files** — follow the templates' vocabulary and sections exactly (say **"Done"**, never "Implemented"). ROADMAP rows stay pointers; detail belongs in the supporting file. Verify every ID appears in both, that the ratings agree, and that both files are ordered by rating descending. ROADMAP's phase note moves to "no phase in flight" *only after* sign-off (§4) — at hand-off it still says this phase is in progress.
5. **External review loop:** `/localclaude:review-checkpoint phase` (Codex + Gemini). **Up to three review→fix passes, with a blocking pause after every one.**
   - **It runs here, after the docs pass, not before it.** The reviewers' rubric asks for doc-vs-code contradictions, so handing them stale docs spends findings on drift that step 4 was already going to repair. Reviewing last means they see the phase's actual deliverable — code and docs together — and it is the docs the user signs off on that got the outside read.
   - **Pass 1 is full scope; passes 2 and 3 are narrow** — only the fixes made since the previous pass, plus a re-check of the findings that pass claimed to resolve. `review-checkpoint`'s *Follow-up passes* section has the capture and prompt rules, including spotlighting fixes your own verification cannot settle. Never widen a follow-up back to the whole phase.
   - **Present each pass's findings table and stop.** The user decides what is fixed, filed, or rejected before any code is touched. A disposition you assigned yourself is a proposal until they say so.
   - **Every finding takes exactly one of five dispositions** — `Fixed in phase`, `Filed KI-nn`, `Filed ENH-nn`, `Filed UNK-nn`, `Rejected`. Regressions this phase introduced are fixed before hand-off; everything else that survives verification becomes a rated entry in `docs/KNOWN_ISSUES.md`, `docs/ENHANCEMENTS.md`, or `docs/OPEN_QUESTIONS.md`, each with a pointer row in ROADMAP and a provenance line naming the reviewing **model ids** and the phase.
   - **A pass with no confirmed finding needing a code change ends the loop.** At the cap, anything still open is filed rather than fixed-and-unreviewed, and the hand-off says the cap was reached.
   - Any test written to close a finding here goes through step 3's audit before the loop moves on. A fix landing without a discriminating test is how the next phase inherits this one's bug.
6. **Post-fix drift re-check — narrow, not another holistic pass.** Step 5 changed code after step 4 declared the docs true. Re-check only what those fixes touched: the docs and code comments the changed files invalidate, and the CHANGELOG entries whose claims moved. Then confirm every filing from every pass has both its full entry and its ROADMAP pointer row, with ratings that agree. Report what you found, not only what you fixed.
7. **Present to the user and stop** — the phase gate.
   - **Include a findings table per review pass** from step 5, in `review-checkpoint`'s canonical format, with the phase-mode disposition vocabulary. Chat-only — never written to a per-phase review file. It exists so the user can see every finding and pull any deferred one back into this phase before signing off.
   - **Do not commit.** Commit is a post-sign-off action; it happens in §4 and nowhere else.
   - **The gate has two checkable states.** First, **the work is uncommitted**: run `git status` (the phase's changes show as modified/untracked) and `git log origin/main..HEAD` (no new commits on the phase branch). If a commit is already there, the gate has been passed — that is the error, not a detail. Second, **the review artifact exists**: the hand-off carries a findings table for every pass that ran, or the written skip line naming the missing CLIs. Neither present means step 5 did not happen and you are not at the gate yet. This is the check that actually catches a skipped review, because step 7 is the step that always runs.
   - **Name the landing path** recorded at §2 step 2 — path A, or path B with the merge method the repo allows. The gate is where "this needs a PR" costs a sentence; §4 is where it costs a reset.
   - **End the hand-off with the state:** "Uncommitted on `<branch>`, awaiting your sign-off to commit." If that sentence isn't true, don't write it — report what actually happened.
   - Apply only trivial/safe fixes within the phase branch while waiting; phase-introduced regressions are already fixed per step 5.

## 4. Post-sign-off merge cycle

Sign-off — as defined at the top of this file — is the only trigger. Once it comes, run the whole cycle without re-asking.

Steps 1 and 2 are the same on both paths. Only the landing differs.

1. **Cut the release.** Move the phase's completed items into CHANGELOG `[Unreleased]` and delete them from ROADMAP and their supporting file. Rename `[Unreleased]` to `## [<version>] - <date> — <phase name>`, open a fresh empty `[Unreleased]` above it, and add the compare link under the `## Reference` heading at the foot of the file. Update ROADMAP's phase note.
2. **Commit and push** the phase branch.

Then take the path recorded at §2 step 2.

### Path A — unprotected default branch

3. **Merge** into the default branch and push.
4. **Tag:** `git tag v<version> <merge-sha>` then `git push origin v<version>`.
5. **Clean up:** delete the remote feature branch, then run the user's `git-clean-local-branches` alias.

### Path B — protected default branch

**The PR is the merge, not an extra step.** Global CLAUDE.md says "open a PR only when I explicitly ask". That rule does not gate this PR: on a protected branch a PR is the only way to land an already-approved phase, so sign-off authorizes it. Everything else holds — you still never land without sign-off, and a PR outside an approved merge cycle still needs the user to ask.

3. **Open the PR.** Title = the release heading; body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

   ```bash
   gh pr create --base main --head <branch> --title "<release heading>" --body-file <file>
   ```

4. **Wait for required checks:** `gh pr checks <n> --watch`. A failing check or a blocking required review ends the cycle here — report it and stop. Don't push fixes through a gate the user hasn't seen.
5. **Merge with the method §2 step 2 recorded** — exactly one of `--squash`, `--rebase`, `--merge`. The wrong one is rejected. Add `--delete-branch` unless `delete_branch_on_merge` is already on, or nothing cleans up the remote branch.

   ```bash
   gh pr merge <n> --<squash|rebase|merge> --delete-branch   # method per §2; drop --delete-branch if delete_branch_on_merge is on
   ```

6. **Pull, then tag what landed.** A squash or rebase merge writes a new commit whose SHA appears nowhere on the branch, so there is no merge SHA to tag and the branch tip is not what shipped. `main` after the pull is the only reliable source.

   ```bash
   git switch main && git pull
   git tag v<version> $(git rev-parse main)
   git push origin v<version>
   ```

7. **Clean up:** run the user's `git-clean-local-branches` alias. Step 5 already removed the remote branch.

Then stop. The next phase's branch is created at phase start (§2 step 1) — never here.

## Roadmap file rules (summary — templates are canonical)

- Fixed vocabulary: **Done** (never "Implemented"), consistent status terms throughout.
- `docs/ROADMAP.md` is future-tense and index-level only. Exactly these sections: **Status** (prose, plus a short note on the phase in flight or planned — often none), **Known Issues**, **Enhancements**, and **Open Questions** — three pointer tables, no prose. Confidence-check findings land in Open Questions.
- No `Resolved` section and no `Notes` section. Shipped work belongs in CHANGELOG.md; standing limitations belong in ARCHITECTURE.md or the project CLAUDE.md. Both were duplicate stores that drifted from their originals.
- **No phase ledger.** A phase ends by cutting a CHANGELOG release whose heading names it, so the release history is the phase history. ROADMAP records only what is in flight or planned. Version by what the phase did: minor for additive work, patch for fixes and docs, major for a break.
- The rating in a ROADMAP row mirrors the supporting file, which is authoritative. The drift check verifies they agree, that ordering is descending, and that every ID appears in both.
- Completed items are deleted from both files, not annotated in place.
- An entry filed from an external review carries a provenance line naming the model ids that found it — `Source: gpt-5.6-sol, gemini-3.1-pro-high — phase review, phase 4` — never the CLI name, so the attribution survives without a separate review store.
