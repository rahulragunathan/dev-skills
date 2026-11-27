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

# Extract one executable fence from SKILL.md by its `# fence: <name>` marker.
extract_fence() {   # $1 = marker name, $2 = destination, $3 = SKILL.md path
  python3 "$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/tests/fence.py" "$3" "$1" > "$2"
}


teardown() { cd /; [ -n "${TEST_TMP:-}" ] && chmod -R u+w "$TEST_TMP" 2>/dev/null; rm -rf "$TEST_TMP"; }

# --- mutation restore ------------------------------------------------------

@test "restore: a failing test leaves the file byte-identical afterwards" {
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'grep -q "a + b" calc.py'
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
  [[ "$output" == *"TREE IS DIRTY"* ]] || false
  grep -q 'UNCOMMITTED' README.md
}

@test "restore: a test that passes under mutation is reported, not certified" {
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'exit 0'
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not discriminate"* ]] || false
  [ -z "$(git status --porcelain)" ]
}

@test "restore: a collection error is not accepted as an assertion red" {
  # pytest exits 2 on collection errors and 5 on no-tests. Neither is the red
  # the audit is looking for.
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'exit 2'
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT AN ASSERTION RED"* ]] || false
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
  [[ "$output" == *"PUSH URL CHANGED"* ]] || false
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
  [[ "$output" == *"ADVANCED"* ]] || false
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

# Fails if a remote URL that carries credentials passes the check, which would
# let phase start copy the token into the committed docs/PHASE_RECORD.md.
@test "origin check: refuses a URL carrying credentials, without printing it" {
  clean="https://example.invalid/r.git"
  # Forms refused before their credentials are read are in the unsupported-form tests below.
  for url in "https://someone:notasecret@example.invalid/r.git" "https://notasecret@example.invalid/r.git" \
             "https://example.invalid/r.git?token=notasecret" "ssh://me@mail.example:notasecret@example.invalid/r.git"; do
    # A clean fetch URL with a bad push URL, then the reverse: each side is checked.
    for pair in "$clean $url" "$url $clean"; do
      set -- $pair
      git remote set-url origin "$1"
      git remote set-url --push origin "$2"
      run bash "$PUBLISH" --check-origin "$1" "$2"
      [ "$status" -eq 1 ] || false
      [[ "$output" == "CREDENTIALS IN ORIGIN URL"* ]] || false
      [[ "$output" != *notasecret* ]] || false
    done
  done
  git remote set-url origin "ssh://git@example.invalid/r.git"
  git remote set-url --push origin "ssh://git@example.invalid/r.git"
  run bash "$PUBLISH" --check-origin "ssh://git@example.invalid/r.git" "ssh://git@example.invalid/r.git"
  [ "$status" -eq 0 ]
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

@test "restore: a SHA that is not HEAD is refused before anything is mutated" {
  # THE data-loss case. The script accepted any commit containing the file,
  # mutated the current checkout, then restored from that older commit —
  # silently discarding every committed change made since it.
  printf 'def add(a, b):\n    return a + b\n\ndef sub(a, b):\n    return a - b\n' > calc.py
  git add -A && git commit -qm "later work"
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a * b/' bash -c 'exit 1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT HEAD"* ]] || false
  grep -q 'def sub' calc.py
}

@test "restore: a restore that silently does nothing is reported, not swallowed" {
  # Red while cleanup runs in a bare EXIT trap. A failing trap command cannot
  # replace the preceding exit status, so a botched restore reports success and
  # leaves mutated code in the tree. git is faked here so `restore` and
  # `checkout` return 0 without restoring, which is the shape that hides.
  mkdir -p "$TEST_TMP/bin"
  cat > "$TEST_TMP/bin/git" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in restore|checkout) exit 0 ;; esac
done
exec /usr/bin/git "$@"
EOF
  chmod +x "$TEST_TMP/bin/git"
  PATH="$TEST_TMP/bin:$PATH" run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'exit 1'
  [ "$status" -ne 0 ]
  [[ "$output" == *"RESTORE"* ]]
}

@test "restore: the happy path still leaves the file byte-identical" {
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'grep -q "a + b" calc.py'
  [ "$status" -eq 0 ]
  [ -z "$(git status --porcelain)" ]
  grep -q 'a + b' calc.py
}

@test "restore: a test still red on normal code refuses certification" {
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'exit 1'
  [ "$status" -eq 1 ]
  [[ "$output" == *"RESTORED TEST FAILED"* ]] || false
  [ -z "$(git status --porcelain)" ]
}

@test "restore: unrelated tracked index and worktree drift is retained and refused" {
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'echo DRIFT >> README.md; git add README.md; grep -q "a + b" calc.py'
  [ "$status" -eq 1 ]
  [[ "$output" == *"TRACKED TREE CHANGED"* ]] || false
  grep -q DRIFT README.md
  ! git diff --cached --quiet
}

@test "adversarial: failed status cannot discard uncommitted mutation target" {
  printf 'UNCOMMITTED\n' >> calc.py
  cp calc.py "$TEST_TMP/before"
  local real_git; real_git="$(command -v git)"
  mkdir "$TEST_TMP/bin"
  printf '#!/bin/bash\n[ "$1" != status ] || exit 128\nexec "%s" "$@"\n' "$real_git" > "$TEST_TMP/bin/git"
  chmod +x "$TEST_TMP/bin/git"
  PATH="$TEST_TMP/bin:$PATH" run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'grep -q "a + b" calc.py'
  [ "$status" -eq 1 ]
  cmp calc.py "$TEST_TMP/before"
}

@test "adversarial: documented cleanup returns failure when fetch fails" {
  extract_fence prune "$TEST_TMP/cleanup.sh" "$(dirname "$PUBLISH")/SKILL.md"
  mkdir "$TEST_TMP/bin"
  printf '#!/bin/sh\nexit 128\n' > "$TEST_TMP/bin/git"
  chmod +x "$TEST_TMP/bin/git"
  PATH="$TEST_TMP/bin:$PATH" run bash "$TEST_TMP/cleanup.sh"
  [ "$status" -ne 0 ]
  [[ "$output" != *'Nothing to clean up.'* ]]
}

prepare_documented_release() {
  export CLAUDE_PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  export APPROVED_SHA="$TASK_SHA" ORIGIN_URL="$FETCH_URL" ORIGIN_PUSH_URL="$PUSH_URL"
  export PR=1 REPO_ID=fixture/repo TAG=v2.0.0
  git commit -q --allow-empty -m merge
  export MERGE_SHA="$(git rev-parse HEAD)"
  git push -q origin main
  mkdir -p "$TEST_TMP/bin"
  cat > "$TEST_TMP/bin/gh" <<'SH'
#!/bin/bash
case "$*" in *mergeCommit*) echo "$MERGE_SHA" ;; *) echo "$APPROVED_SHA" ;; esac
SH
  chmod +x "$TEST_TMP/bin/gh"
  extract_fence release-tag "$TEST_TMP/release.sh" "$CLAUDE_PLUGIN_ROOT/skills/phase-workflow/SKILL.md"
}

@test "documented release: publishes the merge commit rather than the approved PR head" {
  prepare_documented_release
  [ "$MERGE_SHA" != "$APPROVED_SHA" ]
  PATH="$TEST_TMP/bin:$PATH" run bash "$TEST_TMP/release.sh"
  [ "$status" -eq 0 ]
  [ "$(git rev-parse "$TAG^{commit}")" = "$MERGE_SHA" ]
  [ "$(git --git-dir="$FORK" rev-parse "$TAG^{commit}")" = "$MERGE_SHA" ]
}

