#!/usr/bin/env bats
#
# The standards installer writes the file loaded into every session on every
# machine, and it has corrupted that file once. Every test names the condition
# that turns it red.
#
# The canary is USER-CONTENT: text the user keeps outside the managed block. If
# it ever disappears, the installer took more than its own block.

setup() {
  export TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP/home"
  export TARGET="$HOME/.claude/CLAUDE.md"
  mkdir -p "$HOME/.claude"
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export SCRIPT="$(dirname "$here")/install-standards.sh"
  export CANON="$TEST_TMP/canon.md"
  cat > "$CANON" <<'EOF'
<!-- >>> localclaude standards v1 >>> -->
# Global standards

## Shell commands

- Always double-quote paths.
<!-- <<< localclaude standards <<< -->
EOF
}

teardown() { cd /; [ -n "${TEST_TMP:-}" ] && chmod -R u+w "$TEST_TMP" 2>/dev/null; rm -rf "$TEST_TMP"; }

canary_survives() { grep -q 'USER-CONTENT' "$TARGET"; }
markers_balanced() {
  [ "$(grep -c '^<!-- >>> localclaude standards' "$TARGET")" -eq 1 ] &&
  [ "$(grep -c '^<!-- <<< localclaude standards' "$TARGET")" -eq 1 ]
}

@test "missing file: creates it with exactly one marked block" {
  run bash "$SCRIPT" "$CANON" "$TARGET"
  [ "$status" -eq 0 ]
  markers_balanced
  grep -q 'Always double-quote paths' "$TARGET"
}

@test "markers present: replaces the block and keeps content on both sides" {
  # Red if the slice takes from the first line or runs to end of file.
  { echo "USER-CONTENT above"; echo
    echo "<!-- >>> localclaude standards v0 >>> -->"
    echo "stale body"
    echo "<!-- <<< localclaude standards <<< -->"
    echo; echo "USER-CONTENT below"; } > "$TARGET"

  run bash "$SCRIPT" "$CANON" "$TARGET"
  [ "$status" -eq 0 ]
  markers_balanced
  grep -q 'USER-CONTENT above' "$TARGET"
  grep -q 'USER-CONTENT below' "$TARGET"
  ! grep -q 'stale body' "$TARGET"
}

@test "no markers: appends without disturbing existing content" {
  printf 'USER-CONTENT only\n' > "$TARGET"
  run bash "$SCRIPT" "$CANON" "$TARGET"
  [ "$status" -eq 0 ]
  canary_survives
  markers_balanced
}

@test "closing marker deleted by hand: refuses and changes nothing" {
  # THE regression. Red if the installer edits a file whose markers do not
  # balance: every automatic reading of that file loses the content below.
  { echo "<!-- >>> localclaude standards v0 >>> -->"
    echo "stale body"
    echo "USER-CONTENT below the missing close"; } > "$TARGET"
  local before; before="$(cat "$TARGET")"

  run bash "$SCRIPT" "$CANON" "$TARGET"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MARKER MISMATCH"* ]]
  [ "$(cat "$TARGET")" = "$before" ]
  canary_survives
}

@test "opening marker deleted by hand: refuses and changes nothing" {
  { echo "USER-CONTENT above"; echo "stale body"
    echo "<!-- <<< localclaude standards <<< -->"; } > "$TARGET"
  local before; before="$(cat "$TARGET")"

  run bash "$SCRIPT" "$CANON" "$TARGET"
  [ "$status" -eq 1 ]
  [ "$(cat "$TARGET")" = "$before" ]
}

@test "prose quoting a marker prefix is not mistaken for a delimiter" {
  # Red if the match is a prefix search rather than whole-line: this file's own
  # prose discusses the markers, which is how the live file was corrupted.
  { echo "USER-CONTENT above"
    echo "See the \`<!-- >>> localclaude standards\` marker for details."
    echo "<!-- >>> localclaude standards v0 >>> -->"
    echo "stale body"
    echo "<!-- <<< localclaude standards <<< -->"
    echo "USER-CONTENT below"; } > "$TARGET"

  run bash "$SCRIPT" "$CANON" "$TARGET"
  [ "$status" -eq 0 ]
  markers_balanced
  canary_survives
  grep -q 'See the' "$TARGET"      # the prose line is untouched
  ! grep -q 'stale body' "$TARGET"
}

@test "a backup is written before any modification" {
  { echo "USER-CONTENT"; echo "<!-- >>> localclaude standards v0 >>> -->"
    echo "stale"; echo "<!-- <<< localclaude standards <<< -->"; } > "$TARGET"
  run bash "$SCRIPT" "$CANON" "$TARGET"
  [ "$status" -eq 0 ]
  [ -f "$TARGET.localclaude.bak" ]
  grep -q 'stale' "$TARGET.localclaude.bak"
}

@test "re-running is idempotent" {
  run bash "$SCRIPT" "$CANON" "$TARGET"; [ "$status" -eq 0 ]
  local first; first="$(cat "$TARGET")"
  run bash "$SCRIPT" "$CANON" "$TARGET"; [ "$status" -eq 0 ]
  [ "$(cat "$TARGET")" = "$first" ]
  markers_balanced
}

@test "a symlinked target is refused, not written through" {
  # Red if the installer follows a link and rewrites whatever it points at.
  printf 'SECRET-CANARY\n' > "$TEST_TMP/real.md"
  ln -s "$TEST_TMP/real.md" "$TARGET"
  run bash "$SCRIPT" "$CANON" "$TARGET"
  [ "$status" -eq 1 ]
  grep -q 'SECRET-CANARY' "$TEST_TMP/real.md"
  ! grep -q 'localclaude standards' "$TEST_TMP/real.md"
}

@test "a canonical file missing its closing marker is refused" {
  printf '<!-- >>> localclaude standards v1 >>> -->\nbody\n' > "$CANON"
  run bash "$SCRIPT" "$CANON" "$TARGET"
  [ "$status" -eq 1 ]
  [ ! -e "$TARGET" ]
}

@test "two managed blocks: refuses and changes nothing" {
  # The procedure used to say "take the last opening marker" while also requiring
  # exactly one of each afterwards. Both cannot hold. Two blocks means an earlier
  # run appended instead of replacing, and picking one silently drops the other.
  { echo "<!-- >>> localclaude standards v0 >>> -->"
    echo "USER-CONTENT first block"
    echo "<!-- <<< localclaude standards <<< -->"
    echo "<!-- >>> localclaude standards v0 >>> -->"
    echo "second block"
    echo "<!-- <<< localclaude standards <<< -->"; } > "$TARGET"
  local before; before="$(cat "$TARGET")"

  run bash "$SCRIPT" "$CANON" "$TARGET"
  [ "$status" -eq 1 ]
  [[ "$output" == *"TWO MANAGED BLOCKS"* ]]
  [ "$(cat "$TARGET")" = "$before" ]
}
