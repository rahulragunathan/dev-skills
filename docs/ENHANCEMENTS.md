# Enhancements

Candidate work, highest priority first. [ROADMAP.md](ROADMAP.md) carries the one-line index;
this file carries enough detail to pick an item up without digging.

Each entry has a stable ID — use it in branch names (`feature/enh-01-<slug>`) and in the
CHANGELOG entry that closes it. How an entry enters, ships or is dropped is in
[ROADMAP.md](ROADMAP.md).

## Priority

`roadmap.py check` reads these levels, in row order, from the template bundled with
`project-docs`. In a project's own copy this table is for reading: editing it changes nothing.

Priority is about value, not urgency. Effort is a rough estimate — a session, or days.

| Level | Means |
| ------- | ------- |
| **High** | Closes a gap hit during real use. |
| **Medium** | Worth doing when the area is already open. Removes a sharp edge or a duplication. |
| **Low** | Tidying. Do it while passing through. |

---

<a id="enh-14"></a>

## ENH-14 — Share recorded-answer validation between evidence and grading

**Priority:** Medium · **Effort:** ~1 day
**Where:** [evidence.py](../skills/design-review/tests/evidence.py) — `A batch is only worth grading if every answer in it was produced` · **Regression Net:** `skills/design-review/tests/evidence.bats`

### What It Is

Extract one answer reader that checks containment, presence, nonempty text and the recorded hash, and use it from the evidence and grading tools. Grade selection already reuses evidence.slot_key; answer validation still has separate implementations.

### Why It Matters

Different readers can accept different evidence for the same manifest record.

### Notes For The Work

Preserve evidence.py and grade_batch.py commands, exit codes and manifest formats. This crosses tools outside the small QC edits; test missing, empty, changed and escaping paths at every caller. Source: QC Tier 5, grade.py reuse.

---

<a id="enh-16"></a>

## ENH-16 — Emit shared answer evidence once in grading JSON

**Priority:** Medium · **Effort:** ~1 day
**Where:** [grade.py](../skills/design-review/tests/grade.py) — `def build_report(` · **Regression Net:** `skills/design-review/tests/grade.bats`

### What It Is

Store the full extracted answer evidence once per report and reference it from questions instead of serializing one copy per condition.

### Why It Matters

Repeating a long answer enlarges reports and packets without adding evidence.

### Notes For The Work

Audit all consumers and provide a migration for existing reports before changing the JSON layout. Keep tonight's batch interface intact. The separate --production coverage gap is now covered by a CLI regression. Source: QC Tier 5, grading output size.

---

<a id="enh-18"></a>

## ENH-18 — Evaluate an isolated subprocess alternative to the fixture interpreter

**Priority:** Medium · **Effort:** ~1 day
**Where:** [grade_eval.py](../skills/design-review/tests/grade_eval.py) — `A bounded interpreter for fixture expressions` · **Regression Net:** `skills/design-review/tests/grade.bats`

### What It Is

Compare the bounded expression interpreter with an isolated subprocess using controlled import stubs, explicit resource limits and a defined fixture execution boundary.

### Why It Matters

A growing interpreter and scenario-shaped allowlists increase maintenance and semantic gaps.

### Notes For The Work

A subprocess alone is not isolation. Preserve the prohibition on arbitrary filesystem or network effects, retain unsupported-input diagnostics, and measure against the same hand-checked fixtures before choosing an approach. This is an architecture decision, not permission to execute untrusted answers. Source: QC Tier 5, interpreter altitude.

---

<a id="enh-20"></a>

## ENH-20 — Run mutation audits in a disposable checkout

**Priority:** Medium · **Effort:** ~1 day
**Where:** [mutation-restore.sh](../skills/phase-workflow/mutation-restore.sh) — `The mutation is applied to the current checkout` · **Regression Net:** `skills/phase-workflow/tests/phase-git.bats`

### What It Is

Apply mutations and run both test commands in an isolated disposable checkout of the named task commit.

### Why It Matters

Isolation avoids exposing the main checkout to mutations and generated test output, reducing reliance on restoration after damage.

### Notes For The Work