@test "documented release: a conflicting remote tag is retained" {
  prepare_documented_release
  git tag "$TAG" "$TASK_SHA"
  git push -q origin "refs/tags/$TAG"
  git tag -d "$TAG"
  PATH="$TEST_TMP/bin:$PATH" run bash "$TEST_TMP/release.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'REMOTE TAG CONFLICT'* ]] || false
  [ "$(git --git-dir="$FORK" rev-parse "$TAG^{commit}")" = "$TASK_SHA" ]
}

@test "documented release: failed tag push can resume without moving the retained local tag" {
  prepare_documented_release
  local real_git; real_git="$(command -v git)"
  printf '#!/bin/bash\n[ "$1" != push ] || exit 1\nexec "%s" "$@"\n' "$real_git" > "$TEST_TMP/bin/git"
  chmod +x "$TEST_TMP/bin/git"
  PATH="$TEST_TMP/bin:$PATH" run bash "$TEST_TMP/release.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'TAG PUSH FAILED'* ]] || false
  [ "$(git rev-parse "$TAG^{commit}")" = "$MERGE_SHA" ]
  rm "$TEST_TMP/bin/git"
  PATH="$TEST_TMP/bin:$PATH" run bash "$TEST_TMP/release.sh"
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$FORK" rev-parse "$TAG^{commit}")" = "$MERGE_SHA" ]
}

@test "QC T2-5: untracked test output is cleaned after both runs and permits the next audit" {
  for attempt in 1 2; do
    run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'echo generated > coverage.xml; grep -q "a + b" calc.py'
    [ "$status" -eq 0 ]
    [ -z "$(git status --porcelain -uall)" ]
  done
}

@test "QC T2-5: interruption during the restored run retains cleanup traps" {
  run bash "$RESTORE" "$TASK_SHA" calc.py 's/a + b/a - b/' bash -c 'if grep -q "a + b" calc.py; then echo generated > coverage.xml; echo broken >> calc.py; kill -TERM "$PPID"; exit 143; else exit 1; fi'
  [ "$status" -ne 0 ]
  [ -z "$(git status --porcelain -uall)" ]
}

# ---------------------------------------------------------------------------
# KI-46 — the phase cleanup must delete a branch whose commits are on the
# remote and retain everything else.
#
# `git branch -d` refuses a squash-merged branch however completely its work
# landed, and `git cherry` is wrong in both directions: a multi-commit squash
# reports `+` for every commit though the tree is identical, and a merge commit
# whose parents are upstream reports nothing though it carries unique work.
# ---------------------------------------------------------------------------

ki46_extract_cleanup() { extract_fence prune "$TEST_TMP/cleanup.sh" "$(dirname "$PUBLISH")/SKILL.md"; }

# Publish a branch, land it on main by $2, then orphan its upstream so the
# prune fence considers it at all.
ki46_orphan() {
  local branch="$1"
  git push -q -u origin "$branch"
  git checkout -q main
  git push -q origin main
  git push -q origin --delete "$branch"
  git fetch -q --prune origin
}

@test "KI-46: a multi-commit squash-merged branch at the approved tip is deleted" {
  ki46_extract_cleanup
  git checkout -q -b feature/multi
  echo one > f1; git add -A; git commit -qm one
  echo two > f2; git add -A; git commit -qm two
  git push -q -u origin feature/multi
  git checkout -q main
  git merge -q --squash feature/multi && git commit -qm "squashed feature/multi"
  export APPROVED_SHA="$(git rev-parse feature/multi)"
  ki46_orphan feature/multi
  # fixture properties: upstream gone, more than one commit, work already landed
  [ "$(git for-each-ref --format='%(upstream:track)' refs/heads/feature/multi)" = '[gone]' ] || false
  [ "$(git rev-list --count main..feature/multi)" -eq 2 ] || false
  [ -z "$(git diff feature/multi main)" ] || false
  run git branch -d feature/multi
  [ "$status" -ne 0 ]                      # -d alone cannot do this
  run bash "$TEST_TMP/cleanup.sh"
  [ "$status" -eq 0 ]
  run git rev-parse --verify feature/multi
  [ "$status" -ne 0 ]
}

@test "KI-46: a branch holding an unmerged commit is retained with the reason" {
  ki46_extract_cleanup
  git checkout -q -b feature/un
  echo unique > g1; git add -A; git commit -qm unique
  export APPROVED_SHA="$TASK_SHA"
  ki46_orphan feature/un
  [ -n "$(git diff feature/un main)" ] || false
  run bash "$TEST_TMP/cleanup.sh"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'RETAINED'
  run git rev-parse --verify feature/un
  [ "$status" -eq 0 ]
}

@test "KI-46: a branch whose unique work is a merge commit is retained" {
  ki46_extract_cleanup
  # Both sides land on main first, so every ordinary commit on feature/mc is
  # already upstream. What is NOT upstream is the merge commit's conflict
  # resolution -- and `git cherry` skips merge commits entirely, so it reports
  # nothing unique while the trees plainly differ.
  git checkout -q -b sideA; printf 'A\n' > c1; git add -A; git commit -qm A
  git checkout -q main; git merge -q --no-ff sideA -m "merge sideA"
  git checkout -q -b sideB main~1; printf 'B\n' > c1; git add -A; git commit -qm B
  git checkout -q main; git merge -q --no-ff sideB -m "merge sideB" || {
    printf 'main-resolution\n' > c1; git add -A; git commit -qm "merge sideB"; }
  git checkout -q -b feature/mc sideA
  git merge --no-ff sideB -m "merge with resolution" >/dev/null 2>&1 || true
  printf 'branch-only-resolution\n' > c1; git add -A
  git commit -q --no-edit          # completes the conflicted merge
  export APPROVED_SHA="$TASK_SHA"
  ki46_orphan feature/mc
  # fixture properties: every non-merge commit is upstream, the tree is not
  [ -z "$(git cherry main feature/mc | grep '^+' || true)" ] || false
  [ -n "$(git diff feature/mc main)" ] || false
  [ "$(git rev-list --parents -1 feature/mc | wc -w)" -eq 3 ] || false
  run bash "$TEST_TMP/cleanup.sh"
  [ "$status" -ne 0 ]
  run git rev-parse --verify feature/mc
  [ "$status" -eq 0 ]
}

@test "KI-46: an ordinary merged branch is still deleted" {
  ki46_extract_cleanup
  git checkout -q -b feature/ff; echo f > f3; git add -A; git commit -qm ff
  git checkout -q main; git merge -q --no-ff feature/ff -m "merge ff"
  export APPROVED_SHA="$TASK_SHA"
  ki46_orphan feature/ff
  run bash "$TEST_TMP/cleanup.sh"
  [ "$status" -eq 0 ]
  run git rev-parse --verify feature/ff
  [ "$status" -ne 0 ]
}

# KI-53 — zsh applies its `:r` history modifier to an unbraced `$VAR:`, so
# "+refs/heads/$DEFAULT_BRANCH:refs/remotes/origin/$DEFAULT_BRANCH" expands to
# "+refs/heads/mainefs/remotes/origin/main" and the phase-start fetch dies with
# a nonsense message. The block is labelled bash, but zsh is the default macOS
# shell and the step tells the operator to run it.
@test "KI-53: the phase-start refspec survives zsh parameter modifiers" {
  command -v zsh >/dev/null || skip "zsh is not installed"
  local refspec
  refspec=$(grep -o '"+refs/heads/[^"]*"' "$(dirname "$PUBLISH")/SKILL.md" | head -1)
  [ -n "$refspec" ] || false
  run zsh -c "DEFAULT_BRANCH=main; printf '%s' $refspec"
  [ "$output" = "+refs/heads/main:refs/remotes/origin/main" ]
}

