# S02 — Lifetime and Surface

**Kind:** build

## Rules under test

- **Lifetime** — does any state outlive one call?
- **Surface** — can a consumer use this unit without reading its internals?

## What the subagent should do

Notice that the design carries state across calls, say which boundary it is shared across
(request, thread, process), and either establish that sharing is safe or scope it so the
question does not arise. Keep requirements a caller must satisfy visible in the signature.

The earlier version said "module-level global, reused by every call" and "threaded workers, so
several requests run concurrently." That hands over the answer. This version hides the state in
things that read as ordinary utilities — a cache on a compile step, a ruleset built once — and
mentions the worker model only as a deployment aside, well away from the code.

## Failure conditions

1. **Lifetime** — the design carries state across calls and **does not name the boundary it is
   shared across or what makes that safe**. Concluding it is "probably fine" without requiring
   verification is the failure, not merely failing to spot the object.
2. **Surface** — a produced function requires the caller to have arranged something not visible
   in its signature — module-level configuration, an import-time side effect, a preloaded cache
   — without that requirement being stated.

## Prompt

> You are designing a new feature for an existing Python web service. Produce the module
> design: which files exist, what each is responsible for, its public functions with
> signatures, and what it depends on.
>
> **The feature.** Merchants upload a CSV of product listings. Each row must be validated
> against that merchant's category ruleset before it is accepted, and rejected rows come back
> to the merchant with a reason. Validation is the slow part: the rulesets are regex-heavy and
> a large upload is 50,000 rows.
>
> **What the rulesets are.** One YAML file per category, about 400 of them, shipped in the repo
> under `rules/`. Each compiles to roughly 60 regexes. Compiling one category takes about 40 ms;
> compiling all of them takes about 16 seconds. A merchant's upload usually touches three or
> four categories. Category rulesets change when the catalogue team edits the YAML, which
> happens a few times a week and ships with a deploy.
>
> **What exists today.** `db.py` wraps the Postgres connection pool. `listings.py` holds the
> `Listing` model and its CRUD. `taxonomy.py` exposes `category_for(sku_prefix) -> str`, and it
> already does its own `@lru_cache` on that lookup because the mapping is static.
>
> **Deployment.** The service runs under gunicorn. The current arguments are in
> `deploy/gunicorn.conf.py` and have not changed in two years.
>
> Give the module design. Then write a short paragraph on anything about the structure you
> would flag to a reviewer.
>
> IMPORTANT: answer purely from the text above. Do not read files, do not explore any
> repository, and do not use any tools.

## Results

| Run | Model | Date | Lifetime | Surface | Notes |
| ----- | ------- | ------ | ---------- | --------- | ------- |
| Without skill | Opus | 2026-09-06 | Rule not needed here | Rule not needed here | Named the cache boundary as process-local, addressed fork safety and `preload_app` unprompted, noted the lock-free race costs one wasted 40 ms compile, and flagged that it was adding a second cache alongside `taxonomy`'s with a different lifetime and eviction policy — "a reviewer should see it named rather than assume I missed it". Kept `validate_row` taking the ruleset explicitly so it never reaches the cache. |
| With skill | Opus | 2026-09-07 | **Rule works** | **Rule works** | Lifetime: named process lifetime, one copy per gunicorn worker, the 400-entry bound, immutability after publication, and that a threaded double-compile wastes 40 ms and cannot corrupt anything, so no lock. Stated the invariant the rule exists for: "Nothing merchant-specific or request-specific goes into a cached object, which is the single rule the module exists to hold." Surface: "there is no `warm()` or `preload()` entry point... no setup step a caller can forget or call in the wrong order." Declined Duplication at two using the threshold's second half exactly — "no shared cache module already exists to move them into". |
