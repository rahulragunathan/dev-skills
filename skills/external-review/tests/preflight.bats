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
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex"*"READY"* ]] || false
  [[ "$output" == *"gemini"*"READY"* ]]
}

@test "an exhausted account is reported as QUOTA, not as a model problem" {
  # THE finding. Quota is account-wide and availability is per model, so the
  # two demand different responses: downshift for one, wait for the other.
  fake_codex_ready; fake_agy_quota
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
  [[ "$output" == *"gemini"*"QUOTA"* ]] || false
  [[ "$output" != *"gemini"*"UNAVAILABLE"* ]]
}

@test "the quota reset window is surfaced, not swallowed" {
  # Red if the probe reports only pass/fail: the caller needs to know whether
  # to wait an hour or five days before planning the pass.
  fake_codex_ready; fake_agy_quota
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
  [[ "$output" == *"110h19m32s"* ]]
}

@test "an availability error is UNAVAILABLE, so the caller downshifts instead of waiting" {
  fake_codex_ready; fake_agy_unavailable
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
  [[ "$output" == *"gemini"*"UNAVAILABLE"* ]] || false
  [[ "$output" != *"gemini"*"QUOTA"* ]]
}

@test "one reviewer ready is exit 0: the pass runs with partial coverage" {
  fake_codex_ready; fake_agy_quota
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
  [ "$status" -eq 0 ]
  [[ "$output" == *"PARTIAL"* ]]
}

@test "no reviewer able to answer is exit 1" {
  fake_agy_quota
  printf '#!/usr/bin/env bash\necho "error: quota" >&2\nexit 1\n' > "$BIN/codex"; chmod +x "$BIN/codex"
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
  [ "$status" -eq 1 ]
}

@test "a missing CLI is MISSING, and is not confused with a failing one" {
  fake_agy_ready
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
  [[ "$output" == *"codex"*"MISSING"* ]] || false
  [ "$status" -eq 0 ]
}

@test "both CLIs missing is exit 1 and says so" {
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
  [ "$status" -eq 1 ]
  [[ "$output" == *"codex"*"MISSING"* ]] || false
  [[ "$output" == *"gemini"*"MISSING"* ]]
}

@test "a CLI that exits 0 without producing an answer is not READY" {
  # Codex exits 0 on some quota failures and writes no -o file. Exit status
  # alone cannot tell a finished review from an exhausted account.
  fake_codex_silent_zero; fake_agy_ready
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
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
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
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
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
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
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
  [[ "$output" == *"gemini"*"TIMEOUT"* ]] || false
  [[ "$output" != *"gemini"*"READY"* ]]
}

@test "unexpected nonempty answer is not the readiness token" {
  fake_codex_ready
  printf '#!/bin/sh\necho thinking\n' > "$BIN/agy"
  chmod +x "$BIN/agy"
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
  [[ "$output" == *"gemini"*"NO ANSWER"* ]]
}

@test "codex deadline kills the process group and still probes Gemini" {
  fake_agy_ready
  printf '#!/bin/sh\nsleep 20 &\necho $! > "%s"\nwait\n' "$TEST_TMP/child" > "$BIN/codex"
  chmod +x "$BIN/codex"
  local started=$SECONDS
  PREFLIGHT_TIMEOUT=1 run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
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
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model unavailable --codex-model discovered --gemini-model selected
  [[ "$output" == *"codex"*"discovered"*"READY"* ]] || false
  [ "$(cat "$TEST_TMP/models")" = $'unavailable\ndiscovered' ]
}

@test "one discovered ladder still reports a missing other reviewer" {
  fake_codex_ready
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected
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
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex"*"READY"* ]]
}

