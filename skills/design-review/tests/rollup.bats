#!/usr/bin/env bats
setup() {
  T="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME"/s0*.md "$T/"
  R="$BATS_TEST_DIRNAME/rollup.py"
  W="$BATS_TEST_DIRNAME/write_results.py"
}
teardown() { rm -rf "$T"; }
@test "rollup reads corrected cells and keeps Mutation choice inside P2" {
  run python3 "$R" --tests "$T"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'Fixture: 4/5.*Fixture: 5/5'
  printf '%s\n' "$output" | grep -q 'Lifetime: 4/5'
  [ "$(printf '%s\n' "$output" | awk '/^\| [DRGP][0-9] / {n++} END {print n}')" = 15 ]
  printf '%s\n' "$output" | grep -q 'Mutation choice: 2/5.*Mutation choice: 5/5'
}
@test "rollup changes when named Results cells change and never pools revisions" {
  python3 "$W" "$T/s02-lifetime-surface.md" --run 'With skill (round 9, n=5)' --set 'Lifetime=**Unstable** (1/5)'
  run python3 "$R" --tests "$T"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'Lifetime: 1/5'
  printf '%s\n' "$output" | grep -q 'ff76fc3a6dc19f2a'
  printf '%s\n' "$output" | grep -q '3d791568afe9334d'
  # A superseded batch must not reach the rollup: only the latest round renders.
  run python3 "$W" "$T/s02-lifetime-surface.md" --run 'With skill (round 7, n=3)' --set 'Lifetime=**Unstable** (1/3)'
  [ "$status" -eq 0 ]
  run python3 "$R" --tests "$T"
  [ "$(printf '%s\n' "$output" | grep -c 'Lifetime: 1/3')" = 0 ]
}

@test "QC T3-9: checked README rollup matches and rejects drift without writing" {
  cp "$BATS_TEST_DIRNAME/README.md" "$T/README.md"
  run python3 "$R" --tests "$T" --check "$T/README.md"
  [ "$status" -eq 0 ]
  python3 - "$T/README.md" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); s=p.read_text(); assert '| D1 |' in s
before,block=s.split('<!-- BEGIN GENERATED ROLLUP -->',1)
p.write_text(before+'<!-- BEGIN GENERATED ROLLUP -->'+block.replace('| D1 |','| DRIFT |',1))
PY
  cp "$T/README.md" "$T/before"
  run python3 "$R" --tests "$T" --check "$T/README.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"differs"* ]] || false
  cmp "$T/README.md" "$T/before"
}

@test "QC T5 rollup: accepted row indentation preserves every observation" {
  python3 "$R" --tests "$T" > "$T/expected"
  python3 - "$T" <<'PY'
import pathlib,sys
for p in pathlib.Path(sys.argv[1]).glob('s0*.md'):
    p.write_text(''.join('  '+l if l.startswith('|') else l for l in p.read_text().splitlines(True)))
PY
  run python3 "$R" --tests "$T"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$T/expected")" ]
}

@test "QC T4-2 T4-3: evidence prose uses historical framing and reconciles the declared count" {
  run python3 - "$BATS_TEST_DIRNAME" <<'PY'
import pathlib,re,sys
root=pathlib.Path(sys.argv[1]); readme=(root/'README.md').read_text(); changelog=(root.parents[2]/'CHANGELOG.md').read_text()
assert 'is the current and only complete batch' not in changelog, 'round 4 presented as current'
assert 'Seven of fifteen units need their rule' not in changelog, 'historical grade presented as current'
count=int(re.search(r'partial batch: (\d+) of 42 declared answers',readme)[1])
assert count==2*2+3*2+4*3+2+3, 'round 7 subtotal disagrees with enumerated arms'
assert '*Corrections* below' not in readme, 'reference names a missing heading'
PY
  [ "$status" -eq 0 ]
}
