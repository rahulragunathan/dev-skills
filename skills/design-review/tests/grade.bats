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