Define dependency and ignored-file availability, command working directories, cleanup and assertion-red reporting. Preserve current SHA validation and do not certify fixture or collection failures. Source: QC Tier 5, mutation audit altitude.

---

<a id="enh-21"></a>

## ENH-21 — Reconcile bundle and export scope exclusions

**Priority:** Medium · **Effort:** ~1 day
**Where:** [capture.sh](../skills/external-review/capture.sh) — `NUL-delimited paths in scope before exclusions` · **Regression Net:** `skills/external-review/tests/capture.bats`

### What It Is

Define one supported scope-exclusion contract for capture bundles and Codex exports, and check that both select the same in-scope paths.

### Why It Matters

The same --exclude spelling currently drives Git pathspec filtering and literal path pruning, so a caller can assume agreement that is not checked.

### Notes For The Work

Choose whether to restrict the shared vocabulary or implement matching semantics. Test directories, wildcard-looking names, case, symlinks, repeated exclusions and paths matching nothing; retain the distinction between scope control and read isolation. Source: QC Tier 5, exclusion altitude.

---

<a id="enh-22"></a>

## ENH-22 — Validate verbatim judgement evidence in grade.py

**Priority:** Medium · **Effort:** ~1 day
**Where:** [grade.py](../skills/design-review/tests/grade.py) — `Execute fixture checks and expose unresolved artifact judgements.` · **Regression Net:** `skills/design-review/tests/grade_batch.bats`

### What It Is

Move the rule requiring judgement evidence to quote the answer verbatim from grade_batch.py into grade.py judgement validation, so human and model reviewers meet the same rule.

### Why It Matters

The current entry points impose different evidence requirements on otherwise equivalent judgements.

### Notes For The Work

Deferred by the user after Claude's grading-tool review. Define allowed multi-excerpt notation, preserve hash binding and explicit disputes, and test both direct judgements and batch collection before migrating the validator.

---

<a id="enh-23"></a>

## ENH-23 — Calibrate graders with blind hand-graded anchors

**Priority:** Medium · **Effort:** ~1 day
**Where:** [grade_batch.py](../skills/design-review/tests/grade_batch.py) — `Graders receive the whole packet, not just the prompt` · **Regression Net:** `skills/design-review/tests/grade_batch.bats`

### What It Is

Mix a few hand-graded answers into grading packets without marking them for graders, and report how often graders agree with the reference judgements.

### Why It Matters

Agreement between model graders does not establish grader quality when both share a mistake.

### Notes For The Work

Deferred by the user after Claude's grading-tool review. Retain reference provenance and rationale, control anchor exposure and revisions, and report condition-level denominators without using anchors as experimental answers.

---

<a id="enh-26"></a>

## ENH-26 — Test the conversion of a helper's evaluation gap into an opaque call

**Priority:** Medium · **Effort:** ~1 hour
**Where:** [grade_eval.py](../skills/design-review/tests/grade_eval.py) — `return fn(*args, **kwargs)` · **Regression Net:** `skills/design-review/tests/grade.bats`

### What It Is

Add a `grade.bats` case where an imported helper stops at an unsupported statement, and assert that bindings the call could change become unknown afterwards.

### Why It Matters

Astra's F-02 added this conversion, but reverting the hunk leaves the suite green, so nothing protects it.

### Notes For The Work

Found in Claude's adversarial review of the overnight passes, 2026-09-14. Write the test against HEAD, then confirm it fails for its named reason with the hunk reverted.

---

<a id="enh-28"></a>

## ENH-28 — Let `publish-release.sh` verify remote presence itself

**Priority:** Medium · **Effort:** ~2 hours
**Where:** [publish-release.sh](../skills/phase-workflow/publish-release.sh) — `--check-origin exits before any ref changes.` · **Regression Net:** `skills/phase-workflow/tests/phase-git.bats`

### What It Is

`--confirmed-on-remote` is an operator assertion, not a verification. The script runs
`git branch -D` on the strength of a flag, having checked only that the branch tip equals the
positional `<approved-sha>`.

### Why It Matters

