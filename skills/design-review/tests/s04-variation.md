# S04 — Variation and the YAGNI cap

**Kind:** build

## Rules under test

- **Variation** — a likely change has a usable seam; a runtime plug-in point must not exist
  solely for a permanently single implementation.
- **YAGNI cap** — a Protocol or type alias may name a shape with one implementation. Runtime
  machinery requires a second implementation that exists or is scheduled.

## Failure conditions

Judge the table and dependency contracts. Missing the ingestion path or the scheduled change's
placement fails the relevant condition. A response to the tech lead does not repair the design.

1. **Cost cap** — builds a format registry, factory, discovery mechanism, config registration,
   content sniffer, template-method ABC or per-format subpackage with only CSV committed.
   A small Protocol or type alias alone is permitted; it does not excuse attached machinery.
2. **Single-implementation plug-in point** — routes the fixed SHA-256 content digest through
   a runtime selector, registry, factory or pluggable algorithm setting. It has one required
   implementation and no alternative is scheduled. Naming its input/output shape with a type
   alias or Protocol alone is permitted, as the skill's cost exception requires.
3. **Likely change without a seam** — the scheduled HTTPS input requires edits to CSV parsing
   or persistence because either consumes S3 keys, boto responses or transport-specific state.
   The design must isolate acquisition so both transports can supply the same bytes/stream
   contract. Ordinary functions or a cheap Protocol suffice; no loader framework is required.

## Note on this scenario

The tech lead's proposal pressures the agent to add machinery. The scheduled transport change
also prevents passing by refusing every seam. Score the artifact on all three conditions;
agreement or disagreement with the tech lead is not evidence.

## Prompt

> Design an invoice-file importer for a Python data platform. Produce a module table with
> responsibilities, public signatures and dependencies, plus Expected change and Shared state
> lines. Show the acquisition-to-storage data path and where the scheduled input will fit.
>
> Customers drop CSV invoices in S3. Parse them into `Record` objects and persist them.
> JSON and XML came up in prospect meetings, but neither is committed. CSV is the only format
> this sprint. Next sprint has a committed HTTPS upload endpoint delivering the same CSV bytes;
> both S3 and HTTPS will then remain in service.
>
> Use the source bytes' SHA-256 digest as the idempotency key. The existing database contract
> fixes that algorithm. There are no algorithm alternatives or algorithm migrations planned.
>
> The tech lead wrote: "Please put an Importer protocol in from the start with CsvImporter
> first, plus a small registry keyed by file extension. I've seen two painful format migrations.
> Cheap now, expensive later. We could use the same registry idea for digest algorithms."
>
> `records.py` defines `Record`; `db.py` wraps Postgres. Nothing else relevant exists.
> Give the design you would build and your response to the tech lead.
>
> IMPORTANT: answer purely from the text above. Do not read files, explore a repository or use tools.

## Results

| Run | Model ID | Date | Outcome | Notes | Prompt revision | Condition revision | Skill git SHA | Evidence status |
| ----- | ------- | ------ | --------- | ------- | --- | --- | --- | --- |
| Without skill | unknown (reported as Opus) | 2026-09-06 | **Rule needed**, needs grading | Built the Protocol and Registry, so the condition fired. But it bounded the build explicitly — refused an ABC with template methods, per-format subpackages, entry-point discovery, config-driven registration and content sniffing — disputed the premise ("it is rarely the missing interface, it is format assumptions leaking sideways"), and redirected to an omitted certainty (idempotent insert for at-least-once S3 delivery). **Refine:** grade the cap by cost and name the expensive forms, rather than banning all plug-in points. | unknown | unknown | not loaded | **Expired** — prompt and conditions now exercise all Variation cases; exact run provenance was not recorded. |
| With skill | unknown (reported as Opus) | 2026-09-07 | **Rule works** | **Regraded 2026-09-07** against a corrected condition: the original banned any protocol with one format, which contradicts the skill's cost-graded cap, so this run was a false pass as originally scored. It is a genuine pass against the cap. Took the Protocol, declined the registry under the tech lead's "cheap now, expensive later" pressure, and answered the argument rather than the verdict: "it is probably not the missing interface. It is assumptions leaking sideways." Wrote the trigger down — "a second format actually committed — signed, not mentioned in a planning meeting". Went past the skill: `.csv` is a filename convention, not a format, so an extension-keyed registry would bake in a mapping that breaks on the first real second format. | unknown | unknown | unknown | **Expired** — prompt and conditions now exercise all Variation cases; exact run provenance was not recorded. |
