# Changelog

All notable changes to the `dev-skills` plugin, named `localclaude` before 2.0.0, are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Versions before 1.8.0 predate this file. Their changes are not reconstructed
here — the plugin manifest's version is the only record of them.

## [Unreleased]

## [2.3.0] - 2026-11-27 — review triage

### Added

- **Every review finding carries a Path, an Area and Steps To Reproduce.** Path says what kind
  of use reaches the defect: `Happy Path`, `Unusual Input` or `External Interference`. Area says
  what kind of file holds it: `Code`, `Docs` or `Tests`. external-review's shared rubric asks for
  both, with Severity and Likelihood, in every mode; phase and repo mode add numbered steps from
  a fresh fixture, and plan mode a concrete failure. Reviewers report every
  finding, on any Path.
- **The blocking rule.** A confirmed Critical or High finding blocks a phase when it is on the
  Happy Path, or Likely or Almost Always. Only those are fixed in the phase; the rest are filed,
  and the user can pull any of them back in at the gate. Each reviewer's ratings are judged on
  their own, never mixed. The review loop now stops on a pass with no blocking finding, and the
  gate shows a Steps To Reproduce summary grouped by Path and a trend table with each pass's
  blocking count.
- **Steps are evidence, not commands.** Triage runs them only in a fresh `mktemp -d` folder
  with a scratch `HOME`, no credential variables and no network, refuses a step that reaches
  outside it or fetches and runs code, and reconstructs steps where needed and says so. The whole
  record, not only the steps, is sanitised of secrets, account names and local paths before it
  is published (KI-97, KI-107). Findings from `/code-review`,
  `/security-review`, `design-review` and the dependency scan get the same fields at intake.
- **The KI template gains Path and Area scales**, a `**Path:**` and an `**Area:**` field and a
  `### Steps To Reproduce` section; the ENH template gains an optional one. `roadmap.py check`
  validates either field when an entry sets it, reading only the entry's metadata block, and
  refuses an unknown, empty or repeated one. Both are optional for now and not mirrored in
  ROADMAP.

### Changed

- **Title case for the labels and fixed values external-review shows, and for the KI and ENH
  section headings.** Likelihood's top level is
  `Almost Always`; `roadmap.py check` still accepts `Almost always` until Path becomes required.
  The dispositions are `Fixed In Phase`, `Unfixed Blocker`, `Filed KI-nn`,
  `Confirmed: Accepted, No Work Planned`, `Recorded Only: No Roadmap Files` and `Rejected`, and in
  plan mode `Incorporated`, `Already Covered` and `Not Incorporated`. The keyed notes, the gate
  headings and the KI and ENH section headings follow.
- **`Unfixed Blocker` replaces `Proposed: fixed in phase`**, and **`Recorded Only: No Roadmap
  Files` replaces `Open — no roadmap files`**, so each name says what the row is.
- **Regressions follow the blocking rule** like every other finding, rather than always being
  fixed in the phase.
- **Each keyed note opens with *Blocking* or *Non-Blocking*, then its Disposition**, so a note
  reads without the table.

### Fixed

- **Every row has a disposition, and the rules agree.** A repo review's blocking row, and a
  blocker from an incomplete pass waiting for its retry, are `Unfixed Blocker`. A change you make
  at the gate is written `<new> — was <old>, the user's call`. A row has one Path, the one that
  blocks first. Likelihood is attributed per reviewer like Severity, and a filed merged row takes
  one whole set of ratings. A `Rejected` or accepted row gets no roadmap entry. Plan mode asks
  for no steps anywhere. phase-workflow §3 step 2 sends its own checks' findings and gaps through
  intake and the blocking rule (KI-98, KI-99, KI-100, KI-103, KI-104, KI-105, KI-106, KI-108).
- **Reviewers no longer open with a summary line**, dropped before release: each finding's Path
  says the same, and the trend's Blocking column answers the gate's question (KI-101).
- **`progress.sh` reports a failed Codex attempt as failed**, not running: the Codex loop now
  writes `.state` as the Gemini loop does (KI-111).
- **The roadmap files have one casing and shape.** The ENH and UNK templates' `Regression Net`
  and `What Settles It` labels and the `None Offered` fallback are in title case, and every
  dev-skills entry uses its template's headings and labels, guarded by new tests (KI-110).

## [2.2.2] - 2026-11-25

### Fixed

- **The roadmap templates state each rule once.** The `KNOWN_ISSUES` template gave its scale note
  twice, once per table; it now gives it once, above both. `KNOWN_ISSUES` and `ENHANCEMENTS` no
  longer restate how an item closes, which the `ROADMAP` template states; they point to it. This
  repository's own roadmap files take the same change.

## [2.2.1] - 2026-11-24

### Changed

- **Ready for a public repository.** The plugin manifest no longer lists an author email, the
  phase record reads `No phase in flight.` now that 2.2.0 has merged, and the design-review
  evidence notes no longer name a private archive path.

## [2.2.0] - 2026-11-23 — dependable helpers

### Added

- **Security in every review.** The external review's shared rubric gains a security item for
  every mode: trust boundaries, secrets and outside services in a plan; injection, traversal,
  unsafe parsing, weak crypto, file permissions, secret exposure and missing auth checks in code,
  each traced from its untrusted input. The phase-end retrospective runs `/security-review`
  after `/code-review high`.
- **`dependency-scan.py`**, run first at phase end: known vulnerabilities in the committed
  lockfiles, through `osv-scanner`, with a manifest that has no lockfile, a file with no packages
  and an unpinned requirement reported as coverage gaps rather than clean. It reads only what
  `HEAD` commits, never follows a symlink, names what a tracked `osv-scanner.toml` ignores, and
  has an `--offline` mode. A requirements file is read as pip reads it and reaches the scanner
  only as checked `name==version` pins; an include, an unknown option, a variable, an invalid
  name or version, or a file that is not UTF-8 is a gap. Every report line has its control
  characters escaped, so a committed path cannot forge one.
  A folder's `osv-scanner.toml` is passed by name, so one the scanner cannot load fails the scan.
  Every advisory in a package is reported, grouped or not, and one unreadable package leaves the
  others' findings in the report.

### Fixed

- **Fences read the same under zsh and bash (KI-74).** Claude Code's Bash tool runs the login
  shell, often zsh, where the review loops ran once with every rung as one model, the probe passed
  `--root <path>` as one word, and discovery named `--effort` as the effort.
- **Skill arguments no longer rewrite `phase-workflow`'s commands (KI-75).** Claude Code replaces
  `$1`-style text in a skill invoked with arguments; five awk field programs went with it. The
  `mid` count now comes from `bats_assertions.py --count-mid`.
- **The phase record is read by a tested parser, `phase-record.py` (KI-67, KI-69).** The gate
  checks the first table's `REPO`, `PR` and `Release`, so a companion table, a padded row or a
  large record no longer misleads it. The first push refuses a record inherited unchanged from
  the default branch. The review record is published after the gate, headed by the SHA it was
  reviewed at. The record is read whole before the edit starts, so a failed read publishes
  nothing, and it is sent on stdin, so no copy is left on disk. A PR head that differs from the
  gate's afterwards is reported, not prevented, and one that cannot be read is reported as
  unverified.
- **The origin check is an allow-list (KI-70).** It accepts `ssh://`, `git+ssh://`,
  `ssh+git://` and `https://` in lower case, the scp form and an absolute local path without
  spaces; it refuses every transport helper, any other scheme or spelling, an option-shaped URL,
  a `%`-escape anywhere in a URL's authority, a configured `remote.origin.vcs` (even an empty one), and an ssh URL holding a compressed IPv6
  literal (`::`). It decides with shell patterns, so no external command can fail open, and the push
  list must be exactly the approved URL.
- **Branch cleanup reports every retained branch (ENH-29)** before it exits, rather than
  stopping at the first. It skips the checked-out branch when a tag shares its name (KI-86).
- **The post-review gate check sees both sides of a rename and pins one head (KI-62).** A file
  moved into a bookkeeping path is named by its source, a failed listing stops the gate, and the
  ready step refuses a head other than the one the check inspected.
