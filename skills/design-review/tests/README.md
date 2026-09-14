# Pressure tests for `design-review`

Each scenario defines a normal-work artifact and failure conditions judged from that artifact.
Run each prompt in a fresh agent with and without the indicated skill. Re-run affected pairs
when their prompt, conditions or loaded skill changes.

The scenario tables retain rounds 1–7 on `claude-opus-5`. Round 4 is the latest complete
paired batch recorded across all seven scenarios, but its S01/S02 fixtures are superseded.
Round 7 is a **partial batch: 23 of 42 declared answers**. It contains two answers per arm for
S01, three per arm for S02, three baselines each for S03–S06, and two baselines plus three
with-skill answers for S07. S03–S06 have no round-7 with-skill answers or round-7 Results rows.
The rollup below uses the latest Results rows, and labels their batch and revision separately.
It does not turn ungraded archived answers into results.
Provenance is tracked per scenario, not per repository — `evidence.py check` recomputes each
scenario's loaded-skill hash, prompt hash and condition hash, so it can say which single scenario
has gone stale. A repository-wide SHA could only mark everything stale or nothing, which is how
S07's evidence outlived two changes to `phase-workflow`.

Several grades have been corrected across rounds, always in the same direction — see
*Corrections* below.

## What a unit's result means

Report observed passes and denominators for each arm, prompt revision, condition revision and
loaded-skill hash. A single artifact can receive a supported grade; one run cannot establish an
outcome rate. Disagreement among retained runs describes the sample, not a stable property of
the model. Historical labels such as “Unstable” mean only that the recorded sample contains
both passes and failures.

Three passes out of three are three observed successes. A process with a 50% success probability
would produce that outcome 12.5% of the time. Under independent, identically distributed trials,
the exact two-sided 95% binomial interval for 3/3 is approximately 29%–100%. Those assumptions
may not hold for these runs. Do not claim reliability or a causal improvement from these tallies.
Quoting an instruction shows instruction uptake, not proof that the instruction caused a pass.

For a future comparison, choose the sample size and stopping rule before dispatch. Record every
scheduled replicate, including failures and incomplete runs; do not increase the sample only
when the first three disagree. These historical batches used different sampling decisions and
must remain descriptive.
Transcripts, dispatched prompts and hash-verified skill snapshots are archived
outside the repo, under this project's artifact folder — the standard home for run evidence, one
dated directory per round — at
`Claude-Projects/Project Artifacts/Plugins/localclaude/design-review-evidence-<date>/`.

## Which model to run on

Use the exact model that will follow the skill in the main session. Record its full provider
model identifier from the execution record, not a family label such as "Opus" or a date.
Both members of a pair use the same model identifier and settings. Do not infer an identifier
for retained evidence whose runner recorded only the family.

## When a recorded row expires

A row is valid only for the recorded prompt, failure conditions and loaded skill text.
Changing a prompt or condition expires both runs unless the original output can be judged
fully against the new condition. A changed loaded skill expires its with-skill run; an unchanged
baseline prompt and condition do not expire merely because the skill changed.

Mark invalid evidence **Expired — `<one-line reason>`** in its Evidence status cell. Keep its
recorded grade. Unknown revision or model metadata also makes a row expired. Do not backfill
missing provenance with today's HEAD or a guessed model. Unknown means unknown.

For each new run, record:

- Exact model identifier, date, run ID and relevant model settings.
- Prompt revision and condition revision: the scenario's git commit SHA and section content
  hashes, with the verbatim dispatched prompt retained as an artifact.
- Skill git commit SHA and file path for each loaded skill, plus a content hash of the loaded
  text. Record `not loaded` for a baseline. S01–S06 load `skills/design-review/SKILL.md`;
  S07 loads `skills/phase-workflow/SKILL.md`.
- Output artifact path and content hash, each condition's result, and the paired rule grade.

Use committed snapshots for revision identifiers. If the runner tests uncommitted edits, record
both the base git SHA and an archived patch with its hash, plus the exact prompt, condition and
loaded-skill hashes. A git SHA alone must never claim to identify a dirty working-tree revision.
The artifact archive belongs to the runner's evidence store; do not put a guessed outcome here.

## How to run one

Dispatch only the scenario's **Prompt** verbatim to a fresh agent. Supply no expected output,
failure conditions, result notes or prior conversation. Keep fixture, prompt and settings
identical within the pair.

- **Without-skill run** — load no skill.
- **With-skill run** — additionally load the skill specified above, from the recorded snapshot.

