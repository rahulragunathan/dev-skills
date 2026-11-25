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

@test "a streaming answer past the print timeout is flagged" {
  # Fails if a .part run never gets the timeout warning, so a killed run reads as running forever.
  printf '1. half' > "$TEST_TMP/gemini_phase_p2_c1_a1_m.part"
  : > "$TEST_TMP/gemini_phase_p2_c1_a1_m.err"
  age "$TEST_TMP/gemini_phase_p2_c1_a1_m.err" 40
  run bash "$PROGRESS" "$TEST_TMP" 2
  [[ "$output" == *"gemini c1: running 40m"*"past its timeout"* ]]
}

# --- KI-66: attempts and end states -----------------------------------------

@test "a late stderr line does not reset a Gemini run's age" {
  # Fails if the run is dated from its stderr file, which a diagnostic can touch at any time.
  printf '1. half' > "$TEST_TMP/gemini_phase_p2_c1_a1_m.part"
  echo $(( $(date +%s) - 40 * 60 )) > "$TEST_TMP/gemini_phase_p2_c1_a1_m.start"
  echo "a late warning" > "$TEST_TMP/gemini_phase_p2_c1_a1_m.err"
  run bash "$PROGRESS" "$TEST_TMP" 2
  [[ "$output" == *"gemini c1: running 40m"*"past its timeout"* ]]
}

@test "a retried chunk's earlier attempt is superseded, and a sibling chunk still runs" {
  # Fails if attempt 1 of a retried chunk is reported running beside attempt 2.
  printf 'x' > "$TEST_TMP/gemini_phase_p2_c1_a1_m.part"
  printf 'x' > "$TEST_TMP/gemini_phase_p2_c1_a2_m.part"
  printf 'x' > "$TEST_TMP/gemini_phase_p2_c2_a1_m.part"
  run bash "$PROGRESS" "$TEST_TMP" 2
  [ "$(printf '%s\n' "$output" | grep -c 'running')" -eq 2 ] || false
  [[ "$output" == *"gemini c1 a1: superseded by a later attempt"* ]] || false
  [[ "$output" == *"gemini c2: running"* ]]
}

@test "a failed run with output reads failed, and a cut-off reads cut off" {
  # Fails if every set-aside answer is called cut off, whatever ended the run.
  printf '1. half' > "$TEST_TMP/gemini_phase_p2_c1_a1_m.partial"; echo failed > "$TEST_TMP/gemini_phase_p2_c1_a1_m.state"
  printf '1. half' > "$TEST_TMP/gemini_phase_p2_c2_a1_m.partial"; echo cut-off > "$TEST_TMP/gemini_phase_p2_c2_a1_m.state"
  run bash "$PROGRESS" "$TEST_TMP" 2
  [[ "$(printf '%s\n' "$output" | grep 'c1:')" == *"failed — 7 bytes set aside"* ]] || false
  [[ "$(printf '%s\n' "$output" | grep 'c1:')" != *"cut off"* ]] || false
  [[ "$(printf '%s\n' "$output" | grep 'c2:')" == *"failed — answer cut off"* ]]
}

@test "an attempt that only left a state file is reported" {
  # Fails if a pass whose rungs were all unavailable reads as "no invocations" (pass 1, Codex 21).
  echo $(date +%s) > "$TEST_TMP/gemini_phase_p2_c1_a1_m.start"
  echo unavailable > "$TEST_TMP/gemini_phase_p2_c1_a1_m.state"
  run bash "$PROGRESS" "$TEST_TMP" 2
  [[ "$output" == *"gemini c1: unavailable"* ]]
}

@test "a set-aside answer with no state is not called a cut-off" {
  # Fails if a .partial whose end state was never written is labelled cut off.
  printf 'x' > "$TEST_TMP/gemini_phase_p2_c1_a1_m.partial"
  run bash "$PROGRESS" "$TEST_TMP" 2
  [[ "$output" == *"gemini c1: failed — 1 bytes set aside, reason not recorded"* ]]
}

@test "a part file without an attempt number is not superseded and raises no error" {
  # Fails if superseded() compares a missing attempt number and prints an integer error.
  printf 'x' > "$TEST_TMP/gemini_phase_p2_c1_m.part"
  run bash "$PROGRESS" "$TEST_TMP" 2
  [[ "$output" != *"integer"* ]] || false
  [[ "$output" == *"running"* ]]
}

@test "a .part whose state is already final is not reported as running" {
  # Fails if the process stopped after writing its state but before moving .part (pass 2, Codex 17).
  printf 'x' > "$TEST_TMP/gemini_phase_p2_c1_a1_m.part"
  echo failed > "$TEST_TMP/gemini_phase_p2_c1_a1_m.state"
  run bash "$PROGRESS" "$TEST_TMP" 2
  [[ "$output" != *"running"* ]] || false
  [[ "$output" == *"gemini c1: failed"* ]]
}

@test "a retried chunk's earlier failed attempt is superseded too" {
  # Fails if only a .part is checked for a later attempt (Gemini c1 1).
  printf 'x' > "$TEST_TMP/gemini_phase_p2_c1_a1_m.partial"; echo failed > "$TEST_TMP/gemini_phase_p2_c1_a1_m.state"
  printf 'x' > "$TEST_TMP/gemini_phase_p2_c1_a2_m.part"
  run bash "$PROGRESS" "$TEST_TMP" 2
  [[ "$output" == *"gemini c1 a1: superseded by a later attempt"* ]]
}
