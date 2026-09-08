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

| Run | Model ID | Date | Under side | Over side | Notes | Prompt revision | Condition revision | Skill git SHA · content | Evidence status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Without skill (round 1) | `claude-opus-5` | 2026-09-07 | Rule not needed here | Rule not needed here | Created a shared provenance module with three consumers, deleted `_fmt_timestamp` into the existing `time_text.format_utc`, and kept `_fmt_money` duplicated in CSV and XLSX. All three subcases correct without the skill. | `ba57ff9` · `7e1ef621d32bdd1d` | `ba57ff9` · `a6b60af770d5d478` (unchanged) | not loaded | Current |
| With skill (round 2) | `claude-opus-5` | 2026-09-08 | **Rule works** | **Rule works** | Identical placement for all three helpers. Stated the asymmetry as the point worth reviewing — the timestamp helper has an owner whose responsibility it matches exactly, money display has none — and noted that Parquet using neither helper is the evidence the seam sits in the right place. | `ba57ff9` · `7e1ef621d32bdd1d` | `ba57ff9` · `a6b60af770d5d478` (unchanged) | `ba57ff9` · `a6b60af770d5d478` (unchanged) | Current |
