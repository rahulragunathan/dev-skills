#!/usr/bin/env bash
# capture.sh — build the review bundle that leaves this machine.
#
# Usage:
#   capture.sh [--exclude <pathspec>]... phase <outdir> <base-ref>
#   capture.sh [--exclude <pathspec>]... repo  <outdir>
#   capture.sh [--exclude <pathspec>]... plan  <outdir> <plan-file>
#
#   phase  committed changes since <base-ref>, plus untracked files
#   repo   every tracked file
#   plan   one named file, which may live outside the repo
#
# --exclude drops a path or directory from the bundle and counts it as
# excluded. Use it for an area that is out of scope for the review — a
# component being rebuilt, or one with its own phase. Naming the exclusion in
# the review prompt does not remove the files; this does. Repeatable, and
# refused in plan mode, which captures a single named file.
#
# Writes into <outdir>:
#   bundle.txt    what is sent to the reviewer
#   withheld.txt  NUL-delimited "<path>\t(<reason>)" records
#   manifest.z    NUL-delimited paths selected after exclusions — what capture reads
#   all.z         NUL-delimited paths in scope before exclusions
#   counts.txt    the reconciled count line, also printed
#
# Exit 0 only when a complete bundle was built. Any enumeration or read failure
# exits 1 and the bundle must not be sent.

set -uo pipefail

EXTRA_EXCL=()
while [ "${1:-}" = "--exclude" ]; do
  [ -n "${2:-}" ] || { echo "--exclude needs a pathspec"; exit 1; }
  EXTRA_EXCL+=(":(top,exclude)$2")
  shift 2
done

MODE="${1:?usage: capture.sh [--exclude <path>]... <phase|repo|plan> <outdir> [base-ref|plan-file]}"
OUT="${2:?missing output directory}"
ARG="${3:-}"

# Paths from git are relative to the repository root, not to the working
# directory, so every path the script resolves is anchored there too. Outside a
# repository — plan mode — the working directory is the only root there is.
REPO_TOP="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$REPO_TOP" ]; then
  REPO_PHYS="$(cd -- "$REPO_TOP" && pwd -P)" || { echo "CANNOT RESOLVE REPO ROOT"; exit 1; }
else
  REPO_PHYS="$(pwd -P)"
fi
ALLOWED_ROOTS=("$REPO_PHYS")

