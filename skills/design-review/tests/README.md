# Pressure tests for `design-review`

Each scenario defines a normal-work artifact and failure conditions judged from that artifact.
Run each prompt in a fresh agent with and without the indicated skill. Re-run affected pairs
when their prompt, conditions or loaded skill changes.

The evidence below spans four rounds on `claude-opus-5`. **Round 4 (2026-09-09) is the current
one and the only complete one**: both arms of all seven scenarios were gathered on the same day
against the same skill text, after the earlier batches were found to be mixing baselines from one
round with with-skill answers from another. Rounds 1 to 3 are retained as history and marked
superseded in each scenario's Results table.

Provenance is tracked per scenario, not per repository — `evidence.py check` recomputes each
scenario's loaded-skill hash, prompt hash and condition hash, so it can say which single scenario
has gone stale. A repository-wide SHA could only mark everything stale or nothing, which is how
S07's evidence outlived two changes to `phase-workflow`.

Several grades have been corrected across rounds, always in the same direction — see
*Corrections* below.

## What a unit's result means

The goal is that the answer is right, not that the skill can be shown to be necessary. A unit
where the baseline already gets it right is not a mark against the skill; it is a situation the
skill does not have to rescue. So the units divide three ways, and only two of them are worth
spending runs on.

| Baseline behaviour | What the skill has to do | Worth re-measuring |
| --- | --- | --- |
| Reliably right | Not break it | No. Consistency across rounds is the evidence. |
| Reliably wrong | Fix it, and reliably | Yes — measure how often it holds. |
| **Unstable** | **Make the outcome reliable** | **Yes. This is the highest-value case.** |

The third row is the one this table could not express until round 6. A baseline that is a coin
flip and a with-skill arm that is consistently right is the skill doing its most valuable work,
and `Rule not needed here` / `Rule works` has no way to say so. Where an arm has been run more
than once, the cell carries the tally, and a unit whose runs disagree is recorded as **Unstable**
rather than graded from whichever run happened to be taken.

**One run per arm cannot support a grade.** Two units flipped on byte-identical inputs before
this was understood: S05's report-form rules across rounds 3 and 4, and S07's mutation choice,
which has now gone FAIL, PASS, FAIL, PASS across four observations. Every single-run grade of
those units reported a coin toss as a property, including grades that were presented as
findings and acted on.

Three replicates is the standard, five where three disagree. Neither measures a rate: S05's
roughly one-in-seven tail survives five clean runs about 44% of the time. What replication buys
is not precision but the ability to tell a stable direction from a toss.

Transcripts, dispatched prompts and hash-verified skill snapshots for both rounds are archived
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

**Rounds 6 and 7 replaced the single-run grades with replicated ones, and the picture changed.**
Nine of the fifteen units are stable and already right without the skill; the skill's job there is
not to break them, and five rounds show it does not. Two units are reliably wrong in the baseline
and the skill fixes them most of the time. **Three units were unstable in the baseline** — S01
Direction (2/3), S02 Lifetime (2/3), S07 Mutation choice (2/4) — **and the with-skill arm is
consistent on all three**: 4/4, 3/3 and 3/3.

The clearest result is S07's Mutation choice, because the skill text changed under it. Before
`phase-workflow` carried the host-independence rule, the with-skill arm was 1 of 2. After, it is
3 of 3, and every one of those three cites the rule in its own words — *"per the procedure's
worked case"*, *"per the workflow's rule that a prediction must survive a change of machine"*.
The baseline over the same period stayed at 2 of 4. That is a rule changing behaviour, measured
rather than asserted, and it is the only such measurement in this suite.

That is a worse result than round 3 reported, and three of the five come from grading errors
found in pass 9 rather than from the skill getting worse. Round 3 graded S07's Fixture unit a
pass because its replacement fixture was checked on a UTC host; `gpt-6-astra` executed it under
`TZ=Asia/Tokyo`, where the fixture's own guard is False and the test errors before reaching
production code. Both arms carry that defect, so both are regraded.

All fifteen units are current as of round 4.

| Unit | Rule | Without the skill | With it | Evidence status |
| --- | --- | --- | --- | --- |
| D1 | Responsibility | **Rule needed** | **Rule ineffective** | Current |
| R1 | Only what fired | **Rule needed** | **Rule ineffective** | Current |
| R4 | No filler verdicts | **Rule needed** | **Rule ineffective** | Current |
| P2 | Mutation reasoning | **Rule needed** | **Rule ineffective** | Current |
| P3 | Fixture validity | **Rule needed** | **Rule ineffective** | Current |
| D2 | Direction | **Rule needed** | **Rule works** | Current |
| D3 | Lifetime | **Rule needed** | **Rule works** | Current |
| D4 | Surface | Rule not needed here | Rule works | Current |
| D5 | Duplication | Rule not needed here | Rule works | Current |
| D6 | Variation / YAGNI cap | Rule not needed here | Rule works | Current |
| R2 | Resolution not observation | Rule not needed here | Rule works | Current |
| R3 | Record the declined check | Rule not needed here | Rule works | Current |
| G1 | Diagram distinctness | Rule not needed here | Rule works | Current |
| G2 | Produce versus edit | Rule not needed here | Rule works | Current |
| P1 | Skip vs partial coverage | Rule not needed here | Rule works | Current |

### Corrections — three grades were wrong, and external review found them

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

### What round 3 changed in the artifacts

Re-gathering is not bookkeeping — the clarified conditions changed what the agent produced:

- **S01** left the email subject inline in `run()` in round 2 and flagged it as an open question.
  Round 3 extracts it into the report module and cites that as why the composition-root
  exemption applies. The delivery-content clause is what moved it.
- **S02 and S03** applied the same clause unprompted, to rejection message copy and to the
  exporter dispatch root respectively.
- **S07** pins `TZ=UTC` only in the replacement test. Its substitute mutation does not meet P2's
  requirement for the original test on every host. See the round-3 Notes in
  [S07](s07-process-rules.md#results) for the corrected grade and the two additional evidence
  observations that leave grades unchanged.

### Conditions reworded this round

Three, all because a careful reader could reach the opposite verdict:

- **D1** — the policy list read as four entries or five depending on how `or` binds. Now
  enumerated, with selection-or-grouping stated as one entry.
- **D2** — reachability, plus the composition-root exemption above.
- **P3** — required "an instant whose local date differs from its UTC date", which is sufficient
  but not necessary; a non-zero UTC offset is what actually makes the mutation detectable, and
  the round-2 fixture discriminates without a date difference. Now states the offset property,
  and adds the rule the baseline broke: every fixture property a test asserts must actually hold.

### What the proposed tests inside the outputs do not establish

Several runs propose test code. Grading judges the *design artifact*, not that code, and the two
should not be conflated:

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
