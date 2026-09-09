#!/usr/bin/env bats
#
# Capture suite. Every test names the condition that turns it red.
#
# The bundle is the one artifact in this repo that leaves the machine, so these
# tests are about containment first and completeness second. Each test names
# the condition that must be rejected or captured without losing content.

load helpers/setup

setup()    { setup_capture_env; }
teardown() { teardown_capture_env; }

# --- containment -----------------------------------------------------------

@test "repo: a symlinked parent directory does not leak its target" {
  # Red if capture tests -L on the final component only: the parent is the
  # symlink, the child looks like an ordinary file, and cat reads through it.
  mkdir -p sub && printf 'inner\n' > sub/ok.txt
  git add -A && git commit -qm sub
  rm -r sub && ln -s "$OUTSIDE" sub

  run bash "$CAPTURE" repo "$OUT"
  [ "$status" -eq 0 ]
  refute_canary
  withheld_for "sub/ok.txt" "outside every allowed root"
}

@test "repo: a symlinked file is withheld, not followed" {
  # Red if the symlink test is dropped: cat follows the link out of the repo.
  ln -s "$OUTSIDE/secret.txt" leak.txt
  git add -A && git commit -qm link

  run bash "$CAPTURE" repo "$OUT"
  [ "$status" -eq 0 ]
  refute_canary
  withheld_for "leak.txt" "symlink"
}

@test "repo: credential-shaped files never reach the bundle" {
  # Red if the exclusion pathspecs lose their leading * or icase: a path below
  # the repo root, or a capitalised name, then passes.
  mkdir -p config
  printf 'AWS_SECRET=SECRET-CANARY\n' > .env
  printf 'token: SECRET-CANARY\n'     > config/Credentials.yaml
  printf 'key: SECRET-CANARY\n'       > deploy.PEM
  git add -A && git commit -qm creds

  run bash "$CAPTURE" repo "$OUT"
  [ "$status" -eq 0 ]
  refute_canary
}

# --- completeness ----------------------------------------------------------

@test "repo: a tracked file missing from the tree is withheld, not skipped" {
  # Red if the loop uses `[ -f ] || continue`: the file vanishes from the bundle
  # and from the withheld list, so the counts still look complete.
  printf 'gone\n' > removed.txt
  git add -A && git commit -qm add
  rm removed.txt

  run bash "$CAPTURE" repo "$OUT"
  [ "$status" -eq 0 ]
  withheld_for "removed.txt" "absent from the tree"
}

@test "repo: a file named -n is read, not parsed as an option" {
  # Red if paths reach cat/perl without ./ or --: `cat -n` numbers stdin instead
  # of reading the file, and the bundle silently loses its content.
  printf 'dash-content\n' > ./-n
  git add -A && git commit -qm dash

  run bash "$CAPTURE" repo "$OUT"
  [ "$status" -eq 0 ]
  grep -q 'dash-content' "$OUT/bundle.txt"
}

@test "repo: a filename containing a newline is counted once" {
  # Red if any count uses wc -l on a NUL-delimited list.
  printf 'multi\n' > "$(printf 'two\nlines.txt')"
  git add -A && git commit -qm newline

  run bash "$CAPTURE" repo "$OUT"
  [ "$status" -eq 0 ]
  [ "$(nulcount "$OUT/manifest.z")" -eq "$(git ls-files | wc -l | tr -d ' ')" ]
}

@test "repo: a binary file is withheld and its bytes stay out of the bundle" {
  printf '\x00\x01\x02BINARY-CANARY\x00' > blob.bin
  git add -A && git commit -qm binary

  run bash "$CAPTURE" repo "$OUT"
  [ "$status" -eq 0 ]
  withheld_for "blob.bin" "binary"
  ! grep -q 'BINARY-CANARY' "$OUT/bundle.txt"
}

# --- reconciliation --------------------------------------------------------

@test "repo: the reported captured count matches what is actually in the bundle" {
  # Red if CAPTURED is derived as SELECTED - WITHHELD rather than recorded:
  # dropping an append then still reconciles.
  printf 'a\n' > a.txt; printf 'b\n' > b.txt
  git add -A && git commit -qm more

  run bash "$CAPTURE" repo "$OUT"
  [ "$status" -eq 0 ]
  local headers; headers="$(grep -c '^===== ' "$OUT/bundle.txt")"
  [ "$(nulcount "$OUT/captured.z")" -eq "$headers" ]
  grep -q "bundle contains $headers of" "$OUT/counts.txt"
}

@test "repo: a read failure refuses the bundle" {
  # Red if the failure guard is searched with a grep that ignores NUL input,
  # or if the guard is the block's last command and returns its own status.
  printf 'unreadable\n' > locked.txt
  git add -A && git commit -qm locked
  chmod 000 locked.txt

  run bash "$CAPTURE" repo "$OUT"
  chmod 644 locked.txt
  [ "$status" -eq 1 ]
  [[ "$output" == *"do not send this bundle"* ]]
}

