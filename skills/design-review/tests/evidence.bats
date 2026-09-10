#!/usr/bin/env bats
#
# The evidence harness. Every test names the condition that turns it red.
#
# The canary is STALE: evidence recorded against a skill that has since changed.
# Both real incidents this replaces were a mixed batch — baselines from one
# round, with-skill answers from another, and one repo-wide SHA that could not
# say which scenario had gone stale. So the assertions are per scenario.

setup() {
  export TEST_TMP="$(mktemp -d)"
  export WORK="$TEST_TMP/repo"
  export EV="$TEST_TMP/evidence"
  mkdir -p "$WORK/skills/design-review/tests" "$WORK/skills/phase-workflow"
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export EVPY="$here/evidence.py"

  cd "$WORK"
  git init -q -b main .
  git config user.email t@example.invalid
  git config user.name Test

  printf 'DESIGN REVIEW SKILL BODY\n' > skills/design-review/SKILL.md
  printf 'PHASE WORKFLOW SKILL BODY\n' > skills/phase-workflow/SKILL.md

  cat > skills/design-review/tests/s01-alpha.md <<'EOF'
# S01 — alpha

**Loads:** design-review

## Failure conditions

1. Fails if the answer omits the module table.

## Prompt

> Do the alpha thing.
> Second line.

## Results

| Run | Model ID | Date | Notes | Evidence status |
| --- | --- | --- | --- | --- |
EOF

  cat > skills/design-review/tests/s07-omega.md <<'EOF'
# S07 — omega

**Loads:** phase-workflow

## Failure conditions

1. Fails if the coverage line is absent.

## Prompt

> Do the omega thing.

## Results

| Run | Model ID | Date | Notes | Evidence status |
| --- | --- | --- | --- | --- |
EOF
  git add -A && git commit -qm base
}

teardown() { cd /; [ -n "${TEST_TMP:-}" ] && chmod -R u+w "$TEST_TMP" 2>/dev/null; rm -rf "$TEST_TMP"; }

jqv() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(eval(sys.argv[2],{'d':d}))" "$EV/manifest.json" "$1"; }

@test "init: records the loaded skill per scenario, not one SHA for the repo" {
  # THE point. A repo-wide SHA cannot say which scenario went stale.
  run python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 \
      --tests skills/design-review/tests
  [ "$status" -eq 0 ]
  [ "$(jqv "d['scenarios']['S01']['loads']")" = "design-review" ]
  [ "$(jqv "d['scenarios']['S07']['loads']")" = "phase-workflow" ]
  [ "$(jqv "d['scenarios']['S01']['skill_path']")" = "skills/design-review/SKILL.md" ]
  [ "$(jqv "d['scenarios']['S07']['skill_path']")" = "skills/phase-workflow/SKILL.md" ]
  [ "$(jqv "d['scenarios']['S01']['skill_content_hash'] != d['scenarios']['S07']['skill_content_hash']")" = "True" ]
}

@test "init: writes each dispatched prompt and it matches the scenario file" {
  run python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 \
      --tests skills/design-review/tests
  [ "$status" -eq 0 ]
  grep -q 'Do the alpha thing' "$EV/S01-prompt.txt"
  grep -q 'Second line' "$EV/S01-prompt.txt"
  ! grep -q '^> ' "$EV/S01-prompt.txt"
}

@test "init: snapshots the skill text that was loaded" {
  run python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 \
      --tests skills/design-review/tests
  [ "$status" -eq 0 ]
  grep -q 'DESIGN REVIEW SKILL BODY' "$EV/loaded-design-review.md"
  grep -q 'PHASE WORKFLOW SKILL BODY' "$EV/loaded-phase-workflow.md"
}

@test "check: a batch gathered against the current skills is current" {
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  run python3 "$EVPY" check "$EV"
  [ "$status" -eq 0 ]
  [[ "$output" == *"S01"*"current"* ]]
}

@test "check: only the scenario whose skill moved is reported expired" {
  # THE regression. One repo-wide SHA marks everything stale or nothing;
  # per-scenario tracking names exactly the row that has to be re-run.
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  printf 'PHASE WORKFLOW SKILL BODY — CHANGED\n' > skills/phase-workflow/SKILL.md
  run python3 "$EVPY" check "$EV"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S07"*"EXPIRED"* ]]
  [[ "$output" == *"S01"*"current"* ]]
}

@test "check: a changed grading condition also expires the scenario" {
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  python3 - <<'PY'
import pathlib
p = pathlib.Path("skills/design-review/tests/s01-alpha.md")
p.write_text(p.read_text().replace("omits the module table", "omits the module table and the cadence column"))
PY
  run python3 "$EVPY" check "$EV"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S01"*"EXPIRED"* ]]
}

