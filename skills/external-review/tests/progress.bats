#!/usr/bin/env bats
#
# progress.sh: the status line posted while a review pass runs.
# Every test names the condition that turns it red.

setup() {
  export TEST_TMP="$(mktemp -d)"
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export PROGRESS="$(dirname "$here")/progress.sh"
}

teardown() { rm -rf "$TEST_TMP"; }

# age <file> <minutes>: set a file's modification time that many minutes back.
age() { touch -t "$(date -v-"$2"M +%Y%m%d%H%M.%S)" "$1"; }

@test "a finished invocation reports its byte count" {
  # Fails if a non-empty output file is not reported as done with its size.
  printf 'No findings.\n' > "$TEST_TMP/codex_phase_p1_c1_a1_m_max.txt"
  run bash "$PROGRESS" "$TEST_TMP" 1
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"codex c1: done, 13 bytes"* ]]
}

@test "a running invocation reports how long it has run and when its log last moved" {
  # Fails if an empty output is not reported as running with its elapsed time and log age.
  : > "$TEST_TMP/codex_phase_p1_c2_a1_m_max.txt"; age "$TEST_TMP/codex_phase_p1_c2_a1_m_max.txt" 12
  : > "$TEST_TMP/codex_phase_p1_c2_a1_m_max.log"; age "$TEST_TMP/codex_phase_p1_c2_a1_m_max.log" 1
  run bash "$PROGRESS" "$TEST_TMP" 1
  [[ "$output" == *"codex c2: running 12m, log written 1m ago"* ]]
}

@test "a run past the print timeout is flagged" {
  # Fails if an invocation running longer than 30 minutes is reported as ordinary progress.
  : > "$TEST_TMP/gemini_phase_p1_c3_a1_g-high.txt"; age "$TEST_TMP/gemini_phase_p1_c3_a1_g-high.txt" 31
  run bash "$PROGRESS" "$TEST_TMP" 1
  [[ "$output" == *"gemini c3: running 31m — past its timeout; check it"* ]]
}

@test "only the named pass is reported, and prompts are not invocations" {
  # Fails if another pass's files or the prompt files appear in the status.
  printf 'x\n' > "$TEST_TMP/codex_phase_p2_c1_a1_m_max.txt"
  printf 'x\n' > "$TEST_TMP/codex_prompt_p1_c1.txt"
  printf 'x\n' > "$TEST_TMP/gemini_phase_p1_c1_a1_g-high.txt"
  run bash "$PROGRESS" "$TEST_TMP" 1
  [ "$(printf '%s\n' "$output" | grep -c ':')" -eq 1 ] || false
  [[ "$output" == *"gemini c1: done"* ]]
}

@test "no invocation files is said plainly" {
  # Fails if an empty scratch directory prints nothing, which reads as a hang.
  run bash "$PROGRESS" "$TEST_TMP" 1
  [[ "$output" == *"no invocations for pass 1"* ]]
}

@test "an answer still being written is running, not done" {
  # Fails if a Gemini answer that agy is still streaming is reported as done.
  printf '1. half' > "$TEST_TMP/gemini_phase_p2_c1_a1_m.part"
  run bash "$PROGRESS" "$TEST_TMP" 2
  [[ "$output" == *"gemini c1: running"*"bytes so far"* ]]
}

@test "a cut-off answer is reported as failed" {
  # Fails if an answer set aside as .partial vanishes from the report.
  printf '1. half' > "$TEST_TMP/gemini_phase_p2_c1_a1_m.partial"
  run bash "$PROGRESS" "$TEST_TMP" 2
  [[ "$output" == *"gemini c1: failed"* ]]
}
