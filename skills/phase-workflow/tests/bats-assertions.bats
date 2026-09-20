#!/usr/bin/env bats
#
# KI-45 — bats_assertions.py reports every [[ ]] assertion and whether it is
# its test's final command. Brace-depth parsing breaks on ${...} and embedded
# python, and heredoc content must never be inventoried as test code.

setup() {
  FIX="$BATS_TEST_DIRNAME/fixtures"
  SCRIPT="$BATS_TEST_DIRNAME/../bats_assertions.py"
}

# Fails if an assertion followed by a later command is reported `final` when the
# body contains an unbalanced brace inside a string.
@test "an assertion before a later command is mid, even past an unbalanced brace" {
  grep -q 'printf .%s. "{"' "$FIX/brace.bats"
  run python3 "$SCRIPT" "$FIX/brace.bats"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | awk -F'\t' '$3=="brace in a string" && $4=="mid"' | grep -q .
  printf '%s\n' "$output" | awk -F'\t' '$3=="assertion is last" && $4=="final"' | grep -q .
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
}

# Fails if a test's last assertion is reported `mid` because a function
# definition follows the test.
@test "a trailing function definition does not make the last assertion mid" {
  grep -q '^helper_defined_after()' "$FIX/trailing-helper.bats"
  run python3 "$SCRIPT" "$FIX/trailing-helper.bats"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | awk -F'\t' '$3=="ends with an assertion" && $4=="final"' | grep -q .
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
}

# Fails if assertion text inside a quoted heredoc is reported as an assertion.
@test "assertion text inside a heredoc is not inventoried" {
  grep -q 'not a real test' "$FIX/heredoc.bats"
  run python3 "$SCRIPT" "$FIX/heredoc.bats"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 0 ]
}
