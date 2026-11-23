# Known Issues

Open defects, most severe first. [ROADMAP.md](ROADMAP.md) carries the one-line index; this
file carries enough detail to pick an item up without digging.

Each entry has a stable ID — use it in branch names (`bugfix/ki-02-<slug>`) and in the
CHANGELOG entry that closes it. When fixed, delete it from here and from the ROADMAP index;
the record lives in [CHANGELOG.md](../CHANGELOG.md). IDs are never reused.

Every entry carries its own source line; they come from several review passes, not one.
Entries for skills that left this repo in v2.0.0 moved with them, keeping their IDs.

## Severity

`roadmap.py check` reads these levels, in row order, from the template bundled with
`project-docs`. In a project's own copy this table is for reading: editing it changes nothing.

| Level | Means |
| ------- | ------- |
| **Critical** | Loses or corrupts data, or sends wrong information to real recipients. |
| **High** | Silently produces a wrong result, or reports success without doing the work. |
| **Medium** | Wrong under conditions the operator can notice or work around. |
| **Low** | Cosmetic, or wrong in a field nothing consumes. |

**Severity is the consequence if it fires, and nothing about how often.**

## Likelihood

`roadmap.py check` reads these levels, in row order, from the template bundled with
`project-docs`. In a project's own copy this table is for reading: editing it changes nothing.

| Level | Means |
| ------- | ------- |
| **Almost always** | Anyone following the documented workflow hits it. |
| **Likely** | Hit whenever a common condition holds — a second machine, an overlapping run, a particular option. |
| **Rare** | Needs an unusual trigger, or only bites in combination with another failure. |

**Judge the harm, not the code path.** A wrong value computed on every run is `Rare` when it only
misleads after something else has already failed, and **a defect that is always present but
harmful only in combination is `Rare`**. Conversely, if a documented step is what triggers it,
that is `Almost always` for everyone who follows the step, however unusual it looks from outside.

**Rate both, because one number cannot carry both.** `Rare · Critical` and `Almost always · Low`
are opposite kinds of work — the first is a landmine, the second is friction — and a single
rating hides which you are looking at. Both still get fixed.

---

<a id="ki-57"></a>

## KI-57 — `roadmap.py close` can lose a concurrent edit and rewrites line endings

**Severity:** Critical
**Likelihood:** Rare
**Where:** [roadmap.py](../skills/project-docs/roadmap.py) — `def install_documents(`

### What happens

`close` builds both new documents from one read, then installs them without checking the
files are still what it read. An entry added in between disappears from both files, and `close`
reports success. It also reads in text mode and rebuilds line boundaries, so closing one entry
can turn CRLF into LF throughout both files, and the byte-identity check compares survivors after
`.strip()`.

### Example scenario

An editor saves a new KNOWN_ISSUES entry while `close KI-07` runs. The new entry is gone
after the close, from the detail file and the index.

### Notes for a fix

Compare each file with what was read just before replacing it, or hold a lock from load to
install. Preserve the newline style, and compare surviving slices without stripping them.

**Source:** gpt-6.2-astra:max, gemini-4-argon-high — phase review pass 1, project-docs phase, 2026-11-22.

---

<a id="ki-70"></a>

## KI-70 — the origin check still lets some helper URLs through, and passes when grep fails

**Severity:** Critical
**Likelihood:** Rare
**Where:** [publish-release.sh](../skills/phase-workflow/publish-release.sh) — `TRANSPORT HELPER IN ORIGIN URL`

### What happens

The transport-helper refusal matches only names that start with a letter, so `9p::…`,
`my_helper::…` or an empty `::…` prefix passes, and git can also hand an unknown `scheme://` to a
custom helper. A `grep` that fails to run reads as "no match", so the check passes.

### Example scenario

A push URL `9p::https://token@host/r.git` passes `--check-origin`, and phase start records the
token in `docs/PHASE_RECORD.md`.

### Notes for a fix