- **external-review's helpers (KI-43, KI-63, KI-64, KI-66, KI-71).** A Codex refusal quoted
  in the material under review no longer downshifts the ladder: a probe of the rung must confirm
  it. `preflight.sh` refuses a Codex probe without a review root and Gemini ids for efforts the
  review never uses, and reads a ready answer beside a retried-request note as ready. The Gemini
  loop records each attempt's start and end, so `progress.sh` dates a run from its start,
  reports a retried chunk's earlier attempt as superseded, and tells a failed run from a cut-off
  one; only agy's own cut-off notice counts as one. Discovery says which program failed, agy or
  the ranker.
- **`roadmap.py close` keeps an edit made before its final check (KI-57).** It stages each
  replacement first, then refuses if the file changed since it read it; a rollback leaves a file
  someone edited meanwhile as they wrote it. Only an edit in the instant between that check and
  the rename can still be lost. The closed entry is cut out byte for byte, so CRLF line endings,
  trailing whitespace and a missing final newline survive.
- **`roadmap.py check` sees more drift (KI-58, KI-59).** Blank files, an anchor in a fenced
  example, open questions out of Kind order, a displayed `KI-01-extra`, and titles or an
  Effort that differ between index and detail are all reported. A `**Where:**` field after
  another field on its line is checked; an absolute, empty or credential-shaped target is
  refused, the last without being opened; and source files under `docs/` need a fragment.
- **`roadmap.py init` under a signal, and its file mode (KI-65, KI-72).** A signal during error
  cleanup no longer stops the rollback, new files follow the caller's umask, and a file whose
  ownership could not be confirmed is reported as a skipped removal to inspect. (2.1.0 said
  `init` leaves nothing behind on failure; such a file is the exception.)
- **The roadmap templates fill in cleanly, and the close tests can fail (ENH-34).** A template
  example filled in literally passes `check`; the close tests assert absence by status and
  check that their injected faults fired.
- **The name check reads more command spellings, and an unreadable folder no longer stops it
  (KI-68, ENH-33).** `python3 roadmap.py`, a bare script beside a lone flag, a
  `"$CLAUDE_PLUGIN_ROOT/..."` path, a missing script before a subcommand, and a reference link
  whose definition was deleted are all checked. A doc it cannot read is listed and the rest are
  still checked.
- **The release test runs when its file runs directly (KI-73)**, and a CHANGELOG with no
  release heading fails it as an assertion.
- **Smaller fixes (KI-55, ENH-36, ENH-37).** `phase-workflow` §1 says the plan is drafted
  outside the repository. Review-loop and ladder tests that could not fail now can, and the
  origin refusal tests name the exact message. A user-reopened review row gains its Commit and
  evidence, and the red-evidence rule reads "a `Red:` line or a mutation result" everywhere.

## [2.1.0] - 2026-11-20 — project-docs and September's rules

### Added

- **`project-docs`, a fourth skill.** It owns the roadmap files, their templates and
  `roadmap.py`, moved from `phase-workflow`, and states the docs-by-tense rule.
- **`roadmap.py init`** sets up whichever roadmap files are missing, only when the user asks. A
  fresh set-up passes `roadmap.py check` (KI-40). It never touches an existing file and leaves
  nothing behind on failure.
- **`name_check.py`**, an advisory check that lists backticked paths, commands, flags and
  roadmap IDs, and Markdown links and anchors, that no longer exist. It never runs what it reads.
- **`gemini-ladder.py` and `codex-ladder.py`**, tested scripts that rank the reviewer models.
- **A progress line every five minutes** while an external review pass runs (`progress.sh`), so
  a long review is not mistaken for a dead one.
- **Review record.** A phase review keeps one findings table across all passes, with a note per
  row, the red and green of each fix, and per-pass counts. It goes in the PR description.
- **New dispositions:** `Confirmed: accepted, no work planned`, and `Open — no roadmap files`.
- **A release check**: a test that `plugin.json`'s version matches the newest CHANGELOG release
  (ENH-35).
- **`phase-workflow` states when bounded work becomes a phase**, and that anything landing cuts
  a release.

### Changed

- **Roadmap files are optional.** Filing goes through `project-docs` only where the repository
  has all four roadmap files, and phase start no longer seeds them.
- **The rating scales have one source** (ENH-17): `roadmap.py` reads the levels from the
  templates' scale tables, ranks Severity, Likelihood and Priority in row order, and refuses an
  unknown `Kind`.
- **External review** runs up to three passes without checking in. Its stop rule applies
  before any fix, so no fix reaches the gate unreviewed. A fourth pass is the user's call.
- **External reviews run at `high` effort by default**, for Codex and Gemini alike, on the
  strongest model; another effort (`--effort` on both ladders) only when the user asks.
- **ENH-31 is now KI-56**: a check that says `references verified` for an entry it never
  checked is a defect, not an enhancement.
- **`/simplify`** runs at a task's refactor step only when the task added or reshaped code, and
  once on the whole branch diff before review.
- **Test checks:** each test a phase adds or materially changes has red evidence: a `Red:` line
  in its task's commit message, or a mutation result where no red was observed (a test written
  after its fix, or one in doubt). Phase end checks them.
- **Docs pass:** the name check runs on the current docs (not history, templates or test
  input); docs naming something the phase changed, and
  docs found wrong, are read in full.
- **The skills state the rules they rely on** instead of pointing at one user's global
  standards. Where the user's or the project's standards differ, theirs win.

### Fixed

- **The Gemini ladder** put orchestrator models first and `xhigh` last. It now ranks by
  family (Carbon > Neon > Hydrogen, then any other line: superseded Argon, and the older pro,
  flash and lite), then
  version, newest first, and offers each model once at `high` (its `-high` id, or its suffix-less id run with
  `--effort high`); a model without either is skipped. Efforts below `medium`, and `ultra`, are never offered.
- **Gemini calls passed `--effort high`**, which `agy` refuses for any model whose id carries
  another effort, so the ladder could never downshift.
- **The Codex ladder ranked by the cache's `priority`**, OpenAI's default pick: it put
  `gpt-6.2-sol` above `gpt-6.2-astra`. It now ranks by family (Astra > Sol > Terra > Luna),
  then version, newest first, at `high` effort; a model without `high` is skipped. A malformed cache entry is
  skipped rather than emptying the ladder.
- **The Codex loop downshifted on a failed run's transcript**: Codex writes the prompt to stderr,
  so any availability phrase in the material under review read as an unavailable model. It now
  reads `ERROR:` lines only.
- **A Gemini answer cut off by its print timeout counted as coverage.** It is now set aside.
- **Phase start** wrote the phase record before its own clean-tree check, and would have copied a
  token in a remote URL into it; `publish-release.sh --check-origin` now refuses such a URL.
- **The review bundle** let an `id_ecdsa` key or a `.pypirc` through to the reviewers.
- **`roadmap.py check` passed an entry with no `**Where:**` field** and said `references
  verified` (KI-56, formerly ENH-31). A known issue or enhancement without one is now reported.
- **The Codex readiness probe ran in the caller's folder**, not the pruned review root (KI-61).
  `preflight.sh` takes `--root`, and the documented probe passes it.

## [2.0.1] - 2026-11-17

### Fixed

- `plugin.json`: the author email is the personal address, not the old work one.

## [2.0.0] - 2026-09-28

The plugin becomes `dev-skills`: the development-process skills only, written to work in any
repo, on any machine, and under Codex as well as Claude Code. Machine setup moves to private
repos of its own.

### Removed

- **`claude-setup`, `claude-toggle-backend`, `drive-backup`, `local-models` and `project-env`**
  leave the plugin. Each becomes a private repo, imported from `7d7272d`, and the MLX backend
  spec and plan go with `claude-toggle-backend`. The global standards block and the link
  installer move to a private setup hub.

### Changed

- **The plugin is renamed `dev-skills`.** The name appears only in the manifests, the README and
  this file, and `tests/test_plugin_name.py` fails if it spreads further, so a later rename is a
  small edit.
