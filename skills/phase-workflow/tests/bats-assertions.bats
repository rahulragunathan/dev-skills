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

# Fails if a single-line `@test "name" { body; }` declaration is rejected as
# malformed. Bats accepts the form, and toggle.bats uses it five times.
# In the fixture, "one line mid" passes under bats despite a false [[ ]] and
# "one line final" fails -- KI-45's behaviour, so the classification is checked
# against what bats actually does.
@test "a single-line test declaration is parsed, not refused" {
  grep -q '^@test "one line mid" { run true;' "$FIX/oneline.bats"
  run python3 "$SCRIPT" "$FIX/oneline.bats"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | awk -F'\t' '$2=="1" && $3=="one line mid" && $4=="mid"' | grep -q .
  printf '%s\n' "$output" | awk -F'\t' '$2=="2" && $3=="one line final" && $4=="final"' | grep -q .
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
}

# Fails if one unparseable file suppresses every other file's rows. The
# inventory drives conversion, so a file that cannot be read must be named and
# the run must fail -- but the files that did parse still have to be reported.
@test "one unparseable file does not suppress the others" {
  run bash -c "python3 '$SCRIPT' '$FIX/malformed.bats' '$FIX/brace.bats' 2>'$BATS_TEST_TMPDIR/err'"
  [ "$status" -ne 0 ]
  grep -q 'malformed.bats' "$BATS_TEST_TMPDIR/err"
  printf '%s\n' "$output" | awk -F'\t' '$3=="brace in a string" && $4=="mid"' | grep -q .
  printf '%s\n' "$output" | awk -F'\t' '$3=="assertion is last" && $4=="final"' | grep -q .
}

# Fails if `<<` inside an arithmetic expansion registers a heredoc. `$(( 1 << 2 ))`
# made the parser swallow the rest of the file and refuse it outright.
@test "a left-shift is not a heredoc" {
  grep -q '1 << 2' "$FIX/shift.bats"
  run python3 "$SCRIPT" "$FIX/shift.bats"
  # The condition is that the file PARSES -- it was refused outright as an
  # unterminated heredoc. Its classification is the other test's business, and
  # this fixture carries `|| false`, so asserting `mid` here contradicts it.
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | awk -F'\t' '$2=="3" && $3=="shift"' | grep -q .
}

# Fails if an assertion already carrying `|| false` is reported `mid`. The
# inventory's job is finding assertions that are NOT load-bearing; if a
# converted one looks identical to an unconverted one it cannot detect a
# regression, which is the role CHANGELOG and SKILL.md give it.
@test "an assertion already made load-bearing is not reported mid" {
  grep -q '|| false' "$FIX/converted.bats"
  run python3 "$SCRIPT" "$FIX/converted.bats"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$4=="mid"' | grep -c .)" -eq 0 ]
}

# Fails if an assertion spread over continued lines is classified by its first
# line alone. `[[ A \` / `|| B ]] || false` is load-bearing, but only its
# continuation carries the `|| false`; judged line-by-line it reads as `mid`
# and someone converts an assertion that was already converted.
@test "a continued-line assertion is classified by its logical form" {
  grep -q '\*"alpha"\* \\$' "$FIX/verify/wrapped.bats"
  run python3 "$SCRIPT" "$FIX/verify/wrapped.bats"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$4=="mid"' | grep -c .)" -eq 0 ]
}