Refuse any `::` before the first `/` or single `:`, accept only the schemes a phase needs
(ssh, https, the scp form), and use the shell's own pattern matching so no external command can
fail open. Test each case in both URL positions with its exact diagnostic.

**Source:** gpt-6.2-astra:high, gemini-4-neon-high — phase review pass 7, project-docs phase, 2026-11-22.

---

<a id="ki-47"></a>

## KI-47 — grading packets omit information their conditions require

**Severity:** High
**Likelihood:** Almost always
**Where:** [grade_batch.py](../skills/design-review/tests/grade_batch.py) — `def packet_text(` (packet assembly),
[s05-report-form.md](../skills/design-review/tests/s05-report-form.md) — `omits the reason: neither a fitting existing home`

### What happens

The grader prompt states "everything you need is in the packet below this prompt." No packet
carries the scenario prompt, and none carries S05's banned-word list, which its Rule 4 grades
against. Graders reconstruct the fixture from the answer or judge the rule without its terms.

### Example scenario

Verified over round 9: 0 of 84 packets contain the banned list while
`s05-report-form.md` does. Two graders said so in their own judgements — one wrote "The packet
does not list the banned words" — and returned a verdict anyway. The omitted list also sits
outside the failure-condition section whose hash is reproduced, so the check cannot see it.

### Notes for a fix

Include the scenario prompt and every rule's terms in the packet, and hash what is sent rather
than a section of it. Until then a Rule 4 verdict rests on the grader's memory of the rule.

**Source:** gpt-6-astra — review of round-9 evidence and grading, 2026-09-16; packet count
verified by claude-opus-5.

---

<a id="ki-48"></a>

## KI-48 — S07's with-skill arm is handed the answer to the condition it is graded on

**Severity:** High
**Likelihood:** Almost always
**Where:** [s07-process-rules.md](../skills/design-review/tests/s07-process-rules.md) — `This condition is about the audit's bookkeeping` condition 2b,
`loaded-phase-workflow.md` in each round's evidence directory

### What happens

S07 loads `phase-workflow`. Its condition 2b fails a mutation "whose predicted outcome depends on
the host", and names `local = now` and `local = now.astimezone(timezone.utc)` as the acceptable
choices. The loaded skill text supplies those same two expressions as its worked example.

### Example scenario

Round 9 recorded S07 Mutation choice at 5/5 with-skill against 2/5 baseline. Verified: the
with-skill arm was shown the two expressions its condition grades, minutes before answering.
The result measures recall of a supplied example, not mutation reasoning.

### Notes for a fix

Freeze the skill, then construct held-out scenarios whose answers are absent from its text. A
scenario that grades an example the skill contains cannot distinguish transfer from recall.

**Source:** gpt-6-astra — review of round-9 evidence and grading, 2026-09-16; both locations
verified by claude-opus-5.

---

<a id="ki-60"></a>

## KI-60 — helper commands need `CLAUDE_PLUGIN_ROOT`, which a Codex install does not set

**Severity:** High
**Likelihood:** Almost always
**Where:** [README.md](../README.md) — `reads skills as plain folders`

### What happens

Every bundled helper is called as `$CLAUDE_PLUGIN_ROOT/skills/...`. Claude Code sets the
variable; the README's Codex install, linking each skill folder, does not. Under Codex the
commands resolve to `/skills/...` and fail. The PR body template also credits Claude Code
whoever wrote the phase.

### Example scenario

In Codex, follow `project-docs`' set-up step: `python3 "$CLAUDE_PLUGIN_ROOT/skills/project-docs/roadmap.py" init`
runs `/skills/project-docs/roadmap.py` and fails.

### Notes for a fix

Belongs to the Codex parity step of the setup programme: resolve helpers from the installed
skill's own folder, test the plain-folder layout with the variable unset, and name the actual
author in the PR body.

