#!/usr/bin/env bats
#
# The pruned worktree Codex is rooted at. Every test names the condition that
# turns it red.
#
# The canary is EXCLUDED-CONTENT: material from a skill that is out of scope
# for the review. Codex reads the tree it is rooted at, so if that string is
# reachable from the worktree, the exclusion is prose again and the reviewer
# will report on code nobody is about to touch.

load helpers/setup

setup() {
  setup_capture_env
  export ROOT="$TEST_TMP/root"
  export CODEX_ROOT="$BATS_TEST_DIRNAME/../codex-root.sh"
  mkdir -p skills/held skills/kept
  printf 'EXCLUDED-CONTENT\n' > skills/held/SKILL.md
  printf 'IN-SCOPE-CONTENT\n' > skills/kept/SKILL.md
  printf 'readme\n' > README.md
  git add -A && git commit -qm base
}

# Build a runnable copy of the documented Codex invocation loop, with the
# ladder stubbed to emit $1. Both invocation tests need this; the copies
# differed only in the stub's output.
write_invoke_script() {   # $1 = ladder output, $2 = destination, $3 = optional codex() body
  python3 - "$CODEX_ROOT" "$2" "$TEST_TMP" "$1" "${3:-}" <<'INVOKE_PY'
import pathlib,re,sys
text=pathlib.Path(sys.argv[1]).with_name('SKILL.md').read_text()
block=next(b for b in re.findall(r'```bash\n(.*?)```',text,re.S)
           if 'for m in ${CODEX_RUNGS' in b and 'codex exec' in b)
body=sys.argv[5] or 'printf "%s\\n" "$@" > "$ARGS"; while [ "$1" != -o ]; do shift; done; echo "No findings." > "$2";'
prelude=('CODEX_RUNGS="' + sys.argv[4] + '"\n'
         'codex() { ' + body + ' }\n')
pathlib.Path(sys.argv[2]).write_text(prelude+block.replace('<scratchpad>',sys.argv[3]).replace('<repo-root>','SOURCE-REPO'))
INVOKE_PY
}


teardown() { teardown_capture_env; }

@test "the pruned root holds the in-scope files" {
  run bash "$CODEX_ROOT" "$ROOT" --exclude skills/held
  [ "$status" -eq 0 ]
  grep -q 'IN-SCOPE-CONTENT' "$ROOT/skills/kept/SKILL.md"
  grep -q 'readme' "$ROOT/README.md"
}

@test "an excluded directory is not reachable from the pruned root" {
  # THE test. Red while the exclusion is only a sentence in the prompt: Codex
  # is rooted here and reads whatever is on disk.
  run bash "$CODEX_ROOT" "$ROOT" --exclude skills/held
  [ "$status" -eq 0 ]
  [ ! -e "$ROOT/skills/held" ]
  run grep -rq 'EXCLUDED-CONTENT' "$ROOT"
  [ "$status" -ne 0 ]
}

@test "the excluded directory is untouched in the real repository" {
  # Red if the prune runs against the working tree instead of the worktree:
  # a review would delete the skill it was told not to look at.
  run bash "$CODEX_ROOT" "$ROOT" --exclude skills/held
  [ "$status" -eq 0 ]
  grep -q 'EXCLUDED-CONTENT' "$REPO/skills/held/SKILL.md"
  [ -z "$(git -C "$REPO" status --porcelain)" ]
}

@test "several exclusions are all pruned" {
  printf 'EXCLUDED-CONTENT\n' > skills/kept/other.md
  git add -A && git commit -qm more
  run bash "$CODEX_ROOT" "$ROOT" --exclude skills/held --exclude skills/kept/other.md
  [ "$status" -eq 0 ]
  [ ! -e "$ROOT/skills/held" ]
  [ ! -e "$ROOT/skills/kept/other.md" ]
  grep -q 'IN-SCOPE-CONTENT' "$ROOT/skills/kept/SKILL.md"
}

@test "an exclusion that matches nothing is refused" {
  # Red while a typo'd path is accepted: the caller believes an area was pruned
  # and the reviewer reads all of it.
  run bash "$CODEX_ROOT" "$ROOT" --exclude skills/no-such-skill
  [ "$status" -eq 1 ]
  [[ "$output" == *"no-such-skill"* ]]
}

