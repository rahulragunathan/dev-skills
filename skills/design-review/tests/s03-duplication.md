# S03 — Duplication

**Kind:** build · **Model:** Sonnet

## Rules under test

- **Duplication** — is anything now appearing a third time? Three occurrences is the trigger;
  two is recorded and left alone.

## Failure conditions

The rule has two edges and this scenario probes both, because the brief creates a genuine
third occurrence while also dangling a tempting second one.

1. **Fails on the under side** if the produced design leaves the **third** occurrence of the
   header-and-footer logic duplicated without extracting it and without saying why not.
2. **Fails on the over side** if the produced design gives the **currency formatting** — which
   appears exactly twice — a shared home that did not already exist. Creating a new module for
   two callers is the failure, **and counting the occurrences out loud does not excuse it**.
   Moving it into a module that has to exist anyway for a genuine third occurrence is the pass;
   so is leaving the two copies alone.

Judged on the design the agent produces.

## Prompt

> You are adding a feature to an existing Python reporting service. Produce the module design:
> which files exist or change, what each is responsible for, its public functions with
> signatures, and what it depends on.
>
> **The feature.** Add a Parquet export alongside the two exports that already exist.
>
> **What exists today.**
>
> `export_csv.py` — writes a CSV. It opens with a two-line provenance header (`# Generated
> <timestamp>` and `# Account <id>`), writes the rows, then writes a footer line with the row
> count and a SHA-256 of the body. It formats money values with a helper defined at the top of
> the file, `_fmt_money(cents) -> str`, which renders `1234` as `"12.34"`.
>
> `export_xlsx.py` — writes an Excel workbook. It writes the same two-line provenance header
> into the first two rows, writes the rows, then writes the same footer line with the row count
> and body hash. It has its own copy of `_fmt_money`, identical to the one in `export_csv.py`.
>
> Both are called from `reports.py`, which picks the exporter by a `format` argument.
>
> **The new export.** Parquet, same provenance header (as file metadata rather than rows), same
> rows, same row-count-and-hash footer (also as metadata). Parquet is a binary columnar format,
> so money values are written as integer cents and never formatted as strings.
>
> Give the module design for adding this, including what you would change about the two
> existing files. Then write a short paragraph on anything about the structure you would flag
> to a reviewer.
>
> IMPORTANT: answer purely from the text above. Do not read files, do not explore any
> repository, and do not use any tools.

## Results

| Run | Model | Date | Under side | Over side | Notes |
| ----- | ------- | ------ | ------------ | ----------- | ------- |
| Without skill | Opus | 2026-09-06 | passed | **rule defective** | Moved `fmt_money` at two occurrences, but counted first ("one thing is shared between two of them") and justified it ("now public because it crosses a module boundary"). Sound: `export_common.py` must exist anyway, so the move costs no new module. The rule as written would have said create that module and leave two identical copies beside it, which is worse. **Refine:** three occurrences justify *creating* a shared home; two may move into one that exists already. Also flagged the base-class trap unprompted. **Stale:** this scenario's failure condition changed on 2026-09-07 and this baseline predates it. Re-run before citing it. |
| With skill | Opus | 2026-09-07 | passed | **Rule ineffective** (over side) | **Regraded 2026-09-07.** Originally recorded as "Rule works"; the condition it was scored against tested whether the agent *counted* the occurrences, not what it built, so an over-extraction that reasoned out loud passed. Under the corrected condition it fails the over side: it created `money.py` for two callers, which is the construction the threshold forbids. The reasoning was good and the outcome was not — it declined the existing home (`envelope.py`) because folding money rendering in would give that module a second reason to change, which is true, and then conjured a new home instead of leaving two copies of a four-line function. The skill now closes that third option explicitly. Under side: Envelope logic reaches three copies with Parquet, so `envelope.py` is created. `_fmt_money` at two: considered the existing-home clause and **declined** it, because folding money rendering into `envelope.py` "gives that module a second reason to change" — so a separate four-line `money.py`, with a written reversal trigger. Threshold and Responsibility interacting correctly. Also refused to build a speculative `schema.py`: "Not built speculatively; decided by reading the two files." |