@test "QC T2-4: the Codex probe carries the real high reasoning effort" {
  fake_codex_ready; fake_agy_ready
  sed -i.bak '2i\
printf "%s\\n" "$@" > "$TEST_TMP/codex-args"\
' "$BIN/codex"
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
  [ "$status" -eq 0 ]
  grep -Fx 'model_reasoning_effort=high' "$TEST_TMP/codex-args"
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
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).resolve().parents[2] / 'tests')); from fence import fence
code = fence(sys.argv[1], 'failure-probe')
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
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected:medium --gemini-model selected
  [ "$status" -eq 0 ]
  grep -Fx 'model_reasoning_effort=medium' "$TEST_TMP/codex-args"
  run grep -Fx 'model_reasoning_effort=high' "$TEST_TMP/codex-args"
  [ "$status" -ne 0 ]
  # -m must carry the slug only; "selected:medium" is not a model id
  grep -Fx 'selected' "$TEST_TMP/codex-args"
  run grep -Fx 'selected:medium' "$TEST_TMP/codex-args"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# A reviewer that authored the diff is not a reviewer of it.
#
# The skill states this one way only -- "a second opinion from the same model
# is not a second opinion" -- and names Claude. It has to hold for any author:
# when Astra writes the diff, Codex is the author and cannot clear its own work.
# Nothing today expresses that, so a pass with both CLIs ready reads as full
# coverage even when one of them wrote the code under review.
# ---------------------------------------------------------------------------

# Fails if a pass reports full coverage while one of the two answering
# reviewers authored the diff. Full coverage here is the ABSENCE of a partial
# line, so the assertion has to look for the line rather than for its lack.
@test "an authoring reviewer does not count toward coverage" {
  fake_codex_ready; fake_agy_ready          # BOTH answer
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected --authored-by codex
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'PARTIAL COVERAGE'
}

# Fails if excluding the only answering reviewer still reports coverage.
@test "excluding the only answering reviewer leaves no coverage" {
  fake_codex_ready; fake_agy_unavailable
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected --authored-by codex
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'NO REVIEWER CAN ANSWER'
}

# Fails if an excluded reviewer is reported as unable to answer. It answered
# fine; it is barred. Conflating the two hides why coverage dropped, and the
# operator cannot tell a broken CLI from a disqualified author.
@test "an excluded reviewer is reported as the author, not as unable to answer" {
  fake_codex_ready; fake_agy_ready
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected --authored-by codex
  # Require a completed pass first: without this the assertions below are
  # satisfied by the "unknown argument: --authored-by" rejection, which
  # contains the string "author" and would pass with the flag unimplemented.
  [ "$status" -eq 0 ]
  local msg="$output"
  printf '%s\n' "$msg" | grep -qi 'author'
  [[ "$msg" != *"codex cannot answer"* ]] || false
}

@test "the Gemini probe passes no --effort" {
  # Fails if the probe adds --effort, which agy refuses for any model whose id carries another effort.
  fake_codex_ready; fake_agy_ready
  sed -i.bak '2i\
for a in "$@"; do [ "$a" = --effort ] \&\& { echo "error: --model x conflicts with --effort=high" >\&2; exit 2; }; done\
' "$BIN/agy"
  run bash "$PREFLIGHT" --gemini-model gemini-4-neon-xhigh
  [[ "$output" == *"gemini"*"READY"* ]]
}

@test "the documented probe block still probes Codex when the Gemini ladder is empty" {
  # Fails if an empty ladder aborts the block before the other reviewer is probed.
  mkdir -p "$TEST_TMP/plugin/skills/external-review"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/probe-args"\n' "$TEST_TMP" \
    > "$TEST_TMP/plugin/skills/external-review/preflight.sh"
  python3 - "$BATS_TEST_DIRNAME/../SKILL.md" "$TEST_TMP/probe.sh" <<'PY'
import pathlib, re, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).resolve().parents[2] / 'tests')); from fence import fence
block = fence(sys.argv[1], 'probe')
pathlib.Path(sys.argv[2]).write_text('CODEX_RUNGS="fixture:high"\nGEMINI_RUNGS=""\n' + block)
PY
  ROOT="$TEST_TMP" CLAUDE_PLUGIN_ROOT="$TEST_TMP/plugin" run bash "$TEST_TMP/probe.sh"
  [ -f "$TEST_TMP/probe-args" ] || false
  grep -Fx 'fixture:high' "$TEST_TMP/probe-args"
}

