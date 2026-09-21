#!/usr/bin/env bats
#
# Batch grading. Every test names the condition that turns it red.
#
# The canary is an unblinded or unanchored grade: a grader that can see which
# arm it grades, or a verdict whose evidence is not in the answer, looks exactly
# like a real grade in the summary table.

setup() {
  export TEST_TMP="$(mktemp -d)"
  export SESS="$TEST_TMP/proj/sess.jsonl"
  export WORK="$TEST_TMP/repo" EV="$TEST_TMP/evidence" GD="$TEST_TMP/grading" BIN="$TEST_TMP/bin"
  # Run copies, so a test that edits the grader prompt never touches the repository.
  mkdir -p "$BIN" "$WORK/skills/design-review/tests"
  for f in grade_batch.py grade.py grade_eval.py evidence.py grader-prompt.md; do
    cp "$BATS_TEST_DIRNAME/$f" "$BIN/"
  done
  export GB="$BIN/grade_batch.py" EVPY="$BIN/evidence.py"
  cd "$WORK"
  git init -q -b main .
  git config user.email t@example.invalid
  git config user.name Test
  printf 'DESIGN REVIEW SKILL BODY\n' > skills/design-review/SKILL.md
  cat > skills/design-review/tests/s01-alpha.md <<'EOF'
# S01 — alpha

**Loads:** design-review

## Failure conditions

1. **Table** — omits the module table.
2. **Reviewer** — omits the paragraph for the reviewer.

## Prompt

> Do the alpha thing.
EOF
  git add -A && git commit -qm base
  python3 "$EVPY" init "$EV" --round 9 --model m --tests skills/design-review/tests --replicates 2 >/dev/null
  local P n=0; P="$(cat "$EV/S01-prompt.txt")"
  for arm in baseline with-skill; do
    for rep in 1 2; do
      # The agent ID encodes the arm, so the answer text must not repeat it: a
      # packet is only blind if nothing in it can say which arm it came from.
      local id="run${arm:0:1}000$rep"
      n=$((n + 1))
      write_answer "$(session_run "$id")" "$P" "$(printf 'MODULE TABLE from answer %s\nREVIEWER PARAGRAPH from answer %s' "$n" "$n")"
      python3 "$EVPY" log-dispatch "$EV" --scenario S01 --arm "$arm" --replicate "$rep" --agent-id "$id" >/dev/null
    done
  done
}

teardown() { cd /; [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"; }

run_path() {
  mkdir -p "$TEST_TMP/proj/sess/subagents"
  printf '%s\n' "$TEST_TMP/proj/sess/subagents/agent-$1.jsonl"
}
notify() {
  mkdir -p "$TEST_TMP/proj"
  python3 - "$SESS" "$1" "${2:-completed}" <<'PY'
import json, sys
note = ("<task-notification>\n<task-id>%s</task-id>\n<status>%s</status>\n"
        "<summary>Agent finished</summary>\n<result>done</result>\n</task-notification>"
        % (sys.argv[2], sys.argv[3]))
with open(sys.argv[1], "a") as f:
    f.write(json.dumps({"type": "queue-operation", "operation": "enqueue", "content": note}) + "\n")
PY
}
session_run() { notify "$1" completed; run_path "$1"; }
# write_answer <path> <prompt> <answer> [tool]: a finished run, optionally one
# that used a tool first.
write_answer() {
  python3 - "$@" <<'PY'
import json, sys
path, prompt, answer = sys.argv[1:4]
rows = [{"type": "user", "message": {"role": "user", "content": prompt}}]
if len(sys.argv) > 4:
    rows.append({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "name": sys.argv[4], "input": {}}]}})
