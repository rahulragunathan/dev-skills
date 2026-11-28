# Known Issues

Open defects, most severe first. [ROADMAP.md](ROADMAP.md) carries the one-line index; this
file carries enough detail to pick an item up without digging.

Each entry has a stable ID — use it in branch names (`bugfix/ki-02-<slug>`) and in the
CHANGELOG entry that closes it. How an entry enters and closes is in [ROADMAP.md](ROADMAP.md).

Every entry carries its own source line; they come from several review passes, not one.
Entries for skills that left this repo in v2.0.0 moved with them, keeping their IDs.

`roadmap.py check` reads these levels, Severity, Likelihood, Path and Area below, in row order,
from the template bundled with `project-docs`. In a project's own copy the tables are for
reading: editing them changes nothing. Severity and Likelihood are required, and ROADMAP mirrors
them. Path and Area are optional for now; check validates them when present, and ROADMAP does not
mirror them.

**Steps To Reproduce** say how to make the defect happen, from a clean start. **Example
Scenario** says why it matters, in the project's own terms.

## Severity

| Level | Means |
| ------- | ------- |
| **Critical** | Loses or corrupts data, or sends wrong information to real recipients. |
| **High** | Silently produces a wrong result, or reports success without doing the work. |
| **Medium** | Wrong under conditions the operator can notice or work around. |
| **Low** | Cosmetic, or wrong in a field nothing consumes. |

**Severity is the consequence if it fires, and nothing about how often.**

## Likelihood

| Level | Means |
| ------- | ------- |
| **Almost Always** | Anyone following the documented workflow hits it. |
| **Likely** | Hit whenever a common condition holds — a second machine, an overlapping run, a particular option. |
| **Rare** | Needs an unusual trigger, or only bites in combination with another failure. |

**Judge the harm, not the code path.** A wrong value computed on every run is `Rare` when it only
misleads after something else has already failed, and **a defect that is always present but
harmful only in combination is `Rare`**. Conversely, if a documented step is what triggers it,
that is `Almost Always` for everyone who follows the step, however unusual it looks from outside.

**Rate both, because one number cannot carry both.** `Rare · Critical` and `Almost Always · Low`
are opposite kinds of work — the first is a landmine, the second is friction — and a single
rating hides which you are looking at. Both still get fixed.

## Path

| Level | Means |
| ------- | ------- |
| **Happy Path** | The documented workflow, run normally, with ordinary inputs. |
| **Unusual Input** | Odd but legal data: strange names, exotic formats, a rarely used option. |
| **External Interference** | Another process or user writing the same files, a crash or kill mid-run, a hostile local writer, a filesystem quirk. |

## Area

| Level | Means |
| ------- | ------- |
| **Code** | The defect is in code that runs. |
| **Docs** | The defect is in prose: a skill, a README, a comment. |
| **Tests** | The defect is in a test or its fixture. |

**Path is what kind of use reaches the defect; Area is what kind of file holds it.** A README step
that breaks the workflow is `Docs` on the `Happy Path`.

---

<a id="ki-47"></a>

## KI-47 — Grading packets omit information their conditions require

**Severity:** High
**Likelihood:** Almost Always
**Where:** [grade_batch.py](../skills/design-review/tests/grade_batch.py) — `def packet_text(` (packet assembly),
[s05-report-form.md](../skills/design-review/tests/s05-report-form.md) — `omits the reason: neither a fitting existing home`

### What Happens

The grader prompt states "everything you need is in the packet below this prompt." No packet
carries the scenario prompt, and none carries S05's banned-word list, which its Rule 4 grades
against. Graders reconstruct the fixture from the answer or judge the rule without its terms.

### Example Scenario

Verified over round 9: 0 of 84 packets contain the banned list while
`s05-report-form.md` does. Two graders said so in their own judgements — one wrote "The packet
does not list the banned words" — and returned a verdict anyway. The omitted list also sits
outside the failure-condition section whose hash is reproduced, so the check cannot see it.

### Notes For A Fix

Include the scenario prompt and every rule's terms in the packet, and hash what is sent rather
than a section of it. Until then a Rule 4 verdict rests on the grader's memory of the rule.

**Source:** gpt-6-astra — review of round-9 evidence and grading, 2026-09-16; packet count
verified by claude-opus-5.

---

<a id="ki-48"></a>

## KI-48 — S07's with-skill arm is handed the answer to the condition it is graded on

**Severity:** High
**Likelihood:** Almost Always
**Where:** [s07-process-rules.md](../skills/design-review/tests/s07-process-rules.md) — `This condition is about the audit's bookkeeping` condition 2b,
`loaded-phase-workflow.md` in each round's evidence directory

### What Happens

S07 loads `phase-workflow`. Its condition 2b fails a mutation "whose predicted outcome depends on
the host", and names `local = now` and `local = now.astimezone(timezone.utc)` as the acceptable
choices. The loaded skill text supplies those same two expressions as its worked example.

### Example Scenario

Round 9 recorded S07 Mutation choice at 5/5 with-skill against 2/5 baseline. Verified: the
with-skill arm was shown the two expressions its condition grades, minutes before answering.
The result measures recall of a supplied example, not mutation reasoning.

### Notes For A Fix

Freeze the skill, then construct held-out scenarios whose answers are absent from its text. A
scenario that grades an example the skill contains cannot distinguish transfer from recall.

**Source:** gpt-6-astra — review of round-9 evidence and grading, 2026-09-16; both locations
verified by claude-opus-5.

---

<a id="ki-60"></a>

## KI-60 — Helper commands need `CLAUDE_PLUGIN_ROOT`, which a Codex install does not set

**Severity:** High
**Likelihood:** Almost Always
**Where:** [README.md](../README.md) — `reads skills as plain folders`

### What Happens

Every bundled helper is called as `$CLAUDE_PLUGIN_ROOT/skills/...`. Claude Code sets the
variable; the README's Codex install, linking each skill folder, does not. Under Codex the
commands resolve to `/skills/...` and fail. The PR body template also credits Claude Code
whoever wrote the phase.

### Example Scenario

In Codex, follow `project-docs`' set-up step: `python3 "$CLAUDE_PLUGIN_ROOT/skills/project-docs/roadmap.py" init`
runs `/skills/project-docs/roadmap.py` and fails.

### Notes For A Fix

Belongs to the Codex parity step of the setup programme: resolve helpers from the installed
skill's own folder, test the plain-folder layout with the variable unset, and name the actual
author in the PR body.