**Source:** gpt-6.2-astra:max, gemini-4-argon-high — phase review pass 1, project-docs phase, 2026-11-22.

---

<a id="ki-37"></a>

## KI-37 — a replaced evidence slot keeps its old grade

**Severity:** High
**Likelihood:** Rare
**Where:** [grade_batch.py](../skills/design-review/tests/grade_batch.py) — `jpath, rpath = out / "judgements" /`

### What happens

`collect` treats a packet as already collected when its judgement and report exist for the
logged grader. It does not compare the packet's answer hash with the answer the evidence batch
now records. If a run is replaced after `prepare`, its old grade stays, and `agree` and
`summary` count it for an answer that is no longer in the batch.

### Example scenario

A with-skill run is found contaminated after grading starts and is re-run with
`evidence.py log-dispatch --replace`. The evidence check passes again, `collect` reports every
packet as already collected, and the summary reports the voided answer's grade.

### Notes for a fix

Before accepting a cached grade, compare the packet's `answer_hash` with the manifest entry for
its slot, and refuse with a message to prepare a new grading directory. Astra's F-06 fixed the
currentness check for uncached packets only. Until this is fixed, complete the evidence batch
before `prepare` and never replace a slot afterwards.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-38"></a>

## KI-38 — an assertion the test expects to fail still grades as did-not-hold

**Severity:** High
**Likelihood:** Rare
**Where:** [grade_eval.py](../skills/design-review/tests/grade_eval.py) — `self.unexecuted_guards(tail, env, scope,`

### What happens

An `assert` inside `with pytest.raises(AssertionError):`, or inside a `try` whose handler
catches `AssertionError`, is evaluated as an ordinary guard. When it evaluates False, the
executed check reports did-not-hold, although that failure is what the test expects.

### Example scenario

A replacement test checks that a helper rejects bad input by asserting inside
`pytest.raises(AssertionError)`. The executed check reports the assertion as did-not-hold, and a
grader reads it as a broken fixture.

### Notes for a fix

Treat a guard whose failure is expected by the enclosing context manager or handler as
could-not-evaluate. The behaviour predates the overnight QC passes.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-58"></a>

## KI-58 — `check` misses drift: empty files, fenced anchors, question order, mirrored fields

**Severity:** High
**Likelihood:** Rare
**Where:** [roadmap.py](../skills/project-docs/roadmap.py) — `def reconcile(`

### What happens

Four blank files pass `check`, since no heading or pointer table is required. A fenced
example holding a real entry's anchor is read as a duplicate. Open questions are never checked
for order, though the templates order them by Kind. A displayed label such as `KI-01-extra` is
read as `KI-01`, and an enhancement's Effort and every title are never compared between the
index and the detail file.

### Example scenario

Change an enhancement's Effort in ROADMAP from `~1 day` to `~80 days`, or swap two open
questions of different Kinds. `check` passes both.

### Notes for a fix

Validate the empty-roadmap structure, parse anchors and rows outside fences, match displayed
IDs exactly, compare Effort and titles, and order open questions by the Kind table.

**Source:** gpt-6.2-astra:max, gemini-4-argon-high — phase review pass 1, project-docs phase, 2026-11-22.

---

<a id="ki-59"></a>

## KI-59 — the reference check has gaps in what it reads and where

**Severity:** High
**Likelihood:** Rare
**Where:** [roadmap.py](../skills/project-docs/roadmap.py) — `def _where_field(`

### What happens

A `**Where:**` after another field on the same line (`**Priority:** Low · **Where:** …`) is
not found, so the entry is never checked. An absolute path inside the repository passes. An empty
field passes. Any file under `docs/` is exempt from the fragment rule, executable source
included. The cited file is opened without the credential-name screen the name check uses. And
`project-docs/SKILL.md` says a fragment cannot contain a backtick, while the parser accepts a
multi-backtick span.

### Example scenario

An entry written as `**Effort:** ~1 hour · **Where:** [x.py](../x.py)` passes with a
fragment that is not in `x.py`.