`-D` is the one command in this workflow that can discard commits that were never pushed. The
flag replaced an invisible `APPROVED_SHA` environment dependency, which was worse — it could
never fire and the retain message blamed the branch — but neither form proves the commits reached
the remote. An operator who passes the flag while the branch holds an amended or fixup commit
loses it.

### Notes For The Work

The script can establish this itself. `git for-each-ref --contains <sha> refs/remotes/origin/`
non-empty shows the commit is reachable from a remote-tracking ref, and
`[ -z "$(git diff <branch> <default>)" ]` shows the work landed even when a squash discarded the
commits — that tree comparison was measured correct for both the squash and merge-commit cases
`git cherry` gets wrong. Decide whether the flag becomes redundant or remains as an override, and
keep the retain rule: nothing is deleted that was not proven safe.

**Source:** gemini-3.8-flash-high — phase review, phase 1 gate integrity, 2026-09-21.

---

<a id="enh-38"></a>

## ENH-38 — Name security in design-review's plan-time checks

**Priority:** Medium · **Effort:** ~2 hours
**Where:** [design-review/SKILL.md](../skills/design-review/SKILL.md) — `## The six checks` · **Regression Net:** `skills/design-review/tests/`

### What It Is

`design-review` checks structure at plan time and phase end, and names no security question: a
trust boundary, where untrusted input enters, or what a new dependency brings. The external
review now asks both reviewers about security in every mode, and the phase end runs
`/security-review` and a dependency scan, but the design pass itself, which shapes the plan, is
silent on it.

### Why It Matters

A trust boundary drawn in the wrong place is cheapest to move in the plan. The other passes find
it after the code exists.

### Notes For The Work

Editing `design-review/SKILL.md` expires its recorded pressure-test results, so this belongs with
the design-review rework, and its new rule needs its own pressure test.

**Source:** the user's question during plan review, dependable-helpers phase, 2026-11-23.

---

<a id="enh-40"></a>

## ENH-40 — Make Path required in the roadmap check

**Priority:** Medium · **Effort:** ~2 hours
**Where:** [roadmap.py](../skills/project-docs/roadmap.py) — `OPTIONAL_FIELDS = {"KI": ["Path", "Area"]}` · **Regression Net:** `skills/project-docs/tests/roadmap.bats`

### What It Is

Make `check` report a missing Path, and drop the `Almost always` spelling from `OLD_SPELLINGS`.
Do not move Path into `FIELDS`: that list also drives the ROADMAP mirror and the sort key, so
every index would then fail with `rating mismatch: KI-nn Path`. Add the presence check beside
`optional_problems` instead. Decide at the same time whether Area becomes required too.

### Why It Matters

While Path is optional, a known issue can be filed without saying whether it breaks the Happy
Path, which is the one fact the blocking rule turns on.

### Notes For The Work

Do it only after every repository's entries carry a Path and the new spelling, which the fresh
look across the repositories does; otherwise their `check` starts failing. The tests that guard
the optional reading (`check accepts an entry without a Path or an Area`, `check accepts the old
spelling of Almost Always`) change with it; keep the one that proves Path stays out of the index.
Corrected in pass 1 (gpt-6.2-astra:high, gemini-4-neon-high).

**Source:** the user's decision during this phase's design, review-triage phase, 2026-11-26.

---

<a id="enh-41"></a>

## ENH-41 — Make the triage wording tests pin the whole policy

**Priority:** Medium · **Effort:** ~2 hours
**Where:** [test_skill_text.py](../tests/test_skill_text.py) — `def test_every_source_gets_the_fields_at_intake` · **Regression Net:** `tests/test_skill_text.py`

### What It Is

Six gaps in the wording tests: intake passes with the source names alone, the stop-rule test misses a loop that continues past pass 3, the worked-table test leaves out the fourth row, nothing still asserts the empty list's `No findings.` since the opening-line test went, the Codex-loop state test passes with one failure branch's state write removed, and the plan-note test reads every keyed example in the skill, so it would reject a valid phase example.

### Why It Matters

A wording test that passes on a broken rule is a false green on the very text agents follow.

### Notes For The Work