**Source:** gpt-6.2-astra:max, gemini-4-argon-high — phase review pass 1, project-docs phase, 2026-11-22.

---

<a id="ki-37"></a>

## KI-37 — A replaced evidence slot keeps its old grade

**Severity:** High
**Likelihood:** Rare
**Where:** [grade_batch.py](../skills/design-review/tests/grade_batch.py) — `jpath, rpath = out / "judgements" /`

### What Happens

`collect` treats a packet as already collected when its judgement and report exist for the
logged grader. It does not compare the packet's answer hash with the answer the evidence batch
now records. If a run is replaced after `prepare`, its old grade stays, and `agree` and
`summary` count it for an answer that is no longer in the batch.

### Example Scenario

A with-skill run is found contaminated after grading starts and is re-run with
`evidence.py log-dispatch --replace`. The evidence check passes again, `collect` reports every
packet as already collected, and the summary reports the voided answer's grade.

### Notes For A Fix

Before accepting a cached grade, compare the packet's `answer_hash` with the manifest entry for
its slot, and refuse with a message to prepare a new grading directory. Astra's F-06 fixed the
currentness check for uncached packets only. Until this is fixed, complete the evidence batch
before `prepare` and never replace a slot afterwards.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-38"></a>

## KI-38 — An assertion the test expects to fail still grades as did-not-hold

**Severity:** High
**Likelihood:** Rare
**Where:** [grade_eval.py](../skills/design-review/tests/grade_eval.py) — `self.unexecuted_guards(tail, env, scope,`

### What Happens

An `assert` inside `with pytest.raises(AssertionError):`, or inside a `try` whose handler
catches `AssertionError`, is evaluated as an ordinary guard. When it evaluates False, the
executed check reports did-not-hold, although that failure is what the test expects.

### Example Scenario

A replacement test checks that a helper rejects bad input by asserting inside
`pytest.raises(AssertionError)`. The executed check reports the assertion as did-not-hold, and a
grader reads it as a broken fixture.

### Notes For A Fix

Treat a guard whose failure is expected by the enclosing context manager or handler as
could-not-evaluate. The behaviour predates the overnight QC passes.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-77"></a>

## KI-77 — A root lockfile covers every manifest below it

**Severity:** High
**Likelihood:** Rare
**Where:** [dependency-scan.py](../skills/phase-workflow/dependency-scan.py) — `declares dependencies and has no lockfile`

### What Happens

A manifest counts as covered when its ecosystem's lockfile sits in its folder or any folder
above it. An independent project nested under a repository with a root lockfile is then never
reported, though nothing locks its versions.

### Example Scenario

`tools/web/package.json` declares dependencies and has no lockfile; the root
`package-lock.json` belongs to another app. The scan reports nothing missing.

### Notes For A Fix

Decide coverage from workspace membership (npm and pnpm workspaces, Cargo and uv workspaces) or
the lockfile's own contents, not from folder position.

**Source:** gpt-6.2-astra:high — phase review pass 1, dependable-helpers phase, 2026-11-23.

---

<a id="ki-84"></a>

## KI-84 — A dependency file whose name differs only in case can overwrite another

**Severity:** High
**Likelihood:** Rare
**Where:** [dependency-scan.py](../skills/phase-workflow/dependency-scan.py) — `def export_head(`

### What Happens

On a case-insensitive file system two committed paths that differ only in case are written to the same place. The second overwrites the first, so the scan reads one file and the other is never read.

### Example Scenario

`Web/package-lock.json` and `web/package-lock.json` are both committed. Both are exported to one place, so the scan reports one lockfile clean and never reads the other.

### Notes For A Fix

Detect a case collision while exporting and report both paths as a gap.

**Source:** gpt-6.2-astra:high, gemini-4-carbon-high — phase review pass 2, dependable-helpers phase, 2026-11-23.

---

<a id="ki-87"></a>

## KI-87 — The dependency scan still misreads some manifests

**Severity:** High
**Likelihood:** Rare
**Where:** [dependency-scan.py](../skills/phase-workflow/dependency-scan.py) — `def declares_dependencies(`

### What Happens

An inline Dart dependency map, a `dependencies:` key followed by a comment, and a Poetry table heading followed by a comment all read as declaring nothing, so a project with no lockfile reports nothing to scan: exit 0, with nothing to tell the operator a scan was missed.

### Example Scenario

A `pubspec.yaml` with `dependencies: {http: ^1.0.0}` and no `pubspec.lock` reports `no supported dependency files`.

### Notes For A Fix

Parse the supported manifest structures instead of matching lines.

**Source:** gpt-6.2-astra:high, gemini-4-carbon-high — phase review pass 3, dependable-helpers phase, 2026-11-23.

---

<a id="ki-145"></a>

## KI-145 — Six more fences act on a ref by name after checking it

**Severity:** High
**Likelihood:** Rare
**Path:** External Interference
**Area:** Docs
**Where:** [phase-workflow/SKILL.md](../skills/phase-workflow/SKILL.md) — `git push origin "$TAG_REF:$TAG_REF"`

### What Happens

The root rule added in 2.3.0 says a fence resolves each ref to a commit once, acts on that commit, and compares and swaps every ref it writes. Six places still check a ref and then act on its name: branch creation starts from the default branch's name after discovery verified it; `release-tag` verifies the tag, then fetches or pushes by name; `gate` and `publish-record` check the PR head, then act by PR number and only detect a move afterwards; external-review's capture and Codex export re-read the base and `HEAD`; `mutation-restore.sh` accepts a symbolic ref and reuses it while restoring; and `publish-release.sh` deletes a checked branch by name.

### Steps To Reproduce

1. Run `release-tag` with a git wrapper that moves the local tag to another commit just before `git push`.
2. The moved tag is pushed.
3. It should push the commit it verified, or refuse.

### Example Scenario

A ref moved between a check and its action publishes, reviews or deletes something other than what was checked.

### Notes For A Fix

Apply the root rule in each place: resolve once into a SHA variable, act on the SHA, and use `--force-with-lease`, `update-ref <ref> <new> <old>` or `--match-head-commit` for each write. Test each with the moving-ref wrapper T2's tests use.

