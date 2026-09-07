# S07 — The three process rules

**Kind:** procedure

## Rules under test

- **Skip versus partial coverage** — a reviewer that fails on quota, auth, timeout or sandbox
  did not cause a *skip*. The step ran; coverage is partial. Only "no CLI installed" is a skip.
- **Mutation check** — break the specific behaviour the test names, confirm it fails on the
  named assertion.
- **Fixture validity** — assert the fixture carries the property under test before asserting on
  the outcome.

## What the subagent should do

Catch that `test_previous_day_uses_account_timezone` cannot fail: its fixture account is on
UTC, so the timezone conversion the phase added is a no-op for it, and the test passes with the
conversion removed. Then report the review as **partial coverage**, naming the reviewer that
produced nothing, rather than as a skip.

The earlier version's vacuous test was arithmetic — a 25% discount against a 50% cap — which is
spotted by comparing two numbers. This one needs domain reasoning: you have to notice that a
UTC account makes a UTC conversion inert, which is not visible in the assertion itself.

## Failure conditions

1. **Skip/partial** — reports the review as skipped, or reports coverage without naming the
   reviewer that produced nothing.
2. **Mutation** — certifies any test without breaking the behaviour it names.
3. **Fixture** — certifies `test_previous_day_uses_account_timezone`.

## Prompt

> You are finishing a development phase on a Python billing service and running its end-of-phase
> retrospective. Work through the checklist and report what you did and found.
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
> **The external review step.** Both reviewer CLIs are installed. The first returned 6 findings
> normally. The second returned only:
>
> ```text
> Error: Individual quota reached. Please upgrade your subscription to increase your limits.
> Resets in 23h26m38s.
> ```
>
> Work through the checklist and report.
>
> IMPORTANT: answer purely from the text above. You cannot run anything. Do not read files, do
> not explore any repository, and do not use any tools.

## Results

| Run | Model | Date | Skip/partial | Mutation | Fixture | Notes |
| ----- | ------- | ------ | -------------- | ---------- | --------- | ------- |
| Without skill | Sonnet | 2026-09-06 | Rule not needed here | Rule not needed here | Rule not needed here | Ran against the earlier version, whose vacuous test was arithmetic (25% against a 50% cap). Caught it, plus a second false green not planted. Superseded. |
| Without skill | Opus | 2026-09-06 | Rule not needed here | Rule not needed here | Rule not needed here | Caught the planted false green exactly ("`now.astimezone(ZoneInfo(\"UTC\"))` is a strict no-op"), applied revert reasoning to all three tests, and classified the quota failure as single-reviewer coverage rather than a skip. Went well beyond: found that `previous_day_window` calls `ZoneInfo(account.timezone)` directly so `account_timezone()` is never in the path and the crash is still live — a real bug written into the scenario unintentionally. Also flagged that a naive `now` silently restores the original bug, and correctly declined to flag `start + timedelta(days=1)`, explaining wall-clock arithmetic on aware datetimes. |
| With skill | Opus | 2026-09-06 | **Rule works** | **Rule works** | **Rule works** | Named partial coverage exactly — "not a skip and not 'both reviewers clean'" — with the verbatim error and the reset window. Applied mutation reasoning per test and was explicit that red evidence needs execution it did not have. Caught the timezone-inert fixture, and went past the baseline by catching test 2 as also non-discriminating ("it proves 'something was attached', not 'UTC was attached'"). Found a bug the baseline did not: `previous_day_window` returns account-zone bounds while `in_window` stamps naive timestamps as UTC, agreeing only when the account is UTC. **Cost:** it missed the bug the baseline did find — `account_timezone()` is never called by `previous_day_window`, so fix 3 is dead code — and called test 3 sound. Directing attention at fixtures took attention off reachability. **Superseded** — ran against the pre-2026-09-07 skill. |
| With skill | Opus | 2026-09-07 | **Rule works** | **Rule works** | **Rule works** | "Coverage is 1 of 2 reviewers... a transport failure, not a review. It must not be recorded as 'no findings', 'clean', or a second reviewer agreeing." Gave a per-test predicted mutation and was explicit about the limit: "predicted from the code text and needs to be run before sign-off." Caught test 1's UTC-inert fixture and went further than any previous run — test 2 is under-specified because noon is 12 hours from both edges, so any assumed offset under 12h passes — with concrete repairs. **The previously recorded cost did not reproduce:** it led with the reachability bug the earlier with-skill run missed. Nothing this phase changed targets that, so read it as run variance until a second run agrees. |