@test "repo: a clean run exits 0" {
  # Red if a capture block ends on `grep -q … && exit 1`, which returns grep's
  # status: with nothing withheld the whole procedure reports failure.
  run bash "$CAPTURE" repo "$OUT"
  [ "$status" -eq 0 ]
}

# --- phase mode ------------------------------------------------------------

@test "phase: untracked files are included and tracked ones are not duplicated" {
  printf 'new\n' > added.txt
  git add -A && git commit -qm added
  printf 'loose\n' > untracked.txt

  run bash "$CAPTURE" phase "$OUT" HEAD~1
  [ "$status" -eq 0 ]
  grep -q 'loose' "$OUT/bundle.txt"
  [ "$(grep -c '^===== UNTRACKED FILE: ' "$OUT/bundle.txt")" -eq 1 ]
}

@test "phase: a binary forced to text by a diff attribute stays out of the bundle" {
  # Red while tracked paths reach the bundle through git diff without passing
  # the same binary test untracked files face.
  printf '\x00\x01BINARY-CANARY\x00' > forced.bin
  printf 'forced.bin diff\n' > .gitattributes
  git add -A && git commit -qm forced

  run bash "$CAPTURE" phase "$OUT" HEAD~1
  [ "$status" -eq 0 ]
  ! grep -q 'BINARY-CANARY' "$OUT/bundle.txt"
}

# --- plan mode -------------------------------------------------------------

@test "plan: an absolute path outside the repo is captured, not mangled" {
  # Red while capture prefixes ./ onto an absolute path, producing
  # .//Users/... — pass 8 finding M-10. Plans live in ~/.claude/plans by design.
  printf 'PLAN-BODY\n' > "$OUTSIDE/plan.md"

  run bash "$CAPTURE" plan "$OUT" "$OUTSIDE/plan.md"
  [ "$status" -eq 0 ]
  grep -q 'PLAN-BODY' "$OUT/bundle.txt"
}

@test "plan: a file outside both the repo and the named plan directory is withheld" {
  printf 'PLAN-BODY\n' > "$OUTSIDE/plan.md"
  mkdir -p "$TEST_TMP/elsewhere"
  printf 'SECRET-CANARY\n' > "$TEST_TMP/elsewhere/other.md"

  run bash "$CAPTURE" plan "$OUT" "$TEST_TMP/elsewhere/other.md"
  [ "$status" -eq 0 ]
  # allowed because its own directory becomes a root; the canary check below is
  # what proves no *other* directory was opened up by that.
  run bash "$CAPTURE" plan "$OUT" "$OUTSIDE/plan.md"
  refute_canary
}

refute_canary() {
  if grep -q 'SECRET-CANARY' "$OUT/bundle.txt" 2>/dev/null; then
    echo "LEAK: canary content reached the bundle"
    return 1
  fi
}

@test "phase: binary content on the old side is withheld after replacement with text" {
  printf '\x00BINARY-CANARY\x00' > forced.bin
  printf 'forced.bin diff\n' > .gitattributes
  git add -A && git commit -qm binary
  printf 'plain text\n' > forced.bin
  git add -A && git commit -qm text

  run bash "$CAPTURE" phase "$OUT" HEAD~1
  [ "$status" -eq 0 ]
  run grep -q 'BINARY-CANARY' "$OUT/bundle.txt"
  [ "$status" -eq 1 ]
  withheld_for "forced.bin" "binary"
}

@test "phase: tracked symlinks are withheld before building the diff" {
  ln -s "$OUTSIDE/secret.txt" link.txt
  git add -A && git commit -qm link

  run bash "$CAPTURE" phase "$OUT" HEAD~1
  [ "$status" -eq 0 ]
  withheld_for "link.txt" "symlink"
  run grep -q 'diff --git' "$OUT/bundle.txt"
  [ "$status" -eq 1 ]
  grep -q 'bundle contains 0 of 1 files; 1 withheld, 0 excluded' "$OUT/counts.txt"
}

@test "phase: a symlinked parent is withheld before building the diff" {
  mkdir sub
  printf 'PRIVATE-PATCH-CANARY\n' > sub/ok.txt
  git add -A && git commit -qm sub
  rm -r sub && ln -s "$OUTSIDE" sub

  run bash "$CAPTURE" phase "$OUT" HEAD~1
  [ "$status" -eq 0 ]
  withheld_for "sub/ok.txt" "outside every allowed root"
  run grep -q 'PRIVATE-PATCH-CANARY' "$OUT/bundle.txt"
  [ "$status" -eq 1 ]
}

@test "phase: a withheld pathspec-shaped name does not exclude a safe tracked file" {
  printf '\x00BINARY-CANARY\x00' > 'blob[1].bin'
  printf 'SAFE-TEXT\n' > blob1.bin
  printf '*.bin diff\n' > .gitattributes
  git add -A && git commit -qm names

  run bash "$CAPTURE" phase "$OUT" HEAD~1
  [ "$status" -eq 0 ]
  withheld_for 'blob[1].bin' "binary"
  run grep -q 'BINARY-CANARY' "$OUT/bundle.txt"
  [ "$status" -eq 1 ]
  grep -q 'SAFE-TEXT' "$OUT/bundle.txt"
  grep -q 'bundle contains 2 of 3 files; 1 withheld, 0 excluded' "$OUT/counts.txt"
}