- **The repo ships its own `.claude-plugin/marketplace.json`**, so it installs from GitHub with
  `/plugin marketplace add rahulragunathan/dev-skills`.
- **Skills name each other by bare name** (`design-review` in `plan` mode), not
  `/localclaude:design-review plan`. Codex has no plugin namespace.
- **The project conventions file is `AGENTS.md`.** Claude Code reads it when no `CLAUDE.md`
  exists, and Codex reads it natively. `phase-workflow` and the roadmap templates now name
  `AGENTS.md` as the project file.
- **`phase-workflow`'s assertion scan covers `skills/*/tests/*.bats`** again, now that no
  departing suite is held back from it.

### Roadmap

- **Moved with their skills, keeping their IDs:** 19 known issues and ENH-02, ENH-04, ENH-05 to
  `claude-toggle-backend`; 11 known issues and ENH-03, ENH-07 to `drive-backup`; KI-05, KI-16 and
  KI-17 to `local-models`; ENH-10 to `project-env`; UNK-03 to `claude-setup`; ENH-11 to the setup
  hub.
- **Closed as not planned:** ENH-12, ENH-15, ENH-19, ENH-24, ENH-25 and KI-42.
- **Closed, ENH-27:** the standards block is now a Markdown file of its own in the setup hub, so
  the lint gate covers it.

## [1.12.0] - 2026-09-24 — Mini phase, reference integrity

Two instruments phase 1 left uncalibrated, taken before the next phase so the rest of the
programme is not measured with them.

### Added

- **`roadmap.py check` verifies that a roadmap reference still points at real code.** A
  reference is now a file link plus a greppable fragment, and the check confirms that fragment
  still appears in the file it cites. A `#Lnn` line anchor is rejected anywhere in an entry.
  The drift check verifies "every identifier, file path, command, flag and config key a doc
  names" — a line number was none of those, and was the one reference type no gate could catch.
- **Four functions behind it, split by what makes each change:** `_fenced_lines` tracks a
  fence's delimiter character and run length, `_where_field` reads a field's continuation lines,
  `_references` refuses a link shape it cannot parse rather than reading it as no reference, and
  `verify_references` resolves each one. A run-scoped cache reads each cited file once.
- **`skills/phase-workflow/tests/fixtures/vacuity.bats`** — the fixture behind the bash
  measurement, which records `$BASH_VERSION` from inside the run because that is the only place
  the answer is trustworthy.

### Changed

- **59 line anchors across 71 entries became 89 verified fragments.** Each was chosen by reading
  the cited code and each occurs exactly once in the file it cites.
- **The mid-test `[[ ]]` claim is now scoped to the interpreter it was measured on.** Under bash
  3.2.57 a false mid-test `[[ ]]` passes its test; under bash 5.3.20 it fails. `|| false` is
  correct under both and load-bearing only under 3.2, so phase 1's 68 conversions stand and the
  claim made for them narrows.
- **The entry templates show the new reference shape**, so a new entry is written that way from
  the start.

### Fixed

- **The documented 0-`mid` regression gate could not fail.** Piping the scanner into `awk`
  prints nothing when the scanner fails outright, and nothing is exactly what a clean result
  looks like. It now checks the scan succeeded before reading its count.
- **The same gate's `skills/*/tests/*.bats` glob swept in an out-of-scope skill**, so the
  documented command reported 5 while the text beside it claimed 0. It now names the four
  in-scope skills.
- **A phase-1 test encoded bash 3.2's behaviour and failed under bash 5.** It now decides its own
  scope by running its fixture rather than by reading `$BASH_VERSION`, because two measured
  points say nothing about bash 4, and skips with the interpreter named.
- **Three roadmap references were themselves drift**, found by reading: KI-17's fourth link
  pointed at a blank line in an alias block, and KI-07 and KI-17 each carried a line anchor in
  prose rather than in the Where field.
- **Four ways a reference could be skipped without saying so**, all found by review of the new
  code and all of the class the check exists to remove. An unpaired backtick made the links after
  it vanish, because masking code spans erased the `](` the unparseable-link guard watches for —
  so the guard could not fire and the entry reported clean. An entry whose `**Where:**` field did
  not parse was answered with a bare skip. An empty link target resolved to `docs/` itself and
  passed the directory exemption. And the external-link escape tested for `://`, so `mailto:`
  reached the filesystem as a missing path no author could satisfy.
- **A fragment must now occur exactly once**, not merely appear. The conversion verified
  uniqueness and the docs claimed it; the check tested presence, so a fragment could go ambiguous
  later with nothing failing.
- **The ENHANCEMENTS template still showed a bare link with no fragment** — the shape the new
  check rejects — so copying it would have produced an entry that failed on its first run.
- **The hand-off lint globbed a `templates/` directory that does not exist**, so the one template
  this phase edited was never linted by the command that claimed to lint it.
- **The bash-version skip in `verify-assertions.bats` fired on any failure**, so a broken fixture
  would have skipped with a misleading interpreter reason rather than failing. It now asserts the
  specific failure first.
- **The gate's reach had no boundary.** `(docs / target).resolve()` followed `../` past the
  repository root, and `pathlib` lets an absolute target win outright, so an entry could aim the
  check at any readable file on the machine and have its contents read and counted. The boundary
  test now runs before the file is opened.
- **The 0-`mid` gate still hid a failure one level below its own fix.** Checking that the scanner
  succeeded left `awk | wc -l` in the pipeline, which reports `0` when `awk` fails. Both copies
  now use `pipefail`.
- **Four fragments passed the gate and failed the reader.** `ENH-07` was anchored to its file's
  description header rather than anything about `$CLAUDE_CONFIG_DIR`, and `ENH-25` to repeat
  grading rather than the blinding it describes. `KI-32` is the phase's third already-wrong
  reference: its subject is the `~/.claude.json` approval state, item 6 of the cited file, while
  the original anchor pointed at item 5 — the conversion faithfully anchored the wrong line, which
  is a real limit of this mechanism.

- **Four reference tests did not prove what they claimed**, found by a post-gate review and
  each confirmed by running it. The title test asserted a line-anchor finding that the anchor scan
  reports whether or not titles parse, so it passed with title support removed. The fixture helper
  succeeded silently when its marker was missing, so a control test could pass against an entry
  that never received the reference under test. The boundary test wrote into the shared system
  temp directory and never showed the outside file went unread. Reference-style links were
  reported verified with no fragment checked; they are now refused.

### Filed (continued)

- **ENH-31** — report an entry that omits its `**Where:**` field entirely. The check reports a
  field that looks like one and does not parse, but an entry with no such line is skipped in
  silence. The obvious fix reds the test fixture, so the work is fixture-first.

### Corrected

- **`bats` cannot be pinned by invoking a bash on its script.** Its helpers re-exec through
  `#!/usr/bin/env bash`, so the interpreter comes from `PATH` however the outer script started.
  Recorded in the skill, because two pinning methods failed silently before one worked.
- The programme spec predicted a patch release for phase 1; it shipped 1.11.0, a minor.

### Filed

- **KI-55** — the plan review cannot run while the plan is inside the repository, because
  `codex-root.sh` refuses any untracked file and a pre-branch plan is necessarily untracked.

### Closed

- **ENH-30** — anchor roadmap references to an identifier rather than a line number.
- **KI-52** — measured: the mid-test `[[ ]]` vacuity does depend on the bash version.

## [1.11.0] - 2026-09-21 — Phase 1, gate integrity

Two of the checks that judge every later phase were not checking. This phase repaired them, and
the repairs found more of the same class in their own code.

### Added

- **`bats_assertions.py`** reports every `[[ ]]` assertion in a bats file and whether another
  command follows it in its test. Extent comes from `@test` and top-level function boundaries,
  never brace depth, which breaks on `${...}` and embedded python; heredoc bodies are skipped so
  fixture text is never inventoried as code. Measured inventory for the four in-scope skills: 309
  tests, 123 assertions, **68 mid-test**. The figures previously recorded in KI-45 — 325, 145, 78
  — were read rather than measured.
