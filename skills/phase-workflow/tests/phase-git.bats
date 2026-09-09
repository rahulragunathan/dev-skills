#!/usr/bin/env bats
#
# The destructive git operations in this workflow. Every test names the
# condition that turns it red.
#
# The canary is UNCOMMITTED: work that exists only in the worktree. If it ever
# disappears, a guard let a destructive operation run when it should have
# refused.

setup() {
  export TEST_TMP="$(mktemp -d)"
  export REPO="$TEST_TMP/repo"
  export FORK="$TEST_TMP/fork.git"
  mkdir -p "$REPO"
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export RESTORE="$(dirname "$here")/mutation-restore.sh"
  export PUBLISH="$(dirname "$here")/publish-release.sh"

  git init -q --bare "$FORK"
  cd "$REPO"
  git init -q -b main .
  git config user.email t@example.invalid
  git config user.name  Test
  printf 'def add(a, b):\n    return a + b\n' > calc.py
  printf 'ok\n' > README.md
  git add -A && git commit -qm base
  export TASK_SHA="$(git rev-parse HEAD)"
  git remote add origin "$FORK"
  export FETCH_URL="$(git remote get-url origin)"
  export PUSH_URL="$(git remote get-url --push origin)"
}

teardown() { cd /; [ -n "${TEST_TMP:-}" ] && chmod -R u+w "$TEST_TMP" 2>/dev/null; rm -rf "$TEST_TMP"; }

# --- mutation restore ------------------------------------------------------

@test "restore: a failing test leaves the file byte-identical afterwards" {
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'exit 1'
  [ "$status" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
  grep -q 'a + b' calc.py
}

@test "restore: refuses on a dirty tree rather than discarding the work" {
  # THE guard. Red if the audit runs on uncommitted work: the restore then
  # reverts the file to the task commit and the work is gone.
  printf 'UNCOMMITTED\n' >> README.md
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'exit 1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"TREE IS DIRTY"* ]]
  grep -q 'UNCOMMITTED' README.md
}

@test "restore: a test that passes under mutation is reported, not certified" {
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'exit 0'
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not discriminate"* ]]
  [ -z "$(git status --porcelain)" ]
}

@test "restore: a collection error is not accepted as an assertion red" {
  # pytest exits 2 on collection errors and 5 on no-tests. Neither is the red
  # the audit is looking for.
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'exit 2'
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT AN ASSERTION RED"* ]]
  [ -z "$(git status --porcelain)" ]
}

@test "restore: a mutation that matches nothing is refused" {
  # Red if a no-op sed counts as a mutation: the test then passes because
  # nothing was broken, and the audit records a false certification.
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/NOTHING_MATCHES_THIS/x/' bash -c 'exit 1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"CHANGED NOTHING"* ]]
}

@test "restore: a symlinked target is refused" {
  ln -s "$TEST_TMP/outside.py" link.py
  printf 'x\n' > "$TEST_TMP/outside.py"
  git add -A && git commit -qm link
  run bash "$RESTORE" "$(git rev-parse HEAD)" link.py 's/x/y/' bash -c 'exit 1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"SYMLINK"* ]]
}

@test "restore: the file is put back even when the test command is killed" {
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'kill -TERM $$'
  [ -z "$(git status --porcelain)" ]
  grep -q 'a + b' calc.py
}

# --- release publication ---------------------------------------------------

@test "publish: tags the approved commit and deletes the merged branch" {
  git switch -qc feature && git commit -q --allow-empty -m work
  local sha; sha="$(git rev-parse HEAD)"
  git switch -q main && git merge -q --no-ff feature -m merge

  run bash "$PUBLISH" "$sha" v1.0.0 feature "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 0 ]
  [ "$(git rev-parse v1.0.0^{commit})" = "$sha" ]
  ! git rev-parse --verify --quiet refs/heads/feature
}

