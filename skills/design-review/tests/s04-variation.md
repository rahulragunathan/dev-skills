# S04 — Variation and the YAGNI cap

**Kind:** build · **Model:** Sonnet

## Rules under test

- **Variation** — what's likely to change, and is there a place to change it?
- The YAGNI cap: no plug-in point without a second implementation that exists or is scheduled.

## Failure conditions

**Fails** if the produced design introduces an abstraction over input formats — an interface,
abstract base class, protocol, strategy, registry, factory, or a `formats/` package — while
exactly one format exists and none is committed.

Adding a differently-named concrete function later (`import_json`) is not a failure; that is
the correct answer. Naming the risk and declining to build for it is also correct.

## Note on this scenario

Two earlier versions came back green: the agent declined the abstraction firmly both times,
including once with the "nothing is scheduled" framing removed. This version adds the pressure
that actually produces over-engineering in practice — a senior colleague who has already
proposed the abstraction, so declining it means disagreeing with someone rather than merely
choosing a design.

If this run is also green, the honest conclusion is cause 3 in the README: the model does this
correctly on its own and the rule is insurance. Record it that way rather than softening the
condition.

## Prompt

> You are designing a feature for an existing Python data platform. Produce the module design:
> which files exist, what each is responsible for, its public functions with signatures, and
> what it depends on.
>
> **The feature.** Customers drop invoice files into an S3 bucket. Build the importer that
> parses them into `Record` objects and persists them.
>
> **Format situation.** Every customer sends CSV today. In last week's planning meeting two
> prospects were mentioned as having asked about JSON feeds, and one existing customer sends
> XML to a competitor. Nothing has been committed and this sprint is the CSV path only.
>
> **Your tech lead's note on the ticket**, verbatim:
>
> > Please put an `Importer` protocol in from the start with `CsvImporter` as the first
> > implementation, plus a small registry keyed by file extension. I've been through two
> > migrations where we bolted formats on afterwards and it was a mess both times. Cheap now,
> > expensive later.
>
> **What exists today.** `records.py` defines the `Record` dataclass. `db.py` wraps Postgres.
> Nothing else relevant.
>
> Give the module design you would actually build, and say how you would respond to the tech
> lead's note.
>
> IMPORTANT: answer purely from the text above. Do not read files, do not explore any
> repository, and do not use any tools.

## Results

| Run | Model | Date | Outcome | Notes |
| ----- | ------- | ------ | --------- | ------- |
| Without skill | Sonnet | 2026-09-06 | **Rule needed** | Built the Protocol, an extension-keyed registry and an `importers/` package for one format. The same model refused this twice when the tech lead's note was absent, so social pressure is what flips it. |
| Without skill | Opus | 2026-09-06 | **Rule needed**, needs grading | Built the Protocol and Registry, so the condition fired. But it bounded the build explicitly — refused an ABC with template methods, per-format subpackages, entry-point discovery, config-driven registration and content sniffing — disputed the premise ("it is rarely the missing interface, it is format assumptions leaking sideways"), and redirected to an omitted certainty (idempotent insert for at-least-once S3 delivery). **Refine:** grade the cap by cost and name the expensive forms, rather than banning all plug-in points. |
| With skill | Opus | 2026-09-06 | **Rule works** | Built the Protocol ("fifteen lines, no runtime machinery... its real work today is stopping CSV detail leaking sideways") and declined the registry ("a plug-in point that only ever holds one thing"), replacing it with a three-line `importer_for` with one branch. Exactly what the graded cap prescribes. Turned the skill's counter-argument into a question back to the tech lead rather than a refusal, and flagged the residual assumption the cap does not cover: extension keying breaks when a customer sends CSV as `.txt`. **Superseded** — ran against the pre-2026-09-07 skill. |
| With skill | Opus | 2026-09-07 | **Rule works** | Took the Protocol, declined the registry under the tech lead's "cheap now, expensive later" pressure, and answered the argument rather than the verdict: "it is probably not the missing interface. It is assumptions leaking sideways." Wrote the trigger down — "a second format actually committed — signed, not mentioned in a planning meeting". Went past the skill: `.csv` is a filename convention, not a format, so an extension-keyed registry would bake in a mapping that breaks on the first real second format. |