# True when physical directory $1 is at or below physical root $2.
under_root() { case "$1/" in "$2"/*|"$2"/) return 0 ;; esac; return 1; }

mkdir -p "$OUT" || { echo "CANNOT CREATE OUTPUT DIR"; exit 1; }
OUT_PHYS="$(cd -- "$OUT" && pwd -P)" || { echo "CANNOT RESOLVE OUTPUT DIR"; exit 1; }

# The untracked sweep lists whatever is untracked. A bundle written inside the
# working tree is listed, appended to itself, and counted as scope it was never
# meant to cover, which drives the excluded count negative.
if [ -n "$REPO_TOP" ] && under_root "$OUT_PHYS" "$REPO_PHYS"; then
  echo "OUTPUT DIRECTORY IS INSIDE THE REPOSITORY: $OUT"
  echo "write the bundle to a scratchpad outside the working tree"
  exit 1
fi

BUNDLE="$OUT/bundle.txt";  : > "$BUNDLE"
WITHHELD="$OUT/withheld.txt"; : > "$WITHHELD"

# Every pattern carries `top` so it anchors at the repository root rather than
# at the working directory, and `icase` so a capitalised name cannot pass.
EXCL=(':(top,exclude,icase)*.env' ':(top,exclude,icase)*.env.*' ':(top,exclude,icase)*.pem'
      ':(top,exclude,icase)*.key' ':(top,exclude,icase)*.p12' ':(top,exclude,icase)*.pfx'
      ':(top,exclude,icase)*.crt' ':(top,exclude,icase)*id_rsa*' ':(top,exclude,icase)*id_ed25519*'
      ':(top,exclude,icase)*credentials*' ':(top,exclude,icase)*.netrc' ':(top,exclude,icase)*.npmrc'
      ':(top,exclude,icase)*.sqlite' ':(top,exclude,icase)*.sqlite3')
if [ "${#EXTRA_EXCL[@]}" -gt 0 ]; then
  EXCL+=("${EXTRA_EXCL[@]}")
fi
ALL=':(top)'

withhold() { printf '%s\t(%s)\0' "$1" "$2" >> "$WITHHELD"; }

# The same policy the pathspecs express, as a name test. git pathspecs filter
# the repo and phase manifests, but plan mode names one file directly and never
# builds a manifest, so that path had no credential filter at all — the one
# mode whose input a human types was the one with nothing checking it.
credential_shaped() {
  local base; base="$(basename -- "$1" | tr '[:upper:]' '[:lower:]')"
  case "$base" in
    *.env|*.env.*|.env|*.pem|*.key|*.p12|*.pfx|*.crt|*id_rsa*|*id_ed25519*) return 0 ;;
    *credentials*|*.netrc|*.npmrc|*.sqlite|*.sqlite3) return 0 ;;
  esac
  return 1
}

# 0 binary, 1 text. Any other status from the detector is a failure, not text:
# `if perl ...; then` treated a missing perl (127) as text, and the bytes it was
# meant to keep out went into the bundle.
is_binary() {
  perl -e 'exit(-B $ARGV[0] ? 0 : 1)' "$1"
  case "$?" in
    0) return 0 ;;
    1) return 1 ;;
    *) echo "BINARY DETECTOR FAILED on $1 — do not send this bundle"; exit 1 ;;
  esac
}

# Containment. Sets CAPTURE_PATH and answers one question: may this path be
# read at all? It applies to every path capture handles, however its content
# reaches the bundle, so a new escape check belongs here rather than at a call
# site.
#   0  contained
#   1  refused, and the reason is recorded
#   2  the parent does not resolve, which the caller decides how to read
contained() {
  local f="$1" d ok=0 r
  case "$f" in /*) CAPTURE_PATH="$f" ;; *) CAPTURE_PATH="$REPO_PHYS/$f" ;; esac
  d="$(cd -- "$(dirname -- "$CAPTURE_PATH")" 2>/dev/null && pwd -P)" || return 2
  for r in "${ALLOWED_ROOTS[@]}"; do
    under_root "$d" "$r" && ok=1
  done
  [ "$ok" = 1 ] || { withhold "$f" "parent outside every allowed root"; return 1; }
  [ -L "$CAPTURE_PATH" ] && { withhold "$f" "symlink"; return 1; }
  return 0
}

# Containment plus the checks that are about the copy in the worktree. Use it
# wherever capture reads that copy: an append, or a tracked path the diff still
# has on disk.
classify() {
  local f="$1" rc
  contained "$f"; rc=$?
  [ "$rc" = 2 ] && { withhold "$f" "unreadable parent"; return 1; }
  [ "$rc" = 0 ] || return 1
  [ -e "$CAPTURE_PATH" ] || { withhold "$f" "tracked, absent from the tree"; return 1; }
  [ -f "$CAPTURE_PATH" ] || { withhold "$f" "not a regular file"; return 1; }
  credential_shaped "$f" && { withhold "$f" "credential-shaped name"; return 1; }
  is_binary "$CAPTURE_PATH" && { withhold "$f" "binary"; return 1; }
  return 0
}

capture() {
  local f="$1" label="${2:-}"
  classify "$f" || return 0
  printf '\n===== %s%s =====\n' "$label" "$f" >> "$BUNDLE"
  cat -- "$CAPTURE_PATH" >> "$BUNDLE" || { withhold "$f" "read failed"; return 0; }
  printf '%s\0' "$f" >> "$OUT/captured.z"
  return 0
}

: > "$OUT/captured.z"

case "$MODE" in
  repo)
    git ls-files -z --full-name -- "$ALL" > "$OUT/all.z" \
      || { echo "LS-FILES FAILED — do not send this bundle"; exit 1; }
    git ls-files -z --full-name -- "$ALL" "${EXCL[@]}" > "$OUT/manifest.z" \
      || { echo "MANIFEST FAILED — do not send this bundle"; exit 1; }
    while IFS= read -r -d '' f; do capture "$f" ""; done < "$OUT/manifest.z"
    ;;
  phase)
    [ -n "$ARG" ] || { echo "phase mode needs a base ref"; exit 1; }
    git diff --no-renames -z --name-only "$ARG"...HEAD -- "$ALL" > "$OUT/tracked-all.z" \
      && git ls-files --others --exclude-standard -z --full-name -- "$ALL" > "$OUT/untracked-all.z" \
      && cat "$OUT/tracked-all.z" "$OUT/untracked-all.z" > "$OUT/all.z" \
      || { echo "ENUMERATION FAILED — do not send this bundle"; exit 1; }
    git diff --no-renames -z --name-only "$ARG"...HEAD -- "$ALL" "${EXCL[@]}" > "$OUT/tracked.z" \
      && git ls-files --others --exclude-standard -z --full-name -- "$ALL" "${EXCL[@]}" > "$OUT/untracked.z" \
      && cat "$OUT/tracked.z" "$OUT/untracked.z" > "$OUT/manifest.z" \
      || { echo "MANIFEST FAILED — do not send this bundle"; exit 1; }
    git diff --raw --no-abbrev --no-renames -z "$ARG"...HEAD -- "$ALL" "${EXCL[@]}" \
      > "$OUT/tracked-raw.z" || { echo "ENUMERATION FAILED — do not send this bundle"; exit 1; }
    DIFF_PATHS=("$ALL")
    while IFS= read -r -d '' metadata && IFS= read -r -d '' f; do
      read -r old_mode new_mode old_blob new_blob change <<< "${metadata#:}"
      allowed=1
      if [ "$new_mode" = 000000 ]; then
        # A deletion has no copy left in the worktree, so the worktree half of
        # classification cannot apply — running it withholds every deletion,
        # and a review that cannot see deletions cannot see what was dropped.
        # Containment still applies: what a deletion carries is the old blob,
        # and rc 2 here means the deletion removed the directory too, which
        # leaves nothing to escape through.
        contained "$f"
        if [ "$?" = 1 ]; then allowed=0; fi
      else
        classify "$f" || allowed=0
      fi
      if [ "$allowed" = 1 ]; then
        # A patch can expose either committed blob, even when the worktree is text.
        for side in "$old_mode:$old_blob" "$new_mode:$new_blob"; do
          mode="${side%%:*}"; blob="${side#*:}"
          [ "$mode" = 000000 ] && continue
          if [ "$mode" != 100644 ] && [ "$mode" != 100755 ]; then
            withhold "$f" "not a regular file in diff"; allowed=0; break
          fi
          git cat-file blob "$blob" > "$OUT/diff-blob" \
            || { echo "BLOB READ FAILED — do not send this bundle"; exit 1; }
          if is_binary "$OUT/diff-blob"; then
            withhold "$f" "binary in diff"; allowed=0; break
          fi
        done
      fi
      if [ "$allowed" = 1 ]; then
        printf '%s\0' "$f" >> "$OUT/captured.z"
      else
        DIFF_PATHS+=(":(top,exclude,literal)$f")
      fi
    done < "$OUT/tracked-raw.z"
    rm -f "$OUT/diff-blob"
    git -c diff.external= diff --no-renames --no-textconv --no-ext-diff "$ARG"...HEAD \
      -- "${DIFF_PATHS[@]}" "${EXCL[@]}" >> "$BUNDLE" \
      || { echo "DIFF FAILED — do not send this bundle"; exit 1; }
    while IFS= read -r -d '' f; do
      capture "$f" "UNTRACKED FILE: "
    done < "$OUT/untracked.z"
    ;;
  plan)
    [ -n "$ARG" ] || { echo "plan mode needs a plan file"; exit 1; }
    # plan mode captures the one file it is given, so there is nothing for an
    # exclusion to remove. Accepting the flag silently would let a caller
    # believe a scope exclusion was applied when none was.
    [ "${#EXTRA_EXCL[@]}" -eq 0 ] || { echo "--exclude does not apply in plan mode"; exit 1; }
    pdir="$(cd -- "$(dirname -- "$ARG")" 2>/dev/null && pwd -P)" \
      || { echo "PLAN DIRECTORY UNREADABLE"; exit 1; }
    # Resolve to an absolute path here, so a relative plan argument is read from
    # the working directory that named it rather than from the repository root.
    ARG="$pdir/$(basename -- "$ARG")"
    ALLOWED_ROOTS+=("$pdir")
    printf '%s\0' "$ARG" > "$OUT/all.z"
    cp "$OUT/all.z" "$OUT/manifest.z"
    capture "$ARG" "PLAN: "
    ;;
  *) echo "unknown mode: $MODE"; exit 1 ;;
esac

nul() { tr -cd '\0' < "$1" | wc -c | tr -d ' '; }
TOTAL="$(nul "$OUT/all.z")"
SELECTED="$(nul "$OUT/manifest.z")"
WITHHELD_N="$(nul "$WITHHELD")"
CAPTURED="$(nul "$OUT/captured.z")"

# A read failure means an incomplete bundle. Search the NUL records with a
# NUL-aware reader: `grep` in some environments injects -I and ignores input it
# considers binary, which NUL-delimited records are.
if tr '\0' '\n' < "$WITHHELD" | grep -q '(read failed)'; then
  echo "A FILE FAILED TO READ — do not send this bundle"; exit 1
fi

printf 'bundle contains %s of %s files; %s withheld, %s excluded\n' \
  "$CAPTURED" "$TOTAL" "$WITHHELD_N" "$(( TOTAL - SELECTED ))" | tee "$OUT/counts.txt"
exit 0