@test "record: stores an answer with its arm, hash and tool-use count" {
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  P="$(cat "$EV/S01-prompt.txt")"
  python3 - "$TEST_TMP/t.jsonl" "$P" <<'MKJSON'
import json, sys
rows = [{"type":"user","message":{"role":"user","content":sys.argv[2]}},
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"ANSWER BODY"}]}}]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows) + "\n")
MKJSON
  run python3 "$EVPY" record "$EV" --scenario S01 --arm baseline --transcript "$TEST_TMP/t.jsonl"
  [ "$status" -eq 0 ]
  grep -q 'ANSWER BODY' "$EV/answers/S01-baseline.md"
  [ "$(jqv "d['scenarios']['S01']['arms']['baseline']['tool_uses']")" = "0" ]
}

@test "record: a baseline that used a tool is refused as contaminated" {
  # THE canary. A baseline that invoked the skill under test is not a baseline;
  # this happened to S02 in round 1 and was caught only by eye.
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  P="$(cat "$EV/S01-prompt.txt")"
  python3 - "$TEST_TMP/t.jsonl" "$P" <<'MKJSON'
import json, sys
rows = [{"type":"user","message":{"role":"user","content":sys.argv[2]}},
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"tool_use","name":"Skill","input":{}}]}},
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"ANSWER BODY"}]}}]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows) + "\n")
MKJSON
  run python3 "$EVPY" record "$EV" --scenario S01 --arm baseline --transcript "$TEST_TMP/t.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"contaminated"* || "$output" == *"tool"* ]]
  [ ! -e "$EV/answers/S01-baseline.md" ]
}

@test "record: an unknown scenario or arm is refused" {
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  printf '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"x"}]}}\n' > "$TEST_TMP/t.jsonl"
  run python3 "$EVPY" record "$EV" --scenario S99 --arm baseline --transcript "$TEST_TMP/t.jsonl"
  [ "$status" -eq 1 ]
  run python3 "$EVPY" record "$EV" --scenario S01 --arm sideways --transcript "$TEST_TMP/t.jsonl"
  [ "$status" -ne 0 ]
}

@test "check: an incomplete batch is reported, not passed" {
  # Red while check only compares hashes: a batch missing an arm reconciles
  # against the skills and still cannot support a grade.
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  run python3 "$EVPY" check "$EV" --require-complete
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing"* ]]
}

@test "init: a scenario that does not declare its skill is refused" {
  # Red while the skill is inferred from prose: the inference is right until a
  # scenario mentions the other skill in passing, and then it is silently wrong
  # about the one fact this file exists to track.
  python3 - <<'PY'
import pathlib, re
p = pathlib.Path("skills/design-review/tests/s01-alpha.md")
p.write_text(re.sub(r'^\*\*Loads:\*\*.*\n\n?', '', p.read_text(), flags=re.M))
PY
  run python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  [ "$status" -eq 1 ]
  [[ "$output" == *"Loads"* ]]
}

@test "record: a run dispatched with a different prompt is refused" {
  # THE S01 failure. A hand-assembled paste dropped the skill's frontmatter and
  # the Evidence section; the answer looked valid because nothing compared what
  # the run was actually given against what the batch says it was given.
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  cat > "$TEST_TMP/t.jsonl" <<'EOF'
{"type":"user","message":{"role":"user","content":"Do a completely different thing."}}
{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"ANSWER BODY"}]}}
EOF
  run python3 "$EVPY" record "$EV" --scenario S01 --arm baseline --transcript "$TEST_TMP/t.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not dispatched with"* ]]
  [ ! -e "$EV/answers/S01-baseline.md" ]
}

@test "record: the matching prompt is accepted even with a preamble around it" {
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  P="$(cat "$EV/S01-prompt.txt")"
  python3 - "$TEST_TMP/t.jsonl" "$P" <<'PY'
import json, sys
rows = [{"type":"user","message":{"role":"user","content":"Answer cold, no tools.\n\n" + sys.argv[2]}},
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"ANSWER BODY"}]}}]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  run python3 "$EVPY" record "$EV" --scenario S01 --arm baseline --transcript "$TEST_TMP/t.jsonl"
  [ "$status" -eq 0 ]
  grep -q 'ANSWER BODY' "$EV/answers/S01-baseline.md"
}