### Notes for a fix

Find the field anywhere on an unfenced line, refuse absolute and empty targets, limit the
`docs/` exemption to Markdown, screen credential names, and make the skill text match the parser.

**Source:** gpt-6.2-astra:max, gemini-4-argon-high — phase review pass 1, project-docs phase, 2026-11-22.

---

<a id="ki-62"></a>

## KI-62 — the post-review gate check can miss a rename's source

**Severity:** High
**Likelihood:** Rare
**Where:** [phase-workflow/SKILL.md](../skills/phase-workflow/SKILL.md) — `CHANGED AFTER REVIEW`, [external-review/SKILL.md](../skills/external-review/SKILL.md) — `git diff <commit the last pass reviewed>..HEAD`

### What happens

`git diff --name-only` reports only the destination of a detected rename, so a file moved
from outside the bookkeeping set into an allowed path passes the path check, and the patch that
follows can show the old file's content. `|| true` also hides a failed listing, and `HEAD` is
read twice. `external-review`'s loop still tells the agent to read a plain `git diff`, without
`--no-ext-diff --no-textconv`.

### Example scenario

A post-review commit renames a skill file to `docs/ROADMAP.md`. The check lists only
`docs/ROADMAP.md`, which is allowed.

### Notes for a fix

Pin the gate commit once, list both sides with `--no-renames`, fail on a failed listing, and
pass the five allowed paths to the patch command.

**Source:** gpt-6.2-astra:high, gemini-4-argon-high — phase review pass 4, project-docs phase, 2026-11-22.

---

<a id="ki-63"></a>

## KI-63 — a quoted refusal of the same model can still downshift Codex

**Severity:** High
**Likelihood:** Rare
**Where:** [external-review/SKILL.md](../skills/external-review/SKILL.md) — `grep -F "$slug"`

### What happens

The loop downshifts on an `ERROR:` line that names the rung's model. Material under review
that quotes an earlier refusal of that same model, or a longer slug containing it, satisfies the
same test when the run later fails for another reason.

### Example scenario

A follow-up review whose bundle includes an earlier Codex log fails on a network error. The
quoted refusal moves it to a weaker model.

### Notes for a fix

Confirm an apparent refusal with a short probe of the same model and effort before
downshifting.

**Source:** gpt-6.2-astra:high — phase review pass 4, project-docs phase, 2026-11-22.

---

<a id="ki-64"></a>

## KI-64 — the Codex probe runs in the caller's folder when ROOT is unset

**Severity:** High
**Likelihood:** Rare
**Where:** [preflight.sh](../skills/external-review/preflight.sh) — `--root) ROOT_ARGS=`

### What happens

The documented probe passes `--root` only when `ROOT` is set, and `preflight.sh` probes Codex
without it. A skipped preparation step probes the live checkout. A directly probed Gemini id
ending in `-low`, `-minimal`, `-none` or `-ultra` also gets `--effort high`.

### Example scenario

A session forgets to prepare the review root; the readiness probe runs Codex in the user's
checkout.

### Notes for a fix

Require a root whenever a Codex candidate will run, and refuse the excluded Gemini suffixes
in the probe.

**Source:** gpt-6.2-astra:high, gemini-4-argon-high — phase review pass 4, project-docs phase, 2026-11-22; gpt-6.2-astra:high — pass 5.

---

<a id="ki-69"></a>

## KI-69 — the phase-record check still misreads some record layouts

**Severity:** High
**Likelihood:** Rare
**Where:** [phase-workflow/SKILL.md](../skills/phase-workflow/SKILL.md) — `PHASE RECORD DOES NOT NAME PR`

### What happens

The check takes the first `| Key | Value |` table, so a first table under another header, or
a fenced example header, lets a companion table count. A tab-padded second PR row is missed and
an aligned valid row is rejected. Its awk stops reading early, so a large record makes
`git show` exit 141 under `pipefail`. The step also edits the PR description before the gate
has verified the PR number.