# KI-46 (publish-release.sh half) — the script takes the approved SHA
# POSITIONALLY as $APPROVED and never sets APPROVED_SHA. Gating -D on an
# undeclared environment variable means the same invocation behaves differently
# depending on the caller's environment, and with it unset the squash-merged
# branch is retained: the bug, unfixed, in the half of KI-46 that names this
# script. The dependency has to be explicit and its absence has to say so.

ki46_squash_branch() {          # leaves feature squash-merged, tip in $1
  git checkout -q -b feature
  echo one > s1; git add -A; git commit -qm one
  echo two > s2; git add -A; git commit -qm two
  local tip; tip="$(git rev-parse feature)"
  git checkout -q main
  git merge -q --squash feature >/dev/null 2>&1 && git commit -qm squashed
  git push -q origin main
  printf '%s' "$tip"          # stdout is the return channel; keep git quiet
}

@test "KI-46: publish-release deletes a squash-merged branch when approval is confirmed" {
  local tip; tip="$(ki46_squash_branch)"
  [ -n "$(git rev-list main..feature)" ] || false      # commits absent from main
  [ -z "$(git diff feature main)" ] || false           # yet the work landed
  run bash "$PUBLISH" "$tip" v3.0.0 feature "$FETCH_URL" "$PUSH_URL" --confirmed-on-remote
  [ "$status" -eq 0 ]
  run git rev-parse --verify feature
  [ "$status" -ne 0 ]
}

@test "KI-46: publish-release says approval was unconfirmed rather than blaming the branch" {
  local tip; tip="$(ki46_squash_branch)"
  run bash "$PUBLISH" "$tip" v3.0.1 feature "$FETCH_URL" "$PUSH_URL"
  [ "$status" -ne 0 ]
  # Save the diagnostic before any later `run` overwrites $output (F-20).
  local msg="$output"
  printf '%s\n' "$msg" | grep -qi 'approval'
  # A glob over the whole string, not `grep -qv`: grep -qv succeeds when ANY
  # line lacks the pattern, so on multiline output it cannot detect its presence.
  [[ "$msg" != *"holds commits absent"* ]] || false
  run git rev-parse --verify feature
  [ "$status" -eq 0 ]
}

# first_push <skill>: the documented first-push fence, for feature/x.
first_push() {
  extract_fence first-push "$TEST_TMP/push.sh" "$1"
  sed -i.bak '1i\
PHASE_BRANCH=feature/x DEFAULT_BRANCH=main
' "$TEST_TMP/push.sh"
  export CLAUDE_PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  git push -q origin main && git fetch -q origin
}

# write_record <branch>: a phase record whose first table names <branch>.
write_record() {
  mkdir -p docs
  printf '# Phase record\n\n| Key | Value |\n| --- | --- |\n| `REPO` | `fixture/repo` |\n| `PHASE_BRANCH` | `%s` |\n' "$1" > docs/PHASE_RECORD.md
}

@test "first push: refuses from another branch, and after a commit that drops the record" {
  # Fails if the check reads HEAD while pushing $PHASE_BRANCH, or accepts a deleted record.
  first_push "$BATS_TEST_DIRNAME/../SKILL.md"
  git switch -qc feature/x
  write_record feature/x
  git add docs && git commit -qm record
  git switch -qc other
  run bash "$TEST_TMP/push.sh"
  [ "$status" -ne 0 ] || false
  ! git ls-remote --exit-code --heads origin feature/x >/dev/null || false
  git switch -q feature/x && git rm -q docs/PHASE_RECORD.md && git commit -qm drop
  run bash "$TEST_TMP/push.sh"
  [ "$status" -ne 0 ] || false
  ! git ls-remote --exit-code --heads origin feature/x >/dev/null
}

@test "first push: publishes the branch whose tip holds its record" {
  # Control: the fence pushes when the checked-out phase branch carries its record.
  first_push "$BATS_TEST_DIRNAME/../SKILL.md"
  git switch -qc feature/x
  write_record feature/x
  git add docs && git commit -qm record
  run bash "$TEST_TMP/push.sh"
  [ "$status" -eq 0 ] || false
  git ls-remote --exit-code --heads origin feature/x >/dev/null
}

# after_review: the documented post-review check, with REVIEWED bound to $1.
after_review() {
  extract_fence after-review "$TEST_TMP/after.sh" "$BATS_TEST_DIRNAME/../SKILL.md"
  sed -i.bak "s|^\( *\)REVIEWED=.*|\1REVIEWED=$1|" "$TEST_TMP/after.sh"
}

@test "after review: a changed file outside the bookkeeping set is named before any content is shown" {
  # Fails if a post-review fix passes the gate, or its contents are printed before the path check.
  reviewed="$(git rev-parse HEAD)"
  printf 'def add(a, b):\n    return a - b  # SECRET-LOOKING\n' > calc.py
  git commit -qam fix
  after_review "$reviewed"
  run bash "$TEST_TMP/after.sh"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"CHANGED AFTER REVIEW"*"calc.py"* ]] || false
  [[ "$output" != *SECRET-LOOKING* ]]
}

@test "after review: a phase-record-only change passes and is shown" {
  # Control: bookkeeping in the allowed files passes, with its patch printed for reading.
  reviewed="$(git rev-parse HEAD)"
  mkdir -p docs && printf '| `PR` | 9 |\n' > docs/PHASE_RECORD.md
  git add docs && git commit -qm record
  after_review "$reviewed"
  run bash "$TEST_TMP/after.sh"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *'`PR` | 9'* ]]
}

# commit_block <id>: the lines the post-review log prints under the commit whose subject names <id>
# as a whole ID (F-07, never F-070). It fails when no commit does, so a negative check never passes
# on an empty block.
commit_block() {
  awk -v id="$1" '/^=== [0-9a-f]+$/ { getline msg; keep = msg ~ ("(^|[^0-9A-Za-z-])" id "([^0-9]|$)"); found = found || keep }
    keep; END { exit !found }' <<< "$output"
}

@test "after review: a CHANGELOG-only document fix passes and is shown" {
  # Fails if a reviewer's confirmed fix to the release's CHANGELOG entry is refused after the last pass.
  printf '## [1.0.0]\n\n- old claim\n' > CHANGELOG.md
  git add CHANGELOG.md && git commit -qm changelog
  reviewed="$(git rev-parse HEAD)"
  printf '## [1.0.0]\n\n- corrected claim\n' > CHANGELOG.md
  git commit -qam "Document fix for F-07: the claim"
  after_review "$reviewed"
  run bash "$TEST_TMP/after.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(commit_block F-07)" == *"+- corrected claim"* ]]
}

@test "after review: each commit's own change is shown under its message, and nothing before review" {
  # Fails if the log shows messages without each commit's own patch, so two fixes to one file can
  # name swapped findings unseen (KI-123), or if it starts before the reviewed commit (KI-124).
  printf '## [1.0.0] - 2026-01-01\n\n- old wording\n' > CHANGELOG.md
  git add CHANGELOG.md && git commit -qm "pre-review marker"
  reviewed="$(git rev-parse HEAD)"
  printf '## [1.0.0] - 2026-01-02\n\n- old wording\n' > CHANGELOG.md
  git commit -qam "Document fix for F-07: the date"
  printf '## [1.0.0] - 2026-01-02\n\n- new wording\n' > CHANGELOG.md
  git commit -qam "Document fix for F-08: the wording"
  after_review "$reviewed"
  run bash "$TEST_TMP/after.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  f07="$(commit_block F-07)" && f08="$(commit_block F-08)" || { echo "$output"; false; }
  [[ "$f07" == *"+## [1.0.0] - 2026-01-02"* && "$f07" != *"+- new wording"* ]] || { echo "$output"; false; }
  [[ "$f08" == *"+- new wording"* && "$f08" != *"+## [1.0.0]"* ]] || { echo "$output"; false; }
  [[ "$output" != *"pre-review marker"* ]]
}

