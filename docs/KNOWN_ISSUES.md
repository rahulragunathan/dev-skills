# Known Issues

Open defects, most severe first. [ROADMAP.md](ROADMAP.md) carries the one-line index; this
file carries enough detail to pick an item up without digging.

Each entry has a stable ID — use it in branch names (`bugfix/ki-02-<slug>`) and in the
CHANGELOG entry that closes it. When fixed, delete it from here and from the ROADMAP index;
the record lives in [CHANGELOG.md](../CHANGELOG.md). IDs are never reused.

Every entry carries its own source line; they come from several review passes, not one.
Entries for skills that left this repo in v2.0.0 moved with them, keeping their IDs.

## Severity

| Level | Means |
| ------- | ------- |
| **Critical** | Loses or corrupts data, or sends wrong information to real recipients. |
| **High** | Silently produces a wrong result, or reports success without doing the work. |
| **Medium** | Wrong under conditions the operator can notice or work around. |
| **Low** | Cosmetic, or wrong in a field nothing consumes. |

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
**Likelihood:** Likely
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

<a id="ki-40"></a>

## KI-40 — the roadmap check fails on freshly seeded roadmap files

**Severity:** Medium
**Likelihood:** Likely
**Where:** [phase-workflow/SKILL.md](../skills/phase-workflow/SKILL.md) — `git fetch --prune origin`

### What happens

The procedure runs `roadmap.py check || exit 1` after every roadmap edit. Roadmap files seeded
from the bundled templates still hold placeholder rows, which the check rejects, so the first
roadmap edit in a new repository stops the procedure.

### Example scenario

A new project seeds its roadmap files and the first phase files one known issue. The check
fails on the template placeholders, not on the new entry.

### Notes for a fix

Seed templates that pass the check, or let the check accept untouched placeholder rows. Add a
bats case that seeds the templates and runs the check.

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
`/localclaude:external-review plan`. `codex-root.sh` exits with `TREE IS DIRTY — commit first`.
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
