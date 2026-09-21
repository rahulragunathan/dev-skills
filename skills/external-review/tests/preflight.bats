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
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex"*"READY"* ]] || false
  [[ "$output" == *"gemini"*"READY"* ]]
}

@test "an exhausted account is reported as QUOTA, not as a model problem" {
  # THE finding. Quota is account-wide and availability is per model, so the
  # two demand different responses: downshift for one, wait for the other.
  fake_codex_ready; fake_agy_quota
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [[ "$output" == *"gemini"*"QUOTA"* ]] || false
  [[ "$output" != *"gemini"*"UNAVAILABLE"* ]]
}

@test "the quota reset window is surfaced, not swallowed" {
  # Red if the probe reports only pass/fail: the caller needs to know whether
  # to wait an hour or five days before planning the pass.
  fake_codex_ready; fake_agy_quota
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [[ "$output" == *"110h19m32s"* ]]
}

@test "an availability error is UNAVAILABLE, so the caller downshifts instead of waiting" {
  fake_codex_ready; fake_agy_unavailable
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [[ "$output" == *"gemini"*"UNAVAILABLE"* ]] || false
  [[ "$output" != *"gemini"*"QUOTA"* ]]
}

@test "one reviewer ready is exit 0: the pass runs with partial coverage" {
  fake_codex_ready; fake_agy_quota
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [ "$status" -eq 0 ]
  [[ "$output" == *"PARTIAL"* ]]
}

@test "no reviewer able to answer is exit 1" {
  fake_agy_quota
  printf '#!/usr/bin/env bash\necho "error: quota" >&2\nexit 1\n' > "$BIN/codex"; chmod +x "$BIN/codex"
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [ "$status" -eq 1 ]
}

@test "a missing CLI is MISSING, and is not confused with a failing one" {
  fake_agy_ready
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [[ "$output" == *"codex"*"MISSING"* ]] || false
  [ "$status" -eq 0 ]
}

@test "both CLIs missing is exit 1 and says so" {
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [ "$status" -eq 1 ]
  [[ "$output" == *"codex"*"MISSING"* ]] || false
  [[ "$output" == *"gemini"*"MISSING"* ]]
}

@test "a CLI that exits 0 without producing an answer is not READY" {
  # Codex exits 0 on some quota failures and writes no -o file. Exit status
  # alone cannot tell a finished review from an exhausted account.
  fake_codex_silent_zero; fake_agy_ready
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  # Scoped to the codex line: a bare glob spans newlines, so *"codex"*"READY"*
  # also matches codex on one line and gemini's READY on the next.
  [[ "$(printf '%s\n' "$output" | grep '^codex')" != *"READY"* ]] || false
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
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [[ "$output" == *"gemini"*"TIMEOUT"* ]] || false
  [[ "$output" != *"gemini"*"QUOTA"* ]] || false
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
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [[ "$output" == *"gemini"*"QUOTA"* ]] || false
  [[ "$output" == *"110h19m32s"* ]]
}

@test "preflight requires discovered candidates rather than fixed default models" {
  fake_codex_ready; fake_agy_ready
  run bash "$PREFLIGHT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"supply discovered"* ]]
}

@test "nonempty timeout output never reports readiness" {
  fake_codex_ready
  printf '#!/bin/sh\necho ready\necho "print timeout: turn in progress" >&2\n' > "$BIN/agy"
  chmod +x "$BIN/agy"
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [[ "$output" == *"gemini"*"TIMEOUT"* ]] || false
  [[ "$output" != *"gemini"*"READY"* ]]
}

@test "unexpected nonempty answer is not the readiness token" {
  fake_codex_ready
  printf '#!/bin/sh\necho thinking\n' > "$BIN/agy"
  chmod +x "$BIN/agy"
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [[ "$output" == *"gemini"*"NO ANSWER"* ]]
}

@test "codex deadline kills the process group and still probes Gemini" {
  fake_agy_ready
  printf '#!/bin/sh\nsleep 20 &\necho $! > "%s"\nwait\n' "$TEST_TMP/child" > "$BIN/codex"
  chmod +x "$BIN/codex"
  local started=$SECONDS
  PREFLIGHT_TIMEOUT=1 run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [ "$status" -eq 0 ]
  [ "$((SECONDS - started))" -lt 8 ]
  [[ "$output" == *"codex"*"TIMEOUT"* ]] || false
  [[ "$output" == *"gemini"*"READY"* ]] || false
  ! kill -0 "$(cat "$TEST_TMP/child")" 2>/dev/null
}

