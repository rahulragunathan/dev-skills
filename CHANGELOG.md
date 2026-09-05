# Changelog

All notable changes to the `localclaude` plugin are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions before 1.8.0 predate this file. Their changes are not reconstructed
here — the plugin manifest's version is the only record of them.

## [Unreleased]

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
