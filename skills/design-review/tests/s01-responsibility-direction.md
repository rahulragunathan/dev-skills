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

1. **Responsibility** — any changed unit owns two policies drawn from **different** entries in
   this list. The entries are: (a) invoice selection *or* grouping — these two count as one
   entry, not two; (b) PDF layout; (c) email delivery; (d) sent-record persistence. Fail any
   cross-entry pair, not only summary-plus-email. Renaming the responsibility to "handle summaries", splitting
   functions inside the same unit, or noting the trade-off does not change the result. A
   coordinator that only passes data between these units is not a second policy owner.
2. **Direction** — the table has a cycle, orders rows by call order instead of the fixture's
   change drivers, or lets a policy-bearing unit depend on a less stable one. Check all
   declared dependencies, including known paths through unchanged modules.

   **Grouping policy is judged by reachability, not by whether it has its own row.** If grouping
   stays a private function inside a module that imports Postgres, the PDF renderer or the mail
   provider, this condition fails — the policy cannot be exercised without them. The generic
   pool wrapper must not import report-owned types.

   **A composition root is exempt from the downward-dependency rule**, but only if every domain
   policy it would otherwise hold — selection, grouping, layout, persistence — has been
   extracted into its own unit. Wiring is not policy. A reordered table, or a paragraph
   defending a downward dependency from a unit that still carries domain policy, does not
   pass.

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

| Run | Model ID | Date | Responsibility | Direction | Notes | Prompt revision | Condition revision | Skill git SHA · content | Evidence status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Without skill | `claude-opus-5` | 2026-09-07 | Rule not needed here | **Ungraded** | Extracted PDF layout and the sent log, but kept grouping as a private `_summaries_by_account` inside the job file, which imports `db`, `mailer` and the renderer. Rows ordered by change driver, not call order; no cycle. Direction ungraded because condition 2 names "stable grouping policy must not depend on Postgres, PDF layout or the mail provider" and grouping is not a unit here, so the clause is either vacuous or a reachability test and the two readings disagree. | `ba57ff9` · `9c9948f304140a69` | `0523dfc4dbe66fbc` | not loaded | Current |
| With skill | `claude-opus-5` | 2026-09-07 | **Rule works** | **Rule works** | Extracted `grouping.py` depending on nothing, and gave it a `BillableInvoice` Protocol naming the two fields it uses so `Invoice` never reaches it: "importing the schema projection would make a quarterly migration an edit to grouping logic and would stop grouping being testable without a live database." Named the composition root as the only unit permitted to point downward. This is the artifact difference the ambiguous baseline condition was trying to describe. | `ba57ff9` · `9c9948f304140a69` | `0523dfc4dbe66fbc` | `d0eb8c7` · `0cb4d2391762d995` | Current |