# discovery_script <codex_ladder body> <gemini_ladder body>: the documented
# discovery block with both ladder functions stubbed, under errexit, ending
# with a line that prints both rung lists.
discovery_script() {   # $3 = agy_models body, default: one model listed
  python3 - "$BATS_TEST_DIRNAME/../SKILL.md" "$TEST_TMP/discover.sh" "$1" "$2" "${3:-echo gemini-4-neon-high;}" "$TEST_TMP" <<'PY'
import pathlib, re, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).resolve().parents[2] / 'tests')); from fence import fence
block = fence(sys.argv[1], 'discovery').replace('<scratchpad>', sys.argv[6])
prelude = ('set -e\n'
           'codex_ladder() { ' + sys.argv[3] + ' }\n'
           'gemini_ladder() { ' + sys.argv[4] + ' }\n'
           'agy_models() { ' + sys.argv[5] + ' }\n')
pathlib.Path(sys.argv[2]).write_text(prelude + block + 'echo "codex=[$CODEX_RUNGS] gemini=[$GEMINI_RUNGS]"\n')
PY
}

@test "a failed Codex discovery still runs Gemini discovery under errexit" {
  # Fails if CODEX_RUNGS="$(codex_ladder)" aborts the block when the ladder exits 1.
  discovery_script 'return 1;' 'echo gemini-4-neon-high;'
  run bash "$TEST_TMP/discover.sh"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"codex=[] gemini=[gemini-4-neon-high]"* ]]
}

@test "a Gemini listing that fails after printing an id gives an empty ladder" {
  # Fails if a failed agy models still yields rungs, because its status is lost.
  discovery_script 'echo fixture:high;' 'cat;' 'echo gemini-4-neon-high; return 1;'
  run bash "$TEST_TMP/discover.sh"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"codex=[fixture:high] gemini=[]"* ]]
}

@test "a Codex rung without an effort clears the ladder" {
  # Fails if discovery says "do not run" but leaves CODEX_RUNGS set for the loops.
  discovery_script 'echo fixture;' 'echo gemini-4-neon-high;'
  run bash "$TEST_TMP/discover.sh"
  [[ "$output" == *"codex=[] gemini=[gemini-4-neon-high]"* ]]
}

# Fails if the documented Gemini loop accepts exit 0 and a non-empty answer
# when agy reports on stderr that it cut the turn short: the partial list then
# counts as coverage and can satisfy the review loop's stop rule.
@test "the documented Gemini loop does not accept a partial answer as coverage" {
  python3 - "$BATS_TEST_DIRNAME/../SKILL.md" "$TEST_TMP/gemini.sh" "$TEST_TMP" <<'PY'
import pathlib, re, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).resolve().parents[2] / 'tests')); from fence import fence
block = fence(sys.argv[1], 'gemini-loop')
prelude = ('GEMINI_RUNGS="gemini-4-neon-high"\n'
           'agy() { echo "1. **[High]** a finding cut off mid"; '
           'echo "[agy] print timeout after 25m0s with turn in progress; returning partial output" >&2; return 0; }\n')
block = (block.replace('<scratchpad>', sys.argv[3]).replace('<mode>', 'phase')
         .replace('<n>', '1').replace('<chunk>', '1').replace('<attempt>', '1'))
pathlib.Path(sys.argv[3], 'gemini_prompt_p1_c1.txt').write_text('prompt')
pathlib.Path(sys.argv[3], 'gemini_prompt_p1.txt').write_text('prompt')
pathlib.Path(sys.argv[2]).write_text(prelude + block)
PY
  run bash "$TEST_TMP/gemini.sh"
  [[ "$output" == *"incomplete"* ]] || false
  [ ! -s "$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-neon-high.txt" ]
}

# Fails if every Gemini chunk reads one prompt file, so a retry or a parallel
# run can answer another chunk's material under this chunk's name.
@test "the documented Gemini loop reads a prompt file per chunk" {
  python3 - "$BATS_TEST_DIRNAME/../SKILL.md" <<'PY'
import pathlib, re, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).resolve().parents[2] / 'tests')); from fence import fence
block = fence(sys.argv[1], 'gemini-loop')
assert 'gemini_prompt_p<n>_c<chunk>.txt' in block, block
PY
}

