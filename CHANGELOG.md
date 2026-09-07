# Changelog

All notable changes to the `localclaude` plugin are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions before 1.8.0 predate this file. Their changes are not reconstructed
here — the plugin manifest's version is the only record of them.

## [Unreleased]

### Added

- **`design-review` skill** — the structural design pass, at plan time and phase
  end. Produces the module table, the expected-change and shared-state lines, and
  verdicts on six named checks. Wired into `phase-workflow` at §1 (drafting), §2
  (landing diagram generators) and §3 step 2, where it runs before `/simplify`.
- **Pressure tests for it**, in `skills/design-review/tests/` — seven scenarios
  covering fourteen rules, each with its prompt, failure conditions and recorded
  results for a run with and without the skill. Two rules were written *by* the
  tests rather than confirmed by them: the produce-versus-edit distinction, and
  never marking a diagram box "new" because the marker is a diff that goes stale
  the moment the phase lands. Every rule's status is recorded
  honestly, including the nine of those fourteen a strong model already follows
  unaided — six of this skill's own rules and three process rules from
  `phase-workflow`.
- **Four roadmap files** under `docs/` — ROADMAP, KNOWN_ISSUES, ENHANCEMENTS and
  OPEN_QUESTIONS, seeded from the templates with 27 issues, 6 enhancements and 1
  open question from an external repo review.
- `LICENSE` — the MIT text the plugin manifest and skill frontmatter already
  declared.

### Changed

- **Test-validity audit now mutates rather than reverts** (`phase-workflow` §3
  step 3). Breaking the named behaviour in place replaces stashing the fix, which
  left newly added files in the tree and falsely certified the test. Restoration
  is by **file snapshot**, never by `git checkout --`, `git restore` or `git stash`
  — at the phase gate those read committed or indexed state, which is the phase's
  starting point rather than its work, and none of them can restore a file the
  phase created. Every failure path stops and names the surviving copy. A fixture
  must carry the property under test.
- **Skip and partial coverage are now distinct** in both `phase-workflow` and
  `review-checkpoint`. A reviewer that fails on quota, auth, timeout or sandbox
  ran and returned nothing; only an uninstalled CLI is a skip.
- **Findings tables carry a `Files` column** — where each finding lives, verified against the
  repo during triage, so a filed `KI-nn` stays actionable from cold.
- **The documentation pass covers docs outside the repo** — a container folder's own README and
  CLAUDE.md drift the same way and never appear in `git status`, so they are named explicitly in
  the hand-off.
- **`review-checkpoint` is canonical for the review loop**; `phase-workflow`
  delegates instead of restating it. The two copies had already drifted into
  contradiction.
- **Bundles exclude credential-shaped, binary and symlinked files** before
  anything is sent to an external reviewer, on tracked and untracked lists alike,
  via `git` pathspecs plus an explicit symlink test — `git ls-files` matches a
  link by its own name, so an innocuous filename pointing at a key passes every
  pathspec. The bundling loop is shown in full rather than described, and the
  withheld files are named in the coverage line.
- **The default branch is detected, never hardcoded**, and the protection probe
  branches on HTTP status so auth and network failures no longer read as
  "unprotected".
- **Global standards:** subagents have three named uses and are never used to
  verify correctness; work runs as a phase when brainstorming classifies it
  architectural; anything that lands cuts a release with semver deciding the
  number; "deterministically testable" and post-gate edits are defined; the
  allowlist is described as a prompt-reducer rather than a security boundary.
- **The phase gate is per-task commits on a draft PR** (`UNK-01`, resolved). The
  gate was "present uncommitted work and stop", which held a phase's whole
  output in the one state `git reflog` cannot recover while the retrospective
  pointed `git checkout`, worktree and stash operations at it. Work now commits
  per task onto a draft PR opened at phase start; the PR goes ready for review at
  the gate and sign-off authorizes the merge.
- **Subagents may commit their own task**, one task per commit, on the phase
  branch. They still never push, merge, tag, or touch the default branch.
  `superpowers:subagent-driven-development` works as built under this rule, since
  its review packages, ledger and crash recovery are all commit-range based —
  which the uncommitted gate had ruled out.
- **Branch-protection detection removed.** Every phase lands by PR, so the
  question no longer arises. The probe could not be made correct anyway:
  `GET /branches/{b}/protection` covers classic protection only, so a repo using
  rulesets to require PRs returns 404 and reads as unprotected.
- **Neither Claude nor the external reviewers open credential-shaped files** by
  default. For the reviewers this is a prompt instruction rather than
  enforcement, because `--sandbox read-only` gates writes and not reads.
- **The phase gate cites the reviewer output files**, per pass, with byte counts.
  The gate's other half asks git a question; this half used to ask the agent's own
  hand-off whether it contained a findings table, which an agent that skipped the
  review satisfies by writing one. It also takes a **coverage line for every pass,
  always** — a pass where both reviewers ran and returned nothing has no findings
  to tabulate, no missing CLI, and no error to quote, and the older wording called
  that a review that never happened.
