# S03 — Duplication

**Kind:** build

## Rules under test

- **Duplication** — three occurrences justify creating a shared home. Two may move into a
  fitting home that exists for another reason. If that home is a poor fit, keep the copies.

## Failure conditions

Judge the produced module table and the stated contents of each changed file. Missing the
placement of any duplicated helper fails that condition. Counting copies or explaining an
extraction does not excuse the resulting design.

1. **Under side** — the three exporters keep separate copies of the identical provenance and
   digest computation. The produced design must give that computation one shared home with
   three consumers. Format-specific encoding stays with each exporter.
2. **Over side, fitting home** — the two timestamp-rendering copies cause a new module, wrapper
   or other indirection. They may use the existing `time_text.py`, which already owns that
   exact responsibility, or stay as two copies. A third consumer must not be invented.
3. **Over side, poor fit** — the two `_fmt_money` copies move to a new home, or into an existing
   home whose only responsibility is UTC timestamp text or export provenance. Currency display
   has an independent change driver and is not part of either interface. They must remain in
   CSV and XLSX. Broadening a name to `export_common.py` or `utils.py` does not make it a fit.
   The shared home justified by the third provenance occurrence does not justify this move.

## Prompt

> Add a Parquet exporter to a Python reporting service. Produce a module table with files
> created or changed, responsibilities, signatures and dependencies, plus Expected change and
> Shared state lines. Include where the helper functions will live after the change.
>
> `export_csv.py` and `export_xlsx.py` each contain identical code computing an envelope:
> generated-at instant, account ID, row count and SHA-256 of canonical input row bytes. The
> canonical byte stream and computation are format-independent. CSV writes the envelope as
> comment lines; XLSX writes it as cells. Each exporter separately encodes its body.
>
> Both also contain these two identical four-line helpers:
>
> - `_fmt_money(cents) -> str`, rendering `1234` as `"12.34"` for display columns.
> - `_fmt_timestamp(instant) -> str`, rendering a UTC timestamp for display columns.
>
> `time_text.py` already exists for audit-log display. It owns UTC timestamp text and exposes
> the identical `format_utc(instant) -> str`. It has no currency or provenance responsibility.
> No other shared export or display module exists. Currency display changes with finance's
> presentation rules; provenance changes with audit requirements; timestamp text follows the
> audit UI's timestamp convention. These change independently.
>
> `reports.py` selects an exporter by `format`. Parquet needs the same envelope computation,
> stored as file metadata, but writes money as integer cents and instants as native timestamps.
> It uses neither display helper. No further exporters or display consumers are scheduled.
>
> Give the design you would build, including changes to the two existing exporters, and a
> short paragraph for its reviewer.
>
> IMPORTANT: answer purely from the text above. Do not read files, explore a repository or use tools.

## Results

| Run | Model ID | Date | Under side | Over side | Notes | Prompt revision | Condition revision | Skill git SHA | Evidence status |
| ----- | ------- | ------ | ------------ | ----------- | ------- | --- | --- | --- | --- |
| Without skill | unknown (reported as Opus) | 2026-09-06 | passed | **rule defective** | Moved `fmt_money` at two occurrences, but counted first ("one thing is shared between two of them") and justified it ("now public because it crosses a module boundary"). Sound: `export_common.py` must exist anyway, so the move costs no new module. The rule as written would have said create that module and leave two identical copies beside it, which is worse. **Refine:** three occurrences justify *creating* a shared home; two may move into one that exists already. Also flagged the base-class trap unprompted. | unknown | unknown | not loaded | **Expired** — fixture and conditions now cover fitting and poor-fit homes; exact run provenance was not recorded. |
| With skill | unknown (reported as Opus) | 2026-09-07 | passed | **Rule ineffective** (over side) | **Regraded 2026-09-07.** Originally recorded as "Rule works"; the condition it was scored against tested whether the agent *counted* the occurrences, not what it built, so an over-extraction that reasoned out loud passed. Under the corrected condition it fails the over side: it created `money.py` for two callers, which is the construction the threshold forbids. The reasoning was good and the outcome was not — it declined the existing home (`envelope.py`) because folding money rendering in would give that module a second reason to change, which is true, and then conjured a new home instead of leaving two copies of a four-line function. The skill now closes that third option explicitly. Under side: Envelope logic reaches three copies with Parquet, so `envelope.py` is created. `_fmt_money` at two: considered the existing-home clause and **declined** it, because folding money rendering into `envelope.py` "gives that module a second reason to change" — so a separate four-line `money.py`, with a written reversal trigger. Also refused to build a speculative `schema.py`: "Not built speculatively; decided by reading the two files." | unknown | unknown | unknown | **Expired** — fixture and conditions now cover fitting and poor-fit homes; exact run provenance was not recorded. |