- **`verify_assertions.sh`** confirms one converted assertion is load-bearing by negating it and
  requiring its own test to fail at that line. It drives `mutation-restore.sh` rather than adding
  mutation logic. `mutation-restore.sh` exits 0 whenever the test returned exactly 1, and bats
  returns 1 for a fixture error too, so exit status alone cannot certify discrimination.
- **`--authored-by <codex|gemini>`** in `preflight.sh` disqualifies a reviewer from coverage when
  it wrote the diff under review. It is reported as the author with its probe result, not as
  unable to answer: it answered and is barred, and an operator has to be able to tell a broken
  CLI from a disqualified one.
- **`docs/PHASE_RECORD.md`** is the phase record, linked from ROADMAP. It holds the phase in
  flight only and is overwritten at each phase start; when none is in flight its body is one
  line. `phase-workflow` referenced "the phase record" in three places and defined it nowhere.
- **`KI-47` to `KI-52`** filed from `gpt-6-astra`'s review of the round-9 evidence and grading.
  The two that change a conclusion: no grading packet carries S05's banned-word list its Rule 4
  grades against, and S07's with-skill arm is shown the two expressions its mutation-choice
  condition grades. Both verified independently.

### Changed

- **The Codex ladder emits `slug:effort` rungs.** Effort identifies a rung: every model in the
  cache defaults to `low`, so naming a slug alone got the weakest setting of the strongest model
  while the log read as if the strongest had run. A `priority` tie also resolved by position in
  the JSON — `gpt-5.6-sol` and `gpt-6-astra` both sit at 1 — and now breaks on higher version.
  `ultra` is excluded: it delegates tasks automatically, so the diff may not come from the model
  recorded against it.
- **Reviewer independence is a property of the diff's author**, not of Claude. The rule ran one
  way only and named Claude; when a non-Claude reviewer writes the diff, it cannot clear its own
  work either.

### Fixed

- **`KI-45` — 68 mid-test `[[ ]]` assertions across twelve suites were checked by the reader and
  never by the suite.** Appending `|| false` is the whole change: the expression is untouched, so
  no assertion can quietly mean something different afterwards. Each of the 68 was then verified
  load-bearing — 66 by `verify_assertions.sh`, 2 by hand after falsifying every branch of a
  disjunction.
- **A broken assertion that had never been evaluated.** `preflight.bats:127` asserted
  `[[ "$output" != *"codex"*"READY"* ]]`. Globs span newlines, so it matched `codex` on one line
  and `gemini ... READY` on the next, and could never have passed once evaluated. `preflight.sh`
  was correct; the assertion is now scoped to the codex line.
- **`KI-46` — the phase cleanup could not delete a squash-merged branch.** `-D` is now reached
  only at a tip already confirmed present on the remote, and the retain message gives its reason.
  `publish-release.sh` carried the same call under a message that was false for a squash merge.
- **`KI-53` — zsh mangled the phase-start refspec.** `$DEFAULT_BRANCH:refs/...` read as a `:r`
  history modifier, building `+refs/heads/mainefs/remotes/origin/main`. The block is labelled
  bash, but zsh is the default macOS shell and the step tells the operator to run it.
- **`KI-54` — the phase record had three consumers and no path.** §2 step 3 wrote it, §2 and §4
  read it back for `MERGE_METHOD`, and nothing said where it lived.

### Fixed at the gate

`/code-review high` found five defects in this phase's own code. Four were real and are fixed
here; the fifth misread a local utility as part of the merge cycle.

- **`verify_assertions.sh` reported `GREEN` for a disjunction split across continued lines.** It
  read only the requested line and required `]]` on it, so `[[ A \` / `|| B ]] || false` slipped
  past the compound guard and earned the one verdict the guard exists to prevent — and §3 step 3
  has an assertion failing the audit fixed or deleted, so a working assertion would have been
  deleted on the strength of it.
- **`bats_assertions.py` read `$(( 1 << 2 ))` as opening a heredoc**, took `2` as the delimiter,
  swallowed the rest of the file and refused it outright. Latent, and total for any file using
  arithmetic shift.
- **A converted assertion was still reported `mid`.** Classification was positional only, so
  `[[ ... ]] || false` looked identical to an unguarded assertion and the inventory could not
  detect a regression. An explicit trailing `|| false` now classifies as `final`, which makes the
  count of `mid` rows across the in-scope skills **0** and turns the inventory into a standing
  check. Continued lines are joined first, so a wrapped assertion is judged by its logical form.
- **`publish-release.sh` gated `-D` on an `APPROVED_SHA` that no fence exports**, so it could
  never fire and the retain message blamed the branch. It is now an explicit
  `--confirmed-on-remote` flag — the right contract for a local utility whose caller is a human.

- **`verify_assertions.sh` reported `GREEN` when an operator appeared inside a quoted literal.**
  Found by external review of the code. The line-addressed `sed` takes the first matching
  operator, so `[[ "$output" != *"a == b"* ]] || false` had its glob rewritten while the real
  `!=` stood; the assertion held, the test passed, and `GREEN` means "not load-bearing". It now
  counts occurrences of the same token set the substitutions use and refuses when more than one
  is present. Shell quoting is not something to parse with `sed`, so the answer is to decline
  the verdict.

  That is the third false verdict from this tool, all fixed the same way — exit status alone
  meant `RED`, a disjunction meant `GREEN`, an ambiguous line meant `GREEN`. Its `REFUSED` path
  is where the correctness lives.

The fifth read `publish-release.sh` as part of the documented merge cycle. It is not: §4 prunes
with its own fence, and the script's header records it as a local-only utility. A test asserting
that coupling was wrong and was removed along with the mode it forced.

### Corrected

Three claims in released sections were wrong. Released sections are never edited, so the
corrections are recorded here.

- **v1.10.2 said KI-46's entry records that "`git cherry` discriminates where `-d` does not".**
  It does not. Measured: a two-commit branch squash-merged reports `+` for every commit while the
  tree is identical, so it is retained forever; and a branch whose unique work is a merge commit
  reports *nothing*, because `git cherry` skips merge commits, so it is **deleted although it
  holds work nothing else has**. The earlier verification used a one-commit branch. Comparing
  trees discriminates; comparing per-commit patches does not.
- **v1.10.0 said "the Codex model ladder tops out at `gpt-6-astra`".** Nothing in the cache ranks
  it above `gpt-5.6-sol`; both sit at `priority: 1`, so the claim held only by file order.
- **v1.10.0 said "every listed model supports low through max".** `gpt-5.6-luna` has no `ultra`
  and `gpt-5.5` has neither `max` nor `ultra`.

### Evidence

- **S07's with-skill evidence is expired by this phase.** S07 loads `phase-workflow`, whose
  `SKILL.md` moved from `eece8525b5b13e01` to `db9d0e7280194046`, and a changed loaded skill
  expires its with-skill run. The round-9 row is marked **Expired** with the reason and its grade
  retained; the rollup is regenerated. S07's baselines stay current — its prompt and condition
  hashes are unchanged, and a baseline does not expire because a skill changed.
- **S01 to S06 are unaffected.** They load `design-review/SKILL.md`, which this phase did not
  touch: it still hashes to `47196f444f840946`, exactly as round 9 recorded.
- **Re-gathering S07 is blocked on KI-48**, not merely pending. That arm was shown the two
  expressions its Mutation choice condition grades, so re-running it before the scenario is fixed
  would buy a fresh hash over the same invalid comparison.

### Filed

- **`ENH-28`** — `--confirmed-on-remote` is an operator assertion, not a verification. The script
  can establish remote presence itself, and `-D` is the one command here that can discard
  unpushed commits.
- **`ENH-29`** — the prune loop exits on the first retained branch, where `xargs git branch -d`
  attempted all of them. Fails safe; a behaviour the KI-46 fix introduced.
- **`ENH-30`** — 44 roadmap entries carry 59 `#Lnn` anchors, and a line number is not an
  identifier, file path, command, flag or config key, so the drift check structurally cannot
  verify one. Two of this phase's own references drifted in-range and wrong. Replace each with a
  greppable fragment and have `roadmap.py check` assert it still appears.