@test "record: a transcript captured mid-run is refused" {
  # Red while completeness is judged by "is there any text": a transcript copied
  # while the agent is still working ends on a tool call, and its last text is
  # the preamble the run opened with. That records as a valid short answer.
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  P="$(cat "$EV/S01-prompt.txt")"
  python3 - "$TEST_TMP/t.jsonl" "$P" <<'PY'
import json, sys
rows = [{"type":"user","message":{"role":"user","content":sys.argv[2]}},
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"I'll read the skill first."}]}},
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"tool_use","name":"Read","input":{}}]}}]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  run python3 "$EVPY" record "$EV" --scenario S01 --arm with-skill --transcript "$TEST_TMP/t.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"incomplete"* ]]
  [ ! -e "$EV/answers/S01-with-skill.md" ]
}

@test "check: a batch whose answer files are gone is not current" {
  # THE hole. check validated manifest keys and never opened the files they
  # name, so a batch with every answer deleted reported all seven current and
  # exited 0. Verified against the real round-4 batch before this test existed.
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  P="$(cat "$EV/S01-prompt.txt")"
  python3 - "$TEST_TMP/t.jsonl" "$P" <<'MKJSON'
import json, sys
rows = [{"type":"user","message":{"role":"user","content":sys.argv[2]}},
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"ANSWER BODY"}]}}]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows) + "\n")
MKJSON
  python3 "$EVPY" record "$EV" --scenario S01 --arm baseline --transcript "$TEST_TMP/t.jsonl"
  rm -f "$EV/answers/S01-baseline.md"
  run python3 "$EVPY" check "$EV"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S01"*"EXPIRED"* ]]
  [[ "$output" == *"answer"* ]]
}

@test "check: an answer edited after recording is reported" {
  # Red while only existence is checked: the recorded hash is what ties the
  # answer to the run that produced it.
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  P="$(cat "$EV/S01-prompt.txt")"
  python3 - "$TEST_TMP/t.jsonl" "$P" <<'MKJSON'
import json, sys
rows = [{"type":"user","message":{"role":"user","content":sys.argv[2]}},
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"ANSWER BODY"}]}}]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows) + "\n")
MKJSON
  python3 "$EVPY" record "$EV" --scenario S01 --arm baseline --transcript "$TEST_TMP/t.jsonl"
  printf 'EDITED BY HAND\n' > "$EV/answers/S01-baseline.md"
  run python3 "$EVPY" check "$EV"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S01"*"EXPIRED"* ]]
}

@test "record: a final message that still holds a tool call is incomplete" {
  # Red while completion means "has any text": a message can carry a preamble
  # and a tool call together, which is a run still in flight.
  python3 "$EVPY" init "$EV" --round 4 --model claude-opus-5 --tests skills/design-review/tests
  P="$(cat "$EV/S01-prompt.txt")"
  python3 - "$TEST_TMP/t.jsonl" "$P" <<'MKJSON'
import json, sys
rows = [{"type":"user","message":{"role":"user","content":sys.argv[2]}},
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[
            {"type":"text","text":"Let me read the skill first."},
            {"type":"tool_use","name":"Read","input":{}}]}}]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows) + "\n")
MKJSON
  run python3 "$EVPY" record "$EV" --scenario S01 --arm with-skill --transcript "$TEST_TMP/t.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"incomplete"* ]]
}

@test "record: replicates of one arm are stored side by side" {
  # A single run per arm cannot separate "the rule is needed" from "that run
  # drew badly" — two scenarios flipped on identical inputs before this existed.
  python3 "$EVPY" init "$EV" --round 6 --model claude-opus-5 --tests skills/design-review/tests --replicates 3
  P="$(cat "$EV/S01-prompt.txt")"
  for i in 1 2 3; do
    python3 - "$TEST_TMP/t$i.jsonl" "$P" "$i" <<'MKJSON'
import json, sys
rows = [{"type":"user","message":{"role":"user","content":sys.argv[2]}},
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"ANSWER " + sys.argv[3]}]}}]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows) + "\n")
MKJSON
    run python3 "$EVPY" record "$EV" --scenario S01 --arm baseline --replicate "$i" \
        --transcript "$TEST_TMP/t$i.jsonl"
    [ "$status" -eq 0 ]
  done
  grep -q 'ANSWER 1' "$EV/answers/S01-baseline-1.md"
  grep -q 'ANSWER 3' "$EV/answers/S01-baseline-3.md"
}

@test "check: a batch missing a replicate is not complete" {
  python3 "$EVPY" init "$EV" --round 6 --model test --replicates 3
  python3 - "$EV/manifest.json" <<'MKJSON'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);m=json.loads(p.read_text())
for s in m['scenarios'].values():
    for arm in ('baseline','with-skill'):
        for i in (1,2):
            name=f"answers/{arm}-{i}.md";(p.parent/name).write_text('answer')
            s['arms'][f'{arm}#{i}']={'answer':name}
