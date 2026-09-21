#!/usr/bin/env bats
setup() {
  T="$(mktemp -d)"
  G="$BATS_TEST_DIRNAME/grade.py"
  S="$BATS_TEST_DIRNAME/s07-process-rules.md"
}
teardown() { rm -rf "$T"; }
report() { python3 "$G" --scenario "$S" --answer "$T/answer.md" --json > "$T/report.json"; }
check_report() { python3 - "$T/report.json" "$1" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]));assert eval(sys.argv[2],{'r':r}),r
PY
}

@test "F-02: missing call attributes and arguments cannot leave stale mutable guards" {
  # Fails if a call setup error escapes the opaque-call invalidation path.
  for call in 'service.close(account)' 'close(account, missing)' 'close(account, **options)'; do
    cat > "$T/answer.md" <<PY
\`\`\`python
from types import SimpleNamespace
def close(account, missing=None):
    return None
service = SimpleNamespace()
account = SimpleNamespace(status="open")
options = {}
result = $call
assert account.status == "closed"
assert 1 == 2
\`\`\`
PY
    report || true
    check_report "[c['status'] for c in r['checks']]==['could-not-evaluate','did-not-hold']"
  done
}

@test "F-02: an opaque call invalidates cached helpers" {
  # Fails when callable objects retain pre-call mutable state.
  cat > "$T/answer.md" <<'PY'
```python
from functools import lru_cache
@lru_cache
def cached():
    return 1
result = cached()
result = clear(cached)
assert cached.cache_info().currsize == 0
```
PY
  report || true
  check_report "len(r['checks'])==1 and r['checks'][0]['status']=='could-not-evaluate'"
}

@test "F-02 recheck: helpers cannot recover stale mutable globals after an opaque call" {
  # Fails if only the copied test scope is invalidated, leaving helper globals usable.
  cat > "$T/answer.md" <<'PY'
```python
from types import SimpleNamespace
account = SimpleNamespace(status="open")
def current_account():
    return account
def constant():
    return 2
def test_close():
    result = close_account(account)
    assert current_account().status == "closed"
    assert constant() == 3
```
PY
  report || true
  check_report "[c['status'] for c in r['checks']]==['could-not-evaluate','did-not-hold']"
}

@test "F-03: skipped context entry and exit effects do not leave stale fixture values" {
  # Entry may mutate account; exit may mutate the object constructed in the body.
  cat > "$T/answer.md" <<'PY'
```python
from types import SimpleNamespace
account = SimpleNamespace(status="open")
with close(account) as opened:
    assert account.status == "closed"
    assert opened.status == "closed"
    created = SimpleNamespace(status="open")
assert created.status == "closed"
```
PY
  report || true
  check_report "len(r['checks'])==3 and all(c['status']=='could-not-evaluate' for c in r['checks'])"
}

@test "F-03: try tails remain visible and cannot leave stale following guards" {
  # Fails when finally effects and assertions vanish from the report.
  cat > "$T/answer.md" <<'PY'
```python
from types import SimpleNamespace
account = SimpleNamespace(status="open")
try:
    pass
finally:
    account.status = "closed"
    assert account.status == "closed"
assert account.status == "closed"
```
PY
  report || true
  check_report "len(r['checks'])==2 and all(c['status']=='could-not-evaluate' for c in r['checks'])"
}

@test "F-04: string and bytes formatting cannot allocate past the sequence limit" {
  # Small witness for the same path that accepts arbitrarily large field widths.
  for expression in "'%100001s' % 'x'" "b'%100001s' % b'x'"; do
    printf '```python\ns = %s\nassert len(s) == 100001\n```\n' "$expression" > "$T/answer.md"
    report || true
    check_report "r['checks'][0]['status']=='could-not-evaluate'"
  done
}
@test "real S07 baseline DST fixture guard executes and did not hold" {
  python3 - "$BATS_TEST_DIRNAME/fixtures/s07-real-dst.json" "$T/answer.md" <<'PY'
import json,pathlib,sys
pathlib.Path(sys.argv[2]).write_text(json.load(open(sys.argv[1]))['excerpt'])
PY
  report || true
  check_report "any(c['status']=='did-not-hold' and 'hours=23' in c['expression'] for c in r['checks'])"
  check_report "r['verdict']=='fail'"
}
@test "only pre-production assertions run with the supplied fixture values" {
  cat > "$T/answer.md" <<'PY'
```python
from datetime import datetime, timedelta, timezone

def test_guard():
    start = datetime(2026, 3, 14, tzinfo=timezone.utc)
    end = start + timedelta(days=1)
    assert start.tzinfo is not None
    assert end - start == timedelta(hours=24)
    result = in_window(start, start, end)
    assert False, 'production result must never execute'
```
PY
  report || true
  check_report "len(r['checks'])==2 and all(c['status']=='held' for c in r['checks'])"
  check_report "r['verdict']=='open'"
}
@test "missing imports and unsupported fixtures report could-not-evaluate without inventing values" {
  cat > "$T/answer.md" <<'PY'
```python
def test_unknown():
    account = Account(timezone='Asia/Tokyo')
    assert account.timezone == 'Asia/Tokyo'
    previous_day_window(account, missing_now)
```
PY
  report || true
  check_report "r['checks'][0]['status']=='could-not-evaluate' and 'Account' in r['checks'][0]['detail']"
  check_report "r['verdict']=='open'"
}
@test "lru_cache defaults are measured by executing the answer's own decorator" {
  cat > "$T/answer.md" <<'PY'
```python
from functools import lru_cache
@lru_cache()
def taxonomy(key):
    return key
assert taxonomy.cache_info().maxsize is None
```
PY
  report || true
  check_report "r['checks'][0]['status']=='did-not-hold'"
}
@test "S05 mechanically finds banned verdicts and named silent checks" {
  S="$BATS_TEST_DIRNAME/s05-report-form.md"
  printf 'Variation: PASS. Lifetime: OK. Surface: clean. Direction: N/A. No issue; nothing to flag.\n' > "$T/answer.md"
  report || true
  check_report "any(c['id']=='S05.banned-words' and len(c['matches'])==6 for c in r['checks'])"
  check_report "any(c['id']=='S05.silent-checks' and len(c['matches'])==4 for c in r['checks'])"
  check_report "all(q['status']=='open' for q in r['questions'])"
}
@test "human placement questions carry module and dependency evidence and cannot silently pass" {
  S="$BATS_TEST_DIRNAME/s01-responsibility-direction.md"
  printf '| Module | Responsibility | Depends on |\n| --- | --- | --- |\n| job | grouping and email | postgres |\n' > "$T/answer.md"
  report || true
  check_report "r['verdict']=='open' and len(r['questions'])==2"
  check_report "'postgres' in str(r['questions'][0]['evidence']) and 'Depends on' in str(r['questions'][1]['evidence'])"
}
@test "a human verdict needs reviewer reasoning and matching answer and condition hashes" {
  printf 'artifact\n' > "$T/answer.md"
  echo '{"reviewer":"someone","judgements":{"1":{"verdict":"pass"}}}' > "$T/judgements.json"
  run python3 "$G" --scenario "$S" --answer "$T/answer.md" --judgements "$T/judgements.json" --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"judgement"* ]]
}
@test "unsafe Python cannot touch disk and remains an explicit evaluation gap" {
  cat > "$T/answer.md" <<PY
\`\`\`python
import pathlib
assert pathlib.Path('$T/canary').write_text('bad')
\`\`\`
PY
  report || true
  [ ! -e "$T/canary" ]
  check_report "r['checks'][0]['status']=='could-not-evaluate'"
}
@test "multiple fences aliases and assertions inside branches never disappear" {
  cat > "$T/answer.md" <<'PY'
```python
from billing.summary import in_window as call_production
from datetime import datetime
```
```python
def test_branch():
    x = 1
    if unknown_fixture:
        assert x == 2
    call_production(None, None, None)
    assert False
```
PY
  report || true
  check_report "len(r['checks'])==1 and r['checks'][0]['status']=='could-not-evaluate'"
}
@test "syntax errors yield evaluation gaps rather than a vacuous supported grade" {
  printf '```python\nassert (\n```\n' > "$T/answer.md"
  report || true
  check_report "r['checks'][0]['status']=='could-not-evaluate' and r['verdict']=='open'"
}

@test "nested production boundary evaluates preceding guards but never later assertions" {
  cat > "$T/answer.md" <<'PY'
```python
def test_nested():
    if True:
        assert 2 + 2 == 4
        in_window(None, None, None)
    assert False
```
PY
  report || true
  check_report "len(r['checks'])==1 and r['checks'][0]['status']=='held'"
}

@test "unsupported side effects cannot leave stale fixture values silently held" {
  cat > "$T/answer.md" <<'PY'
```python
def test_mutating_setup():
    values = []
    values.append(1)
    assert len(values) == 0
    in_window(None, None, None)
```
PY
  report || true
  check_report "r['checks'][0]['status']=='could-not-evaluate'"
}

@test "host offset equality is executed with the answer's own explicit zones" {
  cat > "$T/answer.md" <<'PY'
```python
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
def test_offsets():
    now = datetime(2026, 3, 15, 2, tzinfo=timezone.utc)
    account_offset = now.astimezone(ZoneInfo('Asia/Tokyo')).utcoffset()
    host_offset = now.astimezone(ZoneInfo('Asia/Tokyo')).utcoffset()
    assert account_offset != host_offset
    previous_day_window(None, now)
```
PY
  report || true
  check_report "r['checks'][0]['status']=='did-not-hold'"
}

@test "explicit hash-bound human judgements support a grade and survive in output" {
  S="$BATS_TEST_DIRNAME/s01-responsibility-direction.md"
  printf 'artifact\n' > "$T/answer.md"
  report || true
  python3 - "$T/report.json" "$T/judgements.json" <<'PY'
import json,pathlib,sys
r=json.load(open(sys.argv[1]));j={k:r[k] for k in ('answer_hash','condition_hash')}
j.update(reviewer='Test reviewer',judgements={q['id']:{'verdict':'pass','reason':'Synthetic human judgement for interface test','evidence':'artifact'} for q in r['questions']})
pathlib.Path(sys.argv[2]).write_text(json.dumps(j))
PY
  run python3 "$G" --scenario "$S" --answer "$T/answer.md" --judgements "$T/judgements.json" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'Test reviewer'* ]]
}

@test "test methods and nonstandard test names expose unsupported assertion scopes" {
  cat > "$T/answer.md" <<'PY'
```python
class TestFixtures:
    def test_guard(self):
        assert self.offset != 0
        previous_day_window(None, None)

def repaired_timezone_test():
    assert 1 == 2
    previous_day_window(None, None)
```
PY
  report || true
  check_report "len(r['checks'])==2 and any(c['status']=='could-not-evaluate' for c in r['checks']) and any(c['status']=='did-not-hold' for c in r['checks'])"
}

@test "unknown setup effects cannot silently certify unrelated-looking fixture constants" {
  cat > "$T/answer.md" <<'PY'
```python
def test_setup():
    offset = 0
    configure_fixture()
    assert offset == 0
    previous_day_window(None, None)
```
PY
  report || true
  check_report "r['checks'][0]['status']=='could-not-evaluate'"
}

@test "adversarial: unsupported writes invalidate fixture values including aliases" {
  cat > "$T/answer.md" <<'PYCODE'
```python
def test_assignment():
    x = [1]
    y = x
    y[0] = 2
    assert x[0] == 1

def test_attribute():
    from types import SimpleNamespace
    x = SimpleNamespace(value=1)
    x.value = 2
    assert x.value == 1
```
PYCODE
  report || true
  check_report "len(r['checks'])==2 and all(c['status']=='could-not-evaluate' for c in r['checks'])"
}

@test "adversarial: helper arguments cannot fall back to module globals" {
  cat > "$T/answer.md" <<'PYCODE'
```python
x = 7
def helper(x):
    return x
assert helper() == 7
assert helper(7, 8) == 7
assert helper(x=7, unknown=8) == 7
assert helper(7) == 7
```
PYCODE
  report || true
  check_report "[c['status'] for c in r['checks']]==['could-not-evaluate']*3+['held']"
}

@test "adversarial: naive or implicit-local timezone conversions remain evaluation gaps" {
  cat > "$T/answer.md" <<'PYCODE'
```python
from datetime import datetime, timezone
assert datetime(2026, 1, 1).astimezone(timezone.utc).hour == 0
assert datetime(2026, 1, 1, tzinfo=timezone.utc).astimezone(None).hour == 0
assert datetime(2026, 1, 1, tzinfo=timezone.utc).astimezone(timezone.utc).hour == 0
```
PYCODE
  report || true
  check_report "[c['status'] for c in r['checks']]==['could-not-evaluate','could-not-evaluate','held']"
}

@test "recheck: unresolved conditional writes invalidate aliased fixture state" {
  cat > "$T/answer.md" <<'PY'
```python
x = [1]
y = x
if missing:
    y[0] = 2
assert x[0] == 1
```
PY
  report || true
  check_report "r['checks'][0]['status']=='could-not-evaluate'"
}

@test "a guard sharing a compound statement with production is never dropped silently" {
  # Red when statements() abandons a with/for/try that calls production before
  # walking its body: the false 23-hour guard vanished from checks entirely,
  # making the answer indistinguishable from one carrying no guards at all.
  cat > "$T/answer.md" <<'PY'
```python
from datetime import datetime, timedelta, timezone

def test_guard():
    with freeze_time("2026-03-08"):
        midnight = datetime(2026, 3, 8, 0, 0, tzinfo=timezone.utc)
        next_midnight = datetime(2026, 3, 9, 0, 0, tzinfo=timezone.utc)
        assert next_midnight - midnight == timedelta(hours=23)
        in_window(midnight, next_midnight)
```
PY
  report || true
  check_report "len(r['checks'])>=1"
  check_report "any('hours=23' in c['expression'] for c in r['checks'])"
  check_report "any(c['status']=='did-not-hold' for c in r['checks'])"
}

@test "a guard inside a production-calling for loop is recorded, not discarded" {
  cat > "$T/answer.md" <<'PY'
```python
from datetime import datetime, timedelta, timezone

def test_cases():
    for _ in range(2):
        start = datetime(2026, 3, 8, tzinfo=timezone.utc)
        assert start + timedelta(days=1) - start == timedelta(hours=23)
        in_window(start, start)
```
PY
  report || true
  check_report "len(r['checks'])>=1"
  check_report "any('hours=23' in c['expression'] for c in r['checks'])"
}

@test "an executed failure is overridden only by a judgement naming the disputed check" {
  # Red while any pass judgement on a failed condition is refused outright: an
  # S07 answer that quotes the supplied broken guard, which the task asks it to
  # diagnose, fails condition 3 and no human grade can correct it.
  cat > "$T/answer.md" <<'PY'
```python
from datetime import datetime, timedelta, timezone
midnight = datetime(2026, 3, 8, 0, 0, tzinfo=timezone.utc)
next_midnight = datetime(2026, 3, 9, 0, 0, tzinfo=timezone.utc)
assert next_midnight - midnight == timedelta(hours=23)
```
PY
  report || true
  check_report "r['verdict']=='fail'"
  # no disputes named: still refused
  python3 - "$T/report.json" "$T/bare.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
json.dump({'reviewer':'rr','answer_hash':r['answer_hash'],'condition_hash':r['condition_hash'],
           'judgements':{'3':{'verdict':'pass','reason':'quoted from the prompt',
                              'evidence':'the fence is the supplied fixture'}}}, open(sys.argv[2],'w'))
PY
  run python3 "$G" --scenario "$S" --answer "$T/answer.md" --judgements "$T/bare.json"
  [ "$status" -eq 3 ]
  # disputes naming the failing check id: accepted, and recorded
  python3 - "$T/report.json" "$T/named.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
ids=[c['id'] for c in r['checks'] if c['status']=='did-not-hold']
json.dump({'reviewer':'rr','answer_hash':r['answer_hash'],'condition_hash':r['condition_hash'],
           'judgements':{'3':{'verdict':'pass','reason':'quoted from the prompt',
                              'evidence':'the fence is the supplied fixture','disputes':ids}}},
          open(sys.argv[2],'w'))
PY
  run python3 "$G" --scenario "$S" --answer "$T/answer.md" --judgements "$T/named.json" --json
  [ "$status" -eq 2 ]
  printf '%s' "$output" > "$T/ov.json"
  check_dispute() { python3 - "$T/ov.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
q=[q for q in r['questions'] if q['id']=='3'][0]
assert q['status']=='pass', q
assert q.get('overrides'), q
PY
  }
  check_dispute
}

@test "a disputed check id that did not fail cannot launder an override" {
  cat > "$T/answer.md" <<'PY'
```python
from datetime import datetime, timedelta, timezone
midnight = datetime(2026, 3, 8, 0, 0, tzinfo=timezone.utc)
next_midnight = datetime(2026, 3, 9, 0, 0, tzinfo=timezone.utc)
assert next_midnight - midnight == timedelta(hours=23)
```
PY
  report || true
  python3 - "$T/report.json" "$T/bogus.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1]))
json.dump({'reviewer':'rr','answer_hash':r['answer_hash'],'condition_hash':r['condition_hash'],
           'judgements':{'3':{'verdict':'pass','reason':'x','evidence':'y',
                              'disputes':['no-such-check']}}}, open(sys.argv[2],'w'))
PY
  run python3 "$G" --scenario "$S" --answer "$T/answer.md" --judgements "$T/bogus.json"
  [ "$status" -eq 3 ]
}

@test "QC T3-1: imported fixture helpers preserve independent guards and expose dependent gaps" {
  cat > "$T/answer.md" <<'PY'
```python
from tests.factories import make_account
def test_guard():
    account = make_account()
    assert 1 == 2
    assert account.timezone == 'UTC'
```
PY
  report || true
  check_report "[c['status'] for c in r['checks']]==['did-not-hold','could-not-evaluate']"
}

@test "an unevaluable call's arguments are not graded on their pre-call values" {
  # Fails if the call only makes its assignment target unknown: the object it was
  # handed keeps its fixture value and a correct post-call guard grades as failed.
  cat > "$T/answer.md" <<'PY'
```python
from types import SimpleNamespace
from billing.jobs import close_account

def test_close():
    account = SimpleNamespace(status="open")
    result = close_account(account)
    assert account.status == "closed"
```
PY
  report || true
  check_report "[c['status'] for c in r['checks']]==['could-not-evaluate'] and r['verdict']=='open'"
}

@test "an unevaluable call forgets mutable bindings and leaves immutable guards checkable" {
  # Fails if an opaque call discards the whole scope: nothing it is handed can
  # change the datetime, so its false guard must still grade did-not-hold.
  cat > "$T/answer.md" <<'PY'
```python
from datetime import datetime, timezone

def test_window():
    now = datetime(2026, 3, 14, 16, 0, tzinfo=timezone.utc)
    events = []
    account = Account(id=1, events=events)
    assert now.hour == 17
    assert events == []
```
PY
  report || true
  check_report "[c['status'] for c in r['checks']]==['did-not-hold','could-not-evaluate']"
}

@test "an unevaluable call inside an assert is not followed by stale guards" {
  # Fails if only assignments forget mutable state: the assert form of the same
  # call leaves account on its pre-call value.
  cat > "$T/answer.md" <<'PY'
```python
from types import SimpleNamespace
from billing.jobs import close_account

def test_close():
    account = SimpleNamespace(status="open")
    assert close_account(account)
    assert account.status == "closed"
```
PY
  report || true
  check_report "[c['status'] for c in r['checks']]==['could-not-evaluate','could-not-evaluate']"
}

@test "QC T3-2: print diagnostics neither poison fixture bindings nor corrupt JSON" {
  printf '```python\ndef test_guard():\n    x = 1\n    print("debug", x)\n    assert x == 2\n```\n' > "$T/answer.md"
  report || true
  check_report "r['checks'][0]['status']=='did-not-hold'"
}

@test "QC T3-3: invalid unpacking in an answer is an evaluation gap, not refused input" {
  # Fails if the TypeError escapes the evaluator: exit 3 makes grade_batch
  # prepare refuse the whole batch over one answer's Python.
  printf '```python\na, b = 5\nassert a == 5\n```\n' > "$T/answer.md"
  run report
  [ "$status" -eq 2 ]
  [[ "$output" != *"Traceback"* ]] || false
  check_report "[c['status'] for c in r['checks']]==['could-not-evaluate']"
}

@test "QC T3-3: invalid replicate metadata cannot inherit evidence exit one" {
  mkdir "$T/evidence"
  printf '{"replicates":0}\n' > "$T/evidence/manifest.json"
  run python3 "$G" --scenario "$S" --evidence "$T/evidence" --arm baseline --json
  [ "$status" -eq 3 ]
  [[ "$output" == *"replicates"* ]]
}

@test "QC T3-3: null reviewer is invalid input with no traceback" {
  echo artifact > "$T/answer.md"
  report || true
  python3 - "$T/report.json" "$T/j.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); json.dump({**{k:r[k] for k in ['answer_hash','condition_hash']},'reviewer':None},open(sys.argv[2],'w'))
PY
  run python3 "$G" --scenario "$S" --answer "$T/answer.md" --judgements "$T/j.json" --json
  [ "$status" -eq 3 ]
  [[ "$output" != *"Traceback"* ]]
}

@test "QC T3-3: renumbered S07 refuses a missing fixture condition without traceback" {
  sed 's/^3\. \*\*/9. **/' "$S" > "$T/s07.md"
  printf '```python\nassert False\n```\n' > "$T/answer.md"
  run python3 "$G" --scenario "$T/s07.md" --answer "$T/answer.md" --json
  [ "$status" -eq 3 ]
  [[ "$output" != *"Traceback"* ]]
}

@test "QC T3-4: every scenario protects executed failures unless all linked checks are disputed" {
  for S in "$BATS_TEST_DIRNAME"/s0*.md; do
    printf '```python\nassert 1 == 2\nassert 2 == 3\n```\n' > "$T/answer.md"
    report || true
    python3 - "$T/report.json" "$T" <<'PY'
import json,pathlib,sys
r=json.load(open(sys.argv[1])); checks=[c['id'] for c in r['checks'] if c['status']=='did-not-hold']
for name,disputes in [('none',[]),('partial',checks[:1]),('all',checks)]:
    j={k:r[k] for k in ['answer_hash','condition_hash']}
    j.update(reviewer='Test',judgements={q['id']:{'verdict':'pass','reason':'quoted counterexample','evidence':'assert 1 == 2','disputes':disputes} for q in r['questions']})
    pathlib.Path(sys.argv[2],name+'.json').write_text(json.dumps(j))
PY
    for invalid in none partial; do
      run python3 "$G" --scenario "$S" --answer "$T/answer.md" --judgements "$T/$invalid.json" --json
      [ "$status" -eq 3 ]
      [[ "$output" == *"disputes"* ]] || false
    done
    run python3 "$G" --scenario "$S" --answer "$T/answer.md" --judgements "$T/all.json" --json
    [ "$status" -eq 0 ]
  done
}

@test "QC T3-6: ten method receivers evaluate within the step budget" {
  python3 - "$T/answer.md" <<'PY'
import pathlib,sys
chain='datetime(2026, 1, 1, 0, 0, 0)' + '.replace(hour=1)'*10
pathlib.Path(sys.argv[1]).write_text('```python\nfrom datetime import datetime\nassert '+chain+'.hour == 2\n```\n')
PY
  report || true
  check_report "r['checks'][0]['status']=='did-not-hold'"
}

@test "QC T3-7: repetition is bounded by result size before allocating" {
  for expression in "'a' * 10000 * 10000" "10000 * (10000 * [0])" "(0,) * 10000 * 10000"; do
    printf '```python\nx = %s\nassert len(x) > 0\n```\n' "$expression" > "$T/answer.md"
    report || true
    check_report "r['checks'][0]['status']=='could-not-evaluate' and 'size limit' in r['checks'][0]['detail']"
  done
}

@test "QC T5 S05: banned words come from the scenario rule instead of a second list" {
  S="$T/s05.md"
  sed 's/"clean"/"spotless"/' "$BATS_TEST_DIRNAME/s05-report-form.md" > "$S"
  printf 'spotless\n' > "$T/answer.md"
  report || true
  check_report "next(c for c in r['checks'] if c['id']=='S05.banned-words')['status']=='did-not-hold'"
  printf 'clean\n' > "$T/answer.md"
  report || true
  check_report "next(c for c in r['checks'] if c['id']=='S05.banned-words')['status']=='held'"
}

@test "QC T5 production: explicit CLI boundaries retain preceding guards and exclude subsequent ones" {
  printf '```python\nassert 1 == 1\ncustom_operation()\nassert False\n```\n' > "$T/answer.md"
  run python3 "$G" --scenario "$S" --answer "$T/answer.md" --production custom_operation --json
  [ "$status" -eq 2 ]
  printf '%s' "$output" > "$T/report.json"
  check_report "len(r['checks'])==1 and r['checks'][0]['status']=='held'"
}

@test "QC T3-7: concatenation cannot bypass the sequence allocation bound" {
  printf '```python\nx = "a" * 10000\nx = x + x\nx = x + x\nx = x + x\nx = x + x\nassert len(x) > 0\n```\n' > "$T/answer.md"
  report || true
  check_report "r['checks'][0]['status']=='could-not-evaluate' and 'size limit' in r['checks'][0]['detail']"
}

@test "QC T3-6: receiver reuse preserves supported unbound datetime methods" {
  printf '```python\nfrom datetime import datetime\nx = datetime(2026, 1, 1)\nassert datetime.replace(x, hour=2).hour == 3\n```\n' > "$T/answer.md"
  report || true
  check_report "r['checks'][0]['status']=='did-not-hold'"
}

@test "QC T3-4: contextual lexical matches remain open rather than undisclosed failed conditions" {
  S="$BATS_TEST_DIRNAME/s05-report-form.md"
  printf 'Calls the clean operation to normalize receipt text.\n' > "$T/answer.md"
  report || true
  check_report "all(q['status']=='open' for q in r['questions'])"
  python3 - "$T/report.json" "$T/j.json" <<'PY'
import json,sys
r=json.load(open(sys.argv[1])); j={k:r[k] for k in ['answer_hash','condition_hash']}
j.update(reviewer='Test',judgements={q['id']:{'verdict':'pass','reason':'synthetic context decision for interface regression','evidence':'Calls the clean operation'} for q in r['questions']})
json.dump(j,open(sys.argv[2],'w'))
PY
  run python3 "$G" --scenario "$S" --answer "$T/answer.md" --judgements "$T/j.json" --json
  [ "$status" -eq 0 ]
}