### Closed

- **`UNK-02`** — no test here can be shown to discriminate from git history alone. Answered "do
  nothing" and recorded in CLAUDE.md: the mutation check replaces historical evidence. This phase
  also measured that substitute's limits.

## [1.10.2] - 2026-09-16

### Added

- **`ENH-27` — lint the markdown templates that live inside fences.** markdownlint does not
  lint fenced content, so the `~/.claude/CLAUDE.md` block quoted in `claude-setup/SKILL.md` is
  invisible to the lint gate even though it is deployed verbatim. The v1.10.1 defect below was
  green on a repo-wide sweep both before and after its fix. The entry records byte-equality
  against the installed file as the stronger check, and what a general pass over all five
  fences would have to suppress first.
- **`KI-46` — the phase cleanup cannot delete a squash-merged branch.** §2 step 3 prefers
  `squash` among the allowed merge methods, and §4 prunes with `git branch -d`, which refuses a
  squash-merged branch however completely its work landed. Every squash-merged phase ends on
  `RETAINED — branch deletion failed; inspect it by hand`. It fails safe, but the block bolds
  **Never -D here** while leaving no other way past it. The entry records that the step already
  knows the branch is at the approved SHA before it deletes, and that `git cherry` discriminates
  where `-d` does not.

### Changed

- **The ROADMAP status section no longer looks backward.** It still announced phase 1 as
  "awaiting merge as v1.10.0" after v1.10.0 and v1.10.1 had both shipped, against the rule
  stated three lines above it.

## [1.10.1] - 2026-09-15

### Fixed

- **The `~/.claude/CLAUDE.md` template quoted in `claude-setup/SKILL.md` was
  missing the blank line above `### Secrets`**, so the quoted block failed
  `MD022/blanks-around-headings` and no longer matched the file it documents.
  The installed file already had the blank line, so this was drift in the
  documentation rather than in what `install-standards.sh` writes; the template
  and `~/.claude/CLAUDE.md` are now byte-identical again. Markdown inside a
  fence is not linted, which is why the repo-wide sweep stayed green while the
  block it deploys did not.

## [1.10.0] - 2026-09-15 — Design-review skill and process remediation

### Added

- **Four test suites over the shell that used to live only in prose** (`ENH-13`,
  now closed). Each was built by extracting the procedure into a script and then
  testing it: `capture.sh` (the bundle that leaves the machine),
  `install-standards.sh` (the block inside `~/.claude/CLAUDE.md`),
  `mutation-restore.sh` and `publish-release.sh` (the destructive git
  operations), and `write_results.py` (the results-table writer). Forty-five
  tests at extraction; the two capture regressions are fixed below.
  Each suite carries a canary — a planted secret outside the repo, user content
  outside the managed block, uncommitted work, the columns not named — so a
  regression fails loudly instead of quietly, which is how all four of these
  procedures failed before.

- **`design-review` skill** — the structural design pass, at plan time and phase
  end. Produces the module table, the expected-change and shared-state lines, and
  verdicts on six named checks. Wired into `phase-workflow` at §1 (drafting), §2
  (landing diagram generators) and §3 step 2, where it runs before `/simplify`.
- **Pressure tests for it**, in `skills/design-review/tests/` — seven scenarios
  covering fifteen coverage units, each with its prompt, failure conditions and
  recorded results for a run with and without the skill. Two rules were written
  *by* the tests rather than confirmed by them: the produce-versus-edit
  distinction, and never marking a diagram box "new" because the marker is a diff
  that goes stale the moment the phase lands. Every unit's status is recorded
  honestly, including the nine a strong model already
  follows unaided — this skill's own rules and process rules from
  `phase-workflow`.
- **Four roadmap files** under `docs/` — ROADMAP, KNOWN_ISSUES, ENHANCEMENTS and
  OPEN_QUESTIONS, seeded from the templates with 27 issues, 6 enhancements and 1
  open question from an external repo review.
- `LICENSE` — the MIT text the plugin manifest and skill frontmatter already
  declared.
- **Recorded pressure-test evidence through round 9.** Round 9 (2026-09-14) is
  the complete paired batch across all seven scenarios, with five replicates per
  arm and grades from blind model graders. Round 4 was the earlier complete
  batch, rounds 5 and 7 are partial, and round 8 is not in the Results tables.
  Results retain each batch's grades and provenance. The latest per-scenario
  observations and historical corrections are in
  `skills/design-review/tests/README.md`. Transcripts,
  dispatched prompts and hash-verified snapshots remain in the external
  `Claude-Projects/Project Artifacts/Plugins/localclaude/design-review-evidence-<date>/` archive.
  Two round-1 runs were voided before grading and re-run: an s02 baseline that
  invoked the installed `design-review` plugin skill, and an s01 with-skill run
  whose inline paste of the skill did not match the snapshot hash the others
  loaded. Three conditions were reworded (D1, D2, P3) because a careful reader
  could reach the opposite verdict on each; every existing output was judgeable
  against the new wording, so no baseline expired. The grading corrections
  themselves are recorded under *Fixed*.
- **`drive-backup` skill** (`ENH-08`), holding the Drive backup `claude-setup`
  step 6 used to carry inline: `backup-projects.sh`, the destination-resolution
  order, the `Stop` hook JSON, the rsync flag choices, and the Full Disk Access /
  Automator / Shortcuts path for backing up when Claude Code is not running. One
  concern, one owner — backing conversations up to Drive is a separate product
  that happened to be installed by the same run, with its own script, its own
  bug cluster (KI-06, KI-07, KI-08, KI-14) and its own upcoming phase.
  **The `Stop` hook path changed** to
  `skills/drive-backup/backup-projects.sh`; a hook left on the old path backs
  nothing up and stops growing the log rather than reporting an error.
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

- **The findings table separates likelihood from consequence.** A new
  **Likelihood** column — `Rare` / `Likely` / `Almost always` — records how often
  a user following the documented workflow hits the harm, and **Severity** now
  means only what happens if it does. One rating could not carry both, so it
  defaulted to whichever the reviewer weighted: a rare defect that exfiltrates
  source and friction on every run both read as "High". Judged by harm rather
  than by code path, a bad count computed every run is `Rare` when it only
  misleads after something else failed, and a setup step the docs instruct is
  `Almost always` for everyone who follows it. Keyed notes now open with *When it
  fires* and *What happens*, the same pair that makes a `KNOWN_ISSUES` entry
  assessable, and both travel with a row that gets filed. A third line, *Reviewer's
  fix*, carries the remediation the reviewer proposed in its own words. Rubric item
  7 asks for one with every finding, but nothing in the presentation format held it,
  so it reached the triage and stopped there.

- **Two rules added to the global standards**, both from failures in this phase's
  own doc work. A bulk edit to a structured file is now verified against that
  structure rather than against the match count: a regex written for one table
  column matched every column of the same shape and silently overwrote the
  provenance column in seven files, and a block move that stripped whitespace
  turned a `**Source:**` line into a setext heading. And the drift check now asks
  whether a claim is restated elsewhere in different words, not only whether the
  identifiers it names still exist — across three review passes, one fact
  asserted in five files and corrected in one was the single largest source of
  findings.

- **`claude-setup` gave up two concerns and 20% of its length** — 6,785 words to
  5,395. The Drive backup went to the new `drive-backup` skill (`ENH-08`) and the
  llama.cpp shell aliases and login auto-start went to `claude-toggle-backend`
  (`ENH-09`), which is the skill those aliases control. Step 6 is now a pointer,
  and steps 7 and 8 are gone; the two that followed renumbered to 7 and 8. The
  second move matters beyond the word count: **`claude-setup` now writes nothing
  outside `~/.claude` and the detected Drive root**, because that block was its
  only write to `~/.zshrc`. The hardened marker handling — require both markers,
  back up first, write through `mktemp` — travelled with the block, so
  `~/.zshrc` still has exactly one hardened writer.