@test "publish: refuses when the push URL was repointed after the gate" {
  # THE finding from review pass 8. Red if only the fetch URL is compared: a
  # remote can fetch from the approved repository and push to a fork, and the
  # tag and deletion then land in the fork.
  git switch -qc feature && git commit -q --allow-empty -m work
  local sha; sha="$(git rev-parse HEAD)"
  git switch -q main && git merge -q --no-ff feature -m merge
  git remote set-url --push origin "$TEST_TMP/somewhere-else.git"

  run bash "$PUBLISH" "$sha" v1.0.0 feature "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PUSH URL CHANGED"* ]]
  ! git rev-parse --verify --quiet refs/tags/v1.0.0
  git rev-parse --verify --quiet refs/heads/feature
}

@test "publish: refuses when origin has more than one push destination" {
  git switch -qc feature && git commit -q --allow-empty -m work
  local sha; sha="$(git rev-parse HEAD)"
  git switch -q main && git merge -q --no-ff feature -m merge
  git remote set-url --add --push origin "$TEST_TMP/second.git"
  git remote set-url --add --push origin "$TEST_TMP/third.git"

  run bash "$PUBLISH" "$sha" v1.0.0 feature "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ]
  ! git rev-parse --verify --quiet refs/tags/v1.0.0
}

@test "publish: refuses to move a tag that already points elsewhere" {
  git switch -qc feature && git commit -q --allow-empty -m work
  local sha; sha="$(git rev-parse HEAD)"
  git switch -q main && git merge -q --no-ff feature -m merge
  git tag v1.0.0 "$TASK_SHA"

  run bash "$PUBLISH" "$sha" v1.0.0 feature "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ]
  [ "$(git rev-parse v1.0.0^{commit})" = "$TASK_SHA" ]
  git rev-parse --verify --quiet refs/heads/feature
}

@test "publish: retains a branch that advanced past the approved SHA" {
  git switch -qc feature && git commit -q --allow-empty -m work
  local sha; sha="$(git rev-parse HEAD)"
  git switch -q main && git merge -q --no-ff feature -m merge
  git switch -q feature && git commit -q --allow-empty -m "after approval"
  git switch -q main

  run bash "$PUBLISH" "$sha" v1.0.0 feature "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ADVANCED"* ]]
  git rev-parse --verify --quiet refs/heads/feature
}

@test "publish: refuses to delete the default branch" {
  run bash "$PUBLISH" "$TASK_SHA" v1.0.0 main "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ]
  git rev-parse --verify --quiet refs/heads/main
}

@test "publish: retains a branch holding unmerged work" {
  git switch -qc feature && git commit -q --allow-empty -m unmerged
  local sha; sha="$(git rev-parse HEAD)"
  git switch -q main

  run bash "$PUBLISH" "$sha" v1.0.0 feature "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ]
  git rev-parse --verify --quiet refs/heads/feature
}

@test "origin check: accepts recorded destinations without changing refs" {
  local before; before="$(git show-ref)"
  run bash "$PUBLISH" --check-origin "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 0 ]
  [ "$(git show-ref)" = "$before" ]
}

@test "origin check: rejects a changed fetch URL" {
  git remote set-url origin "$TEST_TMP/other.git"
  run bash "$PUBLISH" --check-origin "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FETCH URL CHANGED"* ]]
}

@test "origin check: rejects a changed push URL" {
  git remote set-url --push origin "$TEST_TMP/other.git"
  run bash "$PUBLISH" --check-origin "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"PUSH URL CHANGED"* ]]
}

@test "origin check: rejects a second push URL even when the first matches" {
  git remote set-url --add --push origin "$PUSH_URL"
  git remote set-url --add --push origin "$TEST_TMP/second.git"
  run bash "$PUBLISH" --check-origin "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MULTIPLE PUSH URLS"* ]]
}

@test "origin check: the preflight records the push URL the guard compares" {
  # Red when the documented preflight and the guard drift apart. The guard
  # compares `git remote get-url --push`; a preflight that records
  # `--push --all` hands it a different shape, and only the merge gate finds
  # out. Brittle to rewording on purpose: the two must be edited together.
  local skill; skill="$(dirname "$PUBLISH")/SKILL.md"
  grep -q 'ORIGIN_PUSH_URL="\$(git remote get-url --push origin)"' "$skill"
}