p.write_text(json.dumps(m))
MKJSON
  run python3 "$EVPY" check "$EV" --require-complete
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing baseline#3, with-skill#3"* ]]
  [[ "$output" != *"missing baseline,"* ]]
  [[ "$output" != *"baseline#1"* ]]
  python3 - "$EV/manifest.json" <<'MKJSON'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);m=json.loads(p.read_text())
for s in m['scenarios'].values():
    for arm in ('baseline','with-skill'):
        name=f"answers/{arm}-3.md";(p.parent/name).write_text('answer')
        s['arms'][f'{arm}#3']={'answer':name}
p.write_text(json.dumps(m))
MKJSON
  run python3 "$EVPY" check "$EV" --require-complete
  [ "$status" -eq 0 ]
}

@test "record: a replicate outside the declared count is refused" {
  python3 "$EVPY" init "$EV" --round 6 --model claude-opus-5 --tests skills/design-review/tests --replicates 3
  P="$(cat "$EV/S01-prompt.txt")"
  python3 - "$TEST_TMP/t.jsonl" "$P" <<'MKJSON'
import json, sys
rows = [{"type":"user","message":{"role":"user","content":sys.argv[2]}},
        {"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"ANSWER"}]}}]
open(sys.argv[1],"w").write("\n".join(json.dumps(r) for r in rows) + "\n")
MKJSON
  run python3 "$EVPY" record "$EV" --scenario S01 --arm baseline --replicate 4 --transcript "$TEST_TMP/t.jsonl"
  [ "$status" -eq 1 ]
}

@test "transcript: truncation missing terminal reason and malformed tails cannot finish" {
  run python3 - "$EVPY" "$TEST_TMP" <<'PY'
import importlib.util, json, pathlib, sys
s=importlib.util.spec_from_file_location('e',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
p=pathlib.Path(sys.argv[2])/'t.jsonl'
for reason,tail in [('max_tokens',''), (None,''), ('end_turn','\n{broken')]:
    p.write_text(json.dumps({'message':{'role':'assistant','content':'answer','stop_reason':reason}})+tail)
    assert m.read_transcript(p)[2] is False, (reason,tail)
p.write_text(json.dumps({'message':{'role':'assistant','content':'answer','stop_reason':'end_turn'}}))
assert m.read_transcript(p)[2] is True
PY
  [ "$status" -eq 0 ]
}

@test "init: zero and negative replicate counts are refused before creating a batch" {
  for count in 0 -1; do
    run python3 "$EVPY" init "$EV" --round 6 --model test --replicates "$count"
    [ "$status" -ne 0 ]
    [ ! -e "$EV/manifest.json" ]
  done
}

@test "check: malformed manifest replicate counts cannot bypass completeness" {
  python3 "$EVPY" init "$EV" --round 6 --model test
  for count in 0 -1; do
    python3 - "$EV/manifest.json" "$count" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);m=json.loads(p.read_text());m['replicates']=int(sys.argv[2]);p.write_text(json.dumps(m))
PY
    run python3 "$EVPY" check "$EV" --require-complete
    [ "$status" -eq 1 ]
    [[ "$output" == *"positive"* ]]
  done
}

@test "adversarial: transcript preserves all final text blocks" {
  run python3 - "$EVPY" "$TEST_TMP/transcript" <<'PYCODE'
import importlib.util, json, pathlib, sys
spec=importlib.util.spec_from_file_location('evidence',sys.argv[1]);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
p=pathlib.Path(sys.argv[2]);p.write_text(json.dumps({'message':{'role':'assistant','stop_reason':'end_turn','content':[{'type':'text','text':'FIRST'},{'type':'text','text':'SECOND'}]}})+'\n')
body, tools, complete=m.read_transcript(p)
assert complete and body == 'FIRST\nSECOND', (body,complete)
PYCODE
  [ "$status" -eq 0 ]
}

@test "adversarial: an unanswered later user turn invalidates completion" {
  run python3 - "$EVPY" "$TEST_TMP/transcript" <<'PYCODE'
import importlib.util, json, pathlib, sys
spec=importlib.util.spec_from_file_location('evidence',sys.argv[1]);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
p=pathlib.Path(sys.argv[2]);p.write_text('\n'.join(json.dumps({'message':v}) for v in [{'role':'assistant','stop_reason':'end_turn','content':'finished earlier'}, {'role':'user','content':'continue'}])+'\n')
assert m.read_transcript(p)[2] is False
PYCODE
  [ "$status" -eq 0 ]
}