- **The merge cycle no longer calls a shell alias.** `phase-workflow` §4 step 6
  ran the user's hand-written `git-clean-local-branches` function, which no skill
  installs and which a fresh machine, a subagent or a non-interactive shell may
  not have loaded. The eight lines are inlined instead. `git branch -d` — never
  `-D` — is what enforces the step's existing retain rule, because it refuses a
  branch holding unmerged work.
- **Test-validity audit now mutates rather than reverts** (`phase-workflow` §3
  step 3). Breaking the named behaviour in place replaces stashing the fix, which
  left newly added files in the tree and falsely certified the test. Restoration
  is by `git restore --source="$TASK_SHA" --staged --worktree`, which returns both
  index and worktree to the recorded task commit; the snippet refuses to run on a
  dirty tree or a symlinked target. Every failure path stops rather than
  continuing. A fixture must carry the property under test.
- **Skip and partial coverage are now distinct** in both `phase-workflow` and
  `external-review`. A reviewer that fails on quota, auth, timeout or sandbox
  ran and returned nothing; only an uninstalled CLI is a skip.
- **Findings tables carry a `Files` column** — where each finding lives, verified against the
  repo during triage, so a filed `KI-nn` stays actionable from cold.
- **The documentation pass covers docs outside the repo** — a container folder's own README and
  CLAUDE.md drift the same way and never appear in `git status`, so they are named explicitly in
  the hand-off.
- **`review-checkpoint` renamed to `external-review`**, matching `design-review`
  and saying what the skill does rather than where it is called from. The two
  mentions in the `[1.8.0]` section keep the old name: that section is released
  and records what the skill was called then. Invoke as
  `/localclaude:external-review`.
- **`external-review` is canonical for the review loop**; `phase-workflow`
  delegates instead of restating it. The two copies had already drifted into
  contradiction.
- **Bundles exclude credential-shaped, binary and symlinked files** before
  anything is sent to an external reviewer, on tracked and untracked lists alike,
  via `git` pathspecs plus an explicit symlink test — `git ls-files` matches a
  link by its own name, so an innocuous filename pointing at a key passes every
  pathspec. The bundling loop is shown in full rather than described, and the
  withheld files are named in the coverage line.
- **The default branch is detected, never hardcoded.** Every phase lands by pull
  request regardless of branch protection, so no protection probe is needed and
  none is run.
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
  163→49, `external-review` 187→59. They are resident in every session.

### Fixed

- **Adversarial review follow-up:** standards installation refuses failed source reads before
  replacing personal content. Fixture grading treats incomplete call setup, mutable caches,
  helper globals and skipped context/exception effects as evaluation gaps, and refuses string
  formatting with unbounded allocation. Replacement dispatches supersede prior evidence and
  grades at completeness and agreement checks; recollection still checks current evidence and
  packet hashes. The phase SOP invokes the roadmap close/check helper, the diagnostic Codex
  probe specifies high effort, and the Node layout names the dependency tree below its env
  container. Command flags, result schemas and grading exit codes remain unchanged.

- **QC fix pass (2026-09-14):** Results separator repair refuses data rows and
  skips indented examples (KI-35, now closed). Diagnostic `--show` exposes malformed
  rows; the README rollup is checked against recorded rows without changing them.
- **Setup and review helpers:** explicit adoption replaces heading-based ownership
  guesses; links are built before replacement and can be repointed repeatedly.
  Setup link examples work before plugin registration. Repository capture ignores
  credential-shaped ancestors above its root, retains read failures on large
  lists, and export refusals stay visible on stderr. Reviewer probes carry high
  effort, distinguish diagnostics from configuration output, and report each
  availability rung once.
- **Grading and workflow:** imported fixture helpers and `print` calls with plain
  arguments no longer hide independent guards; method receivers evaluate once; sequence growth
  is bounded before allocation. A call the evaluator cannot run makes every
  mutable binding unknown, so a guard after it is never graded on pre-call
  values. Malformed unpacking in an answer is an evaluation
  gap rather than a refused input. Invalid grading inputs exit 3. Across scenarios,
  pass judgements must dispute every linked executed failure. Mutation cleanup
  covers generated output and both test runs. Interrupted roadmap closes restore
  originals and remove temporary staging; malformed index rows are refused.
- **Deferred work:** ENH-14 through ENH-21 retain the larger QC reuse and architecture
  items. ENH-22 through ENH-25 track shared verbatim-evidence validation, blind
  hand-graded anchors, agreement statistics and measured arm leakage. The plugin
  version remains reserved for the phase-end release.

- Standards installation rejects malformed canonical marker pairs before first creation and
  refuses symlinked backup destinations and replaces hard-linked backups without writing through them. Failed Git status queries stop exports and mutation
  audits before they can discard or omit uncommitted work.
- Codex review exports preserve committed regular-file bytes regardless of working directory
  or archive attributes, omit links and submodules with a coverage notice, and use one prepared
  root for review and diagnostic invocations. The docs distinguish pruning from read isolation.
- Fixture evaluation reports unsupported writes, invalid helper calls and host-dependent
  timezone conversion as evaluation gaps. Transcript parsing retains every final text block
  and rejects an unanswered later turn. Results-table selection and explicit repairs stay
  inside the Results section. These tooling changes do not alter recorded grades or results.
- Release tests execute the documented publication and cleanup commands. Cleanup reports Git
  failures instead of returning success. Repo documentation reflects the executable helpers,
  routes README installation through the tested link installer, and states the supported
  permission syntax and the manual environment-ownership check accurately.

- **Fourteen defects found by `gpt-6-astra` in external review pass 9**, each verified
  before acceptance and five of them Critical or High. The mutation helper accepted any
  commit containing the file and restored from it, discarding work committed since; its
  cleanup ran in a bare EXIT trap, which cannot change an exit status, so a failed restore
  reported success. The standards installer matched markers as prefixes while its comment
  claimed whole lines, and its symlink refusal sat behind an existence test a dangling link
  satisfies. Plan capture never applied the credential exclusions — the one mode whose input
  a human types. Binary detection treated a missing `perl` as text. Capture exited 0 after
  unchecked artifact writes. `evidence.py` reported a batch current with every answer file
  deleted. `roadmap.py` dropped header prose between the last rule and the first anchor,
  wrote both files before reconciling, and compared displayed IDs without their link targets.
  The results writer accepted line breaks and duplicate `Run` values. Setup linked without
  checking the source existed or that the link resolved.

- **The skills now invoke the scripts their tests cover.** `claude-setup` step 3 and
  `phase-workflow` §3 step 3 each described a procedure in prose while a tested
  implementation of it sat unused beside them, so 35 tests proved things about code the
  documented workflow never ran.

- **The mutation audit says how to choose a mutation.** It must have the same predicted
  outcome on every host, and so must every property a test asserts about its own fixture. An
  environment-dependent red certifies the runner, not the test — which is how the same
  fixture defect was graded a pass twice.

- **Reviewer availability is probed before a pass is committed.** `preflight.sh` asks
  each CLI one cheap question and separates the outcomes that demand different
  responses: `QUOTA` with its reset window (account-wide, so a downshift cannot help),
  `UNAVAILABLE` (per model, so the next rung may answer), `TIMEOUT` (inconclusive,
  retry longer), `NO ANSWER` (exit 0 with nothing produced — the trap both CLIs
  share), and `MISSING`. Pass 9 skipped this and spent about 100 minutes learning one
  chunk at a time that the Gemini account had been out of quota from the first call,
  with 110 hours still to run; all eleven attempted chunks returned zero bytes.
  Eleven tests, with both CLIs faked at the process boundary.

- **Evidence provenance is tracked per scenario, not per repository.** `evidence.py`
  records, for each scenario, the skill it loads, that file's git SHA and content hash,
  its prompt hash and its grading-condition hash; `check` recomputes all four and names
  exactly the scenarios that must be re-run. A single repository SHA could only mark
  everything stale or nothing, which is why S07's evidence outlived two changes to the
  skill it tests. The scenario files now declare `**Loads:**` rather than having the
  skill inferred from their prose. Eleven tests, including the baseline-contamination
  refusal that previously depended on someone reading a tool-use count by eye.