### Example scenario

A record whose first table is headed `| Field | Value |` passes the gate for the companion
repository's PR.

### Notes for a fix

Parse the first actual table, trim cells, count each key, read to the end of input, and move
the PR-description edit after the head checks.

**Source:** gpt-6.2-astra:high, gemini-4-neon-high — phase review pass 6, project-docs phase, 2026-11-22.

---

<a id="ki-67"></a>

## KI-67 — the first push accepts a phase record inherited from the default branch

**Severity:** High
**Likelihood:** Rare
**Where:** [phase-workflow/SKILL.md](../skills/phase-workflow/SKILL.md) — `PHASE RECORD NOT COMMITTED ON`

### What happens

The check reads the branch tip for the branch-name row, which an unchanged record from the
default branch can carry when a branch name is reused, or a second table can supply.

### Example scenario

A phase branch reuses an old name; the inherited record passes and the branch publishes
without a new record.

### Notes for a fix

Also require a commit on the phase range that touches the record, and read the first table
only, as the gate's record check does.

**Source:** gpt-6.2-astra:high — phase review pass 4, project-docs phase, 2026-11-22.

---

<a id="ki-49"></a>

## KI-49 — the headline tally mixes two skills

**Severity:** Medium
**Likelihood:** Almost always
**Where:** [tests/README.md](../skills/design-review/tests/README.md) — `an unexecuted audit plan. S07 does not prove that` rollup,
[s07-process-rules.md](../skills/design-review/tests/s07-process-rules.md) — `## Rules under test`

### What happens

S07 states `**Loads:** phase-workflow`. S01 to S06 load `design-review`. A combined tally over all
seven scenarios therefore reports two skills as one result.

### Example scenario

Round 9's corrected figures are 33/35 with-skill against 21/35 baseline. The design-review-only
subtotal is 28/30 against 19/30; the remaining 5/5 against 2/5 belongs to `phase-workflow`.

### Notes for a fix

Report per-skill subtotals, and never a combined figure without naming which skills it spans.

**Source:** gpt-6-astra — review of round-9 evidence and grading, 2026-09-16.

---

<a id="ki-50"></a>

## KI-50 — S05's fixture contradicts itself

**Severity:** Medium
**Likelihood:** Almost always
**Where:** [s05-report-form.md](../skills/design-review/tests/s05-report-form.md) — `Reporting an extraction contradicts the final decision and fails.`, Final decisions

### What happens

The final decisions say two modules "each copy the exact `taxes.round_line_tax` implementation"
and then that they "will call `taxes.round_line_tax` at that same per-line stage". Both cannot
describe the same final state.

### Example scenario

An answer must repair the contradiction while reporting decisions as final. One baseline replicate
challenged the delivery split instead, and its Rule 2 failure cannot be separated from a
reasonable objection to the fixture's account of the existing design.

### Notes for a fix

Give the scenario an unambiguous before-state and final-state. Until then S05's substantive result
mixes reporting quality with fixture repair.

**Source:** gpt-6-astra — review of round-9 evidence and grading, 2026-09-16.

---

<a id="ki-51"></a>

## KI-51 — rejected grading attempts are not retained

**Severity:** Medium
**Likelihood:** Likely
**Where:** [grade_batch.py](../skills/design-review/tests/grade_batch.py) — `def load_grading(` (`collect`, replacement path)

### What happens

Agreement is computed over retained, accepted attempts. A rejected return is replaced and its body
is not kept, so the agreement figure cannot be recomputed over everything that was actually
returned.

### Example scenario

For one S02 condition the documented history holds three votes, implying 1 of 3 agreeing pairs,
while the retained pair contributes 1 of 1. The rejected verdict is also the one matching the
settled UNK-04 reading, so discarding it removed the disagreement.

### Notes for a fix