@test "a dirty tree is refused rather than reviewed as HEAD" {
  # The worktree is built from HEAD, so uncommitted work is invisible to the
  # reviewer. Say so instead of silently reviewing something else.
  printf 'UNCOMMITTED\n' >> README.md
  run bash "$CODEX_ROOT" "$ROOT" --exclude skills/held
  [ "$status" -eq 1 ]
  [[ "$output" == *"DIRTY"* ]] || false
  grep -q 'UNCOMMITTED' "$REPO/README.md"
}

@test "an existing target directory is refused" {
  mkdir -p "$ROOT"
  run bash "$CODEX_ROOT" "$ROOT" --exclude skills/held
  [ "$status" -eq 1 ]
}

@test "an excluded path is not reachable through git either" {
  # THE claim that was false. A linked worktree shares the object database, so
  # `git show HEAD:<excluded>` returned the file whose files had been deleted.
  # Filesystem absence is not unreadability while the objects are still there.
  run bash "$CODEX_ROOT" "$ROOT" --exclude skills/held
  [ "$status" -eq 0 ]
  run git -C "$ROOT" show "HEAD:skills/held/SKILL.md"
  [ "$status" -ne 0 ]
  run bash -c "git -C '$ROOT' log --all -p 2>/dev/null | grep -c EXCLUDED-CONTENT || true"
  [[ "$output" == "0" ]]
}

@test "the in-scope history is still available to the reviewer" {
  # The exclusion must not cost the reviewer everything else. Red if the fix
  # throws away the whole repository rather than the excluded paths.
  run bash "$CODEX_ROOT" "$ROOT" --exclude skills/held
  [ "$status" -eq 0 ]
  grep -q 'IN-SCOPE-CONTENT' "$ROOT/skills/kept/SKILL.md"
}

@test "export inside the source repository is refused before exposing parent history" {
  run bash "$CODEX_ROOT" "$REPO/export" --exclude skills/held
  [ "$status" -eq 1 ]
  [[ "$output" == *"ENCLOSING REPOSITORY"* ]] || false
  [ ! -e "$REPO/export/README.md" ]
}

@test "export through a symlink into another repository is refused" {
  mkdir "$TEST_TMP/other"
  git -C "$TEST_TMP/other" init -q
  ln -s "$TEST_TMP/other" "$TEST_TMP/alias"
  run bash "$CODEX_ROOT" "$TEST_TMP/alias/nested/export" --exclude skills/held
  [ "$status" -eq 1 ]
  [[ "$output" == *"ENCLOSING REPOSITORY"* ]]
}

@test "adversarial: export from a subdirectory still contains the whole root" {
  cd skills/kept
  run bash "$CODEX_ROOT" "$ROOT"
  [ "$status" -eq 0 ]
  cmp "$ROOT/README.md" "$REPO/README.md"
}

@test "adversarial: archive attributes cannot silently omit or substitute tracked bytes" {
  printf 'README.md export-ignore\nskills/kept/SKILL.md export-subst\n' > .gitattributes
  printf '$Format:%%H$\n' > skills/kept/SKILL.md
  git add -A && git commit -qm attributes
  run bash "$CODEX_ROOT" "$ROOT"
  [ "$status" -eq 0 ]
  cmp "$ROOT/README.md" "$REPO/README.md"
  cmp "$ROOT/skills/kept/SKILL.md" "$REPO/skills/kept/SKILL.md"
}

@test "adversarial: surviving export links cannot reach an excluded source" {
  ln -s "$REPO/skills/held" alias
  git add alias && git commit -qm alias
  run bash "$CODEX_ROOT" "$ROOT" --exclude skills/held
  [ "$status" -eq 0 ]
  [ ! -L "$ROOT/alias" ]
  [ ! -e "$ROOT/alias/SKILL.md" ]
  grep -q IN-SCOPE-CONTENT "$ROOT/skills/kept/SKILL.md"
}

@test "adversarial: failed status refuses export before creating a destination" {
  local real_git; real_git="$(command -v git)"
  mkdir "$TEST_TMP/bin"
  printf '#!/bin/bash\n[ "$1" != status ] || exit 128\nexec "%s" "$@"\n' "$real_git" > "$TEST_TMP/bin/git"
  chmod +x "$TEST_TMP/bin/git"
  PATH="$TEST_TMP/bin:$PATH" run bash "$CODEX_ROOT" "$ROOT"
  [ "$status" -eq 1 ]
  [ ! -e "$ROOT" ]
}