rows.append({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": answer}]}})
open(path, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
}
record_all() { python3 "$EVPY" record-log "$EV" --session "$SESS" >/dev/null; }
prepare() { record_all; python3 "$GB" prepare "$EV" "$GD" --grader-model m --seed 7 >/dev/null; }

# pk <python expression over p>: packet IDs whose packet matches, sorted.
pk() {
  python3 - "$GD/grading.json" "$1" <<'PY'
import json, sys
g = json.load(open(sys.argv[1]))
print(" ".join(pid for pid, p in sorted(g["packets"].items()) if eval(sys.argv[2], {"p": p})))
PY
}
# twin <packet>: the first-pass packet grading the same answer as a repeat.
twin() {
  python3 - "$GD/grading.json" "$1" <<'PY'
import json, sys
g = json.load(open(sys.argv[1])); r = g["packets"][sys.argv[2]]
print(next(pid for pid, p in g["packets"].items() if p["pass"] == 1 and
           (p["scenario"], p["arm"], p["replicate"]) == (r["scenario"], r["arm"], r["replicate"])))
PY
}
# grade_packet <packet> <agent> <verdict-1> <verdict-2|omit> [tool] [evidence-for-1]:
# a finished grader that replied to its packet, logged and notified.
grade_packet() {
  local reply
  reply="$(python3 - "$GD" "$EV" "$1" "$3" "$4" "${6:-}" <<'PY'
import json, pathlib, sys
gd, ev, pid, v1, v2, quote1 = sys.argv[1:7]
p = json.loads((pathlib.Path(gd) / "grading.json").read_text())["packets"][pid]
m = json.loads((pathlib.Path(ev) / "manifest.json").read_text())
rec = m["scenarios"][p["scenario"]]["arms"][f"{p['arm']}#{p['replicate']}"]
lines = (pathlib.Path(ev) / rec["answer"]).read_text().splitlines()
judged = {"1": {"verdict": v1, "reason": "Graded.", "evidence": quote1 or lines[0]}}
if v2 != "omit":
    judged["2"] = {"verdict": v2, "reason": "Graded.", "evidence": lines[1]}
print(json.dumps({"judgements": judged}))
PY
)"
  write_answer "$(run_path "$2")" "$(cat "$GD/dispatch/$1.txt")" "$reply" ${5:+"$5"}
  notify "$2" completed
  python3 "$GB" log-dispatch "$GD" --packet "$1" --agent-id "$2" >/dev/null
}
report_statuses() {
  python3 -c "import json,sys;r=json.load(open(sys.argv[1]));print(' '.join(q['id']+'='+q['status'] for q in r['questions']))" "$GD/reports/$1.json"
}

@test "F-05: summary excludes an old first grade while its replacement is pending" {
  # Fails if report existence substitutes for the current dispatch identity.
  prepare
  local n=0 pid first
  for pid in $(pk "p['pass'] == 1"); do
    n=$((n + 1)); grade_packet "$pid" "grader000$n" pass pass
  done
  python3 "$GB" collect "$GD" --session "$SESS" >/dev/null
  first="$(pk "p['pass'] == 1" | cut -d' ' -f1)"
  python3 "$GB" log-dispatch "$GD" --packet "$first" --agent-id newgrade01 --replace
  run python3 "$GB" summary "$GD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"1 packet(s) not yet collected"* ]]
}

@test "F-06: already collected packets are still checked for edits" {
  # Fails if the cached report path bypasses the prepared packet hash.
  prepare
  local pid; pid="$(pk True | cut -d' ' -f1)"
  grade_packet "$pid" grader0001 pass pass
  python3 "$GB" collect "$GD" --session "$SESS" >/dev/null
  echo CHANGED >> "$GD/dispatch/$pid.txt"
  run python3 "$GB" collect "$GD" --session "$SESS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"edited after prepare"* ]]
}

@test "prepare: one blind packet per recorded answer, plus one repeat per scenario and arm" {
  # Red if a packet names its arm or replicate, which unblinds the grader, or if
  # no answer is graded twice, which leaves agreement unmeasured.
  record_all
  run python3 "$GB" prepare "$EV" "$GD" --grader-model m --seed 7
  [ "$status" -eq 0 ]
  [ "$(ls "$GD/dispatch" | wc -l | tr -d ' ')" -eq 6 ]
  [ "$(pk "p['pass'] == 2 and p['arm'] == 'baseline'" | wc -w | tr -d ' ')" -eq 1 ]
  [ "$(pk "p['pass'] == 2 and p['arm'] == 'with-skill'" | wc -w | tr -d ' ')" -eq 1 ]
  [ -z "$(grep -lE 'baseline|with-skill|replicate|runb|runw' "$GD"/dispatch/*.txt || true)" ]
  first="$(pk True | cut -d' ' -f1)"
  grep -q 'Design-review grader' "$GD/dispatch/$first.txt"
  grep -q 'MODULE TABLE from' "$GD/dispatch/$first.txt"
}

@test "prepare: refuses an evidence batch that is not complete and current" {
  # Red if grading starts on a partial batch: its summary would read as a result.
  python3 - "$EV/dispatch-log.tsv" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); lines = p.read_text().splitlines()
p.write_text("\n".join(lines[:-1]) + "\n")
PY
  record_all
  run python3 "$GB" prepare "$EV" "$GD" --grader-model m --seed 7
  [ "$status" -eq 1 ]
  [ ! -e "$GD/grading.json" ]
}

