#!/usr/bin/env bash
# install-standards.sh — reconcile a CLAUDE.md to the canonical standards block.
#
# Implements claude-setup step 3. That procedure was prose only, and it corrupted
# the live ~/.claude/CLAUDE.md once: a truncated marker quoted in the prose was
# matched instead of the real delimiter, and everything to end of file went with
# it. Prose cannot be tested; this can.
#
# Usage:
#   install-standards.sh [--adopt] <canonical-block-file> [target]
#     target defaults to $HOME/.claude/CLAUDE.md
#
# The canonical file must contain the whole block, opening marker line through
# closing marker line, and nothing else.
#
# Exit 0  block installed or already current
# Exit 1  refused — the target is in a state this script will not guess at
#
# It refuses rather than repairs when marker counts disagree. A file with one
# opening marker and no closing marker is ambiguous: the user may have deleted
# the closing line by hand, and every automatic reading of that loses content.

set -uo pipefail

OPEN='<!-- >>> localclaude standards'
CLOSE='<!-- <<< localclaude standards'
# Whole-line patterns. `^$OPEN` matches any line that merely BEGINS with the
# marker text, so prose at column zero counted as a marker and, paired with a
# real closing line, made the installer replace content that was not its own.
OPEN_RE='^<!-- >>> localclaude standards.*>>> -->$'
CLOSE_RE='^<!-- <<< localclaude standards <<< -->$'

ADOPT=0
if [ "${1:-}" = --adopt ]; then ADOPT=1; shift; fi

CANON="${1:?usage: install-standards.sh [--adopt] <canonical-block-file> [target]}"
TARGET="${2:-$HOME/.claude/CLAUDE.md}"

[ -f "$CANON" ] || { echo "CANONICAL BLOCK NOT FOUND: $CANON"; exit 1; }

block="$(cat "$CANON")" || { echo "CANNOT READ CANONICAL BLOCK"; exit 1; }
case "$block" in
  "$OPEN"*) : ;;
  *) echo "CANONICAL BLOCK DOES NOT START WITH THE OPENING MARKER"; exit 1 ;;
esac
printf '%s' "$block" | head -n 1 | grep -qE "$OPEN_RE" \
  || { echo "CANONICAL BLOCK'S OPENING MARKER IS NOT A COMPLETE MARKER LINE"; exit 1; }
printf '%s' "$block" | tail -n 1 | grep -qE "$CLOSE_RE" \
  || { echo "CANONICAL BLOCK DOES NOT END WITH THE CLOSING MARKER"; exit 1; }

# Reject malformed input before either the create or reconcile path can write.
[ "$(grep -cE "$OPEN_RE" "$CANON")" = 1 ] &&
  [ "$(grep -cE "$CLOSE_RE" "$CANON")" = 1 ] \
  || { echo "CANONICAL BLOCK MUST CONTAIN EXACTLY ONE MARKER PAIR"; exit 1; }

mkdir -p "$(dirname "$TARGET")" || { echo "CANNOT CREATE TARGET DIRECTORY"; exit 1; }

# Test the link before testing existence. A dangling symlink satisfies `! -e`,
# so the create path followed it and wrote through to its target — outside the
# config directory entirely.
[ -L "$TARGET" ] && { echo "TARGET IS A SYMLINK — refusing to write through it"; exit 1; }

if [ ! -e "$TARGET" ]; then
  printf '%s\n' "$block" > "$TARGET" || { echo "WRITE FAILED"; exit 1; }
  echo "created"
else
  [ -f "$TARGET" ] || { echo "TARGET IS NOT A REGULAR FILE"; exit 1; }

  n_open="$(grep -cE "$OPEN_RE" "$TARGET" || true)"
  n_close="$(grep -cE "$CLOSE_RE" "$TARGET" || true)"

  if [ "$n_open" != "$n_close" ]; then
    echo "MARKER MISMATCH in $TARGET — $n_open opening, $n_close closing."
    echo "Repair the block by hand; refusing to edit."
    exit 1
  fi
  if [ "$n_open" -gt 1 ]; then
    # Two managed blocks means an earlier run appended where it should have
    # replaced. Which one is authoritative is not knowable from here, and
    # picking one silently discards the other.
    echo "TWO MANAGED BLOCKS in $TARGET — cannot tell which is current."
    echo "Delete the stale one by hand; refusing to edit."
    exit 1
  fi

  TMP="$(mktemp "${TMPDIR:-/tmp}/claudemd.XXXXXX")" || { echo "MKTEMP FAILED"; exit 1; }
  trap 'rm -f "$TMP"' EXIT

  if [ "$n_open" = "0" ]; then
    # Unmarked bytes carry no ownership information, whatever their headings.
    [ "$ADOPT" = 1 ] || { echo "UNMARKED FILE (personal or LEGACY) — review and reconcile it, then use --adopt; target unchanged" >&2; exit 1; }
    python3 - "$TARGET" <<'PYCODE' || { echo "UNREADABLE TARGET — target unchanged" >&2; exit 1; }
