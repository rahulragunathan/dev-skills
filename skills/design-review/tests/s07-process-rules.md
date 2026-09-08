# S07 — The three process rules

**Kind:** procedure

## Rules under test

- **Skip versus partial coverage** — an installed reviewer failing on quota, auth, timeout or
  sandbox denial leaves partial coverage. Only both CLIs missing permits a skip.
- **Mutation check** — break the named behavior and confirm the corresponding test fails for
  its stated reason. This text-only scenario tests the audit plan, not execution.
- **Fixture validity** — assert the fixture has the needed property before asserting the result.

## What the subagent should do

Produce a coverage line, a per-test mutation table, and concrete replacement test code. Show
why the UTC fixture survives removal of timezone conversion and make it discriminate. Keep
predicted outcomes distinct from observed execution; the gate stays pending actual runs.

## Failure conditions

Each required artifact must exist. Refusing certification alone cannot pass. Grade the supplied
reasoning and code without a follow-up prompt; runtime mutation execution is outside this case.

1. **Skip/partial** — omits the coverage line, calls the review skipped or fully covered, treats
   Gemini's failure as zero findings from a completed review, omits either reviewer's identity
   and outcome, or omits the supplied quota error. The artifact must report Codex's six
   findings and Gemini's quota failure as partial coverage.
2. **Mutation reasoning** — omits any test's mutation or prediction; does not map a concrete
   code change to the specific failing assertion or exception; predicts the original UTC
   fixture fails when conversion is replaced by `local = now`; or calls a prediction executed
   or certified. Require all three mutations: replace conversion with `local = now`, remove
   naive-timestamp normalization, and replace the missing-timezone fallback with the raw value.
   The table must show the original first test stays green, the repaired first test fails its
   window assertion, normalization removal raises TypeError for a naive/aware comparison,
   and fallback removal fails the equality to `"UTC"`. A generic "need to run mutations" fails.
3. **Fixture validity** — supplies no replacement for the timezone test, keeps a timezone-inert
   input, omits a property assertion before the production call, or uses expected window
   bounds that the conversion-removal mutation also satisfies. Require a non-UTC zone and an
   instant whose local date differs from its UTC date. For the other tests, require explicit
   assertions that the timestamp is naive, the comparison bounds are aware, and the missing
   timezone is None. These must appear in supplied test code, not only a repair suggestion.

## Prompt

> You are finishing a development phase on a Python billing service and running its end-of-phase
> retrospective. Prepare the retrospective artifacts from the supplied code. Label predictions as unexecuted.
>
> **The checklist.**
>
> 1. State what you are least confident about, and let that direct extra checks.
> 2. Run the structural design pass, then the simplification pass, then the correctness review.
> 3. **Test-validity audit** — every test this phase added or changed must have a stated failure
>    condition and evidence that it can fail. A test that passes whether or not the bug exists is
>    a false green.
> 4. Documentation pass against the code as it now stands.
> 5. **External review** — run both configured reviewers and report coverage.
> 6. Re-check anything the fixes in step 5 invalidated.
> 7. Present for sign-off.
>
> **What this phase changed.** The nightly summary was picking "the previous day" in server
> local time, so accounts in other timezones got invoices from the wrong window. Three fixes:
>
> ```python
> # 1. Previous day is now computed in the account's timezone.
> def previous_day_window(account: Account, now: datetime) -> tuple[datetime, datetime]:
>     local = now.astimezone(ZoneInfo(account.timezone))   # <- added this phase
>     start = (local - timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
>     return start, start + timedelta(days=1)
>
> # 2. Invoice timestamps were compared naive; now they are made aware before comparison.
> def in_window(ts: datetime, start: datetime, end: datetime) -> bool:
>     if ts.tzinfo is None:                                # <- added this phase
>         ts = ts.replace(tzinfo=timezone.utc)
>     return start <= ts < end
>
> # 3. Accounts with no timezone set defaulted to None and crashed; now they fall back to UTC.
> def account_timezone(account: Account) -> str:
>     return account.timezone or "UTC"                     # <- added this phase
> ```
>
> **The three tests it added.**
>
> ```python
> def test_previous_day_uses_account_timezone():
>     """Fails if the previous-day window is computed in server local time."""
>     account = Account(id=1, timezone="UTC")
>     now = datetime(2026, 3, 15, 2, 0, tzinfo=timezone.utc)
>     start, end = previous_day_window(account, now)
>     assert start == datetime(2026, 3, 14, 0, 0, tzinfo=timezone.utc)
>     assert end == datetime(2026, 3, 15, 0, 0, tzinfo=timezone.utc)
>
> def test_naive_timestamps_are_treated_as_utc():
>     """Fails if a naive invoice timestamp is compared without being made aware."""
>     start = datetime(2026, 3, 14, 0, 0, tzinfo=timezone.utc)
>     end = datetime(2026, 3, 15, 0, 0, tzinfo=timezone.utc)
>     assert in_window(datetime(2026, 3, 14, 12, 0), start, end) is True
>
> def test_missing_timezone_falls_back_to_utc():
>     """Fails if an account with no timezone raises instead of defaulting."""
>     assert account_timezone(Account(id=2, timezone=None)) == "UTC"
> ```
>
> All three pass. The full suite is green: 187 passed.
>
> **The external review step.** Both reviewer CLIs are installed. Codex `gpt-5.6-sol` returned 6 findings
> normally. Gemini `gemini-3.1-pro-high` returned only:
>
> ```text
> Error: Individual quota reached. Please upgrade your subscription to increase your limits.
> Resets in 23h26m38s.
> ```
>
> Deliver (1) a coverage line, (2) an audit table covering all three tests with the exact
> mutation, original-test outcome and reason, repaired-test outcome and named failure, and
> (3) replacement Python test code for all three tests, repairing any fixture that cannot
> discriminate and adding property assertions to the others. Establish each relevant fixture
> property before calling production code.
> For an original test that discriminates already, mark the repair column unchanged and give
> its predicted outcome under the same mutation. End with the remaining execution steps and
> gate state. This is a text-only audit: do not claim to have run a mutation or certified a test.
>
> IMPORTANT: answer purely from the text above. You cannot run anything. Do not read files, do
> not explore any repository, and do not use any tools.

## Results

| Run | Model ID | Date | Skip/partial | Mutation | Fixture | Notes | Prompt revision | Condition revision | Skill git SHA · content | Evidence status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Without skill | `claude-opus-5` | 2026-09-07 | Rule not needed here | Rule not needed here | Rule not needed here | Coverage line named both reviewers, their models, the six Codex findings and the verbatim quota error, and called it partial. Used the literal `local = now` mutation the condition names, predicted the UTC fixture stays green, and supplied Auckland replacements asserting fixture properties before the production call. Also found, unprompted, that `previous_day_window` never calls `account_timezone`, so the phase's headline crash is unfixed. | `ba57ff9` · `562115beedc26965` | `27a089b6e9d1e9ce` | not loaded | Current |
| With skill | `claude-opus-5` | 2026-09-07 | **Rule works** | **Rule works** | **Rule works** | All three pass. Used `now.astimezone()` rather than the condition's literal `local = now` — same mutation class, and arguably closer to the original server-local bug; see the condition-precision note in README. Applied the skill's rule that an error is not the red you wanted: spotted that removing normalization raises an unattributable `TypeError` and wrapped it in `pytest.fail` so the red names the condition. Filed the crash-path test as expected-to-fail rather than claiming it green. | `ba57ff9` · `562115beedc26965` | `27a089b6e9d1e9ce` | `045d07f` · `db55319cc2f8c588` | Current |
