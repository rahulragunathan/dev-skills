#!/usr/bin/env bash
# capture.sh — build the review bundle that leaves this machine.
#
# Usage:
#   capture.sh phase <outdir> <base-ref>    committed changes since <base-ref>, plus untracked
#   capture.sh repo  <outdir>               every tracked file
#   capture.sh plan  <outdir> <plan-file>   one named file, which may live outside the repo
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

MODE="${1:?usage: capture.sh <phase|repo|plan> <outdir> [base-ref|plan-file]}"
OUT="${2:?missing output directory}"
ARG="${3:-}"

mkdir -p "$OUT" || { echo "CANNOT CREATE OUTPUT DIR"; exit 1; }
BUNDLE="$OUT/bundle.txt";  : > "$BUNDLE"
WITHHELD="$OUT/withheld.txt"; : > "$WITHHELD"

REPO_PHYS="$(pwd -P)"
ALLOWED_ROOTS=("$REPO_PHYS")

EXCL=(':(exclude,icase)*.env' ':(exclude,icase)*.env.*' ':(exclude,icase)*.pem'
      ':(exclude,icase)*.key' ':(exclude,icase)*.p12' ':(exclude,icase)*.pfx'
      ':(exclude,icase)*.crt' ':(exclude,icase)*id_rsa*' ':(exclude,icase)*id_ed25519*'
      ':(exclude,icase)*credentials*' ':(exclude,icase)*.netrc' ':(exclude,icase)*.npmrc'
      ':(exclude,icase)*.sqlite' ':(exclude,icase)*.sqlite3')

withhold() { printf '%s\t(%s)\0' "$1" "$2" >> "$WITHHELD"; }

# Apply the same checks before either a file append or a tracked diff.
classify() {
  local f="$1" d ok=0 r
  case "$f" in /*) CAPTURE_PATH="$f" ;; *) CAPTURE_PATH="./$f" ;; esac
  d="$(cd -- "$(dirname -- "$CAPTURE_PATH")" 2>/dev/null && pwd -P)" || {
    withhold "$f" "unreadable parent"; return 1; }
  for r in "${ALLOWED_ROOTS[@]}"; do
    case "$d/" in "$r"/*|"$r"/) ok=1 ;; esac
  done
  [ "$ok" = 1 ] || { withhold "$f" "parent outside every allowed root"; return 1; }
  [ -L "$CAPTURE_PATH" ] && { withhold "$f" "symlink"; return 1; }
  [ -e "$CAPTURE_PATH" ] || { withhold "$f" "tracked, absent from the tree"; return 1; }
  [ -f "$CAPTURE_PATH" ] || { withhold "$f" "not a regular file"; return 1; }
  if perl -e 'exit(-B $ARGV[0] ? 0 : 1)' "$CAPTURE_PATH"; then
    withhold "$f" "binary"; return 1
  fi
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
    git ls-files -z > "$OUT/all.z" \
      || { echo "LS-FILES FAILED — do not send this bundle"; exit 1; }
    git ls-files -z -- . "${EXCL[@]}" > "$OUT/manifest.z" \
      || { echo "MANIFEST FAILED — do not send this bundle"; exit 1; }
    while IFS= read -r -d '' f; do capture "$f" ""; done < "$OUT/manifest.z"
    ;;
  phase)
    [ -n "$ARG" ] || { echo "phase mode needs a base ref"; exit 1; }
    git diff --no-renames -z --name-only "$ARG"...HEAD > "$OUT/tracked-all.z" \
      && git ls-files --others --exclude-standard -z > "$OUT/untracked-all.z" \
      && cat "$OUT/tracked-all.z" "$OUT/untracked-all.z" > "$OUT/all.z" \
      || { echo "ENUMERATION FAILED — do not send this bundle"; exit 1; }
    git diff --no-renames -z --name-only "$ARG"...HEAD -- . "${EXCL[@]}" > "$OUT/tracked.z" \
      && git ls-files --others --exclude-standard -z -- . "${EXCL[@]}" > "$OUT/untracked.z" \
      && cat "$OUT/tracked.z" "$OUT/untracked.z" > "$OUT/manifest.z" \
      || { echo "MANIFEST FAILED — do not send this bundle"; exit 1; }
    git diff --raw --no-abbrev --no-renames -z "$ARG"...HEAD -- . "${EXCL[@]}" \
      > "$OUT/tracked-raw.z" || { echo "ENUMERATION FAILED — do not send this bundle"; exit 1; }
    DIFF_PATHS=(.)
    while IFS= read -r -d '' metadata && IFS= read -r -d '' f; do
      allowed=1
      classify "$f" || allowed=0
      if [ "$allowed" = 1 ]; then
        read -r old_mode new_mode old_blob new_blob change <<< "${metadata#:}"
        # A patch can expose either committed blob, even when the worktree is text.
        for side in "$old_mode:$old_blob" "$new_mode:$new_blob"; do
          mode="${side%%:*}"; blob="${side#*:}"
          [ "$mode" = 000000 ] && continue
          if [ "$mode" != 100644 ] && [ "$mode" != 100755 ]; then
            withhold "$f" "not a regular file in diff"; allowed=0; break
          fi
          git cat-file blob "$blob" > "$OUT/diff-blob" \
            || { echo "BLOB READ FAILED — do not send this bundle"; exit 1; }
          if perl -e 'exit(-B $ARGV[0] ? 0 : 1)' "$OUT/diff-blob"; then
            withhold "$f" "binary in diff"; allowed=0; break
          fi
        done
      fi
      if [ "$allowed" = 1 ]; then
        printf '%s\0' "$f" >> "$OUT/captured.z"
      else
        DIFF_PATHS+=(":(exclude,literal)$f")
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
    pdir="$(cd -- "$(dirname -- "$ARG")" 2>/dev/null && pwd -P)" \
      || { echo "PLAN DIRECTORY UNREADABLE"; exit 1; }
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