Archive every return, accepted or not, with its rejection reason, and report agreement over
attempts as well as over retained pairs. Adjacent to ENH-24 but distinct: that entry is about
denominators, this one is about discarded evidence.

**Source:** gpt-6-astra — review of round-9 evidence and grading, 2026-09-16.

---

<a id="ki-36"></a>

## KI-36 — a grader quote of a table cell that holds a pipe is refused

**Severity:** Medium
**Likelihood:** Likely
**Where:** [grade_batch.py](../skills/design-review/tests/grade_batch.py) — `def unquoted(`

### What happens

Answers are Markdown. In a table cell a pipe must be written `\|`, including inside a code
span, and renderers display it as `|`. `unquoted()` compares the grader's quote with the raw
answer text, so a quote of the rendered cell (`str | None`) does not match `str \| None`, and
`collect` refuses the judgement.

### Example scenario

In round 9 the repeat grader for S02 baseline replicate 2 quoted
`normalise_prefix(sku: str) -> str | None` from a module table. The grade was refused and
replaced, so its verdict, a Lifetime fail, is missing from the 40/40 agreement count.

### Notes for a fix

Replace `\|` with `|` in both the quote and the answer before matching; doing it on both sides
keeps raw quotes matching. `&#124;` is no alternative for authors, because entities are not
decoded inside code spans.

**Source:** claude-opus-5 — round-9 grading, 2026-09-14.

---

<a id="ki-39"></a>

## KI-39 — `print` with an f-string argument still hides later guards

**Severity:** Medium
**Likelihood:** Likely
**Where:** [grade_eval.py](../skills/design-review/tests/grade_eval.py) — `def fixture_print(`

### What happens

The fixture interpreter supports `print` with plain arguments but cannot evaluate an f-string
(`ast.JoinedStr`). A `print(f"x={x}")` diagnostic leaves the rest of the test body unknown, so
later independent guards report could-not-evaluate. QC test T3-2 covers only
`print("debug", x)`.

### Example scenario

A replacement test prints `f"window={start}"` before its property assertions. The executed
checks lose every assertion after the print, and the grader gets no executed evidence for
fixture validity.

### Notes for a fix

Evaluate `JoinedStr` and `FormattedValue` under the same size bound as string concatenation,
or skip a bare `print` statement without evaluating its arguments. Add an f-string case to
T3-2.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-55"></a>

## KI-55 — the plan review cannot run while the plan is inside the repository

**Severity:** Medium
**Likelihood:** Likely
**Where:** [phase-workflow/SKILL.md](../skills/phase-workflow/SKILL.md) — `## 1. Plan review (before the user approves)`, [codex-root.sh](../skills/external-review/codex-root.sh) — `TREE IS DIRTY — commit first; the reviewer only ever sees HEAD`

### What happens

`codex-root.sh` refuses to build the Codex export whenever `git status --porcelain` is non-empty,
and that includes untracked files. §1 runs before the phase branch exists, so the plan it reviews
cannot yet be committed. If the plan was written to `docs/superpowers/plans/` as
`superpowers:writing-plans` directs, the export fails and the Codex half of the plan review cannot
run at all.

### Example scenario

Draft the plan at `docs/superpowers/plans/<date>-<phase>.md`, then run
`external-review` in `plan` mode. `codex-root.sh` exits with `TREE IS DIRTY — commit first`.
The workaround is to hold the plan outside the repository for the review and move it in at §2,
which is what the reference-integrity phase did.

### Notes for a fix

The two documents are individually consistent and neither states the ordering the other needs:
`external-review`'s plan mode already says plans live in `~/.claude/plans` by design and adds that
directory to its allowed roots. Either say in §1 that the plan is drafted outside the repository
and lands as the phase's first commit, or let `codex-root.sh` ignore untracked paths it has been
told to exclude. The first is a wording fix. The second changes a guard whose whole value is
refusing to review a tree that differs from HEAD, so prefer the wording.