The evaluator reads **Failure conditions** and the resulting artifacts. Do not prompt the
agent to spot its mistake afterwards. Missing required artifacts fail the relevant conditions.
Run definitions are text-only; S06 supplies source diagrams without rendering, and S07 produces
an unexecuted audit plan. S07 does not prove that an agent executed cleanup or mutation scripts.

## Running a batch

A batch is many runs of the procedure above, recorded into one evidence directory. Follow
these steps in order. Each one exists because round 8 broke without it.

1. **Work from the repository root.** The manifest stores repository-relative paths, so
   `evidence.py check` run from any other directory reports every scenario `EXPIRED — skill
   file is gone; scenario file is gone`.

   ```bash
   python3 skills/design-review/tests/evidence.py init <dir> --round <n> \
     --model <model-id> --replicates <r>
   ```

2. **Dispatch each run as a fresh agent on the main model.** A without-skill run receives
   `<scenario>-prompt.txt` verbatim. A with-skill run receives one short paragraph telling it
   to read `loaded-<skill>.md` in full first, then the prompt verbatim. `record` checks that
   the recorded prompt appears inside the first user message, so the paragraph is allowed.
   Only a without-skill run is refused for using a tool.
3. **Log every dispatch when it happens.** Append one tab-separated line per run:
   `scenario`, `arm`, `replicate`, agent ID. Write the line as soon as the dispatch returns
   the ID, not afterwards from memory.
4. **Record from the log, and only from the log.** A run's transcript is
   `subagents/agent-<id>.jsonl` under the dispatching session. Never find transcripts by
   searching for prompt text. Earlier rounds dispatched the same prompts, and a content match
   wrote 56 answers from rounds 5–7 into a new round-8 manifest. If that happens, delete the
   evidence directory and start again from step 1. Do not try to repair the manifest.
5. **Read each refusal before acting on it.** `is incomplete` or `carries no assistant
   answer` means the run is still generating: record it again later. `baseline is
   contaminated` means the run used a tool: dispatch a new run for the same slot and replace
   that line's agent ID in the log. Never edit the recorded answer.
6. **Dispatch in waves.** Concurrent agents are capped (20 during round 8). A dispatch over
   the cap fails at once and leaves no transcript, so do not write a log line for it.
7. **Finish with the completeness check** from the repository root. Grading starts only when
   every scenario reports `current`:

   ```bash
   python3 skills/design-review/tests/evidence.py check <dir> --require-complete
   ```

## Execute the grading checks

`grade.py` reads an answer without editing it, executing production code, dispatching an agent,
or writing Results. Run it before a human grades the artifact:

```bash
python3 skills/design-review/tests/grade.py \
  --scenario skills/design-review/tests/s07-process-rules.md --answer /path/to/answer.md
```

Alternatively select a recorded answer with `--evidence /path/to/batch --arm baseline
--replicate 1`. This checks the answer hash and requires matching grading conditions. Add
`--json` for machine-readable output. Exit 0 means every condition has a supported pass;
1 means a supported failure, 2 means questions remain open, and 3 means invalid input.

The evaluator extracts fenced Python and evaluates pre-production assertions with the supplied
constants. Each assertion reports **held**, **did-not-hold**, or **could-not-evaluate**. Datetime
arithmetic, explicit ZoneInfo conversions and `lru_cache` decorators use Python's real standard
library. It never substitutes a guessed Account object or a guessed pytest fixture. Unsupported
imports, mutation of fixture objects, control flow and host timezone assumptions remain visible
evaluation gaps. A guard's dependencies must be supplied before it can support a result.

S07's three production entry points are recognized automatically. Nonstandard imported function
calls also delimit production; add `--production qualified.name` for another boundary. Assertions
after the first production call are excluded. Multiple guards are diagnostic evaluations; a
prior false guard already prevents the real test from reaching production. This harness does
not run pytest or certify mutation predictions. Its Bats suite includes a verbatim fenced Python
excerpt from the real round-7 S07 baseline whose 23-hour guard fails.

S05 scans banned verdict words, silent-check names, and literal cues for its three required
decisions. A match includes its line and surrounding text. Literal cues cannot prove a concrete
resolution, distinguish a legitimate operation name from a silent verdict, or recognize all
paraphrases. Those judgements remain open, alongside the extracted module/dependency tables,
code, diagrams, diff and complete answer. All other scenario failure conditions likewise appear
as explicit questions; a held fixture assertion never grants a design unit a pass.

To record a human judgement for the report, pass `--judgements /path/to/judgements.json`:

```json
{
  "reviewer": "Human grader name",
  "answer_hash": "copy from harness output",
  "condition_hash": "copy from harness output",
  "judgements": {
    "1": {
      "verdict": "pass",
      "reason": "Explain why the artifact satisfies condition 1",
      "evidence": "Quote the relevant artifact rows or lines"
    }
  }
}
```

Use the condition IDs printed by the harness, including `2b` for S07 Mutation choice. Omitted
conditions stay open. Every human judgement requires a reviewer, reason, evidence and matching
hashes. Passing a condition the harness failed on an executed fixture assertion additionally
requires a `disputes` list naming the failing check IDs, and those IDs must be checks that
actually did not hold. The dissent is recorded on the condition as `overrides`. This exists
because S07 asks the answer to diagnose a supplied broken guard, so a correct answer quotes
that guard and the evaluator cannot tell quoted code from authored code. Transfer approved
grades separately with
`write_results.py`, naming only the cells to change. The writer refuses malformed tables;
`--repair-layout` accepts an explicit JSON mapping with a separator repair flag and hash-bound
rows whose `set` object names every resulting column. It never infers displaced cells.

## Produce, don't spot

S01–S04 require the module design the agent would build. S05 requires the actual report. S06
requires diagram sources and a source diff. S07 requires coverage, per-test mutation predictions
and replacement test code. An acknowledgement, trade-off paragraph, future fix or refusal to
certify cannot substitute for these artifacts. A design that retains the forbidden structure
fails even when its author names the flaw.

## A rule the model already follows is not proven

A correct baseline supplies no evidence that the skill changed behavior. Check whether the
scenario telegraphed the answer, the condition tested the wrong thing, or the model already
handled the case. Record the suspected explanation from the artifact. Repair defective cases
and re-run both sides. Do not label a rule proven from a successful with-skill run alone.

## Result vocabulary

| Run | Outcome | Means |
| --- | --- | --- |
| Without skill | Rule needed | The artifact contains the flaw. |
| Without skill | Rule not needed here | The artifact avoids the flaw without the skill. |
| Without skill | Rule defective | The forbidden artifact is correct for the stated requirements. |
| Without skill | Scenario defective | Fixture ambiguity or answer cues prevent a useful comparison. |
| With skill | Rule works | The required artifact meets every applicable failure condition. |
| With skill | Rule ineffective | The artifact fails at least one applicable condition. |

Evidence status is separate from grade. **Expired** is not a new grade. Legacy wording such as
`passed` remains a historical grade and must not be interpreted as a current paired result.

## Coverage

These are the fifteen coverage units. Conditions within a unit are subcases, not extra rules.
The twelve `design-review` units cover six checks, four report rules and two diagram rules;
three `phase-workflow` units cover the process scenario.

| Unit | Scenario | Rule | Required artifact |
| --- | --- | --- | --- |
| D1 | [s01](s01-responsibility-direction.md) | Responsibility | module ownership |
| D2 | s01 | Direction | stability-ordered dependency table |
| D3 | [s02](s02-lifetime-surface.md) | Lifetime | state ownership and lifetime contracts |
| D4 | s02 | Surface | public signatures and consumer call sequence |
| D5 | [s03](s03-duplication.md) | Duplication | placement of third-use, fitting-home and poor-fit helpers |
| D6 | [s04](s04-variation.md) | Variation / YAGNI cap | format and digest choices plus scheduled transport seam |
| R1 | [s05](s05-report-form.md) | Only what fired | report omitting silent checks |
| R2 | s05 | Resolution not observation | acted-on resolutions |
| R3 | s05 | Record the declined check | retained duplication decision and reason |
| R4 | s05 | No filler verdicts | report text |
| G1 | [s06](s06-diagram-cap.md) | Diagram distinctness | complete, nonduplicative diagram sources |
| G2 | s06 | Produce versus edit | bounded system source patch and artifact list |
| P1 | [s07](s07-process-rules.md) | Skip vs partial coverage | reviewer coverage line |
| P2 | s07 | Mutation reasoning | complete per-test prediction table |
| P3 | s07 | Fixture validity | replacement test code with property assertions |

Produce versus edit is explicitly tested by G2. The "never mark a box new" rule was suggested
by a retained S06 run but has no dedicated condition here; it is not an additional tested unit.
Other incidental observations do not add coverage. These scenarios do not claim every sentence
of either skill has been tested.

## Results