@test "adversarial: documented Codex loop uses the prepared root and export flag" {
  write_invoke_script 'fixture-model' "$TEST_TMP/invoke.sh"
  ARGS="$TEST_TMP/args" run bash "$TEST_TMP/invoke.sh"
  [ "$status" -eq 0 ]
  python3 - "$TEST_TMP/args" "$ROOT" <<'PY'
import pathlib,sys
args=pathlib.Path(sys.argv[1]).read_text().splitlines()
assert args[args.index('-C')+1] == sys.argv[2], args
assert '--skip-git-repo-check' in args, args
PY
}

@test "recheck: explicitly excluding an omitted link still produces a usable root" {
  ln -s "$REPO/skills/held" alias
  git add alias && git commit -qm link
  run bash "$CODEX_ROOT" "$ROOT" --exclude alias --exclude skills/held
  [ "$status" -eq 0 ]
  [ ! -L "$ROOT/alias" ]
  [ ! -e "$ROOT/skills/held" ]
  grep -q IN-SCOPE-CONTENT "$ROOT/skills/kept/SKILL.md"
}

@test "QC T2-6: command substitution leaves refusal visible on stderr and root empty" {
  echo dirty >> README.md
  run bash -c 'root=$(bash "$CODEX_ROOT" "$ROOT" 2> "$TEST_TMP/error"); rc=$?; [ "$rc" = 1 ] && [ -z "$root" ] && grep -q "TREE IS DIRTY" "$TEST_TMP/error"'
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# The Codex ladder emits (slug, effort) rungs.
#
# These run the documented codex_ladder() function itself, with HOME pointed at
# a fixture cache, so the wiring from SKILL.md to codex-ladder.py is covered as
# well as the ranking that tests/codex-ladder.bats pins.
# ---------------------------------------------------------------------------

ladder_fn() {
  python3 - "$(dirname "$CAPTURE")/SKILL.md" <<'PY'
import pathlib,re,sys
blocks=re.findall(r'```bash\n(.*?)```',pathlib.Path(sys.argv[1]).read_text(),re.S)
print(next(b for b in blocks if 'codex_ladder()' in b))
PY
}

# Fails if the documented codex_ladder ranks by the cache's priority, OpenAI's
# default pick, instead of calling codex-ladder.py, or if a rung omits its effort.
@test "the documented ladder ranks family over the cache's priority" {
  mkdir -p "$TEST_TMP/home/.codex"
  cat > "$TEST_TMP/home/.codex/models_cache.json" <<'JSON'
{"models":[
 {"slug":"gpt-6-sol","visibility":"list","priority":1,"default_reasoning_level":"low",
  "supported_reasoning_levels":[{"effort":"low"},{"effort":"high"},{"effort":"max"}]},
 {"slug":"gpt-6-astra","visibility":"list","priority":2,"default_reasoning_level":"low",
  "supported_reasoning_levels":[{"effort":"low"},{"effort":"high"},{"effort":"max"}]}]}
JSON
  CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$CAPTURE")/../.." && pwd)" run bash -c "$(ladder_fn); HOME='$TEST_TMP/home' codex_ladder"
  [ "$status" -eq 0 ] || false
  [ "$output" = "gpt-6-astra:high gpt-6-sol:high" ]
}

# Fails if `ultra` is offered as a rung. It delegates tasks automatically, so
# the diff may not come from the model recorded against it.
@test "ultra is never selected as a rung" {
  mkdir -p "$TEST_TMP/home/.codex"
  cat > "$TEST_TMP/home/.codex/models_cache.json" <<'JSON'
{"models":[{"slug":"gpt-6-astra","visibility":"list","priority":1,"default_reasoning_level":"low",
 "supported_reasoning_levels":[{"effort":"low"},{"effort":"ultra"}]}]}
JSON
  CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "$CAPTURE")/../.." && pwd)" run bash -c "$(ladder_fn); HOME='$TEST_TMP/home' codex_ladder"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

# Fails if the documented invocation loop passes a slug:effort rung straight to
# `-m`. The loop above this one stubs the ladder with a bare `fixture-model`,
# so the pair-splitting branch never runs there and the rung format added for
# the ladder had no test reaching it.
@test "adversarial: the documented Codex loop splits a slug:effort rung" {
  write_invoke_script 'fixture-model:medium' "$TEST_TMP/invoke.sh"
  ARGS="$TEST_TMP/args2" run bash "$TEST_TMP/invoke.sh"
  [ "$status" -eq 0 ]
  python3 - "$TEST_TMP/args2" <<'PY'
import pathlib,sys
args=pathlib.Path(sys.argv[1]).read_text().splitlines()
# -m carries the slug alone; the pair is not a model id
assert args[args.index('-m')+1] == 'fixture-model', args
assert 'fixture-model:medium' not in args, args
# and the rung's effort reaches the invocation, not a hardcoded high
assert 'model_reasoning_effort=medium' in args, args
assert 'model_reasoning_effort=high' not in args, args
PY
}

