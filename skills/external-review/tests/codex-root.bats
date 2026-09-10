#!/usr/bin/env bats
#
# The pruned worktree Codex is rooted at. Every test names the condition that
# turns it red.
#
# The canary is EXCLUDED-CONTENT: material from a skill that is out of scope
# for the review. Codex reads the tree it is rooted at, so if that string is
# reachable from the worktree, the exclusion is prose again and the reviewer
# will report on code nobody is about to touch.

setup() {
  export TEST_TMP="$(mktemp -d)"
  export REPO="$TEST_TMP/repo"
  export ROOT="$TEST_TMP/root"
  mkdir -p "$REPO"
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export CODEX_ROOT="$(dirname "$here")/codex-root.sh"

  cd "$REPO"
  git init -q -b main .
  git config user.email t@example.invalid
  git config user.name  Test
  mkdir -p skills/held skills/kept
  printf 'EXCLUDED-CONTENT\n' > skills/held/SKILL.md
  printf 'IN-SCOPE-CONTENT\n' > skills/kept/SKILL.md
  printf 'readme\n' > README.md
  git add -A && git commit -qm base
}

teardown() {
  cd "$REPO" 2>/dev/null && git worktree remove --force "$ROOT" 2>/dev/null
  cd /
  [ -n "${TEST_TMP:-}" ] && chmod -R u+w "$TEST_TMP" 2>/dev/null
  rm -rf "$TEST_TMP"
}

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
  [[ "$output" == *"DIRTY"* ]]
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
  [[ "$output" == *"ENCLOSING REPOSITORY"* ]]
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
  python3 - "$CODEX_ROOT" "$TEST_TMP/invoke.sh" "$TEST_TMP" <<'PY'
import pathlib,re,sys
text=pathlib.Path(sys.argv[1]).with_name('SKILL.md').read_text()
block=next(b for b in re.findall(r'```bash\n(.*?)```',text,re.S) if 'for m in $(codex_ladder)' in b and 'codex exec' in b)
prelude='codex_ladder() { echo fixture-model; }\ncodex() { printf "%s\\n" "$@" > "$ARGS"; while [ "$1" != -o ]; do shift; done; echo "No findings." > "$2"; }\n'
pathlib.Path(sys.argv[2]).write_text(prelude+block.replace('<scratchpad>',sys.argv[3]).replace('<repo-root>','SOURCE-REPO'))
PY
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
