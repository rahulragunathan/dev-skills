# S05 — The four reporting rules

**Kind:** report

## Rules under test

1. Only fired checks get a line, including collective summaries.
2. A fired check states its resolution.
3. A fired check deliberately left unchanged gets a line with its reason.
4. No `PASS`, `N/A`, `OK`, "no issue", "nothing to flag", "clean", or equivalent filler verdicts.

This scenario tests the report artifact. Both runs receive the same fixture and six-check
rubric. Neither receives a different rounding rule or a hidden database dependency.

## The design under review, by intent

- **Responsibility fires and is acted on:** invoice delivery and price computation must be
  separated. The supplied final decision provides a concrete resolution to report.
- **Duplication fires and is left unchanged:** two identical money-display helpers have no
  fitting existing home. The supplied decision keeps the copies, providing a required rule 3
  case. Identical per-line tax rounding also moves into an existing fitting home.
- **Variation is silent:** no alternatives or likely format, provider or backend changes exist.
  No runtime plug-in points are present. The other fixture facts introduce no ambient state or
  caller setup. Do not manufacture findings to fill a report.

## Failure conditions

The report must cover all three supplied decisions. An empty answer, an empty findings section,
"No check fired", or a bare module table fails rules 2 and 3. Judge only the report the agent
produces; do not ask it afterwards what it considered.

1. **Rule 1** — names Variation or another silent check in a verdict, list or collective
   reassurance. Inventing a defect absent from the fixture to give a silent check a line also
   fails. Naming a unit or operation in a real resolution is not a silent-check verdict.
2. **Rule 2** — omits either acted-on decision, or gives its observation without the concrete
   resolution: split price computation from delivery, and use `taxes.round_line_tax` in both
   tax callers. "Consider separating" and "watch duplication" fail.
3. **Rule 3** — omits the retained money-helper duplication, fails to state that the two copies
   remain, or omits the reason: neither a fitting existing home nor a third consumer exists.
   Reporting an extraction contradicts the final decision and fails.
4. **Rule 4** — emits any banned or equivalent filler verdict about a check or the design.

## Prompt

> Write the design-review report to accompany this checkout design's final decisions.
>
> **Units and interfaces.** All operations are call-local. Dependencies are explicit arguments;
> no globals, caches, import-time setup, database handles or open resources are implicit.
>
> | Unit | Responsibility | Interface | Depends on |
> | --- | --- | --- | --- |
> | `taxes.py` | Round per-line tax | `round_line_tax(raw: Decimal) -> Money` | — |
> | `pricing.py` | Price order lines | `total(lines: list[Line], rates: Rates) -> Money` | `taxes` |
> | `adjustments.py` | Price adjustment lines | `total_adjustments(lines: list[Line], rates: Rates) -> Money` | `taxes` |
> | `checkout.py` | Price orders and deliver receipts | `checkout(lines: list[Line], rates: Rates, deliver: Callable[[Receipt], None]) -> Money` | `pricing` |
> | `receipt_text.py` | Render receipt text | `render(receipt: Receipt) -> str` | — |
> | `refund_text.py` | Render refund text | `render(refund: Refund) -> str` | — |
>
> Tax rounding is fixed by a long-standing contract. Pricing changes yearly. Checkout delivery
> policy and text layout change monthly. The two text modules change independently.
>
> **Final decisions for this report.**
>
> 1. Split `checkout.py`: price calculation stays in `pricing.py`; receipt delivery gets
>    `delivery.py` with `deliver_receipt(receipt, deliver) -> None`. Checkout only coordinates
>    the calls. Price policy and delivery policy change independently.
> 2. `pricing.py` and `adjustments.py` each copy the exact `taxes.round_line_tax` implementation:
>    round half up to two decimal places on each raw line tax before summing. They will call
>    `taxes.round_line_tax` at that same per-line stage. No order-total rounding is involved.
> 3. `receipt_text.py` and `refund_text.py` each keep their identical four-line money-display
>    helper. No third consumer is scheduled. `taxes.py` owns tax arithmetic, not money text;
>    no fitting shared display module exists. Do not create one for these two callers.
>
> No format, provider or backend alternatives are planned or discussed, and the design has no
> runtime selectors or registries.
>
> **Six checks:** Responsibility tests unrelated reasons to change. Direction tests cycles and
> dependencies on less stable units, with rows ordered by stability. Duplication permits a new
> shared home at three occurrences; two may use an existing fitting home, but stay copies when
> that home is a poor fit. Variation tests a likely change without a seam or a plug-in point
> with only one implementation; a cheap Protocol/type alias is permitted, but runtime machinery
> needs a second implementation that exists or is scheduled. Lifetime tests state reused across
> calls. Surface tests leaked internals or caller setup absent from a signature.
>
> Report the decisions against those checks.
>
> IMPORTANT: answer purely from the text above. Do not read files, explore a repository or use tools.

## Results

| Run | Model ID | Date | Rule 1 | Rule 2 | Rule 3 | Rule 4 | Notes | Prompt revision | Condition revision | Skill git SHA · content | Evidence status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Without skill (round 1) | `claude-opus-5` | 2026-09-07 | **Rule needed** | Rule not needed here | Rule not needed here | **Rule needed** | Opened with a six-row verdict table reading `Variation | Pass`, `Lifetime | Pass`, `Surface | Pass` for checks the fixture makes silent, then wrote prose sections headed "Lifetime: pass". Fails rule 1 on naming silent checks and rule 4 on the banned verdict. Substance was right on all three decisions. | `ba57ff9` · `a0032527302c3acf` | `ba57ff9` · `1c72d3ab44485175` (unchanged) | not loaded | Current — baseline, unaffected by a skill change |
| With skill (round 2) | `claude-opus-5` | 2026-09-08 | **Rule works** | **Rule works** | **Rule works** | **Rule works** | Three entries and nothing else — Responsibility resolved, Duplication resolved, Duplication deliberately kept with its reason. Variation, Lifetime and Surface absent rather than summarised. No banned verdict. Same three substantive decisions as the baseline. | `ba57ff9` · `a0032527302c3acf` | `ba57ff9` · `1c72d3ab44485175` (unchanged) | `a850251` · `c59ee5bc8b253397` | **Expired** — loaded skill changed at `a8803f6`; re-gather before review |
