---
name: phase-workflow
version: 1.7.0
description: The user's phase-based development process for solo projects — invoke at every phase boundary. Covers plan review, phase start, the seven-step end-of-phase retrospective, the hard gate (per-task commits on a draft PR, marked ready and presented for review), and the post-sign-off merge cycle. Use when a phase is starting, wrapping up, or ready for sign-off.
license: MIT
---

# phase-workflow

Phase-based development for solo projects. One feature branch per phase, cut `--no-track` from the repository's detected default branch (§2 step 1). **Work is committed per task as it goes, onto a draft pull request opened at phase start.** The PR is the gate: it goes ready-for-review at phase end, and sign-off is what authorizes the merge. Four checkpoints: **plan review** (before the user approves the plan), **phase start** (after approval), **phase end** (retrospective + hand-off), **post-sign-off** (merge cycle).

The rules below are this skill's defaults. Where the user's or the project's own standards say something different, theirs win; otherwise both apply.

**When work runs as a phase.** Architectural work does. Bounded work becomes a phase when it turns out architectural partway through, or when the user asks for one. Calling a phase on bounded work is also right whenever its retrospective is worth having, such as a security-sensitive path or a change to a rule other work depends on.

**Anything that lands cuts a release, numbered by semver.** Version by what changed, never by how the work was classified: a fix is a patch, a new flag a minor, a break major. A phase release names the phase in its CHANGELOG heading.

**Roadmap files are optional.** A repository has `docs/ROADMAP.md` and its three supporting files only when the user asked for them, and `project-docs` owns them. Wherever this skill says to file a finding, file it through `project-docs` if the repository has all four files, and run `roadmap.py check` after filing; otherwise the finding stays in that review's own table as `Open — no roadmap files`, and the hand-off says why. A `docs/ROADMAP.md` of another shape is the project's own document. Never create roadmap files to have somewhere to file.