@test "collect: a grader's quoted verdicts come back as a grade.py report" {
  prepare
  P="$(pk True | cut -d' ' -f1)"
  grade_packet "$P" grader01 pass fail
  run python3 "$GB" collect "$GD" --session "$SESS"
  [ "$status" -eq 0 ]
  [ "$(report_statuses "$P")" = "1=pass 2=fail" ]
  python3 -c "import json,sys;j=json.load(open(sys.argv[1]));assert j['reviewer'].startswith('m grader, prompt '), j" "$GD/judgements/$P.json"
}

@test "collect: a verdict whose evidence is not quoted from the answer is refused" {
  # Red while a paraphrase is accepted: an unanchored verdict reads exactly like
  # a grounded one in the summary.
  prepare
  P="$(pk True | cut -d' ' -f1)"
  grade_packet "$P" grader02 pass pass "" "The answer has a fine module table"
  run python3 "$GB" collect "$GD" --session "$SESS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not quoted"* ]] || false
  [ ! -e "$GD/reports/$P.json" ]
  [ ! -e "$GD/judgements/$P.json" ]
}

@test "collect: a grader that used a tool is refused" {
  # Red if it is accepted: a grader with a tool could read the key or another
  # answer, so its verdict is no longer blind.
  prepare
  P="$(pk True | cut -d' ' -f1)"
  grade_packet "$P" grader03 pass pass Read
  run python3 "$GB" collect "$GD" --session "$SESS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool"* ]] || false
  [ ! -e "$GD/reports/$P.json" ]
}

@test "collect: a reply that skips a condition is refused" {
  prepare
  P="$(pk True | cut -d' ' -f1)"
  grade_packet "$P" grader04 pass omit
  run python3 "$GB" collect "$GD" --session "$SESS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"packet asks for"* ]]
}

@test "collect: grades are refused once the grader prompt has changed since prepare" {
  # Red if grades from two prompts are mixed into one summary.
  prepare
  P="$(pk True | cut -d' ' -f1)"
  grade_packet "$P" grader05 pass pass
  printf '\nOne more rule.\n' >> "$BIN/grader-prompt.md"
  run python3 "$GB" collect "$GD" --session "$SESS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"grader-prompt.md changed"* ]]
}

@test "collect: a grader still running is pending, not refused" {
  prepare
  P="$(pk True | cut -d' ' -f1)"
  mkdir -p "$TEST_TMP/proj"; : > "$TEST_TMP/proj/sess.jsonl"
  python3 "$GB" log-dispatch "$GD" --packet "$P" --agent-id busy0001 >/dev/null
  run python3 "$GB" collect "$GD" --session "$SESS"
  [ "$status" -eq 2 ]
  [[ "$output" == *"pending"* ]]
}

