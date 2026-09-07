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
  honestly, including the eleven of those fourteen a strong model already
  follows unaided — eight of this skill's own rules and three process rules from
  `phase-workflow`.
- **Four roadmap files** under `docs/` — ROADMAP, KNOWN_ISSUES, ENHANCEMENTS and
  OPEN_QUESTIONS, seeded from the templates with 27 issues, 6 enhancements and 1
  open question from an external repo review.
- `LICENSE` — the MIT text the plugin manifest and skill frontmatter already
  declared.
- **`project-env` skill** (`ENH-01`), holding the Python and Node environment
  procedures the global standards block used to carry inline: the
  `~/Python-Envs` / `~/Node-Envs` layout, the `standardize-*-envs.sh` scripts,
  the dependency-file split, and which invocations are allow-listed. The split
  follows one test — **a prohibition stays resident, a procedure moves to a
  skill.** The block keeps "no virtualenv ever lives inside Drive" and the
  script names; it no longer carries argument orders.
- **`CLAUDE.md` and `docs/ARCHITECTURE.md`** (`ENH-06`). This repo requires both
  of every project and had neither. ARCHITECTURE carries the module table, the
  expected-change and shared-state lines, and a generated module map
  (`docs/build_architecture.py` → `docs/architecture.{drawio,png}`, validating
  clean). The project `CLAUDE.md` carries the conventions specific to a repo
  whose modules are prose, plus "Decisions taken and not taken" — the rejected
  unpushed gate, the dropped review-pass ceiling, the always-emitted findings
  table, the unsupported `$CLAUDE_CONFIG_DIR`, the triage-subagent exception,
  and the accepted limit on what the bundle exclusions can do about Codex.

### Changed

- **Test-validity audit now mutates rather than reverts** (`phase-workflow` §3
  step 3). Breaking the named behaviour in place replaces stashing the fix, which
  left newly added files in the tree and falsely certified the test. Restoration
  is by `git checkout --`, which is correct here because the audit runs against a
  committed task: the commit is the state to return to, and the snippet refuses to
  run on a dirty tree or a symlinked target. Every failure path stops rather than
  continuing. A fixture must carry the property under test.
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
- **The duplication threshold closes its third option.** A new small module for
  two callers is conjuring an abstraction even when the nearest existing module
  is a poor fit — two copies of a four-line function cost less than a module, an
  import in every caller, and a name everyone learns. Found by a pressure-test
  run that built the module and reasoned well doing it.
- **Skills carry only live evidence.** `design-review`'s results table moved to
  `tests/README.md` where the tests are, and each scenario keeps one baseline row
  and one with-skill row. Superseded rows are project memory, not repo content.
  Three baselines are flagged stale: their failure conditions changed and the
  rows predate the change.
- **The commit trailer names the model that wrote the commit**, not the
  session's — they differ once a subagent commits its own task under model
  tiering. The name comes from what the harness states: `settings.json` holds a
  versionless alias, and a model asked to identify itself unprompted answers
  from training data, a generation behind and with no signal that it is wrong.
- **Reviewer model ladders are discovered at run time**, not hard-coded. Codex is
  ranked from its own `models_cache.json` `priority` field; Gemini is ranked by
  family, then effort, then version, and filtered to `gemini-*` only — `agy`
  also offers `claude-*` and `gpt-oss-*`, and a Claude model is not a second
  opinion on Claude's work. Each ladder is three rungs, and **if all three fail
  the reviewer produces nothing rather than dropping to the weakest tier**: a
  review from the bottom rung carries the same authority as a real one and the
  coverage line cannot convey the difference.
- **Pinned model versions removed** from the backend docs. `opus[1m]` is an
  alias that already tracks the current Opus; only the comments beside it were
  pinned to a version.
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
- **`claude-setup` step 3 corrupted the file it manages** (installed on this
  machine). Its prose quoted a truncated opening marker, so a marker search
  matched the prose before the real delimiter and the installed
  `~/.claude/CLAUDE.md` was written with eight lines of the skill's own
  instructions at the top, a stray code fence, and no closing marker. The step
  now takes canonical text from the fenced block, matches whole marker lines
  only, and verifies the result before finishing.
- **The global standards block is 2,742 words, down from 3,386** (`ENH-01`) —
  19% off a file resident in every request. 644 words left: the environment
  procedures moved to `project-env`, and the roadmap taxonomy was cut from 374
  words to 232, keeping the tense split and the ID rules while handing the
  rating scales, entry format and anchors to `phase-workflow` and the bundled
  templates, which already defined them. Verified byte-identical against the
  installed `~/.claude/CLAUDE.md`.
- **The `.zshrc` shell-block installer no longer truncates the file**
  (`KI-22`, `claude-setup` half). Step 7 stripped its managed block with an
  `awk` that keyed only on the markers it found, so a file whose closing marker
  had been deleted by hand lost everything from the opening marker down —
  `PATH` edits, exports, other tools' managed blocks. Reproduced at 10 lines to
  3. It now refuses on a marker-count mismatch, copies the file to
  `.zshrc.localclaude.bak` first, and writes through `mktemp` instead of a
  fixed `.tmp` path a concurrent shell could be using. `llama-autostart.sh`
  carries the same pattern and is held for the rebuild.
- **`$CLAUDE_CONFIG_DIR` claim removed** (`KI-15`). Step 1 promised the variable
  was honoured while every bundled script resolved `$HOME/.claude` directly. It
  now states plainly that the variable is unsupported and must not be set on a
  managed machine. Supporting it is filed as `ENH-07`, to be done inside the
  backup test harness rather than as a blind substitution.

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