@test "after review: even a CHANGELOG-only merge needs review" {
  # Fails if an allowed path hides a merge inside the review window.
  reviewed="$(git rev-parse HEAD)"
  git switch -qc side
  echo correction > CHANGELOG.md && git add CHANGELOG.md && git commit -qm correction
  git switch -q main
  git merge -q --no-ff side -m "Merge correction"
  after_review "$reviewed"
  run bash "$TEST_TMP/after.sh"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"MERGE AFTER REVIEW — rebase the commits after $reviewed instead, or run a narrow pass that covers the merge"* ]]
}

@test "after review: shallow history is refused" {
  # Fails if the gate trusts a history with missing parents.
  git commit -q --allow-empty -m tip
  git clone -q --depth 1 "file://$REPO" "$TEST_TMP/shallow"
  cd "$TEST_TMP/shallow"
  [ "$(git rev-parse --is-shallow-repository)" = true ] || false
  after_review HEAD
  run bash "$TEST_TMP/after.sh"
  [ "$status" -ne 0 ] || false
  [[ "$output" == *"SHALLOW"* ]]
}

@test "after review: signed bookkeeping passes with signature display enabled" {
  # Fails if Git includes signature text among the filenames.
  reviewed="$(git rev-parse HEAD)"
  ssh-keygen -q -t ed25519 -N '' -f "$TEST_TMP/signing"
  git config gpg.format ssh
  git config user.signingkey "$TEST_TMP/signing"
  echo "tester $(cat "$TEST_TMP/signing.pub")" > "$TEST_TMP/signers"
  git config gpg.ssh.allowedSignersFile "$TEST_TMP/signers"
  git config log.showSignature true
  echo correction > CHANGELOG.md && git add CHANGELOG.md && git commit -qS -m correction
  git verify-commit HEAD || false
  after_review "$reviewed"
  run bash "$TEST_TMP/after.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"+correction"* ]]
}

@test "after review: a change and its revert outside the bookkeeping set still stop the check" {
  # Fails if a post-review commit to an outside file, reverted later, leaves no trace (KI-127).
  reviewed="$(git rev-parse HEAD)"
  [ ! -e helper.py ] || false   # the file must be new, so the revert leaves no net change
  printf 'x = 1\n' > helper.py && git add helper.py && git commit -qm "add helper"
  git rm -q helper.py && git commit -qm "revert helper"
  printf '## [1.0.0]\n\n- fixed claim\n' > CHANGELOG.md
  git add CHANGELOG.md && git commit -qm "Document fix for F-07: the claim"
  after_review "$reviewed"
  run bash "$TEST_TMP/after.sh"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"CHANGED AFTER REVIEW"*"helper.py"* ]]
}

@test "after review under zsh: a document fix passes, and a reverted outside change stops it" {
  # Fails if zsh loses a filename when the fence combines the two listings.
  command -v zsh >/dev/null || skip "zsh not installed"
  printf '## [1.0.0]\n\n- old claim\n' > CHANGELOG.md
  git add CHANGELOG.md && git commit -qm changelog
  reviewed="$(git rev-parse HEAD)"
  printf '## [1.0.0]\n\n- corrected claim\n' > CHANGELOG.md
  git commit -qam "Document fix for F-07: the claim"
  after_review "$reviewed"
  run zsh -f "$TEST_TMP/after.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(commit_block F-07)" == *"+- corrected claim"* ]] || { echo "$output"; false; }
  printf 'x = 1\n' > helper.py && git add helper.py && git commit -qm "add helper"
  git rm -q helper.py && git commit -qm "revert helper"
  run zsh -f "$TEST_TMP/after.sh"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"helper.py"* ]]
}

@test "origin check: accepts a bare user over each ssh spelling" {
  # Fails if git+ssh:// or ssh+git:// with a plain user name is taken for a credential.
  for url in "git+ssh://git@example.invalid/r.git" "ssh+git://git@example.invalid/r.git" "ssh://git@example.invalid:22/r.git"; do
    git remote set-url origin "$url"
    git remote set-url --push origin "$url"
    run bash "$PUBLISH" --check-origin "$url" "$url"
    [ "$status" -eq 0 ] || false
  done
}

# record_check <pr>: the documented phase-record check, for PR <pr>.
record_check() {
  extract_fence record-check "$TEST_TMP/record.sh" "$BATS_TEST_DIRNAME/../SKILL.md"
  export CLAUDE_PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  sed -i.bak -e "s|^\\( *\\)PR=.*|\\1PR=$1|" -e "s|^\\( *\\)REPO=.*|\\1REPO=${2:-fixture/repo}|" "$TEST_TMP/record.sh"
  grep -q "^ *PR=$1\$" "$TEST_TMP/record.sh" && grep -q "^ *REPO=" "$TEST_TMP/record.sh" || false
  # The post-review check's head; the record is read at it, not at a later HEAD.
  printf 'INSPECTED="$(git rev-parse HEAD)"\n%s\n' "$(cat "$TEST_TMP/record.sh")" > "$TEST_TMP/record.sh"
}

@test "phase record: another repository's PR cannot pair with this release" {
  # Fails if PR and Release are matched anywhere in the file, so PR 5 from the companion
  # table passes with this repository's v2.1.0.
  mkdir -p docs
  printf '## [2.1.0] - 2026-11-22\n' > CHANGELOG.md
  printf '| Key | Value |\n| --- | --- |\n| `REPO` | `fixture/repo` |\n| `PR` | 9 |\n| Release | v2.1.0 |\n\nCompanion:\n\n| Key | Value |\n| --- | --- |\n| `REPO` | `fixture/other` |\n| `PR` | 5 |\n| Release | v1.1.0 |\n' > docs/PHASE_RECORD.md
  git add -A && git commit -qm record
  record_check 5
  run bash "$TEST_TMP/record.sh"
  [ "$status" -ne 0 ] || false
  record_check 9
  run bash "$TEST_TMP/record.sh"
  [ "$status" -eq 0 ]
}

@test "phase record: only the first table counts, however the next is headed" {
  # Fails if the check reads past the first table, so a companion table headed differently,
  # or a second PR row, can satisfy it (F-149).
  mkdir -p docs
  printf '## [2.1.0] - 2026-11-22\n' > CHANGELOG.md
  printf '| Key   | Value |\n| --- | --- |\n| `REPO` | `fixture/repo` |\n| `PR` | 9 |\n| Release | v2.1.0 |\n\nCompanion:\n\n| Field | Value |\n| --- | --- |\n| `PR` | 5 |\n' > docs/PHASE_RECORD.md
  git add -A && git commit -qm record
  record_check 5
  run bash "$TEST_TMP/record.sh"
  [ "$status" -ne 0 ] || false
  record_check 9
  run bash "$TEST_TMP/record.sh"
  [ "$status" -eq 0 ] || false
  printf '| Key | Value |\n| --- | --- |\n| `REPO` | `fixture/repo` |\n| `PR` | 9 |\n| `PR` | 5 |\n| Release | v2.1.0 |\n' > docs/PHASE_RECORD.md
  git commit -qam two-prs
  record_check 5
  run bash "$TEST_TMP/record.sh"
  [ "$status" -ne 0 ]
}

