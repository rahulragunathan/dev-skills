#!/usr/bin/env bash
# mutation-restore.sh — break one behaviour, run its test, put the tree back.
#
# Implements phase-workflow §3 step 3. A bug here loses uncommitted work during
# a test-validity audit, which is the worst moment for it, and the procedure
# lived only in a fenced block that nothing ran.
#
# Usage:
#   mutation-restore.sh <task-sha> <file> <sed-expression> <test-command...>
#
# Applies the mutation to <file>, runs the test command, and restores <file>
# from <task-sha> across both index and worktree whatever happens.
#
# Exit 0  the test failed under mutation, which is what the audit wants
# Exit 1  refused, or the test did not fail, or restoration failed

set -uo pipefail

SHA="${1:?usage: mutation-restore.sh <task-sha> <file> <sed-expr> <test-cmd...>}"
FILE="${2:?missing file}"
EXPR="${3:?missing sed expression}"
shift 3
[ "$#" -gt 0 ] || { echo "missing test command"; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 || { echo "NOT A GIT REPOSITORY"; exit 1; }

# A dirty tree means the restore would discard work that was never committed.
TREE_STATE="$(git status --porcelain -uall)" \
  || { echo "CANNOT READ TREE STATUS — refusing"; exit 1; }
if [ -n "$TREE_STATE" ]; then
  echo "TREE IS DIRTY — commit or stash before a mutation audit; refusing"
  exit 1
fi

[ -L "$FILE" ] && { echo "TARGET IS A SYMLINK — refusing to mutate through it"; exit 1; }
[ -f "$FILE" ] || { echo "TARGET IS NOT A REGULAR FILE: $FILE"; exit 1; }

git rev-parse --verify "$SHA^{commit}" >/dev/null 2>&1 \
  || { echo "NOT A COMMIT: $SHA"; exit 1; }

# The mutation is applied to the current checkout, so the restore must come from
# the same commit. Any older commit that merely contains the file would restore
# it over every change committed since — work that looks safe because it was
# committed, which is exactly why this is checked rather than trusted.
HEAD_SHA="$(git rev-parse --verify HEAD)"
[ "$(git rev-parse --verify "$SHA^{commit}")" = "$HEAD_SHA" ] \
  || { echo "SHA IS NOT HEAD — refusing: restoring from it would discard"
       echo "everything committed since. HEAD is $HEAD_SHA"; exit 1; }

git ls-tree -r --name-only "$SHA" -- "$FILE" | grep -qx -- "$FILE" \
  || { echo "FILE IS NOT PRESENT AT $SHA — cannot restore it afterwards"; exit 1; }

RESTORE_FAILED=0
restore() {
  git restore --source="$SHA" --staged --worktree -- "$FILE" 2>/dev/null \
    || git checkout "$SHA" -- "$FILE" 2>/dev/null || true
  # Verify rather than trust the exit status. A restore that returns 0 without
  # restoring leaves mutated code in the tree, and the audit reports success.
  if ! git diff --quiet "$SHA" -- "$FILE" || ! git diff --quiet -- "$FILE"; then
    echo "RESTORE FAILED — $FILE does not match $SHA; repair it by hand"
    RESTORE_FAILED=1
    return 1
  fi
  return 0
}

# Restore on every exit path, including INT and TERM. Without this a killed run
# leaves the mutation in place and the next command reads broken code. The EXIT
# trap preserves the incoming status and overrides it only to report a failed
# restore: a trap's own failure cannot change an exit status on its own.
on_exit() {
  local rc=$?
  restore
  [ "$RESTORE_FAILED" = 1 ] && exit 1
  exit "$rc"
}
trap 'restore; exit 130' INT TERM
trap on_exit EXIT

sed -i.mutbak "$EXPR" "$FILE" || { echo "MUTATION FAILED TO APPLY"; exit 1; }
rm -f "$FILE.mutbak"

if git diff --quiet -- "$FILE"; then
  echo "MUTATION CHANGED NOTHING — the expression did not match; not a valid audit"
  exit 1
fi

"$@"
rc=$?

if [ "$rc" -eq 0 ]; then
  echo "TEST PASSED UNDER MUTATION — it does not discriminate (rc=0)"
  exit 1
fi
if [ "$rc" -ne 1 ]; then
  echo "NOT AN ASSERTION RED — test command exited $rc; inspect the output"
  exit 1
fi
restore || exit 1
# The mutation has been removed. Preserve any later unexpected change for inspection.
trap - EXIT INT TERM
"$@"
normal_rc=$?
if ! git diff --quiet "$SHA" -- ":(top)" || ! git diff --cached --quiet "$SHA" -- ":(top)"; then
  echo "TRACKED TREE CHANGED — inspect index and worktree; unexpected changes retained"
  exit 1
fi
[ "$normal_rc" -eq 0 ] || { echo "RESTORED TEST FAILED (rc=$normal_rc)"; exit 1; }
echo "EXIT 1 — verify the named failure in the output before certifying"
exit 0
