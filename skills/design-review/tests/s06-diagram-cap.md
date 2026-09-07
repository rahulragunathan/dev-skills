# S06 — Diagram distinctness, and produce versus edit

**Kind:** procedure

## Rules under test

- Each produced diagram must carry information absent from the others.
- A single new system edge is a bounded edit to the existing diagram.

## What the subagent should do

Deliver the diagram sources in the plan, including the updated module structure, retry flow
and system-edge patch. Use distinct views when they answer different questions; combine views
only if the resulting diagram still carries the required structure and ordering clearly.

## Failure conditions

Judge the diagram sources and patch supplied in the normal answer. A promise to draw them or
an explanation of their purpose is not an artifact. Do not ask follow-up questions to grade.

1. **Distinctness and required content** — no diagram source is supplied; any produced diagram
   merely repeats another's information; or the set omits changed module responsibilities and
   dependencies, retry ordering, the terminal-failure branch, per-attempt audit writes, or the
   notification that occurs only on exhaustion. Drawings with different titles but the same
   nodes and relationships are duplicates. One combined view can pass if it carries all this
   information; there is no required diagram count.
2. **Produce versus edit** — the system patch is missing, omits `billing --> notifications`,
   removes an existing edge, changes an unchanged box or label, or redraws the system as a new
   produced diagram. The diff must contain only the new edge and any routing adjustment that
   edge requires. The plan's artifact list must classify it as an edit. Saying "bounded edit"
   while shipping a larger diff fails.

## Prompt

> Prepare the diagram section of a phase plan for a Flask billing service. Deliver text diagram
> sources (Mermaid is available as the representation for this exercise), an artifact list
> identifying new diagrams and edits, and a diff for the existing system source below. No
> rendering is needed. Choose the diagram set that communicates the phase's design.
>
> Add nightly dunning retries. New modules: `dunning.py` coordinates attempts,
> `dunning_schedule.py` computes retry times and exhaustion, and `dunning_events.py` persists
> attempt results through `db.py`. The existing nightly runner calls dunning; dunning calls
> `payments.py` for each due attempt. Every attempt writes an audit result. A success ends
> retries. A failed attempt schedules the next one unless exhausted. Exhaustion sends one
> notification to the account manager. There are no new endpoints or datastores.
>
> Existing modules `orders.py`, `pricing.py`, `db.py` and `payments.py` retain their roles.
> The diagram section must let a maintainer follow both the new module dependencies and the
> retry execution path. The module view does not currently exist. Existing request paths
> remain unchanged.
>
> The system source already documents the estate:
>
> ```mermaid
> flowchart LR
>   billing[Billing service] --> postgres[Postgres]
>   billing --> s3[S3 invoice PDFs]
>   billing --> stripe[Stripe]
>   crm[CRM] --> notifications[Notifications service]
>   support[Support service] --> notifications
>   onboarding[Onboarding service] --> notifications
> ```
>
> Billing's terminal-failure notification is its first call to the existing Notifications
> service. All other system boxes and edges stay as shown. This source belongs to
> `docs/build_system.py`; the exercise's text diff stands in for its generator edit.
>
> Deliver the diagram section and source patch, not just recommendations for later diagrams.
>
> IMPORTANT: answer purely from the text above. Do not read files, explore a repository or use tools.

## Results

| Run | Model ID | Date | Diagrams | Outcome | Notes | Prompt revision | Condition revision | Skill git SHA | Evidence status |
| ----- | ------- | ------ | ---------- | --------- | ------- | --- | --- | --- | --- |
| Without skill | unknown (reported as Opus) | 2026-09-07 | 3 | Rule not needed here | Fresh baseline against the rewritten conditions. Three distinct diagrams, no redraw; set its own bar for the flow diagram — "if the whole policy reduces to one sentence... the diagram is a picture of a sentence and I would cut it" — which is the distinctness test in its own words. Got the edit substance right ("the update is cheap because `notifications` is already a box on the page") without produce-versus-edit accounting or a bounded diff. **Volunteered a rule the skill lacked**: never mark a box "new", because the marker is a diff and goes stale the moment the phase lands. Now in the skill. | unknown | unknown | not loaded | **Expired** — prompt now requires diagram sources and a bounded system patch; exact run provenance was not recorded. |
| With skill | unknown (reported as Opus) | 2026-09-07 | 1 produced + 2 edits | **Rule works** | Both conditions pass. Declined the system diagram in the rule's own words — "a module map with a boundary box round it, restating what the existing diagram already says" — and bounded the edit: "if the generator diff shows more than that edge plus whatever waypoint nudge keeps it from crossing something, it went too far." Justified the flow diagram against the distinctness test by naming what only it carries: the terminal branch, that `notifications` fires once at the end on failure only. **Under the old count-based condition this same answer scored a failure.** | unknown | unknown | unknown | **Expired** — prompt now requires diagram sources and a bounded system patch; exact run provenance was not recorded. |