# --- repo anchoring and scope ----------------------------------------------

@test "phase: a deleted file reaches the reviewer as a deletion" {
  # Red while the worktree checks run on a path the diff deletes: the file is
  # absent from the tree, so it is withheld and its removal never appears in
  # the patch. A review that cannot see deletions cannot see what was dropped.
  printf 'DOOMED-LINE\n' > gone.txt
  git add -A && git commit -qm add
  git rm -q gone.txt
  git commit -qm delete

  run bash "$CAPTURE" phase "$OUT" HEAD~1
  [ "$status" -eq 0 ]
  grep -q 'deleted file' "$OUT/bundle.txt"
  grep -q 'DOOMED-LINE' "$OUT/bundle.txt"
}

@test "repo: capture from a subdirectory still covers the whole repository" {
  # Red while pathspecs are cwd-relative: `-- .` scopes the manifest to the
  # subdirectory, so files above it vanish from the bundle and the credential
  # exclusions, anchored at the same place, stop matching the root.
  mkdir -p sub
  printf 'SUBDIR-CONTENT\n' > sub/inner.txt
  printf 'AWS_SECRET=SECRET-CANARY\n' > .env
  git add -A && git commit -qm sub
  cd sub

  run bash "$CAPTURE" repo "$OUT"
  [ "$status" -eq 0 ]
  grep -q 'hello' "$OUT/bundle.txt"
  grep -q 'SUBDIR-CONTENT' "$OUT/bundle.txt"
  refute_canary
}

@test "repo: an output directory inside the repository is refused" {
  # Red while the bundle can be written into the working tree: the untracked
  # sweep lists it, appends it to itself, and the reconciled counts go negative.
  run bash "$CAPTURE" repo "$REPO/inside-out"
  [ "$status" -eq 1 ]
  [[ "$output" == *"INSIDE THE REPOSITORY"* ]]
}

@test "repo: --exclude keeps a named directory out of the bundle and counts it" {
  # Red while a scope exclusion exists only in the review prompt: the files are
  # in the bundle, the reviewer reads them, and reports on them.
  mkdir -p skills/held
  printf 'HELD-CONTENT\n' > skills/held/notes.md
  git add -A && git commit -qm held

  run bash "$CAPTURE" --exclude skills/held repo "$OUT"
  [ "$status" -eq 0 ]
  ! grep -q 'HELD-CONTENT' "$OUT/bundle.txt"
  grep -q '1 excluded' "$OUT/counts.txt"
}

@test "phase: --exclude keeps a named directory out of the diff" {
  mkdir -p skills/held
  printf 'HELD-CONTENT\n' > skills/held/notes.md
  git add -A && git commit -qm held

  run bash "$CAPTURE" --exclude skills/held phase "$OUT" HEAD~1
  [ "$status" -eq 0 ]
  ! grep -q 'HELD-CONTENT' "$OUT/bundle.txt"
}

@test "phase: a deletion under a symlinked parent is withheld" {
  # Red while deletions bypass containment as well as the worktree checks. The
  # rule that a symlinked parent is never read has to hold for every path, not
  # only the ones that still have a copy in the tree.
  mkdir sub
  printf 'PRIVATE-PATCH-CANARY\n' > sub/ok.txt
  printf 'keep\n' > sub/other.txt
  git add -A && git commit -qm sub
  git rm -q sub/ok.txt
  git commit -qm delete
  rm -r sub && ln -s "$OUTSIDE" sub

  run bash "$CAPTURE" phase "$OUT" HEAD~1
  [ "$status" -eq 0 ]
  withheld_for "sub/ok.txt" "outside every allowed root"
  run grep -q 'PRIVATE-PATCH-CANARY' "$OUT/bundle.txt"
  [ "$status" -eq 1 ]
}

@test "phase: a deletion that empties its directory still reaches the reviewer" {
  # The guard on the fix above. A deletion that removes the last file in a
  # directory leaves no parent to resolve, and refusing on that would withhold
  # exactly the deletions the containment check was never about.
  mkdir -p only
  printf 'LAST-LINE\n' > only/last.txt
  git add -A && git commit -qm add
  git rm -q only/last.txt
  git commit -qm delete

  run bash "$CAPTURE" phase "$OUT" HEAD~1
  [ "$status" -eq 0 ]
  grep -q 'LAST-LINE' "$OUT/bundle.txt"
}

@test "plan: --exclude is refused rather than silently ignored" {
  # Red while the flag is parsed for every mode but wired into only two: plan
  # mode captures one named file, so an exclusion there does nothing and saying
  # nothing about it is how a scope exclusion is believed and not applied.
  printf 'PLAN-BODY\n' > "$OUTSIDE/plan.md"
  run bash "$CAPTURE" --exclude skills/held plan "$OUT" "$OUTSIDE/plan.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--exclude"* ]]
}