**Source:** claude-opus-5 — hit while running §1 for the reference-integrity mini phase,
2026-09-21.

---

<a id="ki-73"></a>

## KI-73 — the release-version test is skipped when its file runs directly

**Severity:** Medium
**Likelihood:** Likely
**Where:** [test_plugin_name.py](../tests/test_plugin_name.py) — `class ReleaseVersionTest`

### What happens

`ReleaseVersionTest` is defined after `unittest.main()`, so `python3 tests/test_plugin_name.py`
runs without it and passes even when the manifest and CHANGELOG disagree. A CHANGELOG with no
release heading also raises `TypeError` instead of failing the test.

### Example scenario

A release keeps `plugin.json` at the old version; running the file directly reports OK.

### Notes for a fix

Move the main guard below every class and assert the heading exists first. Discovery
(`python3 -m unittest discover tests`) already runs it.

**Source:** gpt-6.2-astra:high, gemini-4-argon-high — phase review pass 4, project-docs phase, 2026-11-22 (was part of ENH-37).

---

<a id="ki-66"></a>

## KI-66 — progress lines can misreport a Gemini run's age and state

**Severity:** Medium
**Likelihood:** Likely
**Where:** [progress.sh](../skills/external-review/progress.sh) — `*.partial) echo`

### What happens

`progress.sh` dates a streaming Gemini run from its stderr file, so a late diagnostic resets
the clock. A `.part` left by a killed earlier attempt shows as running beside the next attempt,
and a failure with no output reads as "answer cut off". An `[agy] print timeout` setting
announcement would also be taken for a cut-off. The skill's sleep rule still says 30 minutes where
`progress.sh` warns at 25.

### Example scenario

A run killed after sleep is retried as attempt 2; the update shows attempt 1 still running.

### Notes for a fix

Record each attempt's start and end state, retire an earlier attempt's `.part` when the next
starts, and match agy's cut-off wording exactly.

**Source:** gpt-6.2-astra:high, gemini-4-argon-high (clocks), gpt-6.2-astra:high (timeout wording) — phase review pass 4, project-docs phase, 2026-11-22.

---

<a id="ki-41"></a>

## KI-41 — converting a large sequence to text has no size bound

**Severity:** Medium
**Likelihood:** Rare
**Where:** [grade_eval.py](../skills/design-review/tests/grade_eval.py) — `SAFE_CALLS = list(BUILTINS.values()) +` (`SAFE_CALLS`)

### What happens

Repetition and concatenation are bounded before allocation, but `str()` of a large list is not,
and a grade run has no timeout. A fixture that builds a list of long strings within the
sequence bound and converts it to text can allocate from tens of megabytes to many gigabytes.

### Example scenario

An answer's test builds a long list of long strings and formats it into a message. `prepare`
stalls on that answer or exhausts memory, and the whole batch waits.

### Notes for a fix

Bound the rendered size of `str`, `repr` and formatting, and run each grade with a timeout.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-43"></a>

## KI-43 — a ready reviewer probe reads as TIMEOUT when stderr mentions a timeout

**Severity:** Medium
**Likelihood:** Rare
**Where:** [preflight.sh](../skills/external-review/preflight.sh) — `if [ "$rc" = 124 ] || timed_out "$ERR"; then`

### What happens

The probe checks `timed_out "$ERR"` before it checks exit 0 and the answer `ready`. A probe
that succeeds but writes a warning containing "timed out" to stderr is reported as
`TIMEOUT — inconclusive`.

### Example scenario

A CLI logs a retried network call ("request timed out, retrying") and then answers `ready`.
Preflight reports the reviewer as inconclusive, and the review runs with less coverage than it
could have.

### Notes for a fix

Classify exit 0 with the answer `ready` first, then timeouts. Found by reading the
classification order; not reproduced with a real CLI.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-65"></a>

## KI-65 — init can leave work behind on a signal during error cleanup, and creates files at 0644

