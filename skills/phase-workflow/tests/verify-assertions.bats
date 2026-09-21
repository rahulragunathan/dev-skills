#!/usr/bin/env bats
#
# KI-45 — verify_assertions.sh confirms one converted assertion is LOAD-BEARING:
# that a false result stops its test. It does not establish that a conversion
# preserved the assertion's meaning; only review of the conversion diff does.
#
# mutation-restore.sh exits 0 whenever the test command returned exactly 1 and
# the restore was clean. Its own last message says "verify the named failure in
# the output before certifying", and bats returns 1 for fixture errors too, so
# this wrapper must read the output rather than the exit status alone.
#
# FIXTURES ARE REAL FILES, NEVER HEREDOCS. Bats rewrites @test lines wherever
# they appear in a .bats file, heredoc bodies included, so a fixture written
# inline arrives as `bats_test_function --description ... -- test_x;test_x() {`
# rather than as the source it was meant to be.

setup() {
  export TEST_TMP="$(mktemp -d)"
  export REPO="$TEST_TMP/repo"
  mkdir -p "$REPO/t"
  # Run the script from its real home, beside mutation-restore.sh, with the
  # scratch repository as the working directory. Copying it into the scratch
  # repo would strip it of the sibling it has to resolve.
  local here; here="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export VERIFY="$here/verify_assertions.sh"
  cp "$BATS_TEST_DIRNAME"/fixtures/verify/*.bats "$REPO/t/"
  cd "$REPO"
  git init -q -b main .
  git config user.email t@example.invalid
  git config user.name Test
  git add -A && git commit -qm base
  export SHA="$(git rev-parse HEAD)"
}

teardown() { cd /; rm -rf "$TEST_TMP"; }

# Fails if an assertion that cannot fail its test is reported RED.
@test "a mid-test [[ ]] assertion is GREEN because negating it cannot fail its test" {
  run bats t/vac.bats
  [ "$status" -eq 0 ]
  run bash "$VERIFY" "$SHA" t/vac.bats 2 vacuous
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^GREEN'
}

# Fails if a converted assertion that does stop its test is reported anything but RED.
@test "a converted assertion is RED because negating it fails its test" {
  run bash "$VERIFY" "$SHA" t/real.bats 2 loadbearing
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^RED'
}

# Fails if a harness error under mutation is certified as discrimination.
# bats exits 1 for the missing `load`, so exit status alone would say RED.
@test "a fixture error under mutation is REFUSED, not RED" {
  run bats t/broken.bats
  [ "$status" -eq 1 ]
  run bash "$VERIFY" "$SHA" t/broken.bats 3 'needs a missing helper'
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^REFUSED'
  printf '%s\n' "$output" | grep -qv '^RED'
}

# Fails if a red at a line other than the target is certified as discrimination.
# Negating line 2 makes the inner command succeed, so the failure lands on line 3
# while the restored test still passes -- mutation-restore.sh therefore exits 0
# and only reading its output can tell this apart from a real red.
@test "a red at the wrong line is REFUSED, not RED" {
  run bats t/elsewhere.bats
  [ "$status" -eq 0 ]
  run bash "$VERIFY" "$SHA" t/elsewhere.bats 2 'fails at another line'
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^REFUSED'
  printf '%s\n' "$output" | grep -qv '^RED'
}

# Fails if a test name carrying regex metacharacters reaches `bats -f` unescaped.
# "guard [strict]" as a regex is a character class: it matches "guard s" and
# "guard t" but never the literal name, so bats would run no test at all. Real
# names in this repo carry brackets -- this suite has one.
@test "a test name containing regex metacharacters still selects its test" {
  grep -q 'guard \[strict\]' t/meta.bats
  run bash "$VERIFY" "$SHA" t/meta.bats 2 'guard [strict]'
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^RED'
}

# Fails if a disjunction that cannot be falsified by negating one operator is
# reported GREEN. In `A || B` with both true, flipping A's operator leaves B
# true and the test still passes -- which says nothing about whether the
# assertion is load-bearing. GREEN asserts it is not; the honest answer is that
# this mutation cannot tell. Two real assertions in evidence.bats hit this.
@test "a compound || condition is REFUSED, not GREEN" {
  run bats t/compound.bats
  [ "$status" -eq 0 ]
  run bash "$VERIFY" "$SHA" t/compound.bats 3 compound
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^REFUSED'
  printf '%s\n' "$output" | grep -qv '^GREEN'
}

# Fails if a disjunction spread over continued lines is reported GREEN. The
# compound guard reads only the requested line and requires `]]` on it, so a
# `[[ A \` / `|| B ]]` assertion slips past it and earns the wrong verdict --
# and §3 step 3 says an assertion failing the audit is fixed or deleted, so a
# working assertion gets deleted on the strength of it.
@test "a disjunction split across continued lines is REFUSED, not GREEN" {
  run bats t/wrapped.bats
  [ "$status" -eq 0 ]
  run bash "$VERIFY" "$SHA" t/wrapped.bats 3 wrapped
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^REFUSED'
  printf '%s\n' "$output" | grep -qv '^GREEN'
}

# Fails if an operator inside a quoted literal is mutated in place of the
# assertion's own. The sed substitutions are line-addressed and take the first
# match, so `[[ "$output" != *"a == b"* ]] || false` has its glob pattern
# rewritten while the real `!=` stands: the assertion still holds, the test
# still passes, and the tool prints GREEN -- which §3 step 3 reads as licence
# to delete a working assertion. Refusing is the only safe answer; the script
# cannot tell which occurrence is the operator.
@test "an ambiguous operator on the line is REFUSED, not GREEN" {
  run bats t/quoted.bats
  [ "$status" -eq 0 ]
  run bash "$VERIFY" "$SHA" t/quoted.bats 3 'quoted operator'
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^REFUSED'
  printf '%s\n' "$output" | grep -qv '^GREEN'
}