- **The Codex model ladder tops out at `gpt-6-astra`**, and both ladders now set
  reasoning effort explicitly. Every listed model supports low through max and
  `gpt-6-astra` defaults to **low**, so naming only the slug got the weakest
  setting of the strongest model while the run read as stronger than it was. The
  effort is recorded beside the slug.
- **`Direction` orders the module table by stability, not by call order.** Ordering
  rows by their own dependency column made the check circular — any acyclic graph
  can be ordered so every arrow points the same way — so it detected nothing that
  cycle detection did not. Rows now go slowest-changing first, and the check fires
  on a unit depending on something with more reasons to change than itself.
- **The diagram rule is distinctness, not a count.** Each diagram earns its place
  by showing something no other diagram shows; the recurring cost is that every
  phase end regenerates and drift-checks it. Three diagrams that each carry
  something distinct is not a violation.
- **KI-01 and KI-22 re-rated Critical.** Both silently truncate a user's file —
  `settings.json` and `.zshrc` — which is the top line of the severity scale those
  entries are graded against.
- Skill descriptions shortened — `claude-setup` 136→60 words, `phase-workflow`
  163→49, `review-checkpoint` 187→59. They are resident in every session.

### Fixed

- The CHANGELOG move is instructed once, at §3 step 4, not again at §4 step 1.
- CHANGELOG.md is exempt from the current-state rule, which had forbidden it from
  describing removed features.
- `review-checkpoint`'s Model column no longer says `Both` in one place and
  forbids it in another; severity disagreements between reviewers are recorded.
- The bundle file count uses `git status --porcelain -uall`, so untracked
  directories no longer collapse to one line.
- `claude-setup` listed three bundled skills; there are six. README omitted
  `llama-autostart.sh` from the backend scripts.

## [1.8.0] - 2026-09-05 — Review loop and test validity

### Added

- **Test-validity audit** as `phase-workflow` §3 step 3. Every test a phase adds
  or changes must state its failure condition and show evidence of a red state,
  proved by reverting the fix and confirming the assertion fails. An import,
  collection, or fixture failure does not count as red. Tests that pass whether
  or not the bug exists are fixed or deleted, and the issue they claimed to
  close stays open.
- **External review loop** in `review-checkpoint`: up to three review→fix passes
  per phase, with a blocking pause on the findings table after every pass. Pass
  1 is full scope; follow-ups are narrowed to the fixes just made plus a
  re-check of the findings they claimed to resolve, so a second review does not
  churn through the whole phase again.
- **Spotlighting** in follow-up review prompts — naming the fixes where your own
  verification is the weakest available evidence (security-sensitive paths,
  fixes validated by reasoning rather than by a failing test) and asking for an
  adversarial read of those specifically.
- **Already-tracked list** in the shared reviewer rubric. Both reviewers receive
  the current `KNOWN_ISSUES` / `ENHANCEMENTS` / `OPEN_QUESTIONS` entries as
  ID, title, rating and first sentence, so they stop re-deriving the backlog.
- **Test-discrimination question** in the reviewer rubric, as a backstop to the
  step 3 audit: would each test still pass with its change reverted?
- **Red-flags table** in `phase-workflow` §3 naming the rationalizations that
  mean the retrospective has not actually run.
- A stated-failure-condition rule in the global standards managed block, so the
  TDD red step has something specific to check the red against.
- This changelog, and a `.gitignore` for the plugin repo.

### Changed

- **`phase-workflow` §3 is now seven steps**, with the external review moved
  *after* the documentation pass. Reviewers see the phase's real deliverable —
  code and docs together — instead of spending findings on doc drift that the
  docs pass was already going to repair. A narrow post-fix drift re-check
  follows the review loop.
- **The phase gate has a second checkable state.** Alongside "the work is
  uncommitted", the hand-off must carry a findings table for every review pass
  or the written skip line. The gate always runs, so this is what catches a
  skipped review.
- **External review is no longer described as best-effort.** The CLIs are
  best-effort; running the step is not. A missing CLI is the only legitimate
  skip, and it must be stated in writing.

### Fixed

- **`review-checkpoint` captured phase changes with `git diff <base>...HEAD`,
  which is wrong twice over.** It shows only committed work — and at the phase
  gate the work is uncommitted by design, so it can return nothing — and no
  `git diff` contains untracked files, so a phase that added a new module sent
  Gemini a diff full of calls into a file it could not see, which it then
  reported as missing. Replaced with a bundle of `git diff <base> -- .` plus
  every untracked file appended in full, reconciled against
  `git status --porcelain` and with the file count stated in the prompt and the
  coverage line. The failure was silent, so the count is the fix.

## Reference

[Unreleased]: https://github.com/rahulragunathan/localclaude/compare/v1.8.0...HEAD
[1.8.0]: https://github.com/rahulragunathan/localclaude/releases/tag/v1.8.0