# gemini_loop <agy body>: the documented Gemini loop with agy stubbed, one rung,
# pass 1 chunk 1, writing into $TEST_TMP.
gemini_loop() {
  python3 - "$BATS_TEST_DIRNAME/../SKILL.md" "$TEST_TMP/gemini.sh" "$TEST_TMP" "$1" "${2:-1}" <<'PY'
import pathlib, re, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).resolve().parents[2] / 'tests')); from fence import fence
block = fence(sys.argv[1], 'gemini-loop')
prelude = 'GEMINI_RUNGS="gemini-4-neon-high gemini-4-argon-high"\nagy() { ' + sys.argv[4] + ' }\n'
block = (block.replace('<scratchpad>', sys.argv[3]).replace('<mode>', 'phase')
         .replace('<n>', '1').replace('<chunk>', sys.argv[5]).replace('<attempt>', '1'))
pathlib.Path(sys.argv[2]).write_text(prelude + block)
PY
}

@test "the documented Gemini loop does not run without its chunk's prompt" {
  # Fails if a missing prompt file still invokes agy, filing an answer to nothing under the chunk's name.
  gemini_loop 'touch "$TEST_TMP/AGY-RAN"; echo "No findings.";'
  run bash "$TEST_TMP/gemini.sh"
  [ ! -e "$TEST_TMP/AGY-RAN" ] || false
  [ ! -e "$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-neon-high.txt" ]
}

@test "the documented Gemini loop keeps a failed run's partial answer out of the output name" {
  # Fails if agy writes part of an answer and exits non-zero, and the output file keeps it.
  printf 'prompt' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  gemini_loop 'echo "1. half a finding"; echo "connection reset" >&2; return 1;'
  run bash "$TEST_TMP/gemini.sh"
  [ ! -e "$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-neon-high.txt" ] || false
  [ -s "$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-neon-high.partial" ]
}

@test "the documented Gemini loop passes each chunk its own prompt" {
  # Fails if the loop reads a prompt other than this chunk's file.
  printf 'CHUNK-ONE' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  printf 'SHARED' > "$TEST_TMP/gemini_prompt_p1.txt"
  gemini_loop 'printf "%s" "$2" > "$TEST_TMP/seen"; echo "No findings.";'
  run bash "$TEST_TMP/gemini.sh"
  [ "$(cat "$TEST_TMP/seen")" = "CHUNK-ONE" ]
}

@test "the documented Gemini loop keeps a finished answer whose stderr mentions a timeout" {
  # Fails if any "timed out" warning on stderr discards a complete answer.
  printf 'prompt' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  gemini_loop 'echo "No findings."; echo "request timed out, retrying" >&2; return 0;'
  run bash "$TEST_TMP/gemini.sh"
  [ -s "$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-neon-high.txt" ]
}

@test "the documented Gemini loop runs a suffix-less id at high, and a suffixed one as named" {
  # Fails if a suffix-less id runs at agy's default effort, or a suffixed id gets a second effort.
  printf 'prompt' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  gemini_loop 'printf "%s\n" "$@" > "$TEST_TMP/args-$4"; echo "No findings.";'
  sed -i.bak 's/^GEMINI_RUNGS=.*/GEMINI_RUNGS="gemini-4-neon"/' "$TEST_TMP/gemini.sh"
  run bash "$TEST_TMP/gemini.sh"
  grep -qx -- '--effort' "$TEST_TMP/args-gemini-4-neon" || false
  grep -qx -- 'high' "$TEST_TMP/args-gemini-4-neon" || false
  sed -i.bak 's/^GEMINI_RUNGS=.*/GEMINI_RUNGS="gemini-4-neon-xhigh"/' "$TEST_TMP/gemini.sh"
  run bash "$TEST_TMP/gemini.sh"
  ! grep -qx -- '--effort' "$TEST_TMP/args-gemini-4-neon-xhigh" || false
}

