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

# Extract one executable fence from SKILL.md by a substring it contains.
# Three tests needed this and the copies were drifting apart.
extract_fence() {   # $1 = selector, $2 = destination, $3 = SKILL.md path
  python3 - "$3" "$2" "$1" <<'FENCE_PY'
import pathlib,re,sys
blocks=re.findall(r'```bash\n(.*?)```',pathlib.Path(sys.argv[1]).read_text(),re.S)
pathlib.Path(sys.argv[2]).write_text(next(b for b in blocks if sys.argv[3] in b))
FENCE_PY
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
  for url in "https://someone:notasecret@example.invalid/r.git" "HTTPS://notasecret@example.invalid/r.git" \
             "git+https://notasecret@example.invalid/r.git" "https://example.invalid/r.git?token=notasecret" \
             "http::https://notasecret@example.invalid/r.git" "ssh://me@mail.example:notasecret@example.invalid/r.git"; do
    # A clean fetch URL with a bad push URL, then the reverse: each side is checked.
    for pair in "$clean $url" "$url $clean"; do
      set -- $pair
      git remote set-url origin "$1"
      git remote set-url --push origin "$2"
      run bash "$PUBLISH" --check-origin "$1" "$2"
      [ "$status" -eq 1 ] || false
      [[ "$output" == *"CREDENTIALS IN ORIGIN URL"* ]] || false
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
  extract_fence 'GONE=' "$TEST_TMP/cleanup.sh" "$(dirname "$PUBLISH")/SKILL.md"
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
  extract_fence 'REMOTE_TAG=' "$TEST_TMP/release.sh" "$CLAUDE_PLUGIN_ROOT/skills/phase-workflow/SKILL.md"
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

ki46_extract_cleanup() { extract_fence 'GONE=' "$TEST_TMP/cleanup.sh" "$(dirname "$PUBLISH")/SKILL.md"; }

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
  extract_fence 'PHASE RECORD NOT COMMITTED ON' "$TEST_TMP/push.sh" "$1"
  sed -i.bak '1i\
PHASE_BRANCH=feature/x DEFAULT_BRANCH=main
' "$TEST_TMP/push.sh"
  git push -q origin main && git fetch -q origin
}

@test "first push: refuses from another branch, and after a commit that drops the record" {
  # Fails if the check reads HEAD while pushing $PHASE_BRANCH, or accepts a deleted record.
  first_push "$BATS_TEST_DIRNAME/../SKILL.md"
  git switch -qc feature/x
  mkdir -p docs && printf '| `PHASE_BRANCH` | `feature/x` |\n' > docs/PHASE_RECORD.md
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
  mkdir -p docs && printf '| `PHASE_BRANCH` | `feature/x` |\n' > docs/PHASE_RECORD.md
  git add docs && git commit -qm record
  run bash "$TEST_TMP/push.sh"
  [ "$status" -eq 0 ] || false
  git ls-remote --exit-code --heads origin feature/x >/dev/null
}

# after_review: the documented post-review check, with REVIEWED bound to $1.
after_review() {
  extract_fence 'CHANGED AFTER REVIEW' "$TEST_TMP/after.sh" "$BATS_TEST_DIRNAME/../SKILL.md"
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
  extract_fence 'PHASE RECORD DOES NOT NAME PR' "$TEST_TMP/record.sh" "$BATS_TEST_DIRNAME/../SKILL.md"
  if grep -q '^ *PR=' "$TEST_TMP/record.sh"; then
    sed -i.bak "s|^\\( *\\)PR=.*|\\1PR=$1|" "$TEST_TMP/record.sh"
  else
    printf 'PR=%s\n%s\n' "$1" "$(cat "$TEST_TMP/record.sh")" > "$TEST_TMP/record.sh"
  fi
}

@test "phase record: another repository's PR cannot pair with this release" {
  # Fails if PR and Release are matched anywhere in the file, so PR 5 from the companion
  # table passes with this repository's v2.1.0.
  mkdir -p docs
  printf '## [2.1.0] - 2026-11-22\n' > CHANGELOG.md
  printf '| Key | Value |\n| --- | --- |\n| `PR` | 9 |\n| Release | v2.1.0 |\n\nCompanion:\n\n| Key | Value |\n| --- | --- |\n| `PR` | 5 |\n| Release | v1.1.0 |\n' > docs/PHASE_RECORD.md
  git add -A && git commit -qm record
  record_check 5
  run bash "$TEST_TMP/record.sh"
  [ "$status" -ne 0 ] || false
  record_check 9
  run bash "$TEST_TMP/record.sh"
  [ "$status" -eq 0 ]
}