@test "agree: a repeat that disagrees with its first grade is counted and named" {
  # Red if agreement is reported without comparing two grades of one answer.
  prepare
  i=0
  for R in $(pk "p['pass'] == 2"); do
    i=$((i + 1))
    grade_packet "$(twin "$R")" "first00$i" pass pass
    grade_packet "$R" "again00$i" pass fail
  done
  python3 "$GB" collect "$GD" --session "$SESS" >/dev/null
  run python3 "$GB" agree "$GD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| S01 | 1 | 2/2 |"* ]] || false
  [[ "$output" == *"| S01 | 2 | 0/2 |"* ]] || false
  [[ "$output" == *"Overall: 2/4"* ]] || false
  [[ "$output" == *"condition 2: pass then fail"* ]]
}

@test "summary: counts first grades per arm and condition, and ignores repeats" {
  # Red if a repeat is counted: one answer would then count twice.
  prepare
  i=0
  for P in $(pk "p['pass'] == 1 and p['arm'] == 'baseline'"); do i=$((i + 1)); grade_packet "$P" "gradr00$i" pass pass; done
  for P in $(pk "p['pass'] == 1 and p['arm'] == 'with-skill'"); do i=$((i + 1)); grade_packet "$P" "gradr00$i" pass fail; done
  for P in $(pk "p['pass'] == 2"); do i=$((i + 1)); grade_packet "$P" "gradr00$i" fail fail; done
  python3 "$GB" collect "$GD" --session "$SESS" >/dev/null
  run python3 "$GB" summary "$GD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"| S01 | 1 | 2/2 | 2/2 |"* ]] || false
  [[ "$output" == *"| S01 | 2 | 2/2 | 0/2 |"* ]] || false
  [[ "$output" == *"| S01 | all conditions | 2/2 | 0/2 |"* ]]
}

@test "collect: a packet edited after prepare is refused" {
  # Red while only the grader prompt file is hashed: graders receive the whole
  # packet, so dropping a condition from it after prepare would still grade.
  prepare
  P="$(pk True | cut -d' ' -f1)"
  python3 - "$GD/dispatch/$P.txt" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("2. **Reviewer**", "2. **Reviewer (softened)**"))
PY
  grade_packet "$P" edited01 pass pass
  run python3 "$GB" collect "$GD" --session "$SESS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"edited after prepare"* ]] || false
  [ ! -e "$GD/reports/$P.json" ]
}

@test "F-05: replacement evidence makes completeness pending" {
  record_all
  python3 "$EVPY" log-dispatch "$EV" --scenario S01 --arm baseline --replicate 1 --agent-id newrun01 --replace
  run python3 "$EVPY" check "$EV" --require-complete
  echo "observed check status=$status $output" >&3
  [ "$status" -eq 1 ]
}
@test "F-05: replacement graders cannot inherit agreement" {
  prepare
  local n=0 pid first
  for pid in $(pk True); do
    n=$((n + 1))
    grade_packet "$pid" "grader000$n" pass pass
  done
  python3 "$GB" collect "$GD" --session "$SESS"
  first="$(pk "p['pass'] == 2" | cut -d' ' -f1)"
  python3 "$GB" log-dispatch "$GD" --packet "$first" --agent-id newgrade01 --replace
  run python3 "$GB" agree "$GD"
  echo "observed agreement status=$status $output" >&3
  [ "$status" -eq 1 ]
}
@test "F-06: recollection rejects expired evidence even with no pending graders" {
  prepare
  local n=0 pid
  for pid in $(pk True); do
    n=$((n + 1))
    grade_packet "$pid" "grader000$n" pass pass
  done
  python3 "$GB" collect "$GD" --session "$SESS"
  echo CHANGED >> "$EV/answers/S01-baseline-1.md"
  run python3 "$GB" collect "$GD" --session "$SESS"
  echo "observed recollect status=$status $output" >&3
  [ "$status" -eq 1 ]
}