@test "origin check: refuses every transport-helper URL" {
  # Fails if a <transport>:: URL passes in any form: chained, scheme-less, opaque, or even
  # clean, since a normal remote never needs one and the forms cannot all be parsed (F-127).
  clean="https://example.invalid/r.git"
  for url in "http::http::https://notasecret@example.invalid/r.git" "http::notasecret@example.invalid/r.git" \
             "ext::sh -c notasecret" "http::https://example.invalid/r.git"; do
    git remote set-url origin "$clean"
    git remote set-url --push origin "$url"
    run bash "$PUBLISH" --check-origin "$clean" "$url"
    [ "$status" -eq 1 ] || false
    [[ "$output" == "UNSUPPORTED ORIGIN URL"* ]] || false
    [[ "$output" != *notasecret* ]] || false
  done
}

# --- the rewritten fences under each shell (KI-74, KI-75) -------------------
# These fences lost their awk field programs, which skill arguments overwrote.
# Each runs under bash and, in its own test, under zsh -f.

# release_resumes_in <annotated|lightweight> <shell...>: the remote already holds
# the tag at the merge commit; the fence must accept it rather than conflict.
release_resumes_in() {
  local kind="$1"; shift
  prepare_documented_release
  if [ "$kind" = annotated ]; then git tag -a -m release "$TAG" "$MERGE_SHA"; else git tag "$TAG" "$MERGE_SHA"; fi
  git push -q origin "refs/tags/$TAG"
  git tag -d "$TAG" >/dev/null
  [ "$kind" != annotated ] || [ "$(git --git-dir="$FORK" cat-file -t "refs/tags/$TAG")" = tag ] || false
  PATH="$TEST_TMP/bin:$PATH" run "$@" "$TEST_TMP/release.sh"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"TAG VERIFIED AND PUBLISHED: $TAG at $MERGE_SHA"* ]]
}

@test "bash: the release fence accepts an annotated remote tag at the merge commit" {
  # Fails if the parser compares the tag object, not the commit it peels to.
  release_resumes_in annotated bash
}

@test "zsh: the release fence accepts an annotated remote tag at the merge commit" {
  # Fails if the peeled-commit parser reads differently under zsh.
  command -v zsh >/dev/null || skip "zsh is not installed"
  release_resumes_in annotated zsh -f
}

@test "bash: the release fence accepts a lightweight remote tag at the merge commit" {
  # Fails if a tag with no peeled line is not read from its direct line.
  release_resumes_in lightweight bash
}

@test "zsh: the release fence accepts a lightweight remote tag at the merge commit" {
  # Fails if the direct-line fallback reads differently under zsh.
  command -v zsh >/dev/null || skip "zsh is not installed"
  release_resumes_in lightweight zsh -f
}

# prune_in <shell...>: one gone branch already merged, one still tracking; only
# the gone one is pruned.
prune_in() {
  ki46_extract_cleanup
  git checkout -q -b feature/done; echo d > d1; git add -A; git commit -qm done
  git checkout -q main; git merge -q --ff-only feature/done
  git checkout -q -b feature/live; echo l > l1; git add -A; git commit -qm live
  git push -q -u origin feature/live
  git checkout -q main
  export APPROVED_SHA="$TASK_SHA"
  ki46_orphan feature/done
  [ "$(git for-each-ref --format='%(upstream:track)' refs/heads/feature/live)" != '[gone]' ] || false
  run "$@" "$TEST_TMP/cleanup.sh"
  [ "$status" -eq 0 ] || false
  run git rev-parse --verify -q feature/done
  [ "$status" -ne 0 ] || false
  git rev-parse --verify -q feature/live >/dev/null
}

@test "bash: prune removes only the branch whose upstream is gone" {
  # Fails if the branch and track fields are misread, so the wrong branch goes.
  prune_in bash
}

@test "zsh: prune removes only the branch whose upstream is gone" {
  # Fails if the field reading differs under zsh.
  command -v zsh >/dev/null || skip "zsh is not installed"
  prune_in zsh -f
}

@test "prune skips the checked-out branch when a tag shares its name" {
  # Fails if CURRENT is read with --short, which prefixes heads/ to an ambiguous name, so
  # prune tries to delete the branch it stands on and reports it retained (pass 3, Codex 20, Gemini 5).
  ki46_extract_cleanup
  git checkout -q -b feature/cur; echo c > c1; git add -A; git commit -qm cur
  ki46_orphan feature/cur
  git checkout -q feature/cur
  git tag feature/cur
  export APPROVED_SHA=""
  run bash "$TEST_TMP/cleanup.sh"
  [ "$status" -eq 0 ] || false
  [[ "$output" != *RETAINED* ]] || false
  git rev-parse --verify -q refs/heads/feature/cur >/dev/null
}

@test "prune deletes a merged branch whose upstream is gone though a tag shares its name" {
  # Fails if a same-named tag makes prune retain a merged branch, or delete the tag instead.
  # A control: this already worked before KI-86's fix, which is the checked-out case above.
  ki46_extract_cleanup
  git checkout -q -b feature/x; echo x > x1; git add -A; git commit -qm x
  git checkout -q main; git merge -q --ff-only feature/x
  ki46_orphan feature/x
  tagged="$(git rev-list --max-parents=0 HEAD)"
  git tag feature/x "$tagged"
  export APPROVED_SHA=""
  run bash "$TEST_TMP/cleanup.sh"
  [ "$status" -eq 0 ] || false
  ! git rev-parse --verify -q refs/heads/feature/x >/dev/null || false
  [ "$(git rev-parse refs/tags/feature/x)" = "$tagged" ]
}

# --- the phase record's first table (KI-67, KI-69) --------------------------

@test "phase record: a companion table with the same PR and release is not this repository's" {
  # Fails if the gate accepts a first table that names another repository (F-05).
  mkdir -p docs
  printf '## [2.1.0] - 2026-11-22\n' > CHANGELOG.md
  printf '| Key | Value |\n| --- | --- |\n| `REPO` | `fixture/other` |\n| `PR` | 9 |\n| Release | v2.1.0 |\n\n| Key | Value |\n| --- | --- |\n| `REPO` | `fixture/repo` |\n| `PR` | 9 |\n| Release | v2.1.0 |\n' > docs/PHASE_RECORD.md
  git add -A && git commit -qm record
  record_check 9 fixture/repo
  run bash "$TEST_TMP/record.sh"
  [ "$status" -ne 0 ] || false
  [[ "$output" == *"PHASE RECORD DOES NOT NAME"* ]]
}

@test "phase record: the gate reads a large record to its end under pipefail" {
  # Fails if the reader stops early and the producer dies of SIGPIPE, failing a valid gate.
  mkdir -p docs
  printf '## [2.1.0] - 2026-11-22\n' > CHANGELOG.md
  { printf '| Key | Value |\n| --- | --- |\n| `REPO` | `fixture/repo` |\n| `PR` | 9 |\n| Release | v2.1.0 |\n\n'
    for i in $(seq 1 100000); do echo "padding line $i"; done; } > docs/PHASE_RECORD.md
  git add -A && git commit -qm record
  record_check 9
  run bash "$TEST_TMP/record.sh"
  [ "$status" -eq 0 ]
}

@test "first push: refuses a record inherited unchanged from the default branch" {
  # Fails if a reused branch name lets the default branch's old record pass (KI-67).
  first_push "$BATS_TEST_DIRNAME/../SKILL.md"
  write_record feature/x
  git add docs && git commit -qm "old phase's record"
  git push -q origin main && git fetch -q origin
  git switch -qc feature/x
  run bash "$TEST_TMP/push.sh"
  [ "$status" -ne 0 ] || false
  ! git ls-remote --exit-code --heads origin feature/x >/dev/null
}