- **The round-3 results rows carried notes in the `Condition revision` column.** The
  provenance value was overwritten in all seven scenarios. Recomputed from the grading
  conditions and restored; the displaced prose is retained in `Notes` rather than dropped.
- **A scope exclusion now binds Codex, which reads the repository rather than the bundle.**
  `codex-root.sh` builds a detached worktree at HEAD, deletes the excluded paths inside it, and
  verifies each deletion before returning the path to root the reviewer at. The real working
  tree is untouched. It refuses a dirty tree, since the worktree carries HEAD, and refuses an
  exclusion matching nothing tracked, since a typo leaves the area in place while the caller
  believes it pruned. Seven tests.
- **A review scope exclusion now removes files from the bundle, not only from the prompt.**
  `capture.sh` takes `--exclude <pathspec>`, repeatable, and the excluded paths leave the
  manifest and appear in the excluded count. Naming an out-of-scope skill in the preamble did
  not hold: pass 8 named `drive-backup` and the reviewer reported on it anyway, because its
  files were in front of it. Refused in `plan` mode, which captures one named file.
- **Deletions reach the reviewer again.** Phase capture ran the worktree checks on every path
  in the raw diff, so a file the diff deleted was withheld as absent from the tree and its
  removal never appeared in the patch. Classification is now split: containment — allowed roots
  and symlinks — applies to every path, and the worktree checks apply only where capture reads
  the worktree copy. A deletion is covered by containment plus the checks on its committed
  blobs, which is where its content actually comes from.
- **Capture is anchored to the repository root, not the working directory.** Pathspecs carry
  `:(top)` and paths resolve from the root, so a bundle built from a subdirectory covers the
  whole repository and the credential exclusions still match at the root.
- **An output directory inside the repository is refused.** The untracked sweep listed the
  bundle, appended it to itself, and reported counts that could not reconcile.
- **The phase preflight records the push URL the guard compares.** It used
  `git remote get-url --push --all` while `publish-release.sh` compares `--push`.

- **Review capture now classifies tracked paths before building the patch.** Symlinks,
  binaries and paths outside the allowed roots are withheld, including binaries forced to
  text by a diff attribute. Absolute plan paths retain their root. Tracked capture counts
  include the paths sent, and phase enumeration failures stop capture. Four added capture
  regressions cover both patch sides, symlinks, parent escapes and literal path exclusions.
  Four added phase-git tests cover the check-only remote guard.
- **Remote checks use the destinations recorded at phase start.** The workflow calls
  `publish-release.sh --check-origin`, a check-only entry point to the existing guard, at the
  gate and before publication or deletion. It rejects changed or multiple push destinations.
- **Coverage is classified for every required reviewer/chunk pair.** Failed invocations cannot
  count as successful coverage, and a later chunk failure cannot leave a pass marked full.
  `external-review` owns the classification and Gemini timeout; callers point to it. Removed
  duplicated capture commands, tool tutorials and superseded wording from the skills.
- **Both setup symlink sequences bind their paths and guard the actual move and link.** A failed
  move stops installation, existing backups are retained, and the result is checked. The
  reference calls the exploration allowlist a prompt-reduction list and names `find`'s writes.
- **Roadmap ownership and ordering match the supporting records.** Backup work belongs to
  `drive-backup`, KI-34 appears in the active list, issues follow severity and likelihood, and
  verification questions precede risks. Architecture records setup's backup dependency.
- **S07 round-3 P2 is `Rule ineffective`.** Its substitute mutation does not keep the original
  test green on every host; pinning `TZ` in the replacement cannot establish that property.
  The summary now records five of six discriminating units fixed. Evidence notes also record
  the false H1 window finding and the timezone teardown defect, without changing other grades.

- **External review pass 7 — 19 findings, five of them in pass 6's own fixes.**
  The bundle counts read a `manifest.z` that was never created; the invocation
  loops still used the naming the prose had just forbidden, so a chunk could
  overwrite another's findings and a failed retry inherit the previous answer;
  the coverage rewrite left later text still calling a zero-output pass
  "partial"; and the `capture()` function rejected `~/.claude/plans/`, the normal
  location for the file `plan` mode reviews. Tracked changes also bypassed the
  filter entirely, since only untracked files pass through `capture()` — a
  `.gitattributes` `diff` attribute can still force a binary blob into a patch.
- **`phase-workflow` validated the wrong remote URL.** Git keeps a separate push
  URL, so a remote can fetch from the approved repository and push to a fork —
  which would pass every SHA check and then receive the tag and the branch
  deletion. Both URLs are now captured at §2 and compared before publication.
- **New rule: re-gather derived evidence before external review, not after.**
  Evidence produced by *running* something — subagent scenario runs, evals,
  benchmarks — is valid only for what it was gathered against, so a fix expires
  it. Mark it expired at the fix, make every fix that touches the measured thing
  first, then re-gather once as the last action before the review. This repo let
  that evidence go stale three times before the rule was written.
- Smaller corrections: `ln -sfn` links *inside* an existing real directory rather
  than replacing it; markdownlint discovery is bounded by the invocation
  directory, not a walk to `$HOME`, and the CLI verification cannot establish
  editor parity; the canonical findings-table example filed a Confirmed bug as an
  open question; README described the reviewed plan as approved and conflated
  release preparation with post-merge tagging; and roadmap ordering, summaries
  and provenance were reconciled with the entries they describe.

- **External review pass 6 — 29 findings from a single reviewer, and three of the
  worst were introduced by pass 5's own fixes.** `external-review`'s capture
  blocks ended on `grep -q … && exit 1`, which returns grep's status, so a clean
  bundle exited **1** on its success path; the file-level `-L` test missed a
  **symlinked parent directory**, through which `cat` reads straight out of the
  repository (reproduced against a scratch repo, and the guard now blocks it); and
  a tracked file absent from the tree was dropped silently despite the fail-closed
  promise. Coverage classification counted installed CLIs rather than reviewers
  that produced output, so one CLI missing plus one out of quota reported as
  "partial" with nothing reviewed. Bundle counts mixed a newline-delimited total
  with a NUL-delimited selection. Both capture paths are now one checked
  procedure.
- **`design-review`'s Direction rule did not contain the exemption its own test
  grades against.** The composition-root exemption and the reachability scope were
  added to the s01 condition and not to the skill, so D2's "Rule works" certified
  compliance with the test rather than with the rule. Both are now in the skill.
- **The VS Code parity consequence was backwards.** `MD013` is disabled in the
  pinned CLI config too, so line length is not the difference; declining the key
  costs editor squiggles from `MD033`, `MD024` and `MD029` on roadmap anchors,
  CHANGELOG headings and continuing ordered lists.
- **Recorded condition hashes identified superseded text.** S01 and S07 were
  reworded after their runs but kept their pre-reword hashes. Each row now records
  the hash the grade was judged against alongside the one it was dispatched under.
- **The gate demanded of reviewers what only the agent can produce** — a formatted
  table rather than a findings list — and deferred plan findings were restricted
  to `ENH-nn`/`UNK-nn`, which files a real bug as an open question. The merge
  cycle also republished through whatever `origin` names now rather than the
  remote validated at the gate.
- Smaller corrections: the audit now accepts a **predicted production exception**
  as the named red rather than forcing a second mutation to manufacture an
  `AssertionError`; `claude-setup` lists eight bundled skills and no longer calls
  its allowlist read-only; `project-env` gives runnable `ruff check .` /
  `black .` invocations and states honestly that its env-collision workaround has
  no backlink to read; the code root is defined as the directory holding the
  siblings rather than the literal name `Code`; and two obscured diagram labels
  were moved and the render re-inspected.