**Source:** gpt-6.2-astra:high (implementation report, the plan's T2 list of fences that break the rule) — review-triage phase, 2026-11-27.

---

<a id="ki-49"></a>

## KI-49 — The headline tally mixes two skills

**Severity:** Medium
**Likelihood:** Almost Always
**Where:** [tests/README.md](../skills/design-review/tests/README.md) — `an unexecuted audit plan. S07 does not prove that` rollup,
[s07-process-rules.md](../skills/design-review/tests/s07-process-rules.md) — `## Rules under test`

### What Happens

S07 states `**Loads:** phase-workflow`. S01 to S06 load `design-review`. A combined tally over all
seven scenarios therefore reports two skills as one result.

### Example Scenario

Round 9's corrected figures are 33/35 with-skill against 21/35 baseline. The design-review-only
subtotal is 28/30 against 19/30; the remaining 5/5 against 2/5 belongs to `phase-workflow`.

### Notes For A Fix

Report per-skill subtotals, and never a combined figure without naming which skills it spans.

**Source:** gpt-6-astra — review of round-9 evidence and grading, 2026-09-16.

---

<a id="ki-50"></a>

## KI-50 — S05's fixture contradicts itself

**Severity:** Medium
**Likelihood:** Almost Always
**Where:** [s05-report-form.md](../skills/design-review/tests/s05-report-form.md) — `Reporting an extraction contradicts the final decision and fails.`, Final decisions

### What Happens

The final decisions say two modules "each copy the exact `taxes.round_line_tax` implementation"
and then that they "will call `taxes.round_line_tax` at that same per-line stage". Both cannot
describe the same final state.

### Example Scenario

An answer must repair the contradiction while reporting decisions as final. One baseline replicate
challenged the delivery split instead, and its Rule 2 failure cannot be separated from a
reasonable objection to the fixture's account of the existing design.

### Notes For A Fix

Give the scenario an unambiguous before-state and final-state. Until then S05's substantive result
mixes reporting quality with fixture repair.

**Source:** gpt-6-astra — review of round-9 evidence and grading, 2026-09-16.

---

<a id="ki-51"></a>

## KI-51 — Rejected grading attempts are not retained

**Severity:** Medium
**Likelihood:** Likely
**Where:** [grade_batch.py](../skills/design-review/tests/grade_batch.py) — `def load_grading(` (`collect`, replacement path)

### What Happens

Agreement is computed over retained, accepted attempts. A rejected return is replaced and its body
is not kept, so the agreement figure cannot be recomputed over everything that was actually
returned.

### Example Scenario

For one S02 condition the documented history holds three votes, implying 1 of 3 agreeing pairs,
while the retained pair contributes 1 of 1. The rejected verdict is also the one matching the
settled UNK-04 reading, so discarding it removed the disagreement.

### Notes For A Fix

Archive every return, accepted or not, with its rejection reason, and report agreement over
attempts as well as over retained pairs. This is about discarded evidence, not about how the
denominators are counted.

**Source:** gpt-6-astra — review of round-9 evidence and grading, 2026-09-16.

---

<a id="ki-36"></a>

## KI-36 — A grader quote of a table cell that holds a pipe is refused

**Severity:** Medium
**Likelihood:** Likely
**Where:** [grade_batch.py](../skills/design-review/tests/grade_batch.py) — `def unquoted(`

### What Happens

Answers are Markdown. In a table cell a pipe must be written `\|`, including inside a code
span, and renderers display it as `|`. `unquoted()` compares the grader's quote with the raw
answer text, so a quote of the rendered cell (`str | None`) does not match `str \| None`, and
`collect` refuses the judgement.

### Example Scenario

In round 9 the repeat grader for S02 baseline replicate 2 quoted
`normalise_prefix(sku: str) -> str | None` from a module table. The grade was refused and
replaced, so its verdict, a Lifetime fail, is missing from the 40/40 agreement count.

### Notes For A Fix

Replace `\|` with `|` in both the quote and the answer before matching; doing it on both sides
keeps raw quotes matching. `&#124;` is no alternative for authors, because entities are not
decoded inside code spans.

**Source:** claude-opus-5 — round-9 grading, 2026-09-14.

---

<a id="ki-39"></a>

## KI-39 — Calling `print` with an f-string argument still hides later guards

**Severity:** Medium
**Likelihood:** Likely
**Where:** [grade_eval.py](../skills/design-review/tests/grade_eval.py) — `def fixture_print(`

### What Happens

The fixture interpreter supports `print` with plain arguments but cannot evaluate an f-string
(`ast.JoinedStr`). A `print(f"x={x}")` diagnostic leaves the rest of the test body unknown, so
later independent guards report could-not-evaluate. QC test T3-2 covers only
`print("debug", x)`.

### Example Scenario

A replacement test prints `f"window={start}"` before its property assertions. The executed
checks lose every assertion after the print, and the grader gets no executed evidence for
fixture validity.

### Notes For A Fix

Evaluate `JoinedStr` and `FormattedValue` under the same size bound as string concatenation,
or skip a bare `print` statement without evaluating its arguments. Add an f-string case to
T3-2.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-137"></a>

## KI-137 — The Docker reproduction image lacks git and bash

**Severity:** Medium
**Likelihood:** Likely
**Path:** Happy Path
**Area:** Code
**Where:** [repro-sandbox.sh](../skills/external-review/repro-sandbox.sh) — `python:3-alpine "$@"`

### What Happens

Off macOS the helper runs steps in `python:3-alpine`, which has no `git` and no `bash`. A step that needs either exits 127 inside the container. The probe passed, so the helper does not exit 3, and triage step 2 allows reading instead of running only on exit 3.

### Steps To Reproduce

1. On Linux with Docker and `python:3-alpine` pulled, clone a repository into a fresh fixture.
2. Run `repro-sandbox.sh FIXTURE -- git -C repo status`.
3. It exits 127. The triager should have a sandbox with the tools, or a stated fallback.

### Example Scenario

A triager on Linux cannot run most reproduction steps, and the skill gives no way forward.

### Notes For A Fix

Let the caller name a local image with the repository's tools, keeping `--pull=never`; and say in triage step 2 that a missing tool inside the sandbox means verifying by reading.

**Source:** gemini-4-neon-high (Medium, Likely) — phase review pass 12, review-triage phase, 2026-11-27.

---

<a id="ki-41"></a>

## KI-41 — Converting a large sequence to text has no size bound

**Severity:** Medium
**Likelihood:** Rare
**Where:** [grade_eval.py](../skills/design-review/tests/grade_eval.py) — `SAFE_CALLS = list(BUILTINS.values()) +` (`SAFE_CALLS`)

### What Happens

Repetition and concatenation are bounded before allocation, but `str()` of a large list is not,
and a grade run has no timeout. A fixture that builds a list of long strings within the
sequence bound and converts it to text can allocate from tens of megabytes to many gigabytes.

### Example Scenario

An answer's test builds a long list of long strings and formats it into a message. `prepare`
stalls on that answer or exhausts memory, and the whole batch waits.

### Notes For A Fix

Bound the rendered size of `str`, `repr` and formatting, and run each grade with a timeout.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-76"></a>

## KI-76 — The probe's error classes still match loose substrings

**Severity:** Medium
**Likelihood:** Rare
**Where:** [preflight.sh](../skills/external-review/preflight.sh) — `classify_error() {`

### What Happens

`classify_error` reads any `is not available` as a model refusal, and `cut_off`, which `probe` checks before a ready answer, reads any `turn in progress` as a timeout, wherever either appears in stderr. A refusal from another service, or a successful probe
whose stderr mentions a turn, is misread, and the Codex loop's confirming probe inherits the
error.

### Example Scenario

A probe whose stderr says a proxy "is not available" confirms the model unavailable, and the
review moves to a weaker rung.

### Notes For A Fix

Match the deadline runner's own diagnostic and each CLI's model-refusal line, and exercise the
real classifier in one downshift test.

**Source:** gpt-6.2-astra:high — phase review pass 1, dependable-helpers phase, 2026-11-23.

---

<a id="ki-79"></a>

## KI-79 — A symlinked folder above the docs folder still redirects the roadmap tools

**Severity:** Medium
**Likelihood:** Rare
**Where:** [roadmap.py](../skills/project-docs/roadmap.py) — `def refuse_links(`

### What Happens

`refuse_links` checks the docs folder and the four files, not the folders above them, and the files are then opened by path. A link in a repository folder above `--docs` sends `check`, `close` and `init` outside the repository.

### Example Scenario

`project/docs` is reached through `project` linked elsewhere; `init` writes there.

### Notes For A Fix

Anchor at the repository root, check each component below it, and open files relative to a verified folder without following links; macOS's own `/var` link is above the root.

**Source:** gpt-6.2-astra:high, gemini-4-carbon-high — phase review pass 2, dependable-helpers phase, 2026-11-23.

---

<a id="ki-81"></a>

## KI-81 — The osv-scanner configuration is read by pattern, not as TOML

**Severity:** Medium
**Likelihood:** Rare
**Where:** [dependency-scan.py](../skills/phase-workflow/dependency-scan.py) — `IGNORED_ID = re.compile(`

### What Happens

The report of what a tracked `osv-scanner.toml` can suppress matches `id = ...` and `PackageOverrides` by pattern. A commented-out id is counted, a quoted key is missed, and the scope of an override (one package or an ecosystem) is not shown.

### Example Scenario

A suppression written as `"id" = "PYSEC-1"` is reported as nothing recognised.

### Notes For A Fix

Parse with `tomllib` where available, report each rule's scope and action, and name a configuration the helper cannot read.

**Source:** gpt-6.2-astra:high, gemini-4-carbon-high — phase review pass 2, dependable-helpers phase, 2026-11-23.

---

<a id="ki-88"></a>

## KI-88 — Check's table and metadata rules still differ from Markdown in places

**Severity:** Medium
**Likelihood:** Rare
**Where:** [roadmap.py](../skills/project-docs/roadmap.py) — `def structure_problems(`

### What Happens

A four-cell header over a one-cell delimiter passes as a pointer table, and a fence between header and delimiter is filtered away; an Effort in a list item after `·`, or on the line after an empty `**Effort:**`, satisfies the field; ratings are still read from the unfiltered body; closing the last entry removes only one exposed newline; `[x]: <>` with a title counts as a definition in the name check.

### Example Scenario

A fenced `**Severity:** High` example inside a KI entry supplies its rating.

### Notes For A Fix

Read tables and metadata in one section-aware pass over visible lines, with header and delimiter widths checked, and parse reference definitions once.

**Source:** gpt-6.2-astra:high, gemini-4-carbon-high — phase review pass 3, dependable-helpers phase, 2026-11-23.

---

<a id="ki-90"></a>

## KI-90 — The origin check strips a fetch URL's trailing newline

**Severity:** Medium
**Likelihood:** Rare
**Where:** [publish-release.sh](../skills/phase-workflow/publish-release.sh) — `have_fetch=`

### What Happens

The push listing keeps its final newlines, but the fetch URL is read and compared through command substitution, which strips them, so two local paths differing only in a trailing newline compare equal.

### Example Scenario

A fetch path ending in a newline passes the gate as the recorded one.

### Notes For A Fix

Read the fetch URL the same way as the push listing, with a sentinel character.

**Source:** gpt-6.2-astra:high, gemini-4-carbon-high — phase review pass 3, dependable-helpers phase, 2026-11-23.

---

<a id="ki-92"></a>

## KI-92 — Requirements reading still differs from pip in markers, extras, encodings and hash lists

**Severity:** Medium
**Likelihood:** Rare
**Where:** [dependency-scan.py](../skills/phase-workflow/dependency-scan.py) — `def read_requirements(`

### What Happens

A marker after `;` is not parsed, and an extra may end in `.`, `_` or `-`, so a pin pip rejects is still sent as `name==version`. A BOM is stripped before the encoding declaration is read, and an indented declaration counts, where pip gives the BOM precedence and reads only a line starting with `#`. A pin carrying more than 4,096 characters of options, such as 52 or more SHA-256 hashes, is reported as a gap and not scanned.

### Example Scenario

A `pip-compile --generate-hashes` file pins `numpy` with 60 wheel hashes; the scan reports the line as an option it does not read and never checks `numpy`.

### Notes For A Fix

Parse the marker and extras grammars, or report a gap for what cannot be validated; apply pip's BOM-then-declaration order; bound each option token rather than the whole option text, and read repeated hashes one by one.

**Source:** gpt-6.2-astra:high, gemini-4-neon-high — phase review pass 6, dependable-helpers phase, 2026-11-23.

---

<a id="ki-93"></a>

## KI-93 — One unreadable part of a scanner answer still hides readable advisories

**Severity:** Medium
**Likelihood:** Rare
**Where:** [dependency-scan.py](../skills/phase-workflow/dependency-scan.py) — `def package_findings(`

### What Happens

One byte that is not UTF-8 anywhere in the scanner's JSON makes the whole file's answer unreadable, so its readable advisories are not printed. One blank id or alias in a group drops the group's readable ids. Both exit 2, so the scan is never reported clean.

### Example Scenario

A lockfile's answer holds one damaged advisory beside a real one; the report says the output is unreadable and names neither.

### Notes For A Fix

Decode per string where the JSON still parses, keep each readable id, and record each malformed field as its own error.

**Source:** gpt-6.2-astra:high — phase review pass 6, dependable-helpers phase, 2026-11-23.

---

<a id="ki-94"></a>

## KI-94 — Report lines that start with a committed path can pass for findings

**Severity:** Medium
**Likelihood:** Rare
**Where:** [dependency-scan.py](../skills/phase-workflow/dependency-scan.py) — `def shown(`

### What Happens

The configuration line starts with the path of a committed `osv-scanner.toml`, so a folder named `FINDING x` makes it match a `^FINDING` reader. Escaping is not reversible: a literal backslash followed by `n` and a real line break print the same.

### Example Scenario

A committed `FINDING GHSA-x (…) p 1 a/osv-scanner.toml` folder yields a line a script counts as a finding.

### Notes For A Fix

Give every line a fixed prefix of its kind, and escape paths reversibly, backslashes included.

**Source:** gpt-6.2-astra:high — phase review pass 6, dependable-helpers phase, 2026-11-23.

---

<a id="ki-95"></a>

## KI-95 — Publish-record still reads a short hex answer as a moved head

**Severity:** Medium
**Likelihood:** Rare
**Where:** [phase-workflow/SKILL.md](../skills/phase-workflow/SKILL.md) — `# fence: publish-record`

### What Happens

A head that is lowercase hex but not a full object ID, such as `abc` or `502`, is reported as a confirmed push rather than an unreadable head. The record is read after the last check before the edit, so a head that moves during the read is found only after the body is replaced. Command substitution drops the record's trailing newlines, so the published copy can differ from the file at its end.

### Example Scenario

`gh` answers `502` after the edit; the step says the PR head moved, and the operator looks for a push that never happened.

### Notes For A Fix

Require the full width of `GATE_SHA` before reporting movement, read the record before the pre-edit checks, and keep the record's bytes as they are.

**Source:** gpt-6.2-astra:high, gemini-4-neon-high — phase review pass 6, dependable-helpers phase, 2026-11-23.

---

<a id="ki-109"></a>

## KI-109 — The optional-field reader still differs from Markdown in three ways

**Severity:** Medium
**Likelihood:** Rare
**Path:** Unusual Input
**Area:** Code
**Where:** [roadmap.py](../skills/project-docs/roadmap.py) — `def optional_problems(`

### What Happens

`optional_problems` reads a field after any `·`, including one inside a backticked Where fragment; ends the metadata block only on a line that starts with `###` and one space, so an indented heading or one followed by a tab does not end it; and matches only the exact label, so a mis-cased `**path:**` is treated as absent.

### Steps To Reproduce

1. Start each case from its own copy of a valid KI with `**Path:** Happy Path`.
2. Case one: make its Where cite [roadmap.bats](../skills/project-docs/tests/roadmap.bats) with the fragment `grep -qF '**Likelihood:** Rare · **Path:** Sometimes'`, which occurs once in that file. Check reports `repeated Path`; it should pass.
3. Case two: indent `### What Happens` by two spaces and put `**Path:** Sometimes` on its own line below it. Check reports `repeated Path`; it should pass.
4. Case three: change only the label, to `**path:** Happy Path`. Check reports nothing; it should report the mis-cased label.

### Example Scenario

A known issue that cites a line of this very test file is refused.

### Notes For A Fix

Mask code spans before finding field boundaries, accept up to three spaces and any blank after `###`, and report a mis-cased known label. KI-88 is the same family for the rated fields.

Steps rewritten in pass 2 (gpt-6.2-astra:high), so each case starts from a valid entry.

Case one's citation corrected in pass 3 (gpt-6.2-astra:high): it names the file that holds the fragment.

**Source:** gpt-6.2-astra:high — phase review pass 1, review-triage phase, 2026-11-26.

---

<a id="ki-116"></a>

## KI-116 — Progress hides an unavailable rung that left output

**Severity:** Medium
**Likelihood:** Rare
**Path:** Unusual Input
**Area:** Code
**Where:** [progress.sh](../skills/external-review/progress.sh) — `rung_answered() {`

### What Happens

`rung_answered` counts any non-empty output of the same attempt as an answer, the rung's own included, and does not check the other rung's state. An unavailable rung that left output is reported as nothing at all, and a rung beside a failed one that left bytes is hidden as if that one had answered.

### Steps To Reproduce

1. In an empty folder, write `partial` to `codex_phase_p1_c1_a1_m_high.txt` and `unavailable` to its `.state`.
2. Run `progress.sh <folder> 1`.
3. Nothing is printed. It should print `codex c1: unavailable — 8 bytes, not an answer`.

### Example Scenario

A downshift that leaves an error message in its output disappears from the five-minute update.

### Notes For A Fix

Skip the rung's own file, and count another rung only when its state is `done` or absent. Add a bats case for an unavailable rung with output, and one where `a2` is unavailable beside `a1`'s answer, so the per-attempt scope is pinned. A regression from this phase's KI-111 fix.

**Source:** gpt-6.2-astra:high, gemini-4-neon-high — phase review pass 5, review-triage phase, 2026-11-27.

---

<a id="ki-119"></a>

## KI-119 — The record's user-only edit rule blocks settling a retried row

**Severity:** Medium
**Likelihood:** Rare
**Path:** External Interference
**Area:** Docs
**Where:** [external-review/SKILL.md](../skills/external-review/SKILL.md) — `Only the user reopens a row`

### What Happens

When an incomplete pass's retry completes, its waiting `Unfixed Blocker` rows are settled as for any complete pass, and that is not a change by the user. Loop step 1 still says "later, only the user changes a row", and the `Unfixed Blocker` definition says the row waits for the user. An agent can keep a fixed defect labelled unfixed.

### Steps To Reproduce

1. On pass 1, let one reviewer confirm a blocker and the other time out; record `Unfixed Blocker`.
2. Let the retry succeed and fix the blocker.
3. Step 1 forbids changing the row. It should allow the same pass's settlement, and keep the user-only rule for settled rows.

### Example Scenario

A retried pass hands off a fixed blocker as unfixed.

### Notes For A Fix

Limit the user-only rule to rows of completed passes, and say a waiting row becomes `Fixed In Phase` once its fix and evidence exist. KI-108's remainder.

**Source:** gpt-6.2-astra:high — phase review pass 5, review-triage phase, 2026-11-27.

---

<a id="ki-121"></a>

## KI-121 — A document fix on an incomplete pass has no disposition while it waits

**Severity:** Medium
**Likelihood:** Rare
**Path:** Unusual Input
**Area:** Docs
**Where:** [external-review/SKILL.md](../skills/external-review/SKILL.md) — `While it waits, a confirmed blocking row`

### What Happens

The document-fix exception applies only on a complete pass. While an incomplete pass waits for its retry, a non-blocking document fix falls to the ordinary order and is filed. Retry settlement covers only the waiting `Unfixed Blocker` rows, so the filed row never becomes `Fixed In Phase`.

### Steps To Reproduce

1. On pass 1, let one reviewer time out and the other report a Low CHANGELOG correction that you verify and agree with.
2. Apply the disposition order while the retry waits: the row is filed.
3. Complete the retry and settle the pass. The row should wait and then be fixed, not filed.

### Example Scenario

A pass with a failed reviewer files a one-word release-note fix as a roadmap entry.

### Notes For A Fix

Let a document fix from an incomplete pass wait with no disposition until the pass completes, and widen retry settlement to every confirmed row of that pass. Distinct from KI-119, which is about the user-only edit rule.

**Source:** gpt-6.2-astra:high (External Interference, Medium, Rare) and gemini-4-neon-high (Unusual Input, Medium, Rare) — phase review pass 9, review-triage phase, 2026-11-27.

---

<a id="ki-130"></a>

## KI-130 — The gate's unreviewed-fix sentence ignores an accepted coverage gap

**Severity:** Medium
**Likelihood:** Rare
**Path:** External Interference
**Area:** Docs
**Where:** [external-review/SKILL.md](../skills/external-review/SKILL.md) — `Nothing is fixed-and-unreviewed but a document fix`

### What Happens

When every reviewer of a follow-up pass fails and the user decides to land anyway, a code fix is unreviewed. The coverage section says so, while the gate sentence says only a document fix can be.

### Steps To Reproduce

1. Fix a pass-1 blocker, let every pass-2 reviewer fail on quota, and record the user's decision to land.
2. Prepare the hand-off.
3. The two statements contradict each other. The gate should name the uncovered fix commits.

### Example Scenario

The hand-off says two opposite things about the same commit.

### Notes For A Fix

Qualify the sentence by successful coverage, and name the uncovered fix commits beside the user's decision.

**Source:** gpt-6.2-astra:high — phase review pass 10, review-triage phase, 2026-11-27.

---

<a id="ki-138"></a>

## KI-138 — Prune can delete a branch a worktree is rebasing

**Severity:** Medium
**Likelihood:** Rare
**Path:** Unusual Input
**Area:** Docs
**Where:** [phase-workflow/SKILL.md](../skills/phase-workflow/SKILL.md) — `grep -Fxq "branch refs/heads/$b" <<< "$WORKTREES"`

### What Happens

Prune now deletes with `update-ref -d` and checks worktrees itself. During a rebase or bisect the worktree's HEAD is detached, so `git worktree list --porcelain` shows no branch line for it. The old `git branch -D` refused here (`used by worktree`); the new check does not.

### Steps To Reproduce

1. Make a merged branch whose upstream is gone, and check it out in a linked worktree.
2. Start an interactive rebase on it in that worktree, stopping at an `edit`.
3. Run the prune block. The branch is deleted. It should be retained, as `git branch -D` would.

### Example Scenario

A rebase in progress loses its branch ref, and its tracking config.

### Notes For A Fix

Retain the branch when any worktree's `rebase-merge/head-name`, `rebase-apply/head-name` or bisect start names it; or retain every gone branch while any worktree is detached. A regression of T2's change (KI-80).

**Source:** gemini-4-neon-high (Medium, Rare) — phase review pass 12, review-triage phase, 2026-11-27.

---

<a id="ki-139"></a>

## KI-139 — First push cannot set the upstream in a single-branch clone

**Severity:** Medium
**Likelihood:** Rare
**Path:** Unusual Input
**Area:** Docs
**Where:** [phase-workflow/SKILL.md](../skills/phase-workflow/SKILL.md) — `git branch --set-upstream-to="origin/$PHASE_BRANCH" "$PHASE_BRANCH"`

### What Happens

The first push now pushes a commit, not the branch, and sets the upstream afterwards. In a clone whose fetch refspec names only the default branch, the push makes no `origin/<branch>` tracking ref, so setting the upstream fails. A retry then fails the lease, since the remote branch exists.

### Steps To Reproduce

1. Clone with `--single-branch`, make the phase branch and commit its record.
2. Run the first-push block.
3. The push succeeds and the upstream step exits 128. It should set the upstream, as `git push -u` did.

### Example Scenario

Phase start stops halfway, and a plain retry cannot finish it.

### Notes For A Fix

Write `branch.<name>.remote` and `branch.<name>.merge` with `git config`, which is what `push -u` does. A regression of T2's change (KI-80).

**Source:** gemini-4-neon-high (Medium, Rare) — phase review pass 12, review-triage phase, 2026-11-27.

---

<a id="ki-140"></a>

## KI-140 — The repro-sandbox tests miss several of the helper's guards

**Severity:** Medium
**Likelihood:** Rare
**Path:** Happy Path
**Area:** Tests
**Where:** [repro-sandbox.bats](../skills/external-review/tests/repro-sandbox.bats) — `repro: a child cannot connect to a live host loopback listener`

### What Happens

On Linux the loopback test passes without `--network none`, because a container's 127.0.0.1 is its own. The Docker and macOS launcher tests use fakes and check only some flags, so removing `--read-only`, `--cap-drop=ALL`, `no-new-privileges` or `--user` stays green. No test makes the start probe fail, so dropping `|| unavailable` stays green.

### Steps To Reproduce

1. Remove `--cap-drop=ALL` from the Docker launcher.
2. Run `repro-sandbox.bats`.
3. All tests pass. One should fail.

### Example Scenario

A weakened sandbox ships with a green suite.

### Notes For A Fix

Assert every Docker hardening flag in the launcher test; add a test whose fake backend fails the probe and expects exit 3 with the command not run; on Linux, test the network by reaching a non-loopback host address.

**Source:** gemini-4-neon-high (Medium, Rare) — phase review pass 12, review-triage phase, 2026-11-27.

---

<a id="ki-144"></a>

## KI-144 — The macOS sandbox reads all of /opt/homebrew and /Library

**Severity:** Medium
**Likelihood:** Rare
**Path:** External Interference
**Area:** Code
**Where:** [repro-sandbox.sh](../skills/external-review/repro-sandbox.sh) — `(subpath "/Library") (subpath "/opt/homebrew")`

### What Happens

The profile allows reading all of `/opt/homebrew` and `/Library`, for the runtimes a step needs. Those trees also hold Homebrew service data and configs (`/opt/homebrew/var`, `/opt/homebrew/etc`) and machine-wide application data, which a reproduction step can read.

### Steps To Reproduce

1. Put a synthetic secret in `/opt/homebrew/etc`.
2. Run `repro-sandbox.sh FIXTURE -- cat` on it.
3. It prints the file. It should be refused.

### Example Scenario

A hostile reproduction step reads a local service's credentials. The network is denied, so it can only print them into the triager's transcript.

### Notes For A Fix

Narrow the reads to the runtime subtrees (`/opt/homebrew/bin`, `Cellar`, `opt`, `lib`, `Frameworks`, `share`; `/Library/Frameworks`, `/Library/Developer`).

**Source:** gemini-4-neon-high (Medium, Rare) — phase review pass 12, review-triage phase, 2026-11-27.

---

<a id="ki-82"></a>

## KI-82 — The zsh lint misses traps hidden by quotes and other subscripts

**Severity:** Low
**Likelihood:** Likely
**Where:** [test_skill_text.py](../tests/test_skill_text.py) — `def unquoted(`

### What Happens

`unquoted` blanks text between any two apostrophes, including ones inside double quotes, so code between them is not linted; `${A[$i]}`, `A[0]=` and a variable after the first word of a `for` list are not flagged.

### Example Scenario

`echo "can't"; for m in $RUNGS; do echo "it's"; done` passes the lint.

### Notes For A Fix

Track quote state per character, and widen the subscript and word-list patterns, with fixtures for each.

**Source:** gpt-6.2-astra:high, gemini-4-carbon-high — phase review pass 2, dependable-helpers phase, 2026-11-23.

---

<a id="ki-44"></a>

## KI-44 — A stale dispatch log gives a misleading replacement message

**Severity:** Low
**Likelihood:** Rare
**Where:** [evidence.py](../skills/design-review/tests/evidence.py) — `if agent is not None and rec.get("agent_id")`

### What Happens

When a run is replaced through `record` while the dispatch log still names the old agent, the
check reports "replacement dispatch has not been recorded". The replacement was recorded; the
dispatch log is what is out of date.

### Example Scenario

An operator re-runs `record` several times after the message. The fix was to log the new agent
with `log-dispatch --replace`.

### Notes For A Fix

Name both agent IDs in the message and say which command brings the log and the manifest back
in line.

**Source:** claude-opus-5 — adversarial code review of the overnight QC passes, 2026-09-14.

---

<a id="ki-78"></a>

## KI-78 — Index rows are not bound to their section

**Severity:** Low
**Likelihood:** Rare
**Where:** [roadmap.py](../skills/project-docs/roadmap.py) — `def index_rows(`

### What Happens

`index_rows` finds a KI row anywhere in ROADMAP.md, so a known-issue row under the Enhancements
heading reconciles.

### Example Scenario

A KI row pasted into the Enhancements table passes `check`.

### Notes For A Fix

Read rows per section, and refuse a row whose prefix does not belong to its section's table.

**Source:** gpt-6.2-astra:high — phase review pass 1, dependable-helpers phase, 2026-11-23.

---

<a id="ki-83"></a>

## KI-83 — The name check misses multi-line reference definitions and counts test fixtures as scripts

**Severity:** Low
**Likelihood:** Rare
**Where:** [name_check.py](../skills/project-docs/name_check.py) — `REFDEF_LABEL = re.compile(`

### What Happens

A reference definition whose destination is on the next line is not read, so its uses are reported. Bare script names resolve against every tracked file, test fixtures included, and a name with two matches leaves the line's lone flags unchecked.

### Example Scenario

`[guide]:` followed by an indented `guide.md` line reports `[guide]` as undefined.

### Notes For A Fix

Join a definition with its continuation line; leave fixture folders out of the basename map.

**Source:** gpt-6.2-astra:high, gemini-4-carbon-high — phase review pass 2, dependable-helpers phase, 2026-11-23.

---

<a id="ki-85"></a>

## KI-85 — The release test reads only plain X.Y.Z headings

**Severity:** Low
**Likelihood:** Rare
**Where:** [test_plugin_name.py](../tests/test_plugin_name.py) — `class ReleaseVersionTest`

### What Happens

A pre-release heading such as `## [2.2.0-rc.1]` is skipped, so the test compares the manifest with the release below it.

### Example Scenario

plugin.json keeps 2.1.0 while CHANGELOG prepares 2.2.0-rc.1; the test passes.

### Notes For A Fix

Read the first heading that is not `[Unreleased]` and compare its full version.

**Source:** gpt-6.2-astra:high, gemini-4-carbon-high — phase review pass 2, dependable-helpers phase, 2026-11-23.

---

<a id="ki-89"></a>

## KI-89 — Progress calls a finished Gemini attempt running when its answer could not be moved

**Severity:** Low
**Likelihood:** Rare
**Where:** [progress.sh](../skills/external-review/progress.sh) — `A final state is authoritative`

### What Happens

When the move of a finished answer fails, the loop still writes `done`, and progress, which treats only failed, cut-off and unavailable as final for a `.part`, reports it running. An earlier attempt that left only an `unavailable` state is not marked superseded.

### Example Scenario

A full disk fails the move after a complete answer; the update keeps saying running.

### Notes For A Fix

Write `done` only after the move succeeds, treat `done` with a `.part` as missing evidence, and apply supersession to state-only attempts.

**Source:** gpt-6.2-astra:high, gemini-4-carbon-high — phase review pass 3, dependable-helpers phase, 2026-11-23.

---

<a id="ki-96"></a>

## KI-96 — The Gemini prompt measurement can still accept a count it should refuse

**Severity:** Low
**Likelihood:** Rare
**Where:** [external-review/SKILL.md](../skills/external-review/SKILL.md) — `# fence: gemini-loop`

### What Happens

The loop does not set `pipefail`, so a failed producer before a successful `wc` still gives a count, and removing all whitespace turns two fields such as `1 2` into `12`. The precheck example reports a failed measurement through `echo`, which succeeds.

### Example Scenario

A `wc` shim that prints `1 2` lets a prompt through as 12 bytes.

### Notes For A Fix

Measure in one checked step that requires every stage to succeed and exactly one decimal field, and use it in both places. The comment explaining pipeline status is an ENH-32 case.

**Source:** gpt-6.2-astra:high — phase review pass 6, dependable-helpers phase, 2026-11-23.

---

<a id="ki-91"></a>

## KI-91 — Init and close can lose their caller's signal handler while registering their own

**Severity:** Low
**Likelihood:** Rare
**Where:** [roadmap.py](../skills/project-docs/roadmap.py) — `def cmd_init(`

### What Happens

A signal delivered between installing a handler and saving the one it replaced leaves `init`'s or `close`'s handler installed in a caller that imported it; both register handlers the same way.

### Example Scenario

A test harness imports `roadmap.py`, sends SIGINT during `cmd_init`, and keeps a handler that raises.

### Notes For A Fix

Block the managed signals while registering and recording, then restore the caller's mask.

**Source:** gpt-6.2-astra:high, gemini-4-carbon-high — phase review pass 3, dependable-helpers phase, 2026-11-23.

---

<a id="ki-102"></a>

## KI-102 — An empty Likelihood reads the Path line below it as its value

**Severity:** Low
**Likelihood:** Rare
**Path:** Unusual Input
**Area:** Code
**Where:** [roadmap.py](../skills/project-docs/roadmap.py) — `val = spelled(match[1].strip()) if match else ""`

### What Happens

The rated fields are read with `\s*` after the label, which crosses a line break. The template now puts `**Path:**` on the line after Likelihood, so a blank Likelihood takes the Path line as its value.

### Steps To Reproduce

1. Fill the KI template's sample entry, leave `**Likelihood:**` blank, and set `**Path:** Happy Path` below it.
2. Run `roadmap.py check`.
3. It reports `unknown Likelihood: KI-01 (**Path:** Happy Path)`. It should say the Likelihood is empty.

### Example Scenario

Someone filing a known issue in a hurry is pointed at the wrong field.

### Notes For A Fix

Read the rated fields with `[ \t]*`, as the optional fields already are, keeping the whole-body search the existing roadmaps rely on.

**Source:** `/code-review high` — phase end, review-triage phase, 2026-11-26. Path, Area and steps supplied by the triager.

---

<a id="ki-120"></a>

## KI-120 — Two blocking sets of ratings leave a merged row's filing open

**Severity:** Low
**Likelihood:** Rare
**Path:** Unusual Input
**Area:** Docs
**Where:** [external-review/SKILL.md](../skills/external-review/SKILL.md) — `else the set that decided a blocking disposition`

### What Happens

A filed merged row takes the set that decided a blocking disposition. When both reviewers' sets block and you then file the row at the gate, both decided it, and the rule does not say which to take.

### Steps To Reproduce

1. Merge two confirmed reports rated High · Happy Path · Rare and High · Unusual Input · Almost Always; both block.
2. At the gate, file the row instead of fixing it.
3. Two sets qualify. The rule should choose one, for example by the same Severity, Likelihood and Path order.

### Example Scenario

Two agents file the same row with different ratings.

### Notes For A Fix

Apply the Severity, then Likelihood, then Path order to the qualifying sets too. (The Path order itself is stated in the Path column rule.)

**Source:** gemini-4-neon-high — phase review pass 5, review-triage phase, 2026-11-27.

---

<a id="ki-141"></a>

## KI-141 — The signed-bookkeeping test misses signature text in the printed patch

**Severity:** Low
**Likelihood:** Rare
**Path:** Unusual Input
**Area:** Tests
**Where:** [phase-git.bats](../skills/phase-workflow/tests/phase-git.bats) — `after review: signed bookkeeping passes with signature display enabled`

### What Happens

Removing `--no-show-signature` from the patch log, and only there, leaves the test green: it checks that the patch appears, not that signature text does not. The wording test still catches the removal.

### Steps To Reproduce

1. Remove `--no-show-signature` from the fence's `git log -p`.
2. Run the signed-bookkeeping test.
3. It passes. It should fail.

### Example Scenario

The behavioural test does not pin one of the two flags it covers.

### Notes For A Fix

Assert the output holds no signature line.

**Source:** gemini-4-neon-high (Low, Rare) — phase review pass 12, review-triage phase, 2026-11-27.

---

<a id="ki-142"></a>

## KI-142 — The per-pass severity and kind counts have no rule for a split finding

**Severity:** Low
**Likelihood:** Rare
**Path:** Unusual Input
**Area:** Docs
**Where:** [external-review/SKILL.md](../skills/external-review/SKILL.md) — `Count rows in disposition tallies and note each split.`

### What Happens

The trend counts base IDs and disposition tallies count rows. The per-pass block's counts by severity, of findings in earlier fixes, and of documentation drift say neither, so halves with different severities or kinds can be counted either way.

### Steps To Reproduce

1. Split a finding into a Low document half and a High code half.
2. Write the pass's block.
3. Nothing says whether it counts once or twice, or at which severity.

### Example Scenario

Two triagers write different counts for the same pass.

### Notes For A Fix

Say the per-pass counts follow the disposition tallies: rows, noting each split.

**Source:** gemini-4-neon-high (Low, Rare) — phase review pass 12, review-triage phase, 2026-11-27.

---

<a id="ki-143"></a>

## KI-143 — The gate's land-by-default rule misses a pass whose only blocker was a document fix

**Severity:** Low
**Likelihood:** Rare
**Path:** Unusual Input
**Area:** Docs
**Where:** [external-review/SKILL.md](../skills/external-review/SKILL.md) — `After a complete pass with no blocking finding, recommend landing by default.`

### What Happens

The loop stops on a pass whose only blocking rows are document fixes, as if it had none. The gate's recommendation rule names only a pass with no blocking finding, so read literally it does not cover that pass.

### Steps To Reproduce

1. Finish a pass whose only blocking row is a document fix, and make the fix.
2. Read the gate's recommendation rule.
3. It does not say to recommend landing. It should.

### Example Scenario

The recommendation default does not apply where the stop rule says the pass is clean.

### Notes For A Fix

Write `no blocking finding other than a document fix`, as the stop rule does.

**Source:** gemini-4-neon-high (Low, Rare) — phase review pass 12, review-triage phase, 2026-11-27.
