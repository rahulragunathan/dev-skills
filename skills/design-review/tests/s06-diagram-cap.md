# S06 — Diagram distinctness, and produce versus edit

**Kind:** procedure

## Rules under test

- Each diagram earns its place by showing something no other diagram shows. There is no number
  to hit.
- The distinctness test: *name something in this diagram that is not in any of the others. A
  system diagram that is the module map with a boundary box round it is not a second diagram.*
- Produce versus edit: a single new edge on an already-documented diagram is a bounded **edit**,
  not a diagram the plan produces.

## What the subagent should do

Treat the new outbound call as a **bounded edit** to the existing system diagram, not as a
diagram this plan produces — and justify every diagram it does produce against the distinctness
test, naming what each shows that the others do not.

The judgement is deliberately arguable. The phase adds one outbound call to a service that
already exists in the estate but which this deployable has never talked to before. That is a new
edge at the system level, which is exactly the kind of thing that invites redrawing the picture.
Redrawing four unchanged boxes to add one line earns nothing; annotating the existing diagram
does.

**How many diagrams is not the question.** An earlier version of this scenario scored the count,
and the recorded run showed why that was wrong: the subagent added a flow diagram carrying
ordering the module map cannot express — which attempt is the terminal one, and that the audit
row is written on every attempt while the notification fires only on exhaustion — and it was
right to. A diagram that shows something no other diagram shows has earned its place, whatever
the total.

## Failure conditions

**Fails** on either of two things:

1. **A duplicate diagram** — one whose content is already carried by another, most likely a
   system diagram that is the module map with a boundary box round it. A diagram the subagent
   cannot distinguish from another when asked is a duplicate even if it is drawn differently.
2. **Treating the single new edge as a diagram the plan produces**, rather than as a bounded
   edit to the diagram that already documents that service.

**Producing more than one diagram is not a failure.** Three diagrams that each show something
the others do not is a pass. The check is distinctness and the produce-versus-edit call, never
a count.

## Prompt

> You are starting a development phase and preparing its plan. Part of that plan is its
> diagrams.
>
> **The phase.** Add dunning retries to the billing service, a single Flask deployable.
> `pricing.py` is untouched. Three new modules: `dunning.py` (decide when to retry a failed
> payment), `dunning_schedule.py` (compute the retry timetable) and `dunning_events.py` (write
> the audit trail). They sit alongside the existing `orders.py`, `pricing.py`, `db.py` and
> `payments.py`. No new endpoints. No new datastore. The existing request paths are unchanged,
> and the retry work runs from the nightly job runner that already exists.
>
> **One new outbound call.** When a retry finally fails, `dunning.py` posts a message to the
> `notifications` service so the account manager is told. `notifications` is an existing
> internal service, already in the estate, already documented in the system diagram, and
> already called by three other deployables. This billing service has never called it before,
> so the call is new for this deployable.
>
> **Its surroundings, otherwise unchanged.** Postgres for storage, S3 for stored invoice PDFs,
> Stripe for money movement. All three were already wired up long before this phase.
>
> **The diagram options available to you.**
>
> | Level | When | Files |
> | --- | --- | --- |
> | System | More than one deployable, or a real external boundary | `docs/build_system.py` → `docs/system.{drawio,png}` |
> | Modules | Structure changes inside a deployable | `docs/build_architecture.py` → `docs/architecture.{drawio,png}` |
> | Flow | A pipeline, request path, or ordering changes | `docs/build_<topic>_flow.py` → `docs/<topic>-flow.{drawio,png}` |
>
> Decide which diagrams this phase's plan should carry, and say what each one would show.
>
> IMPORTANT: answer purely from the text above. Do not read files, do not explore any
> repository, and do not use any tools.

## Results

| Run | Model | Date | Diagrams | Outcome | Notes |
| ----- | ------- | ------ | ---------- | --------- | ------- |
| Without skill | Sonnet | 2026-09-06 | 2 | scenario defective | v1 said "the request path is unchanged apart from the two new endpoints", and two new endpoints *are* a request-path change. Ambiguous brief. |
| Without skill | Sonnet | 2026-09-06 | 1 | Rule not needed here | v2, a pure internal refactor. Declined both extras, restating the level test almost verbatim. Too easy — nothing to argue about. Superseded. |
| Without skill | Opus | 2026-09-06 | 2 | **Rule needed**, rule incomplete | Produced system + modules, declined flow with sound reasoning. But it framed the system diagram as an **edit** — one new edge on an already-documented diagram — and bounded it tightly: "if the diff on `system.drawio` shows more than the new edge and whatever waypoint nudge it needs, the edit went too far". **Refine:** the cap governs diagrams the plan *produces*; correcting an existing diagram the phase made factually wrong is drift repair and is always in scope. Separately it proposed light and dark renders, which contradicts the one-render callout. |
| With skill | Opus | 2026-09-06 | 2 produced + 1 edit | **Rule works**, scenario expectation wrong | Applied the produce-versus-edit rule exactly: system diagram framed as a bounded edit, "not a diagram this plan produces, so it does not count against the cap", with the diff bounded to one edge plus a waypoint nudge. Still two produced, because it added a flow diagram the baseline did not — justified against the level test: "name something here that is not on the module map: which attempt is the terminal one", and the audit row is written on every attempt while the notification fires only on exhaustion. That is ordering the module map cannot carry, so the scenario's expected answer of one diagram was wrong. **Superseded** — ran against the pre-2026-09-07 skill. |
| Without skill | Opus | 2026-09-07 | 3 | Rule not needed here | Fresh baseline against the rewritten conditions. Three distinct diagrams, no redraw; set its own bar for the flow diagram — "if the whole policy reduces to one sentence... the diagram is a picture of a sentence and I would cut it" — which is the distinctness test in its own words. Got the edit substance right ("the update is cheap because `notifications` is already a box on the page") without produce-versus-edit accounting or a bounded diff. **Volunteered a rule the skill lacked**: never mark a box "new", because the marker is a diff and goes stale the moment the phase lands. Now in the skill. |
| With skill | Opus | 2026-09-07 | 1 produced + 2 edits | **Rule works** | Both conditions pass. Declined the system diagram in the rule's own words — "a module map with a boundary box round it, restating what the existing diagram already says" — and bounded the edit: "if the generator diff shows more than that edge plus whatever waypoint nudge keeps it from crossing something, it went too far." Justified the flow diagram against the distinctness test by naming what only it carries: the terminal branch, that `notifications` fires once at the end on failure only. **Under the old count-based condition this same answer scored a failure.** |