@test "first push: refuses a record changed and then reverted on the branch" {
  # Fails if a commit touching the record counts although the tip matches the default branch.
  first_push "$BATS_TEST_DIRNAME/../SKILL.md"
  write_record feature/x
  git add docs && git commit -qm "old phase's record"
  git push -q origin main && git fetch -q origin
  git switch -qc feature/x
  printf 'edit\n' >> docs/PHASE_RECORD.md && git commit -qam edit
  git revert --no-edit HEAD >/dev/null
  run bash "$TEST_TMP/push.sh"
  [ "$status" -ne 0 ] || false
  ! git ls-remote --exit-code --heads origin feature/x >/dev/null
}

@test "first push: refuses a record whose first table names another branch" {
  # Fails if a PHASE_BRANCH row in a later table satisfies the check.
  first_push "$BATS_TEST_DIRNAME/../SKILL.md"
  git switch -qc feature/x
  write_record feature/old
  printf '\n| Key | Value |\n| --- | --- |\n| `PHASE_BRANCH` | `feature/x` |\n' >> docs/PHASE_RECORD.md
  git add docs && git commit -qm record
  run bash "$TEST_TMP/push.sh"
  [ "$status" -ne 0 ] || false
  ! git ls-remote --exit-code --heads origin feature/x >/dev/null
}

# publish_record <gate sha>: the documented PR-description step, with gh faked.
publish_record() {
  extract_fence publish-record "$TEST_TMP/publish.sh" "$BATS_TEST_DIRNAME/../SKILL.md"
  mkdir -p "$TEST_TMP/bin"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/gh-calls"\ncase "$*" in *headRefOid*) echo "$FAKE_PR_HEAD" ;; esac\n' "$TEST_TMP" > "$TEST_TMP/bin/gh"
  chmod +x "$TEST_TMP/bin/gh"
  export FAKE_PR_HEAD="$1"
  printf 'record\n' > "$TEST_TMP/record.md"
  sed -i.bak "s|<review record file>|$TEST_TMP/record.md|" "$TEST_TMP/publish.sh"
  printf 'PR=9 REPO=fixture/repo GATE_SHA=%s\n%s\n' "$1" "$(cat "$TEST_TMP/publish.sh")" > "$TEST_TMP/publish.sh"
}

@test "the review record reaches the PR only at the gate's verified head" {
  # Fails if the PR description is edited when HEAD is not the SHA the gate verified.
  publish_record 0000000000000000000000000000000000000000
  PATH="$TEST_TMP/bin:$PATH" run bash "$TEST_TMP/publish.sh"
  [ "$status" -ne 0 ] || false
  [ ! -e "$TEST_TMP/gh-calls" ] || false
  publish_record "$(git rev-parse HEAD)"
  PATH="$TEST_TMP/bin:$PATH" run bash "$TEST_TMP/publish.sh"
  [ "$status" -eq 0 ] || false
  grep -q '^pr edit 9 -R fixture/repo --body-file' "$TEST_TMP/gh-calls"
}

# --- the origin allow-list (KI-70) ------------------------------------------

# origin_refused <url> <message>: the URL is refused with exactly <message>, as the
# fetch and as the push destination, and never printed.
origin_refused() {
  local clean="https://example.invalid/r.git" pair
  for pair in "$clean|$1" "$1|$clean"; do
    git remote set-url origin "${pair%%|*}"
    git remote set-url --push origin "${pair#*|}"
    run bash "$PUBLISH" --check-origin "${pair%%|*}" "${pair#*|}"
    [ "$status" -eq 1 ] || { echo "accepted: $pair"; return 1; }
    [[ "$output" == "$2"* ]] || { echo "message for $pair: $output"; return 1; }
    [[ "$output" != *"$1"* ]] || { echo "printed: $1"; return 1; }
  done
}

@test "origin check: refuses each unsupported form in both positions" {
  # Fails if a helper, an unlisted scheme or an option-shaped URL passes (KI-70).
  local url
  for url in '9p::https://h/r' 'my_helper::x' '::x' 'ext::ssh git@h:r' '9p::git@github.com:o/r' \
             '-oProxyCommand=x@h:r' 'foo://h/r' 'file:///r' 'http://u@h:80/r' 'git+https://h/r'; do
    origin_refused "$url" "UNSUPPORTED ORIGIN URL" || false
  done
}

@test "origin check: refuses credentials inside an accepted form, with grep absent" {
  # Fails if the credential check needs an external command and passes when it cannot run.
  local url
  mkdir -p "$TEST_TMP/nogrep"
  for tool in git bash dirname wc tr sed cat; do ln -sf "$(command -v "$tool")" "$TEST_TMP/nogrep/$tool"; done
  for url in 'https://tok@example.invalid/r.git' 'https://u:tok@example.invalid/r.git' \
             'https://example.invalid/r.git?tok' 'ssh://me:tok@example.invalid/r.git' 'git:tok@example.invalid:o/r'; do
    git remote set-url origin "$url"; git remote set-url --push origin "$url"
    PATH="$TEST_TMP/nogrep" run bash "$PUBLISH" --check-origin "$url" "$url"
    [ "$status" -eq 1 ] || { echo "accepted: $url"; false; }
    [[ "$output" == "CREDENTIALS IN ORIGIN URL"* ]] || false
  done
}

@test "origin check: a failed push-URL listing refuses" {
  # Fails if a push-URL listing that errors counts as one destination.
  local real_git; real_git="$(command -v git)"
  mkdir -p "$TEST_TMP/bin"
  printf '#!/bin/bash\ncase "$*" in *"--push --all"*) exit 128 ;; esac\nexec "%s" "$@"\n' "$real_git" > "$TEST_TMP/bin/git"
  chmod +x "$TEST_TMP/bin/git"
  PATH="$TEST_TMP/bin:$PATH" run bash "$PUBLISH" --check-origin "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"PUSH URL"* ]]
}

@test "origin check: accepts ssh, git+ssh, ssh+git, https, scp form and a local path" {
  # Control: the forms a phase uses pass.
  local url
  for url in 'ssh://git@example.invalid/r.git' 'git+ssh://git@example.invalid/r.git' \
             'ssh+git://git@example.invalid/r.git' 'https://example.invalid/r.git' \
             'git@github.com:owner/r.git' 'github.com:owner/r.git' "$TEST_TMP/fork.git"; do
    git remote set-url origin "$url"; git remote set-url --push origin "$url"
    run bash "$PUBLISH" --check-origin "$url" "$url"
    [ "$status" -eq 0 ] || { echo "refused: $url: $output"; false; }
  done
}

@test "prune: reports every retained branch, then exits 1" {
  # Fails if the loop stops at the first retained branch, leaving later ones unconsidered (ENH-29).
  ki46_extract_cleanup
  export APPROVED_SHA="$TASK_SHA"
  for b in feature/a feature/b; do
    git checkout -q -b "$b" main; echo "$b" > "${b#feature/}"; git add -A; git commit -qm "$b"
    git push -q -u origin "$b"
  done
  git checkout -q -b feature/c main; echo c > c; git add -A; git commit -qm c
  git push -q -u origin feature/c
  git checkout -q main; git merge -q --ff-only feature/c; git push -q origin main
  for b in feature/a feature/b feature/c; do git push -q origin --delete "$b"; done
  git fetch -q --prune origin
  run bash "$TEST_TMP/cleanup.sh"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"RETAINED — feature/a"* ]] || false
  [[ "$output" == *"RETAINED — feature/b"* ]] || false
  run git rev-parse --verify -q feature/c
  [ "$status" -ne 0 ]
}

# --- the post-review check and the gate's head (KI-62) ----------------------

@test "after review: a rename into an allowed path names its source" {
  # Fails if --name-only reports only the destination of a detected rename (KI-62).
  reviewed="$(git rev-parse HEAD)"
  mkdir -p docs && git mv calc.py docs/ROADMAP.md && git commit -qm "move calc.py"
  after_review "$reviewed"
  run bash "$TEST_TMP/after.sh"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"CHANGED AFTER REVIEW"*"calc.py"* ]]
}

