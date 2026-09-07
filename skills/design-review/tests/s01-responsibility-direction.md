# S01 — Responsibility and Direction

**Kind:** build

## Rules under test

- **Responsibility** — separate units with unrelated reasons to change.
- **Direction** — order rows by stability; reject cycles and dependencies on less stable units.

## What the subagent should do

Produce a module table that separates summary policy and layout, delivery, and sent-record
persistence. A coordinator may call these operations but must not implement their policies.
Derive row stability from the stated change drivers. Keep stable policy independent of storage,
provider and layout details through data arguments or narrow interfaces.

## Failure conditions

A missing module table, signature or dependency needed to trace the feature fails the affected
check. Judge the final design, including code or diagrams supplied with it. A warning or future
extraction trigger does not repair a failing artifact.

1. **Responsibility** — any changed unit owns two unrelated policies: invoice selection or
   grouping, PDF layout, email delivery, or sent-record persistence. Fail any such pair, not
   only summary-plus-email. Renaming the responsibility to "handle summaries", splitting
   functions inside the same unit, or noting the trade-off does not change the result. A
   coordinator that only passes data between these units is not a second policy owner.
2. **Direction** — the table has a cycle, orders rows by call order instead of the fixture's
   change drivers, or gives a unit a concrete dependency on a less stable unit. Check all
   declared dependencies, including known paths through unchanged modules. In particular,
   stable grouping policy must not depend on Postgres, PDF layout or the mail provider, and
   the generic pool wrapper must not import report-owned types. A reordered table or a
   paragraph defending an unchanged downward dependency does not pass.

## Prompt

> You are designing a new feature for an existing Python billing service. Produce the module
> design as a table: files created or changed, one responsibility per row, public signatures,
> and dependencies. Order the rows by what makes each unit change, slowest-changing first.
>
> **The feature.** At 02:00 pull the previous day's invoices from Postgres, group them by
> account, build a summary PDF, email it to each billing contact, and record successful sends
> so support can answer "did we send it?". Include the Expected change and Shared state lines.
>
> **What exists today.** `db.py` is a generic connection-pool wrapper. `mailer.py` wraps the
> provider and exposes `send(to, subject, body, attachments) -> None`. The `invoices` and
> `accounts` tables exist. There is no reporting code.
>
> **Repo convention.** Four nightly jobs each have a single file with a module-level `run()`
> that queries, formats, delivers and writes bookkeeping. Each is 200–600 lines. The team likes
> reading a job end to end and disliked the previous team's `jobs/` package hierarchy.
>
> **Change drivers.** Pool management and account-grouping policy have been stable for years.
> Job scheduling changes yearly. The invoice schema changes quarterly. Finance changes PDF
> layout every two months, independently of grouping. The mail provider API changes monthly.
> Sent-record retention and fields follow support requirements, independently of finance.
>
> Python 3.13. No new runtime dependencies beyond a PDF library. Produce the design you would
> build and a short paragraph for its reviewer.
>
> IMPORTANT: answer purely from the text above. Do not read files, explore a repository or use tools.

## Results

| Run | Model ID | Date | Responsibility | Direction | Notes | Prompt revision | Condition revision | Skill git SHA | Evidence status |
| ----- | ------- | ------ | ---------------- | ----------- | ------- | --- | --- | --- | --- |
| Without skill | unknown (reported as Opus) | 2026-09-07 | Rule not needed here | Rule not needed here | Fresh baseline against the corrected Direction condition. Fused per convention and named it, with an extraction trigger. Guarded the exact downward dependency the condition names, unprompted: "Nothing depends on it. It adds no import to any existing module." The corrected rule still does not discriminate on Opus. | unknown | unknown | not loaded | **Expired** — prompt and both artifact conditions changed; exact run provenance was not recorded. |
| With skill | unknown (reported as Opus) | 2026-09-07 | **Rule works** | **Rule works** | Direction **fired on a real downward arrow** and the rewrite is what made that possible: "`nightly_invoice_summary.py` (row 2) depends on `invoice_summary_layout.py` (row 3), an arrow from stable to volatile. Kept: it is this job's composition root and its only consumer... if `render_pdf` ever takes a connection, a `Row`, or reads the clock, the arrow starts to matter." Under the old call-order reading both units are leaves and nothing fires. Also declined Duplication at five with a real distinction — "the four jobs share a *shape*, and shape is not duplication" — and caught that `mailer.send()` returns nothing, so `provider_message_id` cannot be filled. | unknown | unknown | unknown | **Expired** — prompt and both artifact conditions changed; exact run provenance was not recorded. |