Assert the intake fields and who supplied them, the completeness and pass-3 conditions, and all four worked rows. Assert `No findings.` in the text sent to reviewers, run the Codex loop's failure branch against a fixture and read its state with `progress.sh`, and scope the plan-note test to the plan examples. (The tracked-ID test went with the Happy Path line.) Each needs a red first.

**Source:** gpt-6.2-astra:high — phase review passes 1, 2 and 4, review-triage phase, 2026-11-26 and 2026-11-27.

---

<a id="enh-39"></a>

## ENH-39 — Make the tests pass 3 found weak fail for their named reason

**Priority:** Low · **Effort:** ~2 hours
**Where:** [dependency-scan.bats](../skills/phase-workflow/tests/dependency-scan.bats) — `the committed file never reaches it` · **Regression Net:** `skills/*/tests/`

### What It Is

Several tests added in this phase's review pass whether or not their fix is in place: the
include test checks a path the old exporter never passed; the commit test prints a SHA without
comparing it to a scan; the single-message test counts messages without requiring the cause;
the bytes test passes under `LC_ALL=C`; the bootstrap v2 assertion was already true; the
partial-write test fails a mocked `ln` rather than a write.

### Why It Matters

A test that cannot fail is false evidence for the behaviour CHANGELOG cites it for.

### Notes For The Work

Give each a fixture where the reverted code answers differently, and assert the cause, not only
the count.

**Source:** gpt-6.2-astra:high, gemini-4-carbon-high — phase review pass 3, dependable-helpers phase, 2026-11-23.

---

<a id="enh-32"></a>

## ENH-32 — Drop explanations of standard tool behaviour from the skills

**Priority:** Low · **Effort:** ~2 hours
**Where:** [phase-workflow/SKILL.md](../skills/phase-workflow/SKILL.md) — `Three dots, not two`, [external-review/SKILL.md](../skills/external-review/SKILL.md) — `Run the discovery block in the same shell as the loops` · **Regression Net:** none (prose)

### What It Is

Several passages explain how Git works rather than stating this project's policy: why a
three-dot diff differs from a two-dot one, what `git mv` tracks, and how `git stash` treats
untracked files. `external-review` repeats the diff explanation in its capture section, explains
shell-variable lifetime beside the ladder discovery, and explains why a diff omits untracked
files. `phase-workflow` explains why a commit cannot contain its own hash, and `AGENTS.md` how
the reflog recovers committed work. Keep the policy and the commands; drop the tutorial.

### Why It Matters

`AGENTS.md` already says skills do not explain standard tools. The passages cost reading time on
every invocation and drift from the tools they describe.

### Notes For The Work

Belongs with the fresh look at this plugin that follows the deep cut of the standards. Keep the
nuances people get wrong, such as which diff a review must use.

**Source:** gpt-6.2-sol:max, gpt-6.2-astra:max — plan review, project-docs phase, 2026-11-20; more sites from gpt-6.2-astra:max, gemini-4-argon-high — phase review pass 1, 2026-11-22.

---

<a id="enh-43"></a>

## ENH-43 — Make the roadmap-shape guards exact

**Priority:** Low · **Effort:** ~1 hour
**Where:** [roadmap.bats](../skills/project-docs/tests/roadmap.bats) — `own_docs() {` · **Regression Net:** `skills/project-docs/tests/roadmap.bats`

### What It Is

The guards added for the casing sweep accept some malformed entries and reject some valid ones. The heading test accepts any subsequence, so a missing required heading passes, and reads a `###` line inside a code fence as a heading. The label test pools all three templates, so an ENH label in a KI passes, and its pattern skips labels with hyphens or apostrophes. The title test sees only an initial ASCII lower-case letter, so a title that starts with a code span passes.

### Why It Matters

A guard that passes a malformed entry is false evidence that the roadmap files are in shape.

### Notes For The Work

Compare each file against its own template, require the required sections, skip fenced blocks, widen the label pattern, and check the first visible word of a title. Each needs a red first.

**Source:** gpt-6.2-astra:high, gemini-4-neon-high — phase review pass 4, review-triage phase, 2026-11-27.