@test "after review: a failed listing stops the check" {
  # Fails if a listing that errors reads as "nothing changed" and the gate continues.
  reviewed="$(git rev-parse HEAD)"
  local real_git; real_git="$(command -v git)"
  mkdir -p "$TEST_TMP/bin"
  printf '#!/bin/bash\ncase "$*" in *--name-only*) exit 128 ;; esac\nexec "%s" "$@"\n' "$real_git" > "$TEST_TMP/bin/git"
  chmod +x "$TEST_TMP/bin/git"
  after_review "$reviewed"
  PATH="$TEST_TMP/bin:$PATH" run bash "$TEST_TMP/after.sh"
  [ "$status" -ne 0 ] || false
  [[ "$output" == *"CANNOT LIST"* ]]
}

@test "the gate refuses a head other than the one the post-review check inspected" {
  # Fails if HEAD moves after the post-review check and the gate still passes. (Origin and the PR are
  # checked against this same head by the later lines of the fence.)
  inspected="$(git rev-parse HEAD)"
  git commit -q --allow-empty -m later
  extract_fence gate "$TEST_TMP/gate.sh" "$BATS_TEST_DIRNAME/../SKILL.md"
  printf 'PHASE_BRANCH=main INSPECTED=%s\n%s\n' "$inspected" "$(cat "$TEST_TMP/gate.sh")" > "$TEST_TMP/gate.sh"
  run bash "$TEST_TMP/gate.sh"
  [ "$status" -ne 0 ] || false
  [[ "$output" == *"HEAD MOVED SINCE THE POST-REVIEW CHECK"* ]]
}

@test "origin check: a local path holding # is not taken for a credential" {
  # Fails if the query/fragment rule meant for URLs refuses a local path.
  local url="$TEST_TMP/repo#2.git"
  git remote set-url origin "$url"; git remote set-url --push origin "$url"
  run bash "$PUBLISH" --check-origin "$url" "$url"
  [ "$status" -eq 0 ]
}

# --- external review pass 1 fixes ----------------------------------------------

@test "first push refuses when the default branch moved its record after the fork" {
  # Fails if the record is compared with the current default branch, not the fork point (pass 1, Codex 10).
  first_push "$BATS_TEST_DIRNAME/../SKILL.md"
  write_record feature/x
  git add docs && git commit -qm "old record" && git push -q origin main
  git switch -qc feature/x
  git switch -q main && printf 'later\n' >> docs/PHASE_RECORD.md && git commit -qam "main edits its record" && git push -q origin main
  git fetch -q origin && git switch -q feature/x
  run bash "$TEST_TMP/push.sh"
  [ "$status" -ne 0 ] || false
  ! git ls-remote --exit-code --heads origin feature/x >/dev/null
}

@test "first push refuses when the default branch ref is missing" {
  # Fails if a failed comparison reads as "the record changed".
  first_push "$BATS_TEST_DIRNAME/../SKILL.md"
  git switch -qc feature/x
  write_record feature/x
  git add docs && git commit -qm record
  sed -i.bak 's/DEFAULT_BRANCH=main/DEFAULT_BRANCH=nosuch/' "$TEST_TMP/push.sh"
  run bash "$TEST_TMP/push.sh"
  [ "$status" -ne 0 ] || false
  ! git ls-remote --exit-code --heads origin feature/x >/dev/null
}

@test "the gate's record check refuses an empty REPO" {
  # Fails if an unset REPO matches a record with no REPO row (Gemini 9).
  mkdir -p docs
  printf '## [2.1.0] - 2026-11-22\n' > CHANGELOG.md
  printf '| Key | Value |\n| --- | --- |\n| `PR` | 9 |\n| Release | v2.1.0 |\n' > docs/PHASE_RECORD.md
  git add -A && git commit -qm record
  record_check 9
  sed -i.bak 's|^\( *\)REPO=.*|\1REPO=|' "$TEST_TMP/record.sh"
  grep -q '^ *REPO=$' "$TEST_TMP/record.sh" || false
  run bash "$TEST_TMP/record.sh"
  [ "$status" -ne 0 ]
}

@test "the review record reaches the PR only while the PR head is the gate's" {
  # Fails if a push straight to the remote after the gate lets the old record land on a new head (Codex 12).
  publish_record "$(git rev-parse HEAD)"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/gh-calls"\ncase "$*" in *headRefOid*) echo 0000000000000000000000000000000000000000 ;; esac\n' "$TEST_TMP" > "$TEST_TMP/bin/gh"
  PATH="$TEST_TMP/bin:$PATH" run bash "$TEST_TMP/publish.sh"
  [ "$status" -ne 0 ] || false
  [ "$(grep -c '^pr edit' "$TEST_TMP/gh-calls")" -eq 0 ]
}

@test "after review: a submodule pointer change is caught even when submodule diffs are hidden" {
  # Fails if diff.ignoreSubmodules hides a gitlink change from the bookkeeping check (Codex 15).
  reviewed="$(git rev-parse HEAD)"
  git config diff.ignoreSubmodules all
  git update-index --add --cacheinfo 160000,1111111111111111111111111111111111111111,vendor/lib
  git commit -qm "pin a submodule"
  after_review "$reviewed"
  run bash "$TEST_TMP/after.sh"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"CHANGED AFTER REVIEW"*"vendor/lib"* ]]
}

@test "origin check: the push list must be exactly the approved URL" {
  # Fails if a failed line count lets two push destinations pass (Codex 13).
  git remote set-url --add --push origin "$PUSH_URL"
  git remote set-url --add --push origin "$TEST_TMP/second.git"
  mkdir -p "$TEST_TMP/nowc"
  for tool in git bash dirname tr sed cat; do ln -sf "$(command -v "$tool")" "$TEST_TMP/nowc/$tool"; done
  PATH="$TEST_TMP/nowc" run bash "$PUBLISH" --check-origin "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ]
}

@test "origin check: refuses mixed-case schemes, percent-encoded userinfo, // paths and a vcs helper" {
  # Fails if a spelling git hands to another transport, or a hidden credential, passes (Codex 14, Gemini 11).
  local url
  for url in 'SSH://git@example.invalid/r.git' 'Https://example.invalid/r.git' 'https://u%3Ap@example.invalid/r.git' \
             '//u:p@host/share/r.git'; do
    git remote set-url origin "$url"; git remote set-url --push origin "$url"
    run bash "$PUBLISH" --check-origin "$url" "$url"
    [ "$status" -eq 1 ] || { echo "accepted: $url"; false; }
  done
  git remote set-url origin "$FETCH_URL"; git remote set-url --push origin "$PUSH_URL"
  git config remote.origin.vcs evil
  run bash "$PUBLISH" --check-origin "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"remote.origin.vcs"* ]]
}

@test "prune: a branch that -D cannot delete is reported, and later branches still considered" {
  # Fails if a failed -D at the approved tip exits before the others (Codex 20).
  ki46_extract_cleanup
  git checkout -q -b feature/at-tip; echo t > t1; git add -A; git commit -qm tip
  export APPROVED_SHA="$(git rev-parse HEAD)"
  git push -q -u origin feature/at-tip
  git checkout -q -b feature/merged main; git checkout -q main
  git worktree add -q "$TEST_TMP/wt" feature/at-tip
  for b in feature/at-tip; do git push -q origin --delete "$b"; done
  git push -q -u origin feature/merged >/dev/null 2>&1; git push -q origin --delete feature/merged
  git fetch -q --prune origin
  run bash "$TEST_TMP/cleanup.sh"
  git worktree remove --force "$TEST_TMP/wt"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"RETAINED — feature/at-tip"* ]] || false
  run git rev-parse --verify -q feature/merged
  [ "$status" -ne 0 ]
}

