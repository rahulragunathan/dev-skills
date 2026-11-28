# S02 — Lifetime and Surface

**Kind:** build

**Loads:** design-review

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
> `taxonomy.category_for(sku_prefix) -> str` caches its static lookup with
> `@lru_cache(maxsize=None)`, taking the caller's prefix string as its argument.
> Gunicorn uses four worker processes, each with eight request threads. Uploads overlap.
>
> Give the design you would build and a short paragraph for its reviewer.
>
> IMPORTANT: answer purely from the text above. Do not read files, explore a repository or use tools.

## Results

| Run | Model ID | Date | Lifetime | Surface | Notes | Prompt revision | Condition revision | Skill git SHA · content | Evidence status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Without skill (round 1) | `claude-opus-5` | 2026-09-07 | Rule not needed here | Rule not needed here | Bounded `lru_cache` of frozen `CompiledCategory`, overrides applied as a read-time overlay and never merged in, stated as an invariant with a concurrency test proposed against it. `run_upload(merchant_id, stream, override_payload)` needs no warmup. **This is the second attempt: the first baseline invoked the installed `design-review` plugin skill and was voided.** | `ba57ff9` · `7ce7ec8fb0454659` | `ba57ff9` · `f2d9d679e9b917fb` (unchanged) | not loaded | Expired — superseded prompt or condition revision; historical grade retained |
| With skill (round 3) | `claude-opus-5` | 2026-09-08 | **Rule works** | **Rule works** | Same split of lifetimes — the cache holds only the deploy-lifetime half, keyed by category name, and `validate_row` takes overrides as a third argument unioned at check time. Named the race on a cold key and left it deliberately, because the two results are equal and immutable. Inverted `service` → `csv_reader` so the upload's steps stop depending on the merchants' file format. **Displaced from the Condition revision column by the round-3 write and retained here:** Same frozen cache and override-overlay split. Applied the delivery-content clause unprompted: moved rejection message copy out of the service because "message copy is policy that merchandising edits on its own schedule". `UploadResult` now reports `rejected_total` and `truncated`, so no caller has to read the service to learn the cap. | `ba57ff9` · `7ce7ec8fb0454659` | `f2d9d679e9b917fb` | `07e1769` · `fcda7a2da8058dd8` | Expired — superseded prompt or condition revision; historical grade retained |
| Without skill (round 4) | `claude-opus-5` | 2026-09-09 | **Rule needed** | Rule not needed here | compiled_rules is keyed by category, bounded, and passes. taxonomy.category_for is given the same justification, but its keys are SKU prefixes supplied by the upload, up to 50,000 per file, so the bound that justification rests on does not exist there. | `6384050` · `7ce7ec8fb0454659` | `f2d9d679e9b917fb` | not loaded | Expired — superseded prompt or condition revision; historical grade retained |
| With skill (round 4) | `claude-opus-5` | 2026-09-09 | **Rule works** | **Rule works** | Frozen rules keyed by category only, with per-upload overrides applied through a copying with_overrides so nothing merchant-scoped can enter the cache. Names the taxonomy cache explicitly and requires its maxsize be bounded before shipping. process_upload takes a stream, a merchant id and an Overrides value, so no caller setup is implied. | `6384050` · `7ce7ec8fb0454659` | `f2d9d679e9b917fb` | `07e1769` · `fcda7a2da8058dd8` | Expired — superseded prompt or condition revision; historical grade retained |
| Without skill (round 5) | `claude-opus-5` | 2026-09-09 | Rule not needed here | Rule not needed here | Both units pass cold. The baseline names the taxonomy cache a merchant-triggered memory exhaust and tells the reader to fix it before the upload path ships. That is the repaired fixture doing too much work — see the note below. | `5ab48ea` · `a8e14d84ce4cac51` | `f2d9d679e9b917fb` | not loaded | Expired — superseded prompt or condition revision; historical grade retained |
| With skill (round 5) | `claude-opus-5` | 2026-09-09 | **Rule works** | **Rule works** | Both hold, and the resolution is stronger: the cache is replaced with the static dict it was caching rather than merely bounded. But the baseline reached the same finding, so this unit no longer discriminates. | `5ab48ea` · `a8e14d84ce4cac51` | `f2d9d679e9b917fb` | `07e1769` · `fcda7a2da8058dd8` | Expired — superseded prompt or condition revision; historical grade retained |
| Without skill (round 7, n=3) | `claude-opus-5` | 2026-09-09 | **Unstable** (2/3) | Rule not needed here (3/3) | Three replicates against the corrected fixture, which now states @lru_cache(maxsize=None) keyed on the caller's string and leaves the consequence to the reader. Two runs name the leak unprompted; one notices the hazard and its precondition — "safe only while keys are bounded prefixes" — without ever establishing it, which is the same failure as S07 2b: noticing is not doing. | `c0c1797` · `ff76fc3a6dc19f2a` | `f2d9d679e9b917fb` | not loaded | Current |
| With skill (round 7, n=3) | `claude-opus-5` | 2026-09-09 | **Unstable** (2/3) | **Rule works** (3/3) | Pass-10 correction: replicate 3 leaves taxonomy unchanged and unbounded, offers unresolved alternatives, and assumes normalization bounds keys without defining a finite key space. Lifetime fails for that artifact. Recorded tally: 2/3; Surface remains 3/3. Archived answer unchanged. | `c0c1797` · `ff76fc3a6dc19f2a` | `f2d9d679e9b917fb` | `07e1769` · `fcda7a2da8058dd8` | **Superseded** by round 9 (2026-09-14): loaded skill revision changed |
| Without skill (round 9, n=5) | `claude-opus-5` | 2026-09-14 | Rule not needed here (5/5) | Rule not needed here (5/5) | Replicate 2 bounds the existing unbounded `taxonomy` cache only through an undefined `normalise_prefix` format check. The round-7 correction treated that as a Lifetime failure, so this pass is disputed pending re-grading ([ENH-44](../../../docs/ENHANCEMENTS.md#enh-44)). Its repeat grade split: the first repeat grader failed Lifetime and was refused because its quote dropped a Markdown pipe escape (KI-36). Model-graded: first blind claude-opus-5 grade per answer from grade_batch.py; the 14 repeat answers agreed 40/40. | `c0c1797` · `ff76fc3a6dc19f2a` | `f2d9d679e9b917fb` | not loaded | Current |
| With skill (round 9, n=5) | `claude-opus-5` | 2026-09-14 | **Unstable** (4/5) | **Rule works** (5/5) | Replicate 3 leaves the existing unbounded `taxonomy` cache in place and bounds it only by a SKU format check that no interface defines. Both graders failed Lifetime. This repeats the round-7 replicate-3 failure. Model-graded: first blind claude-opus-5 grade per answer from grade_batch.py; the 14 repeat answers agreed 40/40. | `c0c1797` · `ff76fc3a6dc19f2a` | `f2d9d679e9b917fb` | `fe19162` · `47196f444f840946` | Current |