@test "the documented Gemini loop keeps an answer whose stderr only mentions a print timeout setting" {
  # Fails if any "print timeout" text, not agy's own cut-off notice, discards a finished answer.
  printf 'prompt' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  gemini_loop 'echo "No findings."; echo "config: print timeout is 25m" >&2; return 0;'
  run bash "$TEST_TMP/gemini.sh"
  [ -s "$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-neon-high.txt" ]
}

@test "the documented Gemini loop sets aside agy's cut-off answer" {
  # Fails if agy's own print-timeout notice still lets a partial answer count.
  printf 'prompt' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  gemini_loop 'echo "1. half"; echo "[agy] print timeout after 25m0s with turn in progress; returning partial output" >&2; return 0;'
  run bash "$TEST_TMP/gemini.sh"
  [ ! -e "$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-neon-high.txt" ] || false
  [ -s "$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-neon-high.partial" ]
}

@test "the documented Gemini loop leaves a trace of a failure that wrote nothing" {
  # Fails if a non-availability failure with no output leaves no file progress.sh can report.
  printf 'prompt' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  gemini_loop 'echo "auth expired" >&2; return 1;'
  run bash "$TEST_TMP/gemini.sh"
  [ -e "$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-neon-high.partial" ]
}

@test "the documented Gemini loop leaves nothing behind for an unavailable rung" {
  # Fails if a rung that downshifted on availability leaves a .partial beside the next rung's answer.
  printf 'prompt' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  gemini_loop 'if [ "$4" = gemini-4-neon-high ]; then echo "x"; echo "model is not supported" >&2; return 1; fi; echo "No findings.";'
  run bash "$TEST_TMP/gemini.sh"
  [ ! -e "$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-neon-high.partial" ] || false
  [ -s "$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-argon-high.txt" ]
}

@test "the documented Gemini loop reads chunk 2's prompt for chunk 2" {
  # Fails if the prompt file is fixed to one chunk rather than following <chunk>.
  printf 'CHUNK-ONE' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  printf 'CHUNK-TWO' > "$TEST_TMP/gemini_prompt_p1_c2.txt"
  # Only the <chunk> placeholder becomes 2, so a chunk number fixed in the fence stays wrong.
  gemini_loop 'printf "%s" "$2" > "$TEST_TMP/seen"; echo "No findings.";' 2
  run bash "$TEST_TMP/gemini.sh"
  [ "$(cat "$TEST_TMP/seen")" = "CHUNK-TWO" ]
}

@test "the Codex probe runs in the review root when one is given" {
  # Fails if preflight probes Codex in the caller's folder instead of the pruned export (KI-61).
  fake_codex_ready; fake_agy_ready
  mkdir -p "$TEST_TMP/root"
  cat > "$BIN/codex" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$TEST_TMP/codex-args"
while [ "$1" != -o ]; do shift; done; echo ready > "$2"
SH
  chmod +x "$BIN/codex"
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model m:high --gemini-model g --root "$TEST_TMP/root"
  grep -qx -- '-C' "$TEST_TMP/codex-args" || false
  grep -qxF -- "$TEST_TMP/root" "$TEST_TMP/codex-args"
}

@test "the Gemini probe runs a suffix-less id at high, as the review does" {
  # Fails if the probe checks a suffix-less id at agy's default while the review runs it at high (F-132).
  fake_codex_ready; fake_agy_ready
  sed -i.bak '2i\
printf "%s\\n" "$@" > "$TEST_TMP/agy-args"\
' "$BIN/agy"
  run bash "$PREFLIGHT" --gemini-model gemini-4-neon
  grep -qx -- '--effort' "$TEST_TMP/agy-args" || false
  grep -qx -- 'high' "$TEST_TMP/agy-args"
}