# --- external review pass 2 fixes ----------------------------------------------

@test "the record check reads the record at INSPECTED, not at a later HEAD" {
  # Fails if the check reads HEAD, so a record fixed after the post-review check passes (pass 2, Codex 22).
  mkdir -p docs
  printf '## [2.1.0] - 2026-11-22\n' > CHANGELOG.md
  printf '| Key | Value |\n| --- | --- |\n| `REPO` | `fixture/repo` |\n| `PR` | 5 |\n| Release | v2.1.0 |\n' > docs/PHASE_RECORD.md
  git add -A && git commit -qm "record at the inspected head"
  inspected="$(git rev-parse HEAD)"
  sed -i.bak 's/| `PR` | 5 |/| `PR` | 9 |/' docs/PHASE_RECORD.md && git commit -qam "a later fix"
  record_check 9
  sed -i.bak "s|^INSPECTED=.*|INSPECTED=$inspected|" "$TEST_TMP/record.sh"
  run bash "$TEST_TMP/record.sh"
  [ "$status" -ne 0 ]
}

@test "the published record names the head it was reviewed at" {
  # Fails if a record published onto a moved head cannot be told from a current one (Codex 4).
  publish_record "$(git rev-parse HEAD)"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/gh-calls"\ncase "$*" in *headRefOid*) echo "$FAKE_PR_HEAD" ;; *"pr edit"*) if [ "${@: -1}" = - ]; then cat > "%s/published"; else cp "${@: -1}" "%s/published"; fi ;; esac\n' "$TEST_TMP" "$TEST_TMP" "$TEST_TMP" > "$TEST_TMP/bin/gh"
  PATH="$TEST_TMP/bin:$PATH" run bash "$TEST_TMP/publish.sh"
  [ "$status" -eq 0 ] || false
  grep -q "$(git rev-parse HEAD)" "$TEST_TMP/published"
}

# publish_fake: gh that answers the head (moved once edited, when MOVE is set; unreadable
# once edited, when NOVIEW is set) and keeps a body sent on stdin as $TEST_TMP/published.
publish_fake() {
  cat > "$TEST_TMP/bin/gh" <<SH
#!/bin/bash
case "\$*" in
  *headRefOid*) if [ -e "$TEST_TMP/edited" ] && [ -n "\$NOVIEW" ]; then exit 1; fi
                if [ -e "$TEST_TMP/edited" ] && [ -n "\$MOVE" ]; then echo ffffffffffffffffffffffffffffffffffffffff; else echo "\$FAKE_PR_HEAD"; fi ;;
  *"pr edit"*) if [ "\${@: -1}" = - ]; then cat > "$TEST_TMP/published"; else touch "$TEST_TMP/body-file"; fi
               touch "$TEST_TMP/edited" ;;
esac
SH
  chmod +x "$TEST_TMP/bin/gh"
}

@test "publishing the record sends its body on stdin, keeps the caller's traps, and reports a push" {
  # Fails if the step writes the body to a file, replaces a trap of the shell it runs in, or
  # misses a head that moves during gh pr edit (pass 3, Codex 19, Gemini 15; pass 4, Codex 9).
  publish_record "$(git rev-parse HEAD)"
  publish_fake
  PATH="$TEST_TMP/bin:$PATH" MOVE= NOVIEW= run bash -c 'trap "echo CALLER-EXIT" EXIT; . "$1"' _ "$TEST_TMP/publish.sh"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *CALLER-EXIT* ]] || false
  [ ! -e "$TEST_TMP/body-file" ] || false
  grep -q "Review record for $(git rev-parse HEAD)" "$TEST_TMP/published" || false
  grep -q '^record$' "$TEST_TMP/published" || false
  rm -f "$TEST_TMP/edited"
  PATH="$TEST_TMP/bin:$PATH" MOVE=1 NOVIEW= run bash "$TEST_TMP/publish.sh"
  [ "$status" -ne 0 ] || false
  [[ "$output" == *"PR HEAD MOVED WHILE THE RECORD WAS PUBLISHED"* ]]
}

@test "zsh: publish-record sends its body on stdin" {
  # Fails if the step's pipe into gh pr edit does not carry the body under zsh.
  command -v zsh >/dev/null || skip "zsh is not installed"
  publish_record "$(git rev-parse HEAD)"
  publish_fake
  PATH="$TEST_TMP/bin:$PATH" MOVE= NOVIEW= run zsh -f "$TEST_TMP/publish.sh"
  [ "$status" -eq 0 ] || false
  grep -q "Review record for $(git rev-parse HEAD)" "$TEST_TMP/published"
}

@test "a PR head that cannot be read after publishing is reported as unverified, not as moved" {
  # Fails if a failed gh pr view after the edit is reported as a confirmed push (pass 4, Codex 9).
  publish_record "$(git rev-parse HEAD)"
  publish_fake
  PATH="$TEST_TMP/bin:$PATH" MOVE= NOVIEW=1 run bash "$TEST_TMP/publish.sh"
  [ "$status" -ne 0 ] || false
  [[ "$output" == *"CANNOT READ THE PR HEAD AFTER PUBLISHING"* ]] || false
  [[ "$output" != *MOVED* ]]
}

@test "a record that cannot be read never reaches the PR" {
  # Fails if gh pr edit starts before the record is read, so a failed read publishes the
  # heading alone over the PR description (pass 5, Codex 1, Gemini 1).
  publish_record "$(git rev-parse HEAD)"
  publish_fake
  rm -f "$TEST_TMP/record.md"
  PATH="$TEST_TMP/bin:$PATH" MOVE= NOVIEW= run bash "$TEST_TMP/publish.sh"
  [ "$status" -ne 0 ] || false
  [ ! -e "$TEST_TMP/edited" ] || false
  [ ! -e "$TEST_TMP/published" ]
}

@test "an empty PR head after publishing is reported as unverified, not as moved" {
  # Fails if gh answering status 0 with no SHA is read as a confirmed push (pass 5, Codex 12).
  publish_record "$(git rev-parse HEAD)"
  publish_fake
  sed -i.bak 's|exit 1; fi$|echo; exit 0; fi|' "$TEST_TMP/bin/gh"
  grep -q 'echo; exit 0; fi' "$TEST_TMP/bin/gh" || false
  PATH="$TEST_TMP/bin:$PATH" MOVE= NOVIEW=1 run bash "$TEST_TMP/publish.sh"
  [ "$status" -ne 0 ] || false
  [[ "$output" == *"CANNOT READ THE PR HEAD AFTER PUBLISHING"* ]] || false
  [[ "$output" != *MOVED* ]]
}

@test "origin check: an ssh authority holding a %-escape is refused" {
  # Fails if git's decoding of an ssh authority can hide a user part from the check (Codex 5).
  local url='ssh://git%40evil:x@example.invalid/r.git'
  git remote set-url origin "$url"; git remote set-url --push origin "$url"
  run bash "$PUBLISH" --check-origin "$url" "$url"
  [ "$status" -eq 1 ] || false
  url='ssh://example.invalid%2Fx/r.git'
  git remote set-url origin "$url"; git remote set-url --push origin "$url"
  run bash "$PUBLISH" --check-origin "$url" "$url"
  [ "$status" -eq 1 ]
}

@test "origin check: an empty remote.origin.vcs is still a helper" {
  # Fails if an explicitly empty setting reads as unset (Codex 6).
  git config remote.origin.vcs ""
  run bash "$PUBLISH" --check-origin "$FETCH_URL" "$PUSH_URL"
  [ "$status" -eq 1 ]
}