import pathlib, sys
pathlib.Path(sys.argv[1]).read_text()
PYCODE
    { cat "$TARGET" && printf '\n' && cat "$CANON"; } > "$TMP" \
      || { echo "ASSEMBLE FAILED"; exit 1; }
  else
    # Replace from the LAST opening marker to the first closing marker after it.
    # Assemble with head/tail/cat: the block is multi-line and cannot travel
    # through `awk -v`, which silently truncates at the first newline.
    last_open="$(grep -nE "$OPEN_RE" "$TARGET" | tail -n 1 | cut -d: -f1)"
    close_line="$(awk -v s="$last_open" -v c="$CLOSE_RE" \
      'NR >= s && $0 ~ c { print NR; exit }' "$TARGET")"
    [ -n "$close_line" ] \
      || { echo "NO CLOSING MARKER AFTER THE LAST OPENING MARKER — refusing"; exit 1; }
    # Every read must succeed; a successful tail cannot excuse a failed prefix.
    { if [ "$last_open" -gt 1 ]; then
        head -n "$((last_open - 1))" "$TARGET" || exit 1
      fi
      cat "$CANON" && tail -n +"$((close_line + 1))" "$TARGET"; } > "$TMP" \
      || { echo "ASSEMBLE FAILED"; exit 1; }
  fi

  # Verify the CANDIDATE before it replaces anything. Verifying after the move
  # is how a bad slice destroys the file it was meant to update: the check fires,
  # and the damage is already done.
  v_open="$(grep -cE "$OPEN_RE" "$TMP" || true)"
  v_close="$(grep -cE "$CLOSE_RE" "$TMP" || true)"
  [ "$v_open" = "1" ] && [ "$v_close" = "1" ] \
    || { echo "CANDIDATE REJECTED — $v_open opening, $v_close closing; $TARGET untouched"; exit 1; }
  diff -q <(awk -v o="$OPEN_RE" -v c="$CLOSE_RE" \
      '$0 ~ o{p=1} p{print} $0 ~ c&&p{exit}' "$TMP") "$CANON" >/dev/null \
    || { echo "CANDIDATE REJECTED — block differs from canonical; $TARGET untouched"; exit 1; }

  [ ! -L "$TARGET.localclaude.bak" ] &&
    { [ ! -e "$TARGET.localclaude.bak" ] || [ -f "$TARGET.localclaude.bak" ]; } \
    || { echo "BACKUP IS NOT A REGULAR FILE — refusing"; exit 1; }
  # Replace the backup inode instead of writing through a possible hard link.
  BACKUP_TMP="$(mktemp "${TARGET}.backup.XXXXXX")" || { echo "MKTEMP FAILED"; exit 1; }
  trap 'rm -f "$BACKUP_TMP" "$TMP"' EXIT
  cp -p "$TARGET" "$BACKUP_TMP" && mv "$BACKUP_TMP" "$TARGET.localclaude.bak" \
    || { echo "BACKUP FAILED"; exit 1; }
  trap 'rm -f "$TMP"' EXIT

  mv "$TMP" "$TARGET" || { echo "REPLACE FAILED"; exit 1; }
  trap - EXIT
  echo "reconciled"
fi

# Final check on whatever path ran, including the create path above.
v_open="$(grep -cE "$OPEN_RE" "$TARGET" || true)"
v_close="$(grep -cE "$CLOSE_RE" "$TARGET" || true)"
[ "$v_open" = "1" ] && [ "$v_close" = "1" ] \
  || { echo "VERIFY FAILED — $v_open opening, $v_close closing after write"; exit 1; }
exit 0
