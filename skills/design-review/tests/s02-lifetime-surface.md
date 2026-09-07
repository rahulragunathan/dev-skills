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

| Run | Model ID | Date | Lifetime | Surface | Notes | Prompt revision | Condition revision | Skill git SHA | Evidence status |
| ----- | ------- | ------ | ---------- | --------- | ------- | --- | --- | --- | --- |
| Without skill | unknown (reported as Opus) | 2026-09-06 | Rule not needed here | Rule not needed here | Named the cache boundary as process-local, addressed fork safety and `preload_app` unprompted, noted the lock-free race costs one wasted 40 ms compile, and flagged that it was adding a second cache alongside `taxonomy`'s with a different lifetime and eviction policy — "a reviewer should see it named rather than assume I missed it". Kept `validate_row` taking the ruleset explicitly so it never reaches the cache. | unknown | unknown | not loaded | **Expired** — prompt now fixes concurrency and conditions inspect ownership and usable APIs; exact run provenance was not recorded. |
| With skill | unknown (reported as Opus) | 2026-09-07 | **Rule works** | **Rule works** | Lifetime: named process lifetime, one copy per gunicorn worker, the 400-entry bound, immutability after publication, and that a threaded double-compile wastes 40 ms and cannot corrupt anything, so no lock. Stated the invariant the rule exists for: "Nothing merchant-specific or request-specific goes into a cached object, which is the single rule the module exists to hold." Surface: "there is no `warm()` or `preload()` entry point... no setup step a caller can forget or call in the wrong order." Declined Duplication at two using the threshold's second half exactly — "no shared cache module already exists to move them into". | unknown | unknown | unknown | **Expired** — prompt now fixes concurrency and conditions inspect ownership and usable APIs; exact run provenance was not recorded. |
