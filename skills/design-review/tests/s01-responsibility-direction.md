# S01 — Responsibility and Direction

**Kind:** build

## Rules under test

- **Responsibility** — does any unit have more than one reason to change?
- **Direction** — do dependencies point one way, with rows ordered most-stable-first?

## What the subagent should do

Separate the three things that change for different reasons — producing the summary, delivering
it, and recording that it was sent — and keep the dependency graph acyclic, with the data layer
never importing a type the reporting layer owns.

The brief pushes the other way on purpose. Every other job in the repo is a single `run()` in
one file, and the team is said to like it. So the correct answer is not automatic: following
the convention is defensible, and so is breaking it. What is **not** defensible is fusing the
concerns without noticing the trade-off exists.

## Failure conditions

1. **Responsibility** — one unit both builds the summary and sends it, **and the design does
   not name that as a deliberate choice against the alternative.** Choosing fusion and saying
   why is a pass. Choosing it silently is the failure.
2. **Direction** — a dependency cycle, or an unnamed **downward** dependency: the generic
   data-access wrapper importing a type the feature-specific reporting module owns. `db.py`
   changes when the Postgres schema changes; a summary type changes whenever finance changes
   the report, so it sits *below* `db.py` and that import is an arrow pointing down.

Judged on the design the subagent **produces**. Noticing the problem afterwards does not count
if the design still contains it.

## Prompt

> You are designing a new feature for an existing Python billing service. Produce the module
> design: which files exist, what each is responsible for, its public functions with
> signatures, and what it depends on.
>
> **The feature.** Finance wants a nightly invoice summary. At 02:00 the job should pull the
> previous day's invoices from Postgres, group them by account, produce a summary document,
> email it as a PDF attachment to each account's billing contact, and record that the summary
> was sent so support can answer "did we send it?" without checking the mail provider.
>
> **What exists today.** `db.py` wraps the Postgres connection pool. `mailer.py` wraps the
> transactional email provider and exposes `send(to, subject, body, attachments)`. There is an
> `invoices` table and an `accounts` table. There is no reporting code of any kind yet.
>
> **How this repo does nightly jobs.** There are four already — `nightly_dunning.py`,
> `nightly_reconcile.py`, `nightly_churn_report.py`, `nightly_tax_export.py`. Each is a single
> file with a module-level `run()` that does everything: queries, formatting, delivery, and its
> own bookkeeping writes. They range from 200 to 600 lines. In last month's retro the team said
> explicitly that they like being able to read one job end to end in one file, and that the
> `jobs/` package layout the previous team used made it hard to follow what a job actually did.
> Nobody has proposed changing this.
>
> **Constraints.** Python 3.13, no new runtime dependencies beyond a PDF library. Finance
> changes the summary layout every couple of months. The email provider was swapped once last
> year.
>
> Give the module design. Then write a short paragraph on anything about the structure you
> would flag to a reviewer.
>
> IMPORTANT: answer purely from the text above. Do not read files, do not explore any
> repository, and do not use any tools.

## Results

| Run | Model | Date | Responsibility | Direction | Notes |
| ----- | ------- | ------ | ---------------- | ----------- | ------- |
| Without skill | Opus | 2026-09-07 | Rule not needed here | Rule not needed here | Fresh baseline against the corrected Direction condition. Fused per convention and named it, with an extraction trigger. Guarded the exact downward dependency the condition names, unprompted: "Nothing depends on it. It adds no import to any existing module." The corrected rule still does not discriminate on Opus. |
| With skill | Opus | 2026-09-07 | **Rule works** | **Rule works** | Direction **fired on a real downward arrow** and the rewrite is what made that possible: "`nightly_invoice_summary.py` (row 2) depends on `invoice_summary_layout.py` (row 3), an arrow from stable to volatile. Kept: it is this job's composition root and its only consumer... if `render_pdf` ever takes a connection, a `Row`, or reads the clock, the arrow starts to matter." Under the old call-order reading both units are leaves and nothing fires. Also declined Duplication at five with a real distinction — "the four jobs share a *shape*, and shape is not duplication" — and caught that `mailer.send()` returns nothing, so `provider_message_id` cannot be filled. |
