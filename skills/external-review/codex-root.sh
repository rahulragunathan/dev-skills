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
# Copies regular-file blobs at HEAD, then prunes literal root-relative paths.
# Omits symlinks and submodules and reports them on stderr. Archive attributes
# cannot remove or rewrite the exported blobs. The source tree is never edited.
#
# No .git is exported, so the reviewer needs --skip-git-repo-check. The export
# has no history: inline phase diffs and plans in the prompt. This is a scope
# aid, not read isolation from the original repository or the rest of the host.
# Remove the export with rm -r <dir> when the review is finished.
#
# Exit 0 when the pruned root is ready; exit 1 on any refusal or failure.

set -uo pipefail

# stdout is exclusively the successful root path, including in command substitution.
exec 3>&1 1>&2

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

REPO="$(git rev-parse --show-toplevel)" || { echo "NOT A GIT REPOSITORY"; exit 1; }
case "$DEST" in /*) ;; *) DEST="$PWD/$DEST" ;; esac
cd -- "$REPO" || exit 1
if [ "${#EXCL[@]}" -gt 0 ]; then
  for e in "${EXCL[@]}"; do
    case "/$e/" in *'/../'*|*'/./'*|*'//'*) echo "EXCLUSION MUST BE A ROOT-RELATIVE PATH: $e"; exit 1 ;; esac
  done
fi
[ -e "$DEST" ] && { echo "TARGET EXISTS: $DEST"; exit 1; }

# The worktree is built from HEAD, so uncommitted work is not in it. Reviewing
# HEAD while the tree says something else is worse than not reviewing.
TREE_STATE="$(git status --porcelain)" \
  || { echo "CANNOT READ TREE STATUS — refusing"; exit 1; }
[ -z "$TREE_STATE" ] \
  || { echo "TREE IS DIRTY — commit first; the reviewer only ever sees HEAD"; exit 1; }

# Every exclusion must match something tracked. A typo would otherwise leave the
# area in place while the caller believes it was pruned — which is the failure
# this script exists to prevent, arriving by a different route.
if [ "${#EXCL[@]}" -gt 0 ]; then
  for e in "${EXCL[@]}"; do
    [ -n "$(git --literal-pathspecs ls-files -- "$e")" ] || { echo "EXCLUSION MATCHES NOTHING: $e"; exit 1; }
  done
fi

mkdir -p "$DEST" || { echo "CANNOT CREATE $DEST"; exit 1; }
# Git discovers parent repositories, including through symlinked parents.
DEST="$(cd -- "$DEST" && pwd -P)" || exit 1
if git -C "$DEST" rev-parse --git-dir >/dev/null 2>&1; then
  echo "ENCLOSING REPOSITORY — refusing to export here"
  rmdir "$DEST" 2>/dev/null || true
  exit 1
fi
# Read committed blobs directly: archive attributes may omit or rewrite files.
# Links are omitted so none can lead back into excluded content or another tree.
python3 - "$DEST" <<'PYCODE' || { echo "EXPORT FAILED — do not root a reviewer here"; exit 1; }
import os, pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1])
records = subprocess.check_output(['git', 'ls-tree', '-rz', '--full-tree', 'HEAD']).split(b'\0')
for record in filter(None, records):
    metadata, rawpath = record.split(b'\t', 1)
    mode, kind, oid = metadata.split()
    path = pathlib.Path(os.fsdecode(rawpath))
    if path.is_absolute() or any(p in ('.', '..', '.git') for p in path.parts):
        sys.exit('unsafe export path')
    if mode not in (b'100644', b'100755'):
        print('OMITTED non-regular tracked path: ' + str(path), file=sys.stderr)
        continue
    target = root / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(subprocess.check_output(['git', 'cat-file', 'blob', oid]))
    target.chmod(0o755 if mode == b'100755' else 0o644)
PYCODE

# An export must carry no repository. If one appeared, the excluded paths would
# be readable through it and the exclusion would be filesystem theatre.
[ ! -e "$DEST/.git" ] || { echo "EXPORT CONTAINS .git — refusing"; exit 1; }

if [ "${#EXCL[@]}" -gt 0 ]; then
  for e in "${EXCL[@]}"; do
    # A tracked link/submodule, or a directory containing only those, was
    # already omitted. Repeated or overlapping exclusions are also satisfied.
    if [ -e "$DEST/$e" ]; then
      rm -r "$DEST/$e" || { echo "PRUNE FAILED for $e — do not root a reviewer here"; exit 1; }
    fi
    # Verify the prune rather than trusting the exit status: this is the whole
    # point of the script, and a partial delete looks like a clean one.
    [ ! -e "$DEST/$e" ] \
      || { echo "PRUNE INCOMPLETE for $e — do not root a reviewer here"; exit 1; }
  done
fi

echo "$DEST" >&3
exit 0