**Run the external review checkpoint.** Follow `external-review`'s
[coverage classification](../external-review/SKILL.md#coverage-classification) for missing CLIs,
failed invocations and chunked reviews.

Nothing else exempts the step: not a clean `/code-review`, not a green suite, not a small phase, not the user waiting.

**The phase gate (non-negotiable):** completing phase N never rolls into phase N+1. Present phase N for the user's review and stop. The work at that moment is **committed, pushed, and sitting on a PR marked ready for review** — see §3 step 7 for the checkable state. Nothing merges without sign-off.

**Commit per task; never hold a phase's work in the working tree.** A task lands as one commit once its tests are green, and after `/simplify` where the task added or reshaped code. **The commit message carries one line per test it adds or materially changes: `Red: <test> — <observed failure>`**, the failure you watched before the fix. A test with no observed red gets a mutation check at §3 step 3 instead. §3 step 3 checks those lines. Save the task before the retrospective mutates code or creates audit worktrees.

**The phase's full diff:** `git diff "origin/$DEFAULT_BRANCH"...HEAD`. **Three dots, not two** — two compares against a moving tip and misreports the phase once the default branch advances. Per-review-pass scope is `git diff <last-reviewed-sha>..HEAD`.

**What "sign-off" means.** Sign-off is the user approving the *completed* phase's work: "looks good", "approved", "go ahead and merge". Approval to *start* a phase is not sign-off on it. When one message appears to do both — "merge this and start the next phase" — it authorizes the merge cycle for phase N and the *implementation* of N+1, never the merge of N+1. Nothing else is sign-off: not a passing test run, not a positive external review, not your own confidence.

Subagents may commit their own task; they never push, merge, or tag. Everything that reaches origin goes through the main agent.

## 1. Plan review (before the user approves)

The plan the user sees is always the **revised** one. Reviewing after approval is too late — the findings arrive when the decision is already made.

1. Draft the plan, **running `design-review` in `plan` mode as part of it.** Its output — the module table, the expected-change and shared-state lines, and whatever checks fired — fills the **File Structure** section `superpowers:writing-plans` already reserves. This is not an extra step: doing it here means the table reaches the reviewers in step 2 at no extra cost, and the Interface column is the same content `writing-plans` wants in each task's `Interfaces: Consumes / Produces` block, written once at the top instead of scattered.
2. Run `external-review` in `plan` mode on the draft (Codex + Gemini).
3. **Revise the plan** to incorporate every finding you verified as having merit.
4. Add the **findings table** to the plan — the canonical format is in `external-review`. It goes **after the plan itself and before the testing strategy**, so the user reads the approach, then what outside review said about it, then how it will be verified. Every finding gets a row and a disposition; valid findings that are out of scope are kept rather than dropped — filed where the roadmap files exist, `Open — no roadmap files` where they do not — classified by what they are — defined wrong behaviour is a `KI-nn`, wanted work an `ENH-nn`, an unsettled question a `UNK-nn`. A reviewer reading a plan routinely finds a real bug in existing code, and filing that as an open question misuses the file.
5. Present the whole thing in one pass, whatever the severities. A confirmed Critical does not hold the plan back — the user is in plan mode and can send it back.

## 2. Phase start (plan approved)

1. **Preflight before any phase-start mutation.** Use Bash for these blocks. Replace angle-bracket placeholders before running them. Run from the repo root. Stop on any failed command.

   **Initial discovery.** Run this block once at phase start. Later sections load the recorded values from `docs/PHASE_RECORD.md`; they do not re-run discovery. `gh` must be installed and able to read the repository and its merge settings. Resolve the repository from `origin`, not an upstream setting.

   ```bash
   set -euo pipefail
   command -v gh >/dev/null || { echo "GH MISSING — stop"; exit 1; }
   ORIGIN_URL="$(git remote get-url origin)"
   ORIGIN_PUSH_URL="$(git remote get-url --push origin)"
   bash "$CLAUDE_PLUGIN_ROOT/skills/phase-workflow/publish-release.sh" \
     --check-origin "$ORIGIN_URL" "$ORIGIN_PUSH_URL"
   REPO="$(gh repo view "$ORIGIN_URL" --json nameWithOwner --jq .nameWithOwner)"
   DEFAULT_BRANCH="$(gh repo view "$REPO" --json defaultBranchRef --jq '.defaultBranchRef.name // empty')"
   [ -n "$REPO" ] && [ -n "$DEFAULT_BRANCH" ] || { echo "REPO OR DEFAULT BRANCH UNKNOWN — stop"; exit 1; }
   git check-ref-format "refs/heads/$DEFAULT_BRANCH"
   MERGE_METHOD="$(gh api "repos/$REPO" --jq 'if .allow_squash_merge then "squash" elif .allow_rebase_merge then "rebase" elif .allow_merge_commit then "merge" else empty end')"
   case "$MERGE_METHOD" in squash|rebase|merge) ;; *) echo "NO ALLOWED MERGE METHOD — stop"; exit 1 ;; esac
   git fetch origin "+refs/heads/${DEFAULT_BRANCH}:refs/remotes/origin/${DEFAULT_BRANCH}"
   git rev-parse --verify "refs/remotes/origin/$DEFAULT_BRANCH^{commit}"
   ```

   **One-time branch creation.** Create the branch, then write and commit the phase record on it (step 3), then publish it. The record is written after the clean-tree check, so it never trips it. Never re-create the branch on resume. If publication fails, inspect the existing local branch and retry only its push.

   ```bash
   set -euo pipefail
   PHASE_BRANCH="feature/<slug>"
   TREE_STATE="$(git status --porcelain=v1 --untracked-files=all)"
   [ -z "$TREE_STATE" ] || { echo "TREE DIRTY — save the work before starting"; exit 1; }
   git switch -c "$PHASE_BRANCH" --no-track "refs/remotes/origin/$DEFAULT_BRANCH"
   ```

   Now write `docs/PHASE_RECORD.md` (step 3) and commit it on the branch. Then publish:

   ```bash
   set -euo pipefail
   git diff --quiet HEAD -- docs/PHASE_RECORD.md \
     && git log -1 --format=%H "refs/remotes/origin/$DEFAULT_BRANCH"..HEAD -- docs/PHASE_RECORD.md | grep -q . \
     || { echo "PHASE RECORD NOT COMMITTED ON THE BRANCH — stop"; exit 1; }
   git push -u origin "$PHASE_BRANCH"
   ```

   **This is the only place a phase branch is created.**
2. **Open the draft PR immediately after the first task is committed.** Keep the phase diff available for review as later tasks land.

   ```bash
   gh pr create --draft --base "$DEFAULT_BRANCH" --head "feature/<slug>" \
     --title "<phase name>" --body-file <file>
   ```

   Body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

3. **Record exactly one allowed merge method at phase start.** The preflight selects `squash`, then `rebase`, then `merge`, taking the first allowed method. Persist `ORIGIN_URL`, `ORIGIN_PUSH_URL`, `REPO`, `DEFAULT_BRANCH`, `PHASE_BRANCH` and that selection in **`docs/PHASE_RECORD.md`**, committed on the new branch before its first push — that file is the phase record, linked from `ROADMAP.md` where the repository has one, and it holds the phase in flight only. Overwrite it at each phase start rather than appending: one record per phase accumulating is the phase ledger the roadmap rules forbid. When no phase is in flight its body is the single line `No phase in flight.`, so the pointer never dangles and §4 always has somewhere to read. Preserve that record across sessions. If the user specifies another method, verify it is allowed before selecting it. Later checks do not replace this record. At the gate and merge, load the recorded method into `MERGE_METHOD`. A disabled method ends the merge attempt; do not silently substitute one. Repo rules and required reviews still apply.

4. **Land the plan's diagram generators.** `design-review` builds them into the scratchpad at §1, because §1 runs before this branch exists, and the plan's front matter records their filenames. Copy **every** generator the plan recorded into `docs/` as this phase's first task **and commit it**. That commit is the baseline `design-review phase` compares against at §3 step 2. Skip this step entirely when the plan recorded none, which is the no-`drawio` path.
5. **Roadmap files are not seeded.** If the user asks for them, `project-docs` sets them up with `roadmap.py init`.
6. **`/simplify` runs at a task's refactor step only when the task added or reshaped code** — the *refactor while green* beat of its red-green-refactor cycle, where the tests that just passed re-validate whatever it rewrites. Skip it for tests-only, docs-only and one-line changes. §3 step 2 always runs it once more on the whole branch diff, for duplication no single task could see.
7. Adopting this workflow on an existing project with no in-flight branch? Run `external-review` in `repo` mode first, to review the current state before phase 1 is planned. Its findings are filed where the roadmap files exist, and stay in its table, in the hand-off, where they do not.

## 3. Phase end — retrospective (before hand-off)

**Seven steps, in this order, every one of them.** The retrospective starts once the phase's last task is done and the suite is green — that is its trigger, not a request from the user. Each step produces an artifact, and you do not reach the gate at step 7 without all of them. Findings from every step land in the roadmap files through `project-docs` where the repository has them (the rule above), and in the PR's review record where it does not — never in chat alone.

| Step | Artifact it must produce |
| --- | --- |
| 1. Confidence check | a written answer, and the extra tests it directed |
| 2. `design-review phase` → `/simplify` on the branch diff → `/code-review high` | the module table plus whatever fired, or the line saying nothing did; and a re-run green suite |
| 3. Red record check | a `Red:` line for every test added or changed this phase, or a mutation result for each one without a line, written after its fix, or in doubt |
| 4. Documentation pass | the doc diffs, the name-check output, and the list of docs read in full |
| 5. External review loop | the review record: one findings table across all passes, its notes, and a coverage line per pass |
| 6. Post-fix drift re-check | confirmation that every filing has its ROADMAP row, where the roadmap files exist |
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
| "The tests pass, so they test the right thing" | Passing is what a test does when the bug is absent *and* when the test is vacuous. Step 3 is what tells them apart: a recorded red, or a mutation. |

1. **Confidence check:** explicitly answer "what am I least confident about right now?" (untested edge cases, quota/API assumptions, auth corners) and use it to direct extra tests/verification.
2. **Consolidation & simplification analysis** of the codebase as it now stands. Run **`design-review` in `phase` mode first, then `/simplify` on the whole branch diff, then `/code-review high`** — in that order. External review (step 5) comes after, and only then is the PR marked ready.
   - **That order, not the reverse.** Each pass must read the shape the one before it left: `design-review` moves responsibilities, `/simplify` rewrites, and `/code-review` is the correctness pass over everything that moved.
   - **Invoke it; do not restate its questions here.** The rubric lives in `design-review`; a second copy is a second edit site. Where it says to file a finding it does not fix, the rule at the top of this skill applies: through `project-docs` where the repository has the four roadmap files, otherwise in the PR's review record.
   - **Re-run the test suite after `/simplify`.** It rewrites code after the phase's green bar was established, and step 7 hands the user a diff to sign off on. Green is re-earned and reported, never assumed.
   - **Simpler, not shorter.** Reject any simplification that nests ternaries, trades readability for fewer lines, folds unrelated concerns into one function, or deletes an abstraction that was organising the code. Explicit beats compact.
   - **Always type the level.** `/code-review` with no level reuses the last one you typed *in any project*, so an unstated level silently inherits from an unrelated session.
   - `high` at the gate — the code is about to merge and ship in a release, so a missed bug costs more than a false one, and step 5's triage already handles uncertain findings. `medium` for mid-phase spot checks, where a short actionable list beats a triage pass. Not `ultra`: it's user-triggered and billed, and step 5 already covers that breadth.
3. **Red record check.** A test that passes whether or not the bug exists is worse than no test: it is a false green that the CHANGELOG then cites as evidence. Reading a test does not reveal this. The only proof a test discriminates is having watched it fail for the reason you claim.

   **Every test this phase added or materially changed, including any written during step 5, needs a `Red:` line** in a phase commit message — `Red: <test> — <observed failure>`, written when the test went red:

   ```bash
   git log --format=%B "origin/$DEFAULT_BRANCH"..HEAD | grep '^Red: '
   ```

   List the tests the phase diff adds or changes (an edited assertion, fixture or name) and match each to a line. The red each line records must meet the same three rules that make any red count:

   - **A stated failure condition** — what, specifically, would make this test fail. Not "it tests the parser": *"it fails if a `<script>` survives sanitization"*. Where the test closes a tracked issue it carries the ID (`test_ki_07_...`, or a `# KI-07` docstring line). **Most tests have no ID**, and that is fine; the stated failure condition is the requirement, always.
   - **A fixture that carries the property under test.** Assert this *before* asserting on the outcome. No amount of breaking production code will fail a test whose input never had the property: a quote-escaping test needs a quote in its input, a timezone test needs a non-UTC account.
   - **The named failure, not a harness error** (see below).

   **A mutation check is needed only for a test written after its fix, a test with no `Red:` line, or one whose recorded red is in doubt.** Run it now, as follows. Its result is that test's evidence in place of a `Red:` line, and the hand-off lists it as a mutation, not as an observed red.

   **Mutate, don't revert.** Break the specific behaviour the test names, in place, and confirm the test fails on the named assertion. Reverting the whole fix is coarser and has a hole: `git stash push` without `-u` leaves a newly added file in the tree, so the "reverted" code is still there and the test is falsely certified.

   **Commit the task before you mutate it.** That is what makes the restore safe.

   Do not make concurrent edits during the audit: the restore covers the mutation target, and a
   change elsewhere is not its to put back.

   ```bash
   bash "$CLAUDE_PLUGIN_ROOT/skills/phase-workflow/mutation-restore.sh" \
     "<task-sha>" "<file>" '<sed-expression>' <test-command...>
   ```

   Use the bundled script rather than pasting shell. It refuses a dirty tree, a symlinked or
   non-regular target, a SHA that is not HEAD, and a mutation that matches nothing; it restores
   the target across index and worktree on every exit path including INT and TERM; it verifies
   the file matches the SHA afterwards rather than trusting the restore's exit status; and it
   requires exit 1 specifically, because a fixture or collection error also returns non-zero.
   The test command runs twice: first with the mutation, then after restoration, when it must
   pass. Cleanup traps remain active through both runs. Non-ignored untracked output created
   by the audit is removed after each run; ignored files are left alone. Unexpected tracked
   changes outside the target are retained for inspection and make the audit fail.
   Change its behavior in `mutation-restore.sh` and verify it with `tests/phase-git.bats`.

   **Why the SHA must be HEAD:** the mutation is applied to the current checkout, so restoring
   from any earlier commit would revert every change committed since — work that looks safe
   because it was committed, which is why the script checks rather than trusts.

   **Choose a mutation whose predicted outcome is the same on every host.** A mutation models
   the defect, and several usually can. Pick one whose prediction does not depend on the machine
   the suite runs on: an environment-dependent red is not discrimination, because the same test
   and the same code give a different answer somewhere else, and the audit then certifies the
   runner rather than the test.

   The worked case, from this repo's own pressure tests. The defect is "the window was computed
   in server local time". `local = now.astimezone()` models it faithfully and is the wrong
   choice: it leaves the window in the runner's zone, so a UTC-fixture test stays green on a UTC
   host and goes red elsewhere. `local = now` and `local = now.astimezone(timezone.utc)` both
   model the same defect and both hold on every host. There is rarely one correct mutation, so
   the test is not "which expression" but "does its prediction survive a change of machine".

   The same rule applies to the fixture. **Every property a test asserts about its own input
   must hold wherever the suite runs.** A guard like `assert account_offset != host_offset` reads
   as diligence and is a trap: on a host in that zone it is False, the test errors before it
   reaches production code, and it discriminates nothing whatever the mutation does. Establish
   the property from values the test controls, never from the environment.

   After an untrappable kill or a power loss, no trap runs: inspect the tree and restore the
   target from the recorded task SHA by hand before resuming.

   **A red that is an import error, a collection error, or a fixture failure does not count.** It has to be the failure named in the condition. **That named failure may be a production exception** — if removing the behaviour makes the code under test raise, and the condition says so, that raise *is* the discrimination and the test passes the audit. What does not count is an error from the harness rather than the code: a missing import, a collection error, or a fixture that fell over before the production call. Do not invent a second mutation to manufacture an `AssertionError` when the named failure is already an exception the condition predicted. A false red is worth exactly as much as no check, and it is the easier of the two to mistake for success.

   **When the behaviour cannot be broken in place** — it lives in a dependency, or the fix was a deletion — use a worktree off the base, where the fix is absent by construction:

   ```bash
   set -euo pipefail
   PY="$PWD/.venv/bin/python"
   WT="$(mktemp -d)"
   cleanup_worktree() {
     rc=$?
     trap - EXIT INT TERM
     if [ -d "$WT/audit" ]; then
       git worktree remove --force "$WT/audit" || { echo "WORKTREE CLEANUP FAILED: $WT"; exit 1; }
     fi
     rmdir "$WT" || { echo "AUDIT DIRECTORY RETAINED: $WT"; exit 1; }
     exit "$rc"
   }
   trap cleanup_worktree EXIT
   trap 'exit 130' INT
   trap 'exit 143' TERM
   git worktree add --detach "$WT/audit" "<base>"
   mkdir -p "$WT/audit/$(dirname "<path to the test>")"
   cp -p "<test file>" "$WT/audit/<path to the test>"
   rc=0
   ( cd "$WT/audit" && "$PY" -m pytest "<the test>" -x ) || rc=$?
   [ "$rc" -eq 1 ] || { echo "NOT AN ASSERTION RED — pytest exit $rc; inspect the output"; exit 1; }
   echo "EXIT 1 — verify the named assertion in the output before certifying"
   ```

   **Exit 1 is necessary, not sufficient.** Inspect the output for the named assertion; fixture failures also return 1. A new module absent from the base yields an import failure, not a valid red. Audit that module at the saved task commit with a targeted mutation, or use a recorded TDD assertion red with an importable stub. If neither is available, the audit remains incomplete.

   **`$PY` is absolute.** Verify imports resolve to the worktree. If an editable install redirects them to the phase checkout, or the audit needs older dependency versions, build a throwaway environment inside the worktree and use its interpreter.

   Copy the **test** across, never the fix. For a test that *documents* an open issue rather than closing one, verify it is genuinely `xfail`/`skip` with the issue ID attached and not quietly passing.

   A test with no valid red is fixed or deleted — never carried — and any issue it claimed to close does not move to CHANGELOG until a test that does discriminate exists. Report the tests without a `Red:` line and the result of each mutation; a phase where every new test has its line says so.
4. **Documentation pass — holistic, not delta.** Check every doc against the code *as it now stands*, fixing drift from earlier phases too:
   - **Run `project-docs`' name check** (`python3 "$CLAUDE_PLUGIN_ROOT/skills/project-docs/name_check.py" --root .`). It reads the tracked Markdown except history (CHANGELOG, dated plans and specs), templates and test input; the reads below cover the rest. It is advisory: fix each item it lists or mark it with an ignore comment. It cannot catch a false claim.
   - **Read in full every doc that names something this phase added, changed, renamed or removed.** The diff gives the list: grep the docs for each changed name. Also read in full any doc found wrong during the phase, whatever the reason.
   - **README.md** — setup and usage; rewrite clean-slate when stale.
   - **docs/ARCHITECTURE.md** — **records and explains every diagram the project has**, one short section each saying what it depicts and when to regenerate it, not a bare embed. Regenerate each one with the `drawio` skill and compare against the generator committed at §2 (commit the `.drawio` source, generator script, and rendered PNG). **Drift-check the generator, not the PNG** — its box and edge labels are string literals naming modules and files, so they drop into the identifier check below, while a PNG is opaque to it. Catch a stale render mechanically: regenerate, then `git status`; if the PNG changes it was already out of date with its own source.
   - **CHANGELOG.md** — this phase's user-visible changes, appended to `[Unreleased]` under Added/Changed/Fixed/Removed. Never edit a released section. Where the roadmap files exist, an entry for a closed item is *moved* out of ROADMAP and its supporting file, not copied. Decide the version now (minor for additive work, patch for fixes and docs, major for a break). Prepare the release before external review: rename the populated `[Unreleased]` heading to `## [<version>] - <date> — <phase name>`, add a fresh empty `[Unreleased]` above it, and add the compare link under `## Reference`. Commit and push these edits before step 5. Record the version in the hand-off. Tag only after the approved PR merges.
   - **KNOWN_ISSUES.md / ENHANCEMENTS.md / OPEN_QUESTIONS.md**, where the repository has them — every finding triaged out of steps 1–3 gets a full entry in the right one and a pointer row in ROADMAP, not a one-liner in ROADMAP alone. Getting these current *before* step 5 is what lets the external reviewers be told what is already tracked, so they stop re-deriving the backlog. Rate it when you write it; an unrated item is an untriaged item. Re-check the ordering, and re-check the filing: a question that has become a defined bug moves to KNOWN_ISSUES.
   - **docs/PHASE_RECORD.md** — bring it current. It is written at §2 step 3 and then goes stale by
     default: the phase's later tasks, the deviations taken, the findings triaged and the version
     cut all happen after it was last touched. Record what the phase actually did, not what it
     planned to do. **§4 reads `MERGE_METHOD` from this file**, so a stale record is not a tidiness
     problem — it is the merge cycle reading the wrong value. Overwrite, never append: one record
     per phase accumulating is the phase ledger the roadmap rules forbid.
   - **Location** — root keeps README.md, AGENTS.md (or CLAUDE.md), CHANGELOG.md, LICENSE; every other doc lives in `docs/`. If a doc is at root that shouldn't be, `git mv` it so the rename is tracked, then fix every inbound link.
   - **Current-state rule:** every doc except AGENTS.md, **CHANGELOG.md** and the roadmap files (`ROADMAP.md`, `KNOWN_ISSUES.md`, `ENHANCEMENTS.md`, `OPEN_QUESTIONS.md`) documents only what the code *is*. CHANGELOG is exempt because describing removed features is most of a changelog's job; no "what we didn't build", no rejected alternatives, no removed features. Decisions-not-taken that future developers/agents must know go in the **project AGENTS.md** (or CLAUDE.md) only.
   - **Project AGENTS.md** (or CLAUDE.md) — updated to match the code as it actually is, plus those awareness notes.
   - **Docs about this project that live outside its repo.** A repo nested inside a container folder is usually described by that folder's own `README.md` and `CLAUDE.md` — a plugin inside a marketplace folder, a skill inside a synced skills folder. Those drift exactly like the in-repo docs and are missed exactly because they are one level up. Sweep them in the same pass: the skill list, the command table, the bundled-script list, anything naming a count.

     **They will not show up in `git status`.** The container folder is often not a git repo at all, so edits to it are invisible to the phase diff and to step 7's gate check. **Name them explicitly in the hand-off** — path and what changed — or the user signs off on a diff that does not contain them.
   - **Code comments** — read the comments in every file this phase touched. Delete comments describing removed behavior, fix ones the code outgrew, add a why-comment where the logic is non-obvious. Comments say *why*, not *what*.
   - **Drift check, beyond the name check** — config keys, code comments and diagram labels, which the name check does not read, and **one fact stated in several places**, which it cannot see. Report what you found, not only what you fixed.
   - **Style** — plain, familiar words; short sentences in the active voice; one idea at a time; no needless words, but no lost detail. Rewrite bloated prose you pass through, including text from earlier phases. Where the user's or the project's own standards say something different, theirs win; otherwise both apply.
   - **docs/ROADMAP.md + the three supporting files**, where the repository has them — follow the `project-docs` templates' vocabulary and sections exactly (say **"Done"**, never "Implemented"). ROADMAP rows stay pointers; detail belongs in the supporting file. Verify every ID appears in both, that the ratings agree, and that both files are ordered by rating descending: `project-docs`' `roadmap.py check` does this, and `roadmap.py close <ID>` removes a done item from both. ROADMAP never names the phase in flight; `docs/PHASE_RECORD.md` holds it.
**Re-gather derived evidence before this step, not after.** Some phases produce evidence by
*running* something rather than by reasoning: subagent scenario runs, eval scores, benchmark
numbers, generated diagrams. That evidence is only valid for the thing it was gathered against,
so a fix that changes that thing expires it — and an expired result read as current is worse
than no result, because it carries the authority of a measurement.

Three rules, in order:

- **Mark it expired at the moment of the fix**, in the file that records it, rather than
  remembering to do so later. The mark is what stops the next reader trusting it.
- **Make every fix that touches the measured thing first, then re-gather once.** Re-gathering
  mid-loop and fixing again afterwards expires the fresh evidence immediately; this has happened
  three times in this repo. The re-gather is the *last* action before the review, not a step in
  the middle of it.
- **Never send stale evidence to an external reviewer.** They cannot tell it is stale, and a
  reviewer's agreement with an expired result reads as confirmation.

This matters most where re-gathering is expensive — fresh subagents, paid API calls, long runs —
because that cost is exactly what tempts a skip. Say in the hand-off what was re-gathered and
what remains expired.

5. **External review loop:** `external-review` in `phase` mode (Codex + Gemini). [Its loop](../external-review/SKILL.md#the-loop) runs up to three passes without checking in, with its stop rule applied before any fix, and builds one [review record](../external-review/SKILL.md#the-phase-review-record) across them. Past three passes, or a fix after the loop stopped, is the user's call.
   - **It runs after the docs pass**, including release preparation. Fold later phase fixes into that unpublished release and commit them before the next pass or gate. Each commit a pass reviews has a green full suite.
   - Build the record using `external-review`'s output contract and
     [coverage classification](../external-review/SKILL.md#coverage-classification).
   - Every finding fixed here gets a failing test first, with its `Red:` line. Run step 3's check on those tests before the next pass, and again before the gate.
6. **Post-fix drift re-check — narrow, and inside the loop.** Step 5's fixes change code after step 4 declared the docs true, so each round of fixes re-checks what it touched before it is committed for the next pass: the docs and code comments the changed files invalidate, the CHANGELOG entries whose claims moved, and the diagrams if a module moved. That way the next pass reviews them. After the last pass, confirm only that every filing has both its full entry and its ROADMAP pointer row, with ratings that agree, where the roadmap files exist; anything else this finds needs a narrow pass (`external-review`'s [loop](../external-review/SKILL.md#the-loop)). Report what you found, not only what you fixed.
7. **Present to the user and stop** — the phase gate.
   - **Include the review record** from step 5 in the hand-off, and put it in the PR description (`gh pr edit "$PR" -R "$REPO" --body-file <file>`) — never in a per-phase review file in the repository. It exists so the user can see every finding and pull any deferred or accepted one back into this phase before signing off.
   - **Confirm `docs/PHASE_RECORD.md` is current, and do not take that on trust.** Step 4 brought
     it current, but steps 5 to 7 and every re-gate come after step 4, so it goes stale again by
     default. Compare its last commit against `HEAD`:

     ```bash
     LAST_RECORD="$(git log -1 --format=%H -- docs/PHASE_RECORD.md)"
     BEHIND="$(git rev-list --count "$LAST_RECORD"..HEAD)"
     [ "$BEHIND" -eq 0 ] || { echo "PHASE RECORD PREDATES $BEHIND LATER COMMITS — re-read it"; exit 1; }
     ```

     Updating it makes it the newest commit again, which is why this is the last edit before
     presenting. **A phase whose record still describes an earlier task has not reached the
     gate**, whatever the tests say — §4 reads `MERGE_METHOD` from that file.

   - **Record the PR number and the release version in `docs/PHASE_RECORD.md` before presenting.**
     §4 loads `MERGE_METHOD` from that file and needs `APPROVED_SHA` too, and a hand-off in chat
     does not survive a session boundary — which is what "preserve that record across sessions" at
     §2 step 3 requires. §2 could not record either value: neither is known until the gate.

     **Do not write the SHA into the file.** A commit cannot contain its own hash: the write
     changes the commit it describes, and amending to correct it regresses without end. Record the
     `PR` instead and resolve the SHA from it — the gate has already verified that the PR head,
     `origin/<branch>` and local `HEAD` are the same commit, so this is exact rather than a
     convenience. Sign-off binds to that head; an edit afterwards moves it and means re-requesting
     review on the new one.
   - **Do not merge.** The merge is the post-sign-off action; it happens in §4 and nowhere else. Committing and pushing are not — those happened per task, throughout the phase.
   - **Before marking the PR ready, check what landed after review**, and run the full suite on `HEAD`. Only bookkeeping may follow the last pass: the deferred filings and the phase record (`external-review`'s [loop](../external-review/SKILL.md#the-loop)). List it:

     ```bash
     git merge-base --is-ancestor "<commit the last pass reviewed>" HEAD || { echo "REVIEWED COMMIT REWRITTEN — run a full pass"; exit 1; }
     git diff "<commit the last pass reviewed>"..HEAD
     ```

     Read the patch, not only the file list: a filing and a fix can share a file. Anything beyond new entries, their pointer rows and the record needs a narrow pass first. Name what landed in the hand-off.
   - **The gate has two checkable states.** First, **the work is committed, pushed, and on a PR marked ready for review** — every one of those is a fact git or `gh` will answer, none is self-attested:

     Load the phase's recorded `ORIGIN_URL`, `ORIGIN_PUSH_URL`, `REPO`, `DEFAULT_BRANCH`, `PHASE_BRANCH` and `MERGE_METHOD`. Preserve the §2 URL values in the hand-off; do not refresh them from the current remote. Set `PR` to this phase's PR number. This workflow uses a same-repository PR.

     ```bash
     set -euo pipefail
     TREE_STATE="$(git status --porcelain=v1 --untracked-files=all)"
     [ -z "$TREE_STATE" ] || { echo "UNCOMMITTED WORK — commit it before the gate"; exit 1; }
     BRANCH="$(git symbolic-ref --quiet --short HEAD)"
     [ "$BRANCH" = "$PHASE_BRANCH" ] || { echo "WRONG BRANCH — stop"; exit 1; }
     LOCAL_SHA="$(git rev-parse --verify HEAD)"
     bash "$CLAUDE_PLUGIN_ROOT/skills/phase-workflow/publish-release.sh" \
       --check-origin "$ORIGIN_URL" "$ORIGIN_PUSH_URL"
     [ "$(gh repo view "$ORIGIN_URL" --json nameWithOwner --jq .nameWithOwner)" = "$REPO" ] \
       && [ "$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)" = "$DEFAULT_BRANCH" ] \
       || { echo "REPOSITORY OR BASE CHANGED — stop"; exit 1; }
     REMOTE_SHA="$(git ls-remote --exit-code --heads origin "refs/heads/$PHASE_BRANCH" | awk '{print $1}')"
     PR_SHA="$(gh pr view "$PR" -R "$REPO" --json headRefOid --jq .headRefOid)"
     [ "$LOCAL_SHA" = "$REMOTE_SHA" ] && [ "$LOCAL_SHA" = "$PR_SHA" ] \
       || { echo "HEAD MISMATCH — local, origin and PR must agree"; exit 1; }
     PR_IDENTITY="$(gh pr view "$PR" -R "$REPO" --json state,isCrossRepository,headRefName,baseRefName --jq '[.state, .isCrossRepository, .headRefName, .baseRefName] | @tsv')"
     [ "$PR_IDENTITY" = "$(printf 'OPEN\tfalse\t%s\t%s' "$PHASE_BRANCH" "$DEFAULT_BRANCH")" ] \
       || { echo "WRONG PR STATE, REPOSITORY OR BRANCH — stop"; exit 1; }
     PHASE_COMMITS="$(git log --oneline "refs/remotes/origin/$DEFAULT_BRANCH".."$LOCAL_SHA")"
     [ -n "$PHASE_COMMITS" ] || { echo "NO PHASE COMMITS — stop"; exit 1; }
     DRAFT="$(gh pr view "$PR" -R "$REPO" --json isDraft --jq .isDraft)"
     case "$DRAFT" in
       true) gh pr ready "$PR" -R "$REPO" || { echo "PR READY FAILED — stop"; exit 1; } ;;
       false) ;;
       *) echo "UNKNOWN DRAFT STATE — stop"; exit 1 ;;
     esac
     READY_SHA="$(gh pr view "$PR" -R "$REPO" --json state,isDraft,headRefOid --jq 'if .state == "OPEN" and .isDraft == false then .headRefOid else empty end')"
     [ "$READY_SHA" = "$LOCAL_SHA" ] || { echo "PR NOT READY AT GATE SHA — stop"; exit 1; }
     GATE_SHA="$LOCAL_SHA"
     printf 'Local: %s\nOrigin: %s\nPR: %s\nGate SHA: %s\n' "$LOCAL_SHA" "$REMOTE_SHA" "$PR_SHA" "$GATE_SHA"
     printf '%s\n' "$PHASE_COMMITS"
     ```

     Record these SHAs, the repository, PR number and link, base branch, phase branch, merge method and release tag in the hand-off. Give the phase diff command: `git diff "origin/$DEFAULT_BRANCH"..."$GATE_SHA"`. The user signs off on `GATE_SHA`. Set `APPROVED_SHA` to that recorded value only after approval; never refresh it from a later HEAD.

     Second, **the reviewer artifacts exist on disk**. Apply
     `external-review`'s [coverage classification](../external-review/SKILL.md#coverage-classification)
     to every required chunk of every pass. Include the review record with each pass's coverage
     line. Cite each invocation's exact model ID, output file and byte count, plus
     the error lines of a failed invocation: full paths and error text in the hand-off, file
     names only in the PR copy. For any Failed pair in the last pass, and for no
     coverage, re-run when a reviewer is available or record the user's decision to land
     without that review. Account for skipped reviews
     explicitly. No coverage line means step 5 has not been accounted for.

   - **Name the single merge method** recorded at §2 step 3.
   - **End the hand-off with the actual state:** "Committed and pushed on `<branch>`, PR `<n>` ready at `<gate SHA>`, awaiting your sign-off to merge."
   - **Any edit while waiting for sign-off invalidates approval**, including a typo or release metadata edit. Commit and push it, name it in a follow-up, repeat the gate and obtain sign-off on the new SHA.

### Writing bats assertions — three things that cost a phase

**A false `[[ ]]` does not fail its test unless it is the test's last command — on bash 3.2.**
Measured with bats 1.14.0: under **bash 3.2.57** a false mid-test `[[ ]]` passes its test while a
false `[ ]` stops it; under **bash 5.3.20** both stop it. Sixty-eight assertions in this repo were
therefore read by their author and never by the suite on the interpreter macOS ships.
`bats_assertions.py` finds them.

**The vacuity belongs to the interpreter, which scopes every claim made about it.** Appending
`|| false` is correct under both, and load-bearing only where the bare form was not — so the
evidence that the suffix supplies the discrimination holds for bash 3.2.57 and not for bash
5.3.20. A test that asserts the vacuity itself **decides its own scope by running its fixture**,
never by reading `$BASH_VERSION`: two measured points say nothing about bash 4, and a test whose
fixture no longer carries the property under test asserts nothing. `verify-assertions.bats` skips
that one test, with the interpreter named in the skip reason.

**To measure an interpreter's behaviour, pin it with `PATH` and confirm it from inside the run.**
`bats` re-execs `bats-exec-file` and `bats-exec-test`, each `#!/usr/bin/env bash`, so the
interpreter is resolved from `PATH` however the outer script was started — `/bin/bash "$(command
-v bats)"` runs the tests under whatever `env bash` finds, not under `/bin/bash`. Put the wanted
directory first on `PATH`, and have the fixture `echo "$BASH_VERSION" >&3`: that reading is what
caught two pinning methods that had both looked right.

**It is also the standing regression check, and it is about the interpreter macOS ships.** An
assertion ending in `|| false` is load-bearing wherever it sits, so the tool reports it `final`.
Across the repo's skills the count of `mid` rows is **0**, and any number above zero is an
assertion that went in unguarded — vacuous on stock bash even when the machine running the gate
has a newer one:

```bash
python3 skills/phase-workflow/bats_assertions.py \
  skills/*/tests/*.bats \
  > "$TMPDIR/scan.tsv" || { echo "SCAN FAILED — the gate proves nothing"; exit 1; }
MID="$(set -o pipefail; awk -F'\t' '$4=="mid"' "$TMPDIR/scan.tsv" | tee /dev/stderr | wc -l | tr -d ' ')" \
  || { echo "COUNTING FAILED — the gate proves nothing"; exit 1; }
[ "$MID" -eq 0 ] || { echo "MID ASSERTIONS PRESENT: $MID"; exit 1; }
```

**Check the scanner ran before reading its count.** Piping the scanner straight into `awk`
prints nothing when the scanner fails outright, and nothing is exactly what a clean result looks
like.

The fourth column is `mid` for an unguarded assertion followed by more commands, and `final` for
either the last command or an assertion already ending in `|| false`.

**Convert by appending `|| false`, not by rewriting.** `[[ ... ]] || false` is load-bearing and
leaves the expression untouched, so the assertion cannot quietly come to mean something else.
Rewriting into `printf | grep -q` is the tempting alternative and it narrows every pattern that
spans lines — see below. `verify_assertions.sh` proves an assertion is load-bearing; only reading
the diff proves the conversion preserved its meaning.
Run `verify_assertions.sh` from the repo root with a repo-relative file path;
absolute paths are refused.

**`$output` is multiline, and line-oriented tools reason about it wrongly.** Three separate
defects in one phase came from this:

| Form | What goes wrong |
| ------ | ---------------- |
| `[[ "$output" == *"A"*"B"* ]]` | globs span newlines, so it matches `A` on one line and `B` on another |
| `grep -q 'A.*B'` | line-based, so it does **not** match across lines — the reverse mistake |
| `grep -qv 'A'` | succeeds when *any* line lacks `A`; it cannot show `A` is absent |

To assert a substring is absent from the whole output, use `[[ "$output" != *"A"* ]] || false`.
To scope a match to one line, select it first: `[[ "$(printf '%s\n' "$output" | grep '^codex')" != *"READY"* ]] || false`.

**Also: a second `run` overwrites `$output`.** Save the text you mean to assert on before the
next `run`, or the assertion checks the wrong thing and passes.

## 4. Post-sign-off merge cycle

Sign-off — as defined at the top of this file — is the only trigger. Once it comes, run the whole cycle without re-asking.

**Resume from recorded state.** Load `ORIGIN_URL`, `ORIGIN_PUSH_URL`, `REPO`, `PR`, `PHASE_BRANCH`, `DEFAULT_BRANCH`, `MERGE_METHOD`, `APPROVED_SHA` and `TAG` from the approved hand-off. `TAG` includes the `v` prefix. Never derive approval from the current PR head. A later head needs a new gate and sign-off.

Run the remote check before resuming. `publish-release.sh --check-origin` validates the
recorded fetch and push destinations and rejects multiple push destinations without changing
refs. Use this mode at the gate and before each publication or deletion below; the script owns
the remote-check logic.

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/phase-workflow/publish-release.sh" \
  --check-origin "$ORIGIN_URL" "$ORIGIN_PUSH_URL" || exit 1
```

1. **Confirm release preparation.** The approved commit already contains the release heading and compare link from §3 step 4. Do not repeat those edits. If anything is missing, return to §3 and obtain approval for the new SHA.
2. **Confirm publication.** The gate recorded matching local, origin and PR SHAs. Do not add a release commit after sign-off. On resume, inspect the PR state first: `MERGED` proceeds to step 5, an open PR proceeds to step 3, and a closed unmerged PR stops. Require its `headRefOid` to equal `APPROVED_SHA` in every case.
3. **Wait for checks** on an open PR: `gh pr checks "$PR" -R "$REPO" --watch`. A failing check, an unknown check state or a blocking required review ends this attempt. Report it and stop. If no checks exist, verify that against the repo's requirements before proceeding. Do not bypass branch rules or push fixes through an approved gate.
4. **Merge the approved head with the method recorded in `docs/PHASE_RECORD.md`.** Do not request branch deletion during merge. Queue-based repositories choose their queue's merge strategy. Leave queued work pending until GitHub confirms completion; do not tag an open PR or treat it as merged.

   ```bash
   set -euo pipefail
   case "$MERGE_METHOD" in squash|rebase|merge) ;; *) echo "MERGE METHOD UNKNOWN — stop"; exit 1 ;; esac
   CURRENT_SHA="$(gh pr view "$PR" -R "$REPO" --json headRefOid --jq .headRefOid)"
   [ "$CURRENT_SHA" = "$APPROVED_SHA" ] || { echo "SIGN-OFF INVALID — PR HEAD CHANGED"; exit 1; }
   PR_IDENTITY="$(gh pr view "$PR" -R "$REPO" --json state,isCrossRepository,headRefName,baseRefName --jq '[.state, .isCrossRepository, .headRefName, .baseRefName] | @tsv')"
   [ "$PR_IDENTITY" = "$(printf 'OPEN\tfalse\t%s\t%s' "$PHASE_BRANCH" "$DEFAULT_BRANCH")" ] \
     || { echo "PR IDENTITY CHANGED — return to the gate"; exit 1; }
   MERGE_RC=0
   gh pr merge "$PR" -R "$REPO" "--$MERGE_METHOD" --match-head-commit "$APPROVED_SHA" || MERGE_RC=$?
   OUTCOME="$(gh api graphql -F owner="${REPO%/*}" -F name="${REPO#*/}" -F number="$PR" \
     -f query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){state headRefOid mergeQueueEntry{position} autoMergeRequest{enabledAt}}}}' \
     --jq '.data.repository.pullRequest | [.state, .headRefOid, (if .mergeQueueEntry != null then "queued" elif .autoMergeRequest != null then "auto" else "none" end)] | @tsv')"
   IFS=$'\t' read -r STATE CURRENT_SHA PENDING <<< "$OUTCOME"
   [ "$CURRENT_SHA" = "$APPROVED_SHA" ] || { echo "SIGN-OFF INVALID — PR HEAD CHANGED"; exit 1; }
   case "$STATE" in
     MERGED) echo "MERGED — continue to tag verification" ;;
     OPEN)
       case "$PENDING" in
         queued) echo "QUEUED — wait for completion; resume at step 2, do not tag" ;;
         auto) echo "PENDING — auto-merge awaits requirements; resume at step 2, do not tag" ;;
         *) echo "MERGE NOT CONFIRMED — command exit $MERGE_RC; inspect checks, reviews and queue status" ;;
       esac
       exit 1 ;;
     *) echo "NOT MERGED — state $STATE; stop"; exit 1 ;;
   esac
   ```

   If the queue-status query fails, stop and inspect the PR on GitHub before resuming. If it is removed from the queue or checks fail, report the failure and stop. Resume at step 2; do not submit repeated merge requests while it is pending.
5. **Confirm the completed merge and publish its tag.** This stage can be retried after a fetch, tag or push failure. An existing local or remote tag is accepted only when it resolves to this PR's merge commit. Never replace a conflicting tag.

   ```bash
   set -euo pipefail
   CURRENT_SHA="$(gh pr view "$PR" -R "$REPO" --json headRefOid --jq .headRefOid)"
   [ "$CURRENT_SHA" = "$APPROVED_SHA" ] || { echo "SIGN-OFF INVALID — PR HEAD CHANGED"; exit 1; }
   SHA="$(gh pr view "$PR" -R "$REPO" --json state,mergeCommit \
          --jq 'if .state=="MERGED" and .mergeCommit then .mergeCommit.oid else empty end')"
   [ -n "$SHA" ] || { echo "NOT MERGED — stop; do not tag"; exit 1; }
   git check-ref-format "refs/tags/$TAG"
   bash "$CLAUDE_PLUGIN_ROOT/skills/phase-workflow/publish-release.sh" \
     --check-origin "$ORIGIN_URL" "$ORIGIN_PUSH_URL"
   git fetch origin
   git cat-file -e "$SHA^{commit}"
   TAG_REF="refs/tags/$TAG"
   REMOTE_TAG="$(git ls-remote origin "$TAG_REF" "$TAG_REF^{}")"
   if [ -n "$REMOTE_TAG" ]; then
     REMOTE_TAG_SHA="$(printf '%s\n' "$REMOTE_TAG" | awk '$2 ~ /\^\{\}$/ {peeled=$1} $2 !~ /\^\{\}$/ {direct=$1} END {print (peeled != "" ? peeled : direct)}')"
     [ "$REMOTE_TAG_SHA" = "$SHA" ] || { echo "REMOTE TAG CONFLICT — stop"; exit 1; }
   fi
   if git show-ref --verify --quiet "$TAG_REF"; then
     LOCAL_TAG_SHA="$(git rev-parse --verify "$TAG_REF^{commit}")"
     [ "$LOCAL_TAG_SHA" = "$SHA" ] || { echo "LOCAL TAG CONFLICT — stop"; exit 1; }
   elif [ -n "$REMOTE_TAG" ]; then
     git fetch origin "$TAG_REF:$TAG_REF"
     [ "$(git rev-parse --verify "$TAG_REF^{commit}")" = "$SHA" ] || { echo "FETCHED TAG CONFLICT — stop"; exit 1; }
   else
     git tag "$TAG" "$SHA"
   fi
   if [ -z "$REMOTE_TAG" ]; then
     bash "$CLAUDE_PLUGIN_ROOT/skills/phase-workflow/publish-release.sh" \
       --check-origin "$ORIGIN_URL" "$ORIGIN_PUSH_URL"
     git push origin "$TAG_REF:$TAG_REF" || { echo "TAG PUSH FAILED — retain local tag; resume step 5"; exit 1; }
   fi
   echo "TAG VERIFIED AND PUBLISHED: $TAG at $SHA"
   ```

6. **Clean up only after merge and tag confirmation.** Delete the remote phase branch only if it still points to the approved SHA. If auto-deletion already removed it, continue. A changed branch is retained for inspection.

   ```bash
   set -euo pipefail
   MERGED_HEAD="$(gh pr view "$PR" -R "$REPO" --json state,headRefOid --jq 'if .state == "MERGED" then .headRefOid else empty end')"
   [ "$MERGED_HEAD" = "$APPROVED_SHA" ] || { echo "APPROVED MERGE NOT CONFIRMED — retain branch"; exit 1; }
   [ "$PHASE_BRANCH" != "$DEFAULT_BRANCH" ] || { echo "REFUSE DEFAULT BRANCH DELETION"; exit 1; }
   REMOTE_HEAD="$(git ls-remote --heads origin "refs/heads/$PHASE_BRANCH" | awk '{print $1}')"
   if [ -n "$REMOTE_HEAD" ]; then
     [ "$REMOTE_HEAD" = "$APPROVED_SHA" ] || { echo "BRANCH ADVANCED — retain it"; exit 1; }
     bash "$CLAUDE_PLUGIN_ROOT/skills/phase-workflow/publish-release.sh" \
       --check-origin "$ORIGIN_URL" "$ORIGIN_PUSH_URL"
     git push --force-with-lease="refs/heads/$PHASE_BRANCH:$APPROVED_SHA" origin ":refs/heads/$PHASE_BRANCH"
   fi
   ```

   Then prune the local branches whose upstream is gone. **Run these commands rather than a shell alias** — the workflow must not depend on the user's `~/.zshrc`, which a fresh machine, a subagent or a non-interactive shell may not have loaded.

   ```bash
   set -euo pipefail
   git fetch --prune origin
   BRANCHES="$(git for-each-ref --format='%(refname:short) %(upstream:track)' refs/heads/)"
   CURRENT="$(git symbolic-ref --quiet --short HEAD || true)"
   GONE="$(printf '%s\n' "$BRANCHES" | awk -v current="$CURRENT" '$2 == "[gone]" && $1 != current {print $1}')"
   if [ -n "$GONE" ]; then
     # Never -D except at the approved tip already confirmed present on the remote.
     # That tip contains no unpushed commits; use -d for every other branch.
     while IFS= read -r b; do
       if [ "$(git rev-parse "$b")" = "${APPROVED_SHA:-}" ]; then
         git branch -D "$b"
       elif git branch -d "$b"; then
         :
       else
         echo "RETAINED — $b holds commits absent from ${DEFAULT_BRANCH:-the default branch}"; exit 1
       fi
     done <<< "$GONE"
   else
     echo "Nothing to clean up."
   fi
   ```

   Cleanup failures resume at step 6 and do not repeat release edits or merge.

Then stop. The next phase's branch is created at phase start (§2 step 1) — never here.

**`git reset --hard` appears nowhere in this workflow; do not add it.** Where a reset is genuinely required, branch first (`git branch backup/<phase>-$(date +%s)`) or use `git reset --keep`, which refuses rather than discarding.

## Roadmap file rules

The roadmap files, their templates and `roadmap.py` belong to the `project-docs` skill, which
states the rules for them.