# Fails if the loop reads its availability verdict from the whole log. Codex
# writes the prompt and its transcript to stderr, so a run killed mid-review
# whose material quotes "not supported" or "entitle" was taken for an
# unavailable model and the next rung started (pass 1 of 2.1.0's review).
@test "a failed run whose transcript quotes an availability phrase does not downshift" {
  write_invoke_script 'first:high second:high' "$TEST_TMP/invoke.sh" \
    'echo "${8}" >> "$TEST_TMP/models"; echo "user"; echo "quoted: model is not supported, entitlement error" >&2; return 143;'
  run bash "$TEST_TMP/invoke.sh"
  [ "$(cat "$TEST_TMP/models")" = "first" ] || false
  [[ "$output" == *"not availability"* ]]
}

# Fails if a real availability error, an ERROR: line, stops downshifting.
@test "an ERROR line naming an unsupported model moves to the next rung" {
  write_invoke_script 'first:high second:high' "$TEST_TMP/invoke.sh" \
    'echo "${8}" >> "$TEST_TMP/models"; if [ "${8}" = first ]; then echo "ERROR: The '"'"'first'"'"' model is not supported when using Codex with a ChatGPT account." >&2; return 1; fi; while [ "$1" != -o ]; do shift; done; echo "No findings." > "$2";'
  run bash "$TEST_TMP/invoke.sh"
  [ "$(tr '\n' ' ' < "$TEST_TMP/models")" = "first second " ]
}

# Fails if a quoted ERROR: line in the material under review, early in the
# transcript, still drives a downshift when the run later dies.
@test "an ERROR line quoted mid-transcript does not downshift" {
  write_invoke_script 'first:high second:high' "$TEST_TMP/invoke.sh" \
    'echo "${8}" >> "$TEST_TMP/models"; { echo "user"; echo "ERROR: The x model is not supported"; for i in 1 2 3 4 5 6 7 8; do echo "transcript line $i"; done; } >&2; return 143;'
  run bash "$TEST_TMP/invoke.sh"
  [ "$(cat "$TEST_TMP/models")" = "first" ]
}

# Fails if the loop's bare command aborts under errexit before it can classify
# an availability failure and move to the next rung.
@test "the documented Codex loop still downshifts under errexit" {
  write_invoke_script 'first:high second:high' "$TEST_TMP/invoke.sh" \
    'echo "${8}" >> "$TEST_TMP/models"; if [ "${8}" = first ]; then echo "ERROR: The first model is not supported when using Codex with a ChatGPT account." >&2; return 1; fi; while [ "$1" != -o ]; do shift; done; echo "No findings." > "$2";'
  run bash -e "$TEST_TMP/invoke.sh"
  [ "$(tr '\n' ' ' < "$TEST_TMP/models")" = "first second " ]
}

# Fails if a quoted ERROR: line about another model, at the very end of a
# failed run's log, moves the loop to the next rung.
@test "a quoted ERROR line about another model at the end of the log does not downshift" {
  write_invoke_script 'first:high second:high' "$TEST_TMP/invoke.sh" \
    'echo "${8}" >> "$TEST_TMP/models"; { echo "transcript"; echo "ERROR: The gpt-x model is not supported"; } >&2; return 1;'
  run bash "$TEST_TMP/invoke.sh"
  [ "$(cat "$TEST_TMP/models")" = "first" ]
}

# Fails if a real refusal of this rung's own model, followed by more log lines,
# is missed because only the last lines are read.
@test "a refusal naming this rung's model downshifts even with lines after it" {
  write_invoke_script 'first:high second:high' "$TEST_TMP/invoke.sh" \
    'echo "${8}" >> "$TEST_TMP/models"; if [ "${8}" = first ]; then { echo "ERROR: The '"'"'first'"'"' model is not supported when using Codex with a ChatGPT account."; for i in 1 2 3 4 5 6; do echo "shutdown $i"; done; } >&2; return 1; fi; while [ "$1" != -o ]; do shift; done; echo "No findings." > "$2";'
  run bash "$TEST_TMP/invoke.sh"
  [ "$(tr '\n' ' ' < "$TEST_TMP/models")" = "first second " ]
}