@test "unavailable candidate falls through to the next supplied model" {
  fake_agy_ready
  cat > "$BIN/codex" <<'SH'
#!/bin/bash
out=""; model=""
while [ $# -gt 0 ]; do
 case "$1" in -m) model="$2"; shift;; -o) out="$2"; shift;; esac
 shift
done
echo "$model" >> "$TEST_TMP/models"
[ "$model" = unavailable ] && { echo 'model is not available' >&2; exit 1; }
echo ready > "$out"
SH
  chmod +x "$BIN/codex"
  run bash "$PREFLIGHT" --codex-model unavailable --codex-model discovered --gemini-model selected
  [[ "$output" == *"codex"*"discovered"*"READY"* ]] || false
  [ "$(cat "$TEST_TMP/models")" = $'unavailable\ndiscovered' ]
}

@test "one discovered ladder still reports a missing other reviewer" {
  fake_codex_ready
  run bash "$PREFLIGHT" --codex-model selected
  [ "$status" -eq 0 ]
  [[ "$output" == *"gemini"*"MISSING"* ]] || false
  [[ "$output" == *"PARTIAL COVERAGE"* ]]
}

@test "QC T2-3: healthy Codex configuration output cannot become a timeout" {
  fake_codex_ready
  sed -i.bak '/exit 0/i\
echo stream_idle_timeout_ms=300000\
echo stream_idle_timeout_ms=300000 >&2\
' "$BIN/codex"
  run bash "$PREFLIGHT" --codex-model selected
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex"*"READY"* ]]
}

@test "QC T2-4: both probes carry the real high reasoning effort" {
  fake_codex_ready; fake_agy_ready
  sed -i.bak '2i\
printf "%s\\n" "$@" > "$TEST_TMP/codex-args"\
' "$BIN/codex"
  sed -i.bak '2i\
printf "%s\\n" "$@" > "$TEST_TMP/agy-args"\
' "$BIN/agy"
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [ "$status" -eq 0 ]
  grep -Fx 'model_reasoning_effort=high' "$TEST_TMP/codex-args"
  grep -Fx -- '--effort' "$TEST_TMP/agy-args"
  grep -Fx high "$TEST_TMP/agy-args"
}

@test "F-09: the documented failure probe uses the same explicit high effort" {
  # Execute the SOP fence; testing preflight.sh cannot cover this separate probe.
  cat > "$BIN/codex" <<'SH'
#!/bin/bash
printf '%s\n' "$@" > "$TEST_TMP/failure-probe-args"
SH
  chmod +x "$BIN/codex"
  python3 - "$BATS_TEST_DIRNAME/../SKILL.md" "$TEST_TMP/probe.sh" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text().split('## Failure handling', 1)[1]
code = re.search(r'```bash\n(.*?)```', text, re.S)[1]
pathlib.Path(sys.argv[2]).write_text(code.replace('<same model as the real run>', 'selected'))
PY
  ROOT="$TEST_TMP" run bash "$TEST_TMP/probe.sh"
  [ "$status" -eq 0 ]
  grep -Fx 'model_reasoning_effort=high' "$TEST_TMP/failure-probe-args"
}

@test "QC T5 preflight: exhausted availability ladder reports each rung once" {
  fake_agy_unavailable
  run bash "$PREFLIGHT" --gemini-model first --gemini-model last
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c 'last .*UNAVAILABLE')" -eq 1 ]
}

# Fails if a rung's effort is ignored and the probe runs at the hardcoded high.
# preflight.sh receives the ladder's candidates via --codex-model and then runs
# `-c model_reasoning_effort="high"` regardless, so a probe could clear a rung
# at an effort the real review never uses. "QC T2-4" above pins high as the
# default when a bare slug is given; this pins the pair overriding it.
@test "a slug:effort rung probes at that effort, and -m gets the slug alone" {
  fake_codex_ready; fake_agy_ready
  sed -i.bak '2i\
printf "%s\\n" "$@" > "$TEST_TMP/codex-args"\
' "$BIN/codex"
  run bash "$PREFLIGHT" --codex-model selected:medium --gemini-model selected
  [ "$status" -eq 0 ]
  grep -Fx 'model_reasoning_effort=medium' "$TEST_TMP/codex-args"
  run grep -Fx 'model_reasoning_effort=high' "$TEST_TMP/codex-args"
  [ "$status" -ne 0 ]
  # -m must carry the slug only; "selected:medium" is not a model id
  grep -Fx 'selected' "$TEST_TMP/codex-args"
  run grep -Fx 'selected:medium' "$TEST_TMP/codex-args"
  [ "$status" -ne 0 ]
}
