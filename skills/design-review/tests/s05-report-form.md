# S05 — The four reporting rules

**Kind:** report · **Model:** Sonnet

## Rules under test

1. Only what fired gets a line. A check with nothing to say is silent — not summarized, not
   listed, not named, not even collectively.
2. A fired check states its **resolution**, not the observation.
3. A check that fires and is deliberately not acted on still gets its line, with the reason.
4. Never write `PASS` or `N/A`.

This scenario is a *report* test rather than a *build* test, because the thing under test is
the shape of the report itself.

## The design under review, by intent

- **Responsibility fires and is acted on** — `orders.py` both prices an order and reserves
  stock.
- **Duplication fires and is acted on** — the tax rounding rule appears twice and `taxes.py`
  already owns the rule, so the refined threshold says it moves into the home that exists rather
  than staying as two copies. *(This section described the older naive "leave it at two"
  threshold until 2026-09-07. Two consecutive runs moved it and were right to.)*
- **Rule 3's vehicle is Responsibility on `orders.py`** — "price it, then reserve against it" is
  one job, and declining the split with a stated extraction trigger is the fired-but-not-acted-on
  case the rule exists for.
- **Variation has nothing to say** and should produce no line. *(Direction, Lifetime and Surface
  were listed here as silent too, but the fixture carries genuine issues in all three — a
  call-ordered table, reservations nothing releases, and `reserve` writing through an unmentioned
  `db`. They fire legitimately. Variation is the reliable silent check, and it is the one rule 1
  is judged against.)*

## Failure conditions

1. **Rule 1 fails** if a check with nothing to say is given a line, listed, or named —
   **including collectively in one closing sentence** ("Direction, Variation, Lifetime and
   Surface are all fine"). Judge against the checks that are genuinely silent in the run being
   graded, not a fixed list: this fixture carries real Direction, Lifetime and Surface issues,
   so those fire legitimately and **Variation** is the reliable silent one. The only permitted
   summary is *"No check fired."*, and only when nothing fired at all.
2. **Rule 2 fails** if a fired check reports an observation with no resolution — "worth
   watching", "considered", "may want to revisit" — rather than what was decided.
3. **Rule 3 fails** if a check that fired and was deliberately **not** acted on appears
   nowhere with its reason. Any such check counts — the duplication decision is the expected
   vehicle, but a declined Responsibility split with a stated extraction trigger satisfies it
   just as well.
4. **Rule 4 fails** on any `PASS`, `N/A`, `OK`, "no issue", "nothing to flag", or equivalent
   filler verdict.

Rules 1 and 4 already came back **Rule needed** on an earlier version of this scenario. Rule 2
was probed and came back **Rule not needed here** on Opus. Rule 3 is exercised whenever a check fires and is declined; s01 and s03 exercise it too.

## Prompt

> Review this module design against the six design checks below and report your findings.
>
> **The design.** A checkout service.
>
> | Unit | Responsibility | Interface | Depends on |
> | --- | --- | --- | --- |
> | `orders.py` | Price an order and reserve stock against it | `place(cart, customer) -> Order` | `pricing`, `inventory` |
> | `pricing.py` | Apply price list, discounts and tax | `total(lines) -> Money` | `taxes` |
> | `taxes.py` | Compute tax per line | `tax_for(line) -> Money` | — |
> | `inventory.py` | Reserve and release stock | `reserve(sku, qty) -> Reservation` | `db` |
>
> **Notes on the code.** The rounding rule for tax ("round half up at two decimal places, per
> line, never on the order total") is implemented in `taxes.tax_for` and again in
> `pricing.total`, which re-rounds after summing. Both copies are correct and identical.
>
> No caches, clients or shared objects exist anywhere in this design. Every function takes what
> it needs as arguments. No future format, backend or provider change is planned or under
> discussion.
>
> **The six checks.**
>
> 1. **Responsibility** — does any unit have more than one reason to change?
> 2. **Direction** — do dependencies point one way?
> 3. **Duplication** — is anything now appearing a third time? Three occurrences is the
>    trigger; two is left alone.
> 4. **Variation** — what's likely to change, and is there a place to change it?
> 5. **Lifetime** — does any state outlive one call?
> 6. **Surface** — can a consumer use this unit without reading its internals?
>
> Report your review.
>
> IMPORTANT: answer purely from the text above. Do not read files, do not explore any
> repository, and do not use any tools.

## Results

| Run | Model | Date | Rule 1 | Rule 2 | Rule 3 | Rule 4 | Notes |
| ----- | ------- | ------ | -------- | -------- | -------- | -------- | ------- |
| Without skill | Opus | 2026-09-06 | **Rule needed** | Rule not needed here | Rule not needed here | **Rule needed** | Lines for all six; Responsibility and Direction genuinely silent and both got one. States decisions, not observations — "leave it", "Delete it". Recorded the declined duplication with reasoning. "clean" five times, an equivalent filler verdict. Fixture corrected for this run (added `release()`), so Surface is not comparable with the Sonnet row; rules 1, 2, 4 are. **Stale:** this scenario's failure condition changed on 2026-09-07 and this baseline predates it. Re-run before citing it. |
| With skill | Opus | 2026-09-07 | **Rule works** | **Rule works** | **Rule works** | **Rule works** | The loose wording is fixed: Variation, the one genuinely silent check, got no line, no list and no collective closing sentence. Rule 3 is **now exercised** — via Responsibility on `orders.py`, declined with an extraction trigger — which closes the gap the previous run left. Direction fired on the fixture's own presentation: "the table is ordered by call order, so the check has not been run", then rebuilt it by what makes each unit change. That is the circularity the rewrite exists to prevent, caught unprompted in someone else's table. |