**Severity:** Medium
**Likelihood:** Rare
**Where:** [roadmap.py](../skills/project-docs/roadmap.py) — `def make_file(`

### What happens

When an ordinary I/O error starts the rollback, a signal arriving before the handlers are set
to ignore can raise out of the cleanup. The handlers are also installed before the `try` that
restores them. New files are created at 0644, which drops group write under a group-writable umask
such as 0002 that the old `open(..., "x")` honoured.

### Example scenario

A disk error on the third file, then a Ctrl-C, leaves the first two files in place.

### Notes for a fix

Keep signals blocked from the failure until `SIG_IGN` is set, enter the `try` before installing
handlers, and create files at 0666 under the caller's umask.

**Source:** gpt-6.2-astra:high, gemini-4-argon-high (signals), gpt-6.2-astra:high (file mode) — phase review pass 4, project-docs phase, 2026-11-22.

---

<a id="ki-68"></a>

## KI-68 — the name check can stop on a folder it may not read

**Severity:** Medium
**Likelihood:** Rare
**Where:** [name_check.py](../skills/project-docs/name_check.py) — `def _read(`

### What happens

`Repo._read` catches read errors, but `path.is_file()` runs before that handler. On a Python
where it raises on a denied parent folder, the whole run stops before the other docs are
checked.

### Example scenario

A doc under a folder without search (execute) permission aborts the check with a traceback.

### Notes for a fix

Run the metadata lookup inside the same handler and test a denied folder beside a real
finding.

**Source:** gpt-6.2-astra:high, gemini-4-argon-high — phase review pass 4, project-docs phase, 2026-11-22.

---

<a id="ki-71"></a>

## KI-71 — Gemini discovery blames agy when the ranker fails

**Severity:** Medium
**Likelihood:** Rare
**Where:** [external-review/SKILL.md](../skills/external-review/SKILL.md) — `agy models failed`

### What happens

Either side of the discovery pipeline can fail. When `agy models` succeeds and
`gemini-ladder.py` fails, discovery still says "agy models failed" and points at an empty
`agy-models.err`. `codex-ladder.py`'s docstring does not name `max` as a requestable effort.

### Example scenario

The ranker is missing after a partial checkout; the operator reads an empty error file.

### Notes for a fix

Keep both statuses and say which program failed; name `max` in the Codex docstring.

**Source:** gpt-6.2-astra:high, gemini-4-neon-high — phase review pass 6, project-docs phase, 2026-11-22.

---

<a id="ki-44"></a>

## KI-44 — a stale dispatch log gives a misleading replacement message

**Severity:** Low
**Likelihood:** Rare
**Where:** [evidence.py](../skills/design-review/tests/evidence.py) — `if agent is not None and rec.get("agent_id")`

### What happens

When a run is replaced through `record` while the dispatch log still names the old agent, the
check reports "replacement dispatch has not been recorded". The replacement was recorded; the
dispatch log is what is out of date.

### Example scenario

An operator re-runs `record` several times after the message. The fix was to log the new agent
with `log-dispatch --replace`.

### Notes for a fix

Name both agent IDs in the message and say which command brings the log and the manifest back
in line.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-72"></a>

## KI-72 — init's failure message overstates what it left behind

**Severity:** Low
**Likelihood:** Rare
**Where:** [roadmap.py](../skills/project-docs/roadmap.py) — `could not confirm it is ours`

### What happens

A file `init` could not identify is reported as "left in place" even if another writer has
since removed it. The CHANGELOG and `cmd_init`'s docstring still say nothing is left behind on
failure, which no longer holds for such a file.

### Example scenario

After a failed `fstat`, the message names a file that is no longer there.

### Notes for a fix

Say that removal was skipped because ownership was not confirmed, and correct the two
promises; tell the caller to inspect the path before retrying.

**Source:** gpt-6.2-astra:high, gemini-4-neon-high — phase review pass 7, project-docs phase, 2026-11-22.