@test "the documented Gemini loop gives a -max id no second effort" {
  # Fails if -max is not read as an effort suffix, so the loop adds --effort high to it (F-131).
  printf 'prompt' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  gemini_loop 'printf "%s\n" "$@" > "$TEST_TMP/args-$4"; echo "No findings.";'
  sed -i.bak 's/^GEMINI_RUNGS=.*/GEMINI_RUNGS="gemini-4-neon-max"/' "$TEST_TMP/gemini.sh"
  run bash "$TEST_TMP/gemini.sh"
  [ -e "$TEST_TMP/args-gemini-4-neon-max" ] || false
  ! grep -qx -- '--effort' "$TEST_TMP/args-gemini-4-neon-max"
}

@test "the documented ladder wrappers pass a requested effort through" {
  # Fails if codex_ladder or gemini_ladder drops --effort, so a requested max runs at high (F-150).
  mkdir -p "$TEST_TMP/home/.codex"
  printf '{"models":[{"slug":"gpt-6-sol","visibility":"list","supported_reasoning_levels":[{"effort":"high"},{"effort":"max"}]}]}' \
    > "$TEST_TMP/home/.codex/models_cache.json"
  python3 - "$BATS_TEST_DIRNAME/../SKILL.md" "$TEST_TMP/wrappers.sh" "$TEST_TMP" <<'PY'
import pathlib, re, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).resolve().parents[2] / 'tests')); from fence import fence
block = fence(sys.argv[1], 'ladder-wrappers')
pathlib.Path(sys.argv[2]).write_text(
    'agy() { printf "%s\\n" gemini-4-neon-high gemini-4-neon-xhigh; }\n'
    + block.replace('<scratchpad>', sys.argv[3])
    + 'codex_ladder --effort max; agy_models | gemini_ladder --effort xhigh\n')
PY
  HOME="$TEST_TMP/home" CLAUDE_PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)" run bash "$TEST_TMP/wrappers.sh"
  [ "$status" -eq 0 ] || false
  [ "$output" = "$(printf 'gpt-6-sol:max\ngemini-4-neon-xhigh')" ]
}

@test "discovery tells an empty Gemini ladder from a failed listing" {
  # Fails if a successful listing with no model at the requested effort is blamed on agy-models.err (F-156).
  discovery_script 'echo fixture:high;' 'true;'
  run bash "$TEST_TMP/discover.sh"
  [[ "$output" == *"No Gemini model offers"* ]] || false
  [[ "$output" != *"agy-models.err"* ]] || false
  discovery_script 'echo fixture:high;' 'cat;' 'return 1;'
  run bash "$TEST_TMP/discover.sh"
  [[ "$output" == *"agy models failed"* ]]
}

# --- the documented fences under each shell (KI-74) -------------------------
# The Bash tool runs the user's login shell, often zsh. Each check below runs
# under bash and, in its own test, under zsh -f.

# gemini_rungs_in <shell...>: two rungs, the first unavailable.
gemini_rungs_in() {
  printf 'prompt' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  gemini_loop 'printf "%s\n" "$4" >> "$TEST_TMP/models"; if [ "$4" = gemini-4-neon-high ]; then echo "model is not supported" >&2; return 1; fi; echo "No findings.";'
  run "$@" "$TEST_TMP/gemini.sh"
  [ "$(cat "$TEST_TMP/models")" = "$(printf 'gemini-4-neon-high\ngemini-4-argon-high')" ]
}

@test "bash: the documented Gemini loop tries each rung in turn" {
  # Fails if the loop does not walk the rungs one model at a time under bash.
  gemini_rungs_in bash
}

@test "zsh: the documented Gemini loop tries each rung in turn" {
  # Fails if zsh reads the rung list as one word and the loop runs once.
  command -v zsh >/dev/null || skip "zsh is not installed"
  gemini_rungs_in zsh -f
}

# discovery_effort_in <shell...>: the user asks for max; both ladders get it,
# and the empty-ladder messages name it.
discovery_effort_in() {
  discovery_script 'printf "%s\n" "$@" > "$TEST_TMP/codex-ladder-args";' 'printf "%s\n" "$@" > "$TEST_TMP/gemini-ladder-args";'
  grep -q '^EFFORT=high' "$TEST_TMP/discover.sh" || false
  sed -i.bak 's/^EFFORT=high/EFFORT=max/' "$TEST_TMP/discover.sh"
  run "$@" "$TEST_TMP/discover.sh"
  [ "$(cat "$TEST_TMP/codex-ladder-args")" = "$(printf -- '--effort\nmax')" ] || false
  [ "$(cat "$TEST_TMP/gemini-ladder-args")" = "$(printf -- '--effort\nmax')" ] || false
  [[ "$output" == *"No Codex rung at max"* ]] || false
  [[ "$output" == *"No Gemini model offers max"* ]]
}

