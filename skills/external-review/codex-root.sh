#!/usr/bin/env bash
# codex-root.sh — build a pruned copy of HEAD for a repo-rooted reviewer.
#
# Usage:
#   codex-root.sh <dir> [--exclude <path>]...
#
# Codex reads the tree it is rooted at, so a bundle exclusion does not reach it
# and neither does a sentence in the prompt telling it what to ignore. This
# builds a detached worktree at <dir>, deletes the excluded paths inside it, and
# prints the path to root the reviewer at. What is not there cannot be read.
#
# The worktree is a copy: the real working tree is never modified. Remove it
# afterwards with `git worktree remove --force <dir>`.
#
# Exit 0 when the pruned root is ready; exit 1 on any refusal or failure.

set -uo pipefail

DEST="${1:?usage: codex-root.sh <dir> [--exclude <path>]...}"
shift

EXCL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --exclude)
      [ -n "${2:-}" ] || { echo "--exclude needs a path"; exit 1; }
      EXCL+=("$2"); shift 2 ;;
    *) echo "unknown argument: $1"; exit 1 ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || { echo "NOT A GIT REPOSITORY"; exit 1; }
[ -e "$DEST" ] && { echo "TARGET EXISTS: $DEST"; exit 1; }

# The worktree is built from HEAD, so uncommitted work is not in it. Reviewing
# HEAD while the tree says something else is worse than not reviewing.
[ -z "$(git status --porcelain)" ] \
  || { echo "TREE IS DIRTY — commit first; the reviewer only ever sees HEAD"; exit 1; }

# Every exclusion must match something tracked. A typo would otherwise leave the
# area in place while the caller believes it was pruned — which is the failure
# this script exists to prevent, arriving by a different route.
if [ "${#EXCL[@]}" -gt 0 ]; then
  for e in "${EXCL[@]}"; do
    [ -n "$(git ls-files -- "$e")" ] || { echo "EXCLUSION MATCHES NOTHING: $e"; exit 1; }
  done
fi

git worktree add --detach -q "$DEST" HEAD || { echo "WORKTREE CREATE FAILED"; exit 1; }

if [ "${#EXCL[@]}" -gt 0 ]; then
  for e in "${EXCL[@]}"; do
    git -C "$DEST" rm -r -q -- "$e" \
      || { echo "PRUNE FAILED for $e — do not root a reviewer here"; exit 1; }
    # Verify the prune rather than trusting the exit status: this is the whole
    # point of the script, and a partial delete looks like a clean one.
    [ ! -e "$DEST/$e" ] && [ -z "$(git -C "$DEST" ls-files -- "$e")" ] \
      || { echo "PRUNE INCOMPLETE for $e — do not root a reviewer here"; exit 1; }
  done
fi

echo "$DEST"
exit 0
