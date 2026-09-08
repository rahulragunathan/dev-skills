# S02 — Lifetime and Surface

**Kind:** build

## Rules under test

- **Lifetime** — state reused across calls must have a safe owner and scope.
- **Surface** — consumer requirements belong in the callable or constructor signature.

## What the subagent should do

Keep upload data and validation results local to each call. Shared compiled rules must be
immutable after publication and isolated from merchant overrides. Make a fresh consumer able
to use the API from its arguments, with no hidden initialization sequence.

## Failure conditions

Judge the table, signatures and ownership design together. Missing ownership or API detail
needed to establish these properties fails the affected check; naming a risk is not a repair.

1. **Lifetime** — the design permits one upload to read or overwrite another's rows, errors,
   merchant overrides or mutable validation state through a shared object. Fail an unbounded
   shared cache, unsafe concurrent cache publication, or shared clients whose specified
   lifecycle permits cross-thread use of request state. A cache of immutable category rules
   with bounded keys and safe publication passes; call-local state also passes. Merely saying
   "process-local", "thread-safe" or "verify gunicorn" cannot override unsafe ownership.
2. **Surface** — a consumer must warm a cache, mutate module configuration, rely on an
   import-time side effect, set a global merchant, or call setup in an undocumented order
   before invoking a public operation. Putting that requirement in prose does not pass. Each
   required input or initialized dependency must be supplied by an explicit argument or
   constructor, or obtained automatically by the callable without caller-managed setup.
   Fail signatures that expose raw parser internals or database handles unrelated to the
   consumer's task rather than a usable validation or persistence interface.

## Prompt

> Design CSV listing uploads for an existing Python web service. Produce a module table with
> responsibilities, public signatures and dependencies, plus Expected change and Shared state
> lines. Show the consumer's call sequence and who owns any objects reused across uploads.
>
> Merchants upload up to 50,000 rows. Validate each row against its category rules and return
> rejected rows with reasons. Each upload also supplies merchant-specific allowed-value
> overrides; these apply only to that upload. Validation is the slow part.
>
> The repo ships 400 category YAML files under `rules/`. Each compiles to about 60 regexes in
> 40 ms; compiling all categories costs 16 seconds. An upload touches three or four categories.
> Catalogue edits ship with a deploy a few times a week. Workers restart on every deploy.
>
> `db.py` wraps the Postgres pool; `listings.py` has the `Listing` model and CRUD;
> `taxonomy.category_for(sku_prefix) -> str` caches its static lookup with `lru_cache`.
> Gunicorn uses four worker processes, each with eight request threads. Uploads overlap.
>
> Give the design you would build and a short paragraph for its reviewer.
>
> IMPORTANT: answer purely from the text above. Do not read files, explore a repository or use tools.

## Results

| Run | Model ID | Date | Lifetime | Surface | Notes | Prompt revision | Condition revision | Skill git SHA · content | Evidence status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Without skill | `claude-opus-5` | 2026-09-07 | Rule not needed here | Rule not needed here | `lru_cache` of frozen `CompiledCategory`, stated as bounded at 400 keys, with overrides applied as a read-time overlay and never merged in — written as an invariant, with a concurrency test proposed against it. `run_upload(merchant_id, stream, override_payload)` needs no warmup or setup. Raised GIL contention unprompted. **Second attempt: the first baseline invoked the installed `design-review` plugin skill and was voided.** | `ba57ff9` · `7ce7ec8fb0454659` | `f2d9d679e9b917fb` | not loaded | Current |
| With skill | `claude-opus-5` | 2026-09-07 | **Rule works** | **Rule works** | Same cache shape and the same overlay invariant. Additionally split `rule_compiler.py` from `rule_registry.py` on Responsibility, and moved reader construction out of `process_upload` so the upload workflow stops depending on the CSV format. | `ba57ff9` · `7ce7ec8fb0454659` | `f2d9d679e9b917fb` | `d0eb8c7` · `0cb4d2391762d995` | Current |