@test "bash: discovery passes the requested effort to both ladders and names it" {
  # Fails if a requested effort is dropped, or the messages name something else.
  discovery_effort_in bash
}

@test "zsh: discovery passes the requested effort to both ladders and names it" {
  # Fails if zsh's 1-based arrays make the messages name "--effort" instead of the effort.
  command -v zsh >/dev/null || skip "zsh is not installed"
  discovery_effort_in zsh -f
}

# probe_args_in <shell...>: the documented probe block with a review root whose
# path holds a space; the fake preflight.sh records its argument vector.
probe_args_in() {
  mkdir -p "$TEST_TMP/plugin/skills/external-review" "$TEST_TMP/my root"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/probe-args"\n' "$TEST_TMP" \
    > "$TEST_TMP/plugin/skills/external-review/preflight.sh"
  python3 - "$BATS_TEST_DIRNAME/../SKILL.md" "$TEST_TMP/probe.sh" <<'PY'
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).resolve().parents[2] / 'tests')); from fence import fence
pathlib.Path(sys.argv[2]).write_text('CODEX_RUNGS="m1:high"\nGEMINI_RUNGS="gemini-4-neon-high"\n' + fence(sys.argv[1], 'probe'))
PY
  ROOT="$TEST_TMP/my root" CLAUDE_PLUGIN_ROOT="$TEST_TMP/plugin" run "$@" "$TEST_TMP/probe.sh"
  [ "$(cat "$TEST_TMP/probe-args")" = "$(printf -- '--codex-model\nm1:high\n--gemini-model\ngemini-4-neon-high\n--timeout\n120\n--root\n%s' "$TEST_TMP/my root")" ]
}

@test "bash: the documented probe passes --root and its value as two arguments" {
  # Fails if the root reaches preflight.sh as anything but its own argument.
  probe_args_in bash
}

@test "zsh: the documented probe passes --root and its value as two arguments" {
  # Fails if zsh keeps "--root <path>" as one word.
  command -v zsh >/dev/null || skip "zsh is not installed"
  probe_args_in zsh -f
}

@test "the documented probe refuses to probe Codex without a review root" {
  # Fails if the probe runs Codex in the caller's folder when ROOT is unset (KI-64).
  mkdir -p "$TEST_TMP/plugin/skills/external-review"
  printf '#!/usr/bin/env bash\ntouch "%s/PROBED"\n' "$TEST_TMP" > "$TEST_TMP/plugin/skills/external-review/preflight.sh"
  python3 - "$BATS_TEST_DIRNAME/../SKILL.md" "$TEST_TMP/probe.sh" <<'PY'
import pathlib, sys
sys.path.insert(0, str(pathlib.Path(sys.argv[1]).resolve().parents[2] / 'tests')); from fence import fence
pathlib.Path(sys.argv[2]).write_text('unset ROOT\nCODEX_RUNGS="m1:high"\nGEMINI_RUNGS=""\n' + fence(sys.argv[1], 'probe'))
PY
  CLAUDE_PLUGIN_ROOT="$TEST_TMP/plugin" run bash "$TEST_TMP/probe.sh"
  [ "$status" -ne 0 ] || false
  [ ! -e "$TEST_TMP/PROBED" ] || false
  [[ "$output" == *"ROOT"* ]]
}

# --- KI-43, KI-64, KI-66, KI-71 ---------------------------------------------

