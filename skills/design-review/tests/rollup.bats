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
  [[ "$output" == *'Fixture: 1/2'*'Fixture: 2/3'* ]]
  [[ "$output" == *'Lifetime: 2/3'* ]]
  [ "$(printf '%s\n' "$output" | awk '/^\| [DRGP][0-9] / {n++} END {print n}')" = 15 ]
  [[ "$output" == *'Mutation choice: 1/2'*'Mutation choice: 3/3'* ]]
}
@test "rollup changes when named Results cells change and never pools revisions" {
  python3 "$W" "$T/s02-lifetime-surface.md" --run 'With skill (round 7, n=3)' --set 'Lifetime=**Unstable** (1/3)'
  run python3 "$R" --tests "$T"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Lifetime: 1/3'* ]]
  [[ "$output" == *'ff76fc3a6dc19f2a'* ]]
  [[ "$output" == *'3d791568afe9334d'* ]]
}
