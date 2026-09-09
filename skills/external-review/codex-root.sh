#!/usr/bin/env bash
# codex-root.sh — build a pruned copy of HEAD for a repo-rooted reviewer.
#
# Usage:
#   codex-root.sh <dir> [--exclude <path>]...
#
# Codex reads the tree it is rooted at, so a bundle exclusion does not reach it
# and neither does a sentence in the prompt telling it what to ignore. This
# exports HEAD to <dir> and deletes the excluded paths from the export.
#
# It exports rather than adding a worktree, and that is the whole point. A
# linked worktree shares the repository's object database, so `git show
# HEAD:<excluded path>` returned the file whose copy had just been deleted:
# absent from the filesystem, still fully readable. An export carries no `.git`,
# so there is nothing left to read the excluded paths out of.
#
# The cost is history: the reviewer gets the tree at HEAD and no log. Say so in
# the prompt rather than offering history the export does not have.
#
# The real working tree is never modified. Remove the export with `rm -r <dir>`.
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

mkdir -p "$DEST" || { echo "CANNOT CREATE $DEST"; exit 1; }
git archive --format=tar HEAD | tar -x -C "$DEST" \
  || { echo "EXPORT FAILED — do not root a reviewer here"; exit 1; }

# An export must carry no repository. If one appeared, the excluded paths would
# be readable through it and the exclusion would be filesystem theatre.
[ ! -e "$DEST/.git" ] || { echo "EXPORT CONTAINS .git — refusing"; exit 1; }

if [ "${#EXCL[@]}" -gt 0 ]; then
  for e in "${EXCL[@]}"; do
    [ -e "$DEST/$e" ] || { echo "EXCLUDED PATH NOT IN THE EXPORT: $e"; exit 1; }
    rm -r "$DEST/$e" || { echo "PRUNE FAILED for $e — do not root a reviewer here"; exit 1; }
    # Verify the prune rather than trusting the exit status: this is the whole
    # point of the script, and a partial delete looks like a clean one.
    [ ! -e "$DEST/$e" ] \
      || { echo "PRUNE INCOMPLETE for $e — do not root a reviewer here"; exit 1; }
  done
fi

echo "$DEST"
exit 0
