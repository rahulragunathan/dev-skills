# Pressure tests for `design-review`

Each scenario defines a normal-work artifact and failure conditions judged from that artifact.
Run each prompt in a fresh agent with and without the indicated skill. Re-run affected pairs
when their prompt, conditions or loaded skill changes. The current definitions have no valid
run evidence yet; the retained rows are expired observations, not current outcomes.

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

No scenario was re-run while rewriting these definitions. All grades below are retained and
expired; scenario files hold the individual run rows and their missing provenance fields.
The historical summary has fifteen rows: three **Rule needed** baselines, eleven **Rule not
needed here** baselines and one defective-rule baseline. There are zero current paired results.

| Rule | Without the skill | With it | Evidence status |
| --- | --- | --- | --- |
| Variation / YAGNI cap | **Rule needed** | **Rule works** | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Only what fired | **Rule needed** | **Rule works** | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| No filler verdicts | **Rule needed** | **Rule works** | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Duplication threshold | Rule was defective | **Rule ineffective** (over side) | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Diagram distinctness | Rule not needed here | **Rule works** | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Produce versus edit | Rule not needed here | **Rule works** | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Responsibility | Rule not needed here | Rule works | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Direction | Rule not needed here | **Rule works** | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Lifetime | Rule not needed here | Rule works | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Surface | Rule not needed here | Rule works | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Resolution not observation | Rule not needed here | Rule works | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Record the declined check | Rule not needed here | **Rule works** | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Skip vs partial coverage | Rule not needed here | Rule works | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Mutation check | Rule not needed here | Rule works | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |
| Fixture validity | Rule not needed here | Rule works | **Expired** — prompt and artifact conditions changed; exact model and revisions are unknown. |

A current "Rule not needed here" would mean only that this model avoided the flaw in this
scenario. It would not establish behavior in long sessions, larger systems or other models.
