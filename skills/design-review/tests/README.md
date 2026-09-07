# Pressure tests for `design-review`

A skill is prose that steers an agent, so its tests are scenarios run against a fresh agent
rather than assertions run against code. Each file here holds one scenario, the rules it
probes, the failure condition for each, and the recorded result.

Re-run them after any edit to `SKILL.md`. Two limits on what a re-run proves: **s05** has no run
that exercises report rule 3 (s01 and s03 both do, in their with-skill runs), and rows marked
**Superseded** ran against earlier prompt text, so nothing current can be compared against them.

## Which model to run on

**The model that will actually follow the skill.** `design-review` is invoked in the main
session, so that is Opus under the standard tiering, and Opus is the model whose behaviour
these rules have to change.

The first round ran on Sonnet, chosen on cost. That tested the wrong subject: a rule that
changes Sonnet's output tells you nothing about a skill Opus will read. Those results are kept
and labelled, because subagents doing design work under `dispatching-parallel-agents` do run
on Sonnet, so both rows are worth having. Where the two disagree, the Opus row decides whether
the rule earns its place in the skill.

## When a recorded row expires

A row records what one model did given one prompt. What invalidates it is the **prompt**
changing, or the **failure condition** changing so much that the recorded notes cannot be
re-judged against it.

Editing `SKILL.md` invalidates every **with-skill** row, because the skill is what those runs
loaded. It does **not**, on its own, invalidate a **without-skill** row: no skill was loaded, so
skill churn cannot reach it. Keep those baselines, and re-run one only when its own prompt or
condition moved. Say which, in the row.

## How to run one

Dispatch the scenario's **Prompt** verbatim to a fresh subagent, with no other context.

- **Without-skill run** — no skill loaded. Confirms the rule is not already the agent's default.
- **With-skill run** — the same prompt with `SKILL.md` loaded. Confirms the rule changed the
  outcome.

Judge the output against the **Failure conditions** only. Never widen or soften a condition
to make a run pass; if a condition turns out to be worded wrong, fix the wording and re-run
both sides.

## Produce, don't spot

The six checks are probed with **build** tasks — "design the modules for X" — and judged on
the design the agent produces. They are not probed by handing an agent a broken design and
asking it to find the flaw.

The first round of these tests made that mistake and four of five scenarios came back green.
An agent given one small artifact and an explicit six-item checklist is in the best position
it will ever be in to be careful, and it performed accordingly. The failures these rules
guard against happen with the check in the background: the shared sanitizer that leaked one
request's body into another was **written** by an agent that believed it was correct, and
found four review rounds later.

The reporting rules are different and are probed the old way, because the thing under test
*is* the shape of the report.

## A rule the model already follows is not proven

Record the result honestly. A without-skill run that comes back "Rule not needed here" means one
of three things, and the file should say which is suspected:

1. The scenario telegraphs its answer, so it tests agreement rather than judgement.
2. The failure condition is worded wrong and does not describe the real failure.
3. The model does this correctly on its own, and the rule is insurance rather than a fix.

The first two are defects in the test. Fix them and re-run. The third is a real finding and
is recorded as such — the rule stays, marked unproven, because one small scenario going well is
weak evidence about the conditions it does not reproduce.

## Result vocabulary

Each scenario runs twice. The two runs answer different questions, so they use different words.

| Run | Outcome | Means |
| ----- | --------- | ------- |
| **Without skill** | **Rule needed** | The subagent produced the flaw unprompted. The rule has work to do. |
| | **Rule not needed here** | It avoided the flaw on its own. No evidence this rule changes anything, under these conditions. |
| | **Rule defective** | It did something the rule forbids, and was right to. The rule is wrong, not the subagent. |
| | **Scenario defective** | The brief was ambiguous or telegraphed its answer. Fix the scenario and re-run. |
| **With skill** | **Rule works** | The subagent raised the issue, or avoided the flaw. |
| | **Rule ineffective** | It still produced the flaw despite the rule. Close the rationalization the output shows, then re-run. |