- **`external-review` had three wrong or missing facts about reviewer failure,
  found by running it.** Quota is account-wide, not per-model as the skill
  claimed: Gemini returned the same error with the same countdown on both its
  top and flash rungs, so a downshift can never rescue a quota failure and only
  spends the window on identical refusals. `codex exec` **exits 0** on a quota
  failure and writes no `-o` file, so exit status alone cannot distinguish a
  finished review from an exhausted account — the loop's non-empty-output check
  is what catches it, and now says so. And the coverage vocabulary had only two
  outcomes where there are three: *skipped* (both CLIs missing), *partial* (one
  reviewer empty), and **no coverage** (both installed, both run, neither
  produced output), which cannot reach a phase gate.

- **External review pass 5 — 46 findings, and two of them were mine.** Both
  reviewers independently reproduced a grading error in the pressure-test
  evidence: the S07 baseline's replacement fixture puts Auckland and UTC on the
  same calendar date, so its own property assertion is False and the test can
  never run. P3 becomes **Rule needed / Rule works**. Codex went further and
  showed the P2 correction I had proposed was wrong too — `now.astimezone()` is
  not equivalent to `local = now`, because it keeps the original test green only
  on a UTC host. The seven with-skill arms were then re-run at `a850251` against
  the corrected skills, and the round-2 S07 run uses the literal mutation with a
  fixture whose asserted properties hold, so P2 and P3 both land at **Rule
  needed / Rule works**. Six of fifteen units now discriminate, up from three,
  and the skill fixes all six. Three conditions were reworded because a careful
  reader could reach the opposite verdict; every existing output was judgeable
  against the new wording, so no baseline expired.
- **`claude-setup` no longer writes editor configuration**, and its advertised
  write footprint is stated accurately rather than as the earlier "nothing outside
  `~/.claude`". Step 3b now detects the markdownlint extension by its
  directory — `code --list-extensions` reports "not installed" whenever the CLI
  is off `PATH`, which is common — and hands the user the one-key change to make
  themselves, with the consequence of declining stated. (Corrected in the next
  pass: `MD013` is disabled in the pinned CLI config too, so the difference is
  `MD033`, `MD024` and `MD029`, not line length.)
- **`external-review` had five defects in the machinery that gates a phase.**
  The availability check grepped combined stdout and stderr, so a review whose
  findings contained "not supported" was discarded and overwritten by the next
  rung; `repo` mode reconciled with `git status`, which returns zero on the clean
  tree it is meant to run against; `repo` capture was not fail-closed while phase
  capture was; `codex exec` hung forever without `< /dev/null`; and the ~400k
  chunk ceiling was wrong — the binding limit is wall-clock, measured at ~120k
  per call.
- **Cross-file contradictions the restructuring left behind:** the typo exception
  in the standards against phase-workflow invalidating approval on every edit,
  a reviewer output contract no compliant reviewer could satisfy, KI-22 pointing
  at a deleted step 7, ROADMAP still counting seven skills, README still
  promising a three-pass ceiling, the diagram legend promising `gh` never blocks,
  and ARCHITECTURE claiming every `settings.json` writer patches in place when
  `toggle.sh` does not.

- **ENH-07 was scoped to two files and applies to six.** It named
  `backup-projects.sh` and `claude-setup`, missing all four
  `claude-toggle-backend` scripts. The omission mattered: `toggle.sh` resolves
  `settings.json` the same hardcoded way and *patches* it, so on a machine with
  `$CLAUDE_CONFIG_DIR` set the backend would appear to switch and would not, in
  silence — worse than the backup writing to the wrong folder. Now partly held,
  with counts taken from the files rather than restated (ten occurrences over
  eight distinct paths in `backup-projects.sh`, six over three in
  `claude-setup`, four in `toggle.sh`).
- **The `~/.zshrc` shared-state line overstated the fix.** ENH-09 left one
  *managed* writer, which `ARCHITECTURE.md` recorded as one writer full stop.
  The file also carries two surfaces the repo depends on and does not own. The
  line now says which, and gives the test: ask whether code generates a block,
  not whether it looks managed.
- **KI-16 rewritten: the `HF_HOME` claim had an orphan behind it.** It was filed
  as doc drift — `local-models` says the managed `~/.zshrc` block exports
  `HF_HOME`, and it does not. The machine tells a different story: a second block
  branded `# >>> localclaude HF_HOME >>>` does export it, and
  `git log -S` finds no commit that ever installed one. Hand-written, branded as
  managed. That is why the claim survived review — verifying it on this machine
  confirms it, while a machine built from the skills as written gets nothing. The
  entry now carries both halves and is marked partly held: the docs wait for the
  `local-models` rebuild, the missing installer does not.

- The CHANGELOG move is instructed once, at §3 step 4, not again at §4 step 1.
- CHANGELOG.md is exempt from the current-state rule, which had forbidden it from
  describing removed features.
- `external-review`'s Model column no longer says `Both` in one place and
  forbids it in another; severity disagreements between reviewers are recorded.
- The bundle file count no longer collapses untracked directories to one line.
  (Superseded twice since: `git status` counts changed files, which is zero on the
  clean tree a phase review runs against, and the count now derives from one
  NUL-delimited manifest.)
- `claude-setup` listed three bundled skills; there are six. README omitted
  `llama-autostart.sh` from the backend scripts.
- **`claude-setup` step 3 corrupted the file it manages** (installed on this
  machine). Its prose quoted a truncated opening marker, so a marker search
  matched the prose before the real delimiter and the installed
  `~/.claude/CLAUDE.md` was written with eight lines of the skill's own
  instructions at the top, a stray code fence, and no closing marker. The step
  now takes canonical text from the fenced block, matches whole marker lines
  only, and verifies the result before finishing.
- **The global standards block is 2,480 words, down from 3,386** — 27% off a
  file resident in every request. `ENH-01` took the first 644: the environment
  procedures to `project-env`, and the roadmap taxonomy from 374 words to 232,
  keeping the tense split and the ID rules while handing the rating scales,
  entry format and anchors to `phase-workflow` and the bundled templates, which
  already defined them. After `ENH-01`, four more bullets that
  restated a procedure with an existing owner were compressed to the rule plus
  a pointer: the mutation check and the branch-creation mechanics to
  `phase-workflow` §3 step 3 and §2, the `/simplify` reject-list to §3 step 2,
  and the markdown-lint invocation detail to `claude-setup` step 3b. Each
  pointer was checked to resolve and each dropped passage confirmed present at
  its destination. No new skill: what is left is prohibitions, which only work
  while resident.
- **`claude-setup/REFERENCE.md` drift.** Its allowlist rationale listed only the
  read-only commands, omitting the deliberate write-capable exceptions
  (`pytest`, `ruff`, `black`, `markdownlint-cli2`, the venv forms, `uv`, `npm
  test`). It also presented `backup-projects.sh` always exiting 0 as purely a
  safety feature; exiting 0 is deliberate, but logging `ok` regardless is KI-14,
  and the file now separates them.
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

[Unreleased]: https://github.com/rahulragunathan/dev-skills/compare/v2.3.0...HEAD
[2.3.0]: https://github.com/rahulragunathan/dev-skills/compare/v2.2.2...v2.3.0
[2.2.2]: https://github.com/rahulragunathan/dev-skills/compare/v2.2.1...v2.2.2
[2.2.1]: https://github.com/rahulragunathan/dev-skills/compare/v2.2.0...v2.2.1
[2.2.0]: https://github.com/rahulragunathan/dev-skills/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/rahulragunathan/dev-skills/compare/v2.0.1...v2.1.0
[2.0.1]: https://github.com/rahulragunathan/dev-skills/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/rahulragunathan/dev-skills/compare/v1.12.0...v2.0.0
[1.12.0]: https://github.com/rahulragunathan/localclaude/compare/v1.11.0...v1.12.0
[1.11.0]: https://github.com/rahulragunathan/localclaude/compare/v1.10.2...v1.11.0
[1.10.2]: https://github.com/rahulragunathan/localclaude/compare/v1.10.1...v1.10.2
[1.10.1]: https://github.com/rahulragunathan/localclaude/compare/v1.10.0...v1.10.1
[1.10.0]: https://github.com/rahulragunathan/localclaude/compare/v1.8.0...v1.10.0
[1.8.0]: https://github.com/rahulragunathan/localclaude/releases/tag/v1.8.0