The tables below are generated from the latest recorded Results rows by `rollup.py`; they are
not a fresh grading pass. Numerators count recorded passes, denominators count recorded answers.
Single-run grades become 0/1 or 1/1. D5 includes both duplication subcases, D6 includes all three
variation conditions, and **P2 includes mechanics and mutation choice as separate subchecks**.
There remain fifteen coverage units; the split does not create a sixteenth unit. Marginal
subcheck tallies do not establish a joint per-replicate pass rate when failures may differ.

```bash
python3 skills/design-review/tests/rollup.py
```

<!-- BEGIN GENERATED ROLLUP -->
| Unit | Scenario / batch | Without skill: observed passes | With skill: observed passes |
| --- | --- | --- | --- |
| D1 | [S01](s01-responsibility-direction.md#results) / round 7 | Responsibility: 2/2 | Responsibility: 2/2 |
| D2 | [S01](s01-responsibility-direction.md#results) / round 7 | Direction: 2/2 | Direction: 2/2 |
| D3 | [S02](s02-lifetime-surface.md#results) / round 7 | Lifetime: 2/3 | Lifetime: 2/3 |
| D4 | [S02](s02-lifetime-surface.md#results) / round 7 | Surface: 3/3 | Surface: 3/3 |
| D5 | [S03](s03-duplication.md#results) / round 4 | Under side: 1/1; Over side: 1/1 | Under side: 1/1; Over side: 1/1 |
| D6 | [S04](s04-variation.md#results) / round 4 | Outcome: 1/1 | Outcome: 1/1 |
| R1 | [S05](s05-report-form.md#results) / round 4 | Rule 1: 0/1 | Rule 1: 0/1 |
| R2 | [S05](s05-report-form.md#results) / round 4 | Rule 2: 1/1 | Rule 2: 1/1 |
| R3 | [S05](s05-report-form.md#results) / round 4 | Rule 3: 1/1 | Rule 3: 1/1 |
| R4 | [S05](s05-report-form.md#results) / round 4 | Rule 4: 0/1 | Rule 4: 0/1 |
| G1 | [S06](s06-diagram-cap.md#results) / round 4 | Diagrams: 1/1 | Diagrams: 1/1 |
| G2 | [S06](s06-diagram-cap.md#results) / round 4 | Outcome: 1/1 | Outcome: 1/1 |
| P1 | [S07](s07-process-rules.md#results) / round 7 | Skip/partial: 2/2 | Skip/partial: 3/3 |
| P2 | [S07](s07-process-rules.md#results) / round 7 | Mutation: 2/2; Mutation choice: 1/2 | Mutation: 3/3; Mutation choice: 3/3 |
| P3 | [S07](s07-process-rules.md#results) / round 7 | Fixture: 1/2 | Fixture: 2/3 |

| Scenario | Prompt hash | Condition hash | Loaded skill hash | Record applicability |
| --- | --- | --- | --- | --- |
| S01 | `3d791568afe9334d` | `db4da67c54d1d7db` | `fcda7a2da8058dd8` | Current; Current |
| S02 | `ff76fc3a6dc19f2a` | `f2d9d679e9b917fb` | `fcda7a2da8058dd8` | Current; Current |
| S03 | `7e1ef621d32bdd1d` | `a6b60af770d5d478` | `fcda7a2da8058dd8` | Current; Current |
| S04 | `a287991c188d2a36` | `0619345ddc2e9548` | `fcda7a2da8058dd8` | Current; Current |
| S05 | `a0032527302c3acf` | `1c72d3ab44485175` | `fcda7a2da8058dd8` | Current; Current |
| S06 | `790832afba8ba5fa` | `aa21e532b4457c8b` | `fcda7a2da8058dd8` | Current; Current |
| S07 | `562115beedc26965` | `1c6a4c0f44c0d4bc` | `a38d6bbae3b7d55f` | Current; Current |
<!-- END GENERATED ROLLUP -->

The revision table quotes the scenario records' applicability labels. “Current” is scoped to
those prompt, condition and loaded-skill hashes; it does not mean all fifteen units share one
batch. Older S01/S02 fixture rows are Expired with their historical grades retained.

For S01's revised fixture, round 5 plus round 7 records Direction at baseline 2/3 and with-skill
3/3. Round 4 used a different prompt and condition and is excluded from that tally. The latest
round alone has 2/2 in each arm. For S02 round 7, Lifetime is 2/3 in each arm after correcting
with-skill replicate 3. For S07 round 7, Fixture is baseline 1/2 and with-skill 2/3; the required
awareness assertions are missing in with-skill replicate 3, and baseline replicate 1's 23-hour
fixture assertion is false. Archived answers remain unchanged.

S07 Mutation choice must be grouped by the loaded skill: round 4's
`4ba576f25dab8154` has one with-skill failure; round 5's `a38d6bbae3b7d55f` has one
with-skill pass; round 7 uses that same hash and has three with-skill passes. Round 5 belongs
with the latter snapshot, not in a “before” bucket. The corresponding baseline choice tallies
in rounds 4, 5 and 7 are 0/1, 1/1 and 1/2. These are table records from different batches,
not contemporaneous randomized controls. No causal or reliability claim follows from them.

### Historical corrections

Recorded because the grading error is more instructive than the grades.

**P3 (fixture validity) was graded "Rule not needed here" and is "Rule needed".** The S07
baseline's replacement test sets `Pacific/Auckland` with `2026-03-15 02:00Z`, which is 15:00 on
the same calendar day, so its own `assert local.date() != now.date()` evaluates False and the
test errors before it reaches production code. The grader checked that fixture-property
assertions *existed* and never checked they *held* — which is the failure the scenario exists to
catch, walked into while grading it. Both reviewers in pass 5 found it independently.

**P2 (mutation reasoning) was graded "Rule works" and the first correction was also wrong.** The
round-1 with-skill run substituted `now.astimezone()` for the condition's `local = now`, and the
grader called the condition too literal. It is not: `local = now` keeps the original test green
on *any* host, while `now.astimezone()` does so only on a UTC host, so the two make different
claims — and the run's stated justification, that the unmutated test would fail on a non-UTC
runner, is false, because the unmutated code reads `ZoneInfo(account.timezone)` and never the
host zone. Codex established this arithmetically; Gemini had agreed with the wrong reading.

**D2 (Direction) was ungraded and is "Rule needed".** Its condition did not say whether it tested
declared table rows or reachability. Reworded to say reachability, and to grant a composition
root an explicit exemption when every domain policy it would otherwise hold has been extracted.
Both existing outputs were judged fully against the new wording, so neither run expired.

### Recorded round-3 artifact differences

The records describe these differences; they do not isolate their cause:

- **S01** left the email subject inline in `run()` in round 2 and flagged it as an open question.
  Round 3 extracts it into the report module and cites that as why the composition-root
  exemption applies. The answer refers to the delivery-content clause.
- **S02 and S03** applied the same clause unprompted, to rejection message copy and to the
  exporter dispatch root respectively.
- **S07** pins `TZ=UTC` only in the replacement test. Its substitute mutation does not meet P2's
  requirement for the original test on every host. See the round-3 Notes in
  [S07](s07-process-rules.md#results) for the corrected grade and the two additional evidence
  observations that leave grades unchanged.

### Conditions reworded in round 3

Three, all because a careful reader could reach the opposite verdict:

- **D1** — the policy list read as four entries or five depending on how `or` binds. Now
  enumerated, with selection-or-grouping stated as one entry.
- **D2** — reachability, plus the composition-root exemption above.
- **P3** — required "an instant whose local date differs from its UTC date", which is sufficient
  but not necessary; a non-zero UTC offset is what actually makes the mutation detectable, and
  the round-2 fixture discriminates without a date difference. Now states the offset property,
  and adds the rule the baseline broke: every fixture property a test asserts must actually hold.

### What the proposed tests inside the outputs do not establish

Several runs propose test code. S01–S06 grade the design artifact. S07 also requires executing the
fixture guards in supplied test code; that does not establish production mutation coverage:

- S03's frozen-digest and cross-exporter hash-equality checks stay green if the shared
  computation is copied back into each exporter. They verify output values, not the extraction
  D5 grades.
- Fixture-property assertions check supplied constants and survive production mutation by
  design. They establish a prerequisite, not regression coverage.
- The `187 passed` in the S07 fixture is prompt text, not an observed run.
- Two assertions in the round-1 S07 baseline fail against the *unmutated* implementation: the
  Auckland date-difference assertion, and the supplementary DST check that subtracts two bounds
  sharing one `ZoneInfo` object.

### Runs voided before grading

Two in round 1, both replaced by clean re-runs: an s02 baseline that invoked the installed
`design-review` plugin skill and said so in its answer, and an s01 with-skill run whose inline
paste of the skill dropped its frontmatter, so the loaded text did not match the snapshot hash
the others used. A baseline dispatched where the plugin is installed *can* load it; zero tool
uses is the check that one stayed clean.

A current "Rule not needed here" would mean only that this model avoided the flaw in this
scenario. It would not establish behavior in long sessions, larger systems or other models.
