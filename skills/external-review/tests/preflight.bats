#!/usr/bin/env bats
#
# The reviewer preflight. Every test names the condition that turns it red.
#
# The canary is WASTED: a full run committed against a reviewer that could
# never answer. Pass 9 spent about 100 minutes discovering, one chunk at a
# time, that the Gemini account was out of quota for another 110 hours. The
# probe exists so that costs one call instead of thirteen.

setup() {
  export TEST_TMP="$(mktemp -d)"
  export BIN="$TEST_TMP/bin"
  mkdir -p "$BIN"
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export PREFLIGHT="$(dirname "$here")/preflight.sh"
  # Replace PATH rather than prepend to it. Prepending leaves the real codex and
  # agy reachable, so a test for a missing CLI reaches the network instead — the
  # fixture then stops carrying the property under test.
  export PATH="$BIN:/usr/bin:/bin"
}

teardown() { cd /; [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"; }

# Fake CLIs at the process boundary. Each writes what the real one writes.
fake_codex_ready() {
  cat > "$BIN/codex" <<'EOF'
#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do [ "$1" = "-o" ] && { out="$2"; shift; }; shift; done
[ -n "$out" ] && printf 'ready\n' > "$out"
exit 0
EOF
  chmod +x "$BIN/codex"
}

fake_codex_silent_zero() {
  # The documented trap: exits 0 and writes no -o file.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/codex"; chmod +x "$BIN/codex"
}

fake_agy_ready() {
  printf '#!/usr/bin/env bash\nprintf "ready\\n"\nexit 0\n' > "$BIN/agy"; chmod +x "$BIN/agy"
}

fake_agy_quota() {
  cat > "$BIN/agy" <<'EOF'
#!/usr/bin/env bash
echo "error: Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 110h19m32s." >&2
exit 1
EOF
  chmod +x "$BIN/agy"
}

fake_agy_unavailable() {
  cat > "$BIN/agy" <<'EOF'
#!/usr/bin/env bash
echo "error: model is not available for your account" >&2
exit 1
EOF
  chmod +x "$BIN/agy"
}

@test "both reviewers ready: reports both and exits 0" {
  fake_codex_ready; fake_agy_ready
  run bash "$PREFLIGHT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex"*"READY"* ]]
  [[ "$output" == *"gemini"*"READY"* ]]
}

@test "an exhausted account is reported as QUOTA, not as a model problem" {
  # THE finding. Quota is account-wide and availability is per model, so the
  # two demand different responses: downshift for one, wait for the other.
  fake_codex_ready; fake_agy_quota
  run bash "$PREFLIGHT"
  [[ "$output" == *"gemini"*"QUOTA"* ]]
  [[ "$output" != *"gemini"*"UNAVAILABLE"* ]]
}

@test "the quota reset window is surfaced, not swallowed" {
  # Red if the probe reports only pass/fail: the caller needs to know whether
  # to wait an hour or five days before planning the pass.
  fake_codex_ready; fake_agy_quota
  run bash "$PREFLIGHT"
  [[ "$output" == *"110h19m32s"* ]]
}

@test "an availability error is UNAVAILABLE, so the caller downshifts instead of waiting" {
  fake_codex_ready; fake_agy_unavailable
  run bash "$PREFLIGHT"
  [[ "$output" == *"gemini"*"UNAVAILABLE"* ]]
  [[ "$output" != *"gemini"*"QUOTA"* ]]
}

@test "one reviewer ready is exit 0: the pass runs with partial coverage" {
  fake_codex_ready; fake_agy_quota
  run bash "$PREFLIGHT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PARTIAL"* ]]
}

@test "no reviewer able to answer is exit 1" {
  fake_agy_quota
  printf '#!/usr/bin/env bash\necho "error: quota" >&2\nexit 1\n' > "$BIN/codex"; chmod +x "$BIN/codex"
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
}

@test "a missing CLI is MISSING, and is not confused with a failing one" {
  fake_agy_ready
  run bash "$PREFLIGHT"
  [[ "$output" == *"codex"*"MISSING"* ]]
  [ "$status" -eq 0 ]
}

@test "both CLIs missing is exit 1 and says so" {
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"codex"*"MISSING"* ]]
  [[ "$output" == *"gemini"*"MISSING"* ]]
}

@test "a CLI that exits 0 without producing an answer is not READY" {
  # Codex exits 0 on some quota failures and writes no -o file. Exit status
  # alone cannot tell a finished review from an exhausted account.
  fake_codex_silent_zero; fake_agy_ready
  run bash "$PREFLIGHT"
  [[ "$output" != *"codex"*"READY"* ]]
  [[ "$output" == *"codex"*"NO ANSWER"* ]]
}

@test "a probe timeout is TIMEOUT, not confused with an exhausted account" {
  # Measured live: agy exits 0, writes nothing, and reports a print timeout on
  # stderr. The three silent-zero causes demand different responses — retry,
  # wait for a reset, or downshift — so the probe must say which it saw.
  fake_codex_ready
  cat > "$BIN/agy" <<'EOF'
#!/usr/bin/env bash
echo "[agy] print timeout after 2m0s with turn in progress; returning partial output" >&2
exit 0
EOF
  chmod +x "$BIN/agy"
  run bash "$PREFLIGHT"
  [[ "$output" == *"gemini"*"TIMEOUT"* ]]
  [[ "$output" != *"gemini"*"QUOTA"* ]]
  [[ "$output" != *"gemini"*"READY"* ]]
}

@test "an exhausted account that exits 0 is still reported as QUOTA" {
  # Red while a silent zero is classified without reading stderr: the reason is
  # there, and 'wait 110 hours' is a different answer from 'retry'.
  fake_codex_ready
  cat > "$BIN/agy" <<'EOF'
#!/usr/bin/env bash
echo "error: Individual quota reached. Resets in 110h19m32s." >&2
exit 0
EOF
  chmod +x "$BIN/agy"
  run bash "$PREFLIGHT"
  [[ "$output" == *"gemini"*"QUOTA"* ]]
  [[ "$output" == *"110h19m32s"* ]]
}