@test "a ready answer with an incidental timeout note on stderr is READY" {
  # Fails if any "timed out" on stderr overrides a probe that answered (KI-43).
  fake_codex_ready
  printf '#!/bin/sh\necho ready\necho "request timed out, retrying" >&2\n' > "$BIN/agy"; chmod +x "$BIN/agy"
  run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
  [[ "$(printf '%s\n' "$output" | grep '^gemini')" == *READY* ]]
}

@test "a ready answer beside a deadline or cut-off line is TIMEOUT" {
  # Control: an explicit cut-off still overrides a partial readiness token.
  local msg
  fake_codex_ready
  for msg in "print timeout: turn in progress" "[agy] print timeout after 2m0s with turn in progress; returning partial output" "probe timeout"; do
    printf '#!/bin/sh\necho ready\necho "%s" >&2\n' "$msg" > "$BIN/agy"; chmod +x "$BIN/agy"
    run bash "$PREFLIGHT" --root "$TEST_TMP" --codex-model selected --gemini-model selected
    [[ "$(printf '%s\n' "$output" | grep '^gemini')" == *TIMEOUT* ]] || false
  done
}

@test "a Codex probe without --root is refused" {
  # Fails if Codex is probed in the caller's folder (KI-64).
  fake_codex_ready; fake_agy_ready
  run bash "$PREFLIGHT" --codex-model selected --gemini-model selected
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"--root"* ]]
}

@test "a --root that is not a directory is refused" {
  # Fails if a missing or file root reaches codex -C.
  fake_codex_ready; fake_agy_ready
  : > "$TEST_TMP/afile"
  run bash "$PREFLIGHT" --codex-model selected --root "$TEST_TMP/afile"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"not a directory"* ]]
}

@test "a Gemini id ending -low, -minimal, -none or -ultra is refused" {
  # Fails if the probe runs an effort the review never uses (KI-64).
  local s
  fake_agy_ready
  for s in low minimal none ultra; do
    run bash "$PREFLIGHT" --gemini-model "gemini-4-neon-$s"
    [ "$status" -eq 1 ] || { echo "$s: $output"; false; }
    [[ "$output" == *"gemini-4-neon-$s"*"refused"* ]] || false
  done
}

@test "a Gemini-only probe needs no root" {
  # Control: requiring a root for Codex does not block a Gemini-only probe.
  fake_agy_ready
  run bash "$PREFLIGHT" --gemini-model gemini-4-neon-high
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"gemini"*"READY"* ]]
}

@test "discovery names gemini-ladder.py when the ranker fails" {
  # Fails if a failed ranker is blamed on agy models and its empty error file (KI-71).
  discovery_script 'echo fixture:high;' 'return 3;' 'echo gemini-4-neon-high;'
  run bash "$TEST_TMP/discover.sh"
  [[ "$output" == *"gemini-ladder.py failed"* ]] || false
  [[ "$output" != *"agy models failed"* ]]
}

@test "the documented Gemini loop keeps an answer when stderr announces the print timeout setting" {
  # Fails if an "[agy] print timeout" line that is not agy's cut-off notice discards a finished answer (KI-66).
  printf 'prompt' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  gemini_loop 'echo "No findings."; echo "[agy] print timeout set to 25m0s" >&2; return 0;'
  run bash "$TEST_TMP/gemini.sh"
  [ -s "$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-neon-high.txt" ]
}

@test "the documented Gemini loop records each attempt's start and end state" {
  # Fails if progress.sh has only file times to judge a run by (KI-66).
  printf 'prompt' > "$TEST_TMP/gemini_prompt_p1_c1.txt"
  gemini_loop 'echo "1. half"; echo "connection reset" >&2; return 1;'
  run bash "$TEST_TMP/gemini.sh"
  local base="$TEST_TMP/gemini_phase_p1_c1_a1_gemini-4-neon-high"
  [[ "$(cat "$base.start")" =~ ^[0-9]+$ ]] || false
  [ "$(cat "$base.state")" = failed ] || false
  gemini_loop 'echo "1. half"; echo "[agy] print timeout after 25m0s with turn in progress; returning partial output" >&2; return 0;'
  run bash "$TEST_TMP/gemini.sh"
  [ "$(cat "$base.state")" = cut-off ]
}