"Rule not needed here" is a real result, not a null one. It means the model does this correctly
on its own under the conditions tested, and the rule is insurance rather than a fix. Record it,
say so in the skill, and do not let it read as proven.

## Coverage

| Scenario | Rules probed | Kind |
| ---------- | -------------- | ------ |
| [s01](s01-responsibility-direction.md) | Responsibility, Direction | build |
| [s02](s02-lifetime-surface.md) | Lifetime, Surface | build |
| [s03](s03-duplication.md) | Duplication | build |
| [s04](s04-variation.md) | Variation and the YAGNI cap | build |
| [s05](s05-report-form.md) | Anti-gaming 1, 2, 3, 4 | report |
| [s06](s06-diagram-cap.md) | Diagram distinctness, produce vs edit | procedure |
| [s07](s07-process-rules.md) | Skip vs partial coverage, mutation check, fixture validity | procedure |

Fourteen rules across seven scenarios: the **eleven** `design-review` states — six checks, four
report rules, the diagram judgement — plus the **three** `phase-workflow` process rules in s07,
probed here because a single retrospective invokes both skills. Every rule `design-review` states
has a row.

## Results

Every rule run against a fresh **Opus** subagent, with the skill loaded and without it. Fourteen
rules: the eleven `design-review` states, plus s07's three `phase-workflow` process rules.

| Rule | Without the skill | With it | Read it as |
| ------ | ------------------- | --------- | ------------ |
| Variation / YAGNI cap | **Rule needed** | **Rule works** | Proven. Adopted a Protocol *and* registry for one format under a colleague's pressure. Regraded against the cost-graded cap; the original condition banned any protocol and contradicted the skill |
| Only what fired | **Rule needed** | **Rule works** | Proven. Gave lines to all six checks including silent ones |
| No filler verdicts | **Rule needed** | **Rule works** | Proven. Wrote "clean" five times |
| Duplication threshold | Rule was defective | **Rule ineffective** (over side) | The naive form produced a worse design; the corrected threshold then failed to stop a new module built for two callers. The rule now closes that third option explicitly and is unproven again |
| Diagram distinctness | Rule not needed here | **Rule works** | The count-based rule this replaced would have failed a correct answer |
| Produce versus edit | Rule not needed here | **Rule works** | Baseline got the substance without the accounting or a bounded diff |
| Responsibility | Rule not needed here | Rule works | Fused to match a repo convention, then named the trade-off and set an extraction trigger |
| Direction | Rule not needed here | **Rule works** | Rewritten because it was *wrong*, not unproven. Fired on a real stable-to-volatile arrow, and elsewhere caught a supplied table ordered by call order — "so the check has not been run" |
| Lifetime | Rule not needed here | Rule works | Named the process boundary, worker count and thread safety unprompted |
| Surface | Rule not needed here | Rule works | Kept ambient setup out of signatures unprompted |
| Resolution not observation | Rule not needed here | Rule works | Stated decisions unprompted |
| Record the declined check | Rule not needed here | **Rule works** | A check fired, declined, with the reason and re-fire condition written down |
| Skip vs partial coverage | Rule not needed here | Rule works | Named the reviewer that produced nothing, and refused to call it clean |
| Mutation check | Rule not needed here | Rule works | Per-test predicted mutation, explicit that prediction is not execution |
| Fixture validity | Rule not needed here | Rule works | Caught a timezone-inert fixture and a second under-specified one |

**"Rule not needed here" is not "delete this rule."** It means a strong model did the right thing
on a small design in one shot, which is the easiest condition there is. Large systems, long
sessions under context pressure, and weaker models are untested. Say so rather than presenting
those rules as proven.

**One measured cost.** An earlier run recorded the loaded rules catching more fixture problems
while *missing* a bug the baseline found. The re-run caught it, and nothing in the rules changed
to address it — so read that as run variance, and keep the warning it bought: pointing attention
somewhere takes it from elsewhere.
