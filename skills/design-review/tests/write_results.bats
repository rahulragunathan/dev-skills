#!/usr/bin/env bats
#
# The results writer. Every test names the condition that turns it red.
#
# Both incidents this replaces looked like success: the edit reported the right
# number of matches and wrote the wrong column. So the tests assert on the
# columns that were NOT named, which is where the damage landed.

setup() {
  export TEST_TMP="$(mktemp -d)"
  export SCEN="$TEST_TMP/s01.md"
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export W="$here/write_results.py"
  cat > "$SCEN" <<'EOF'
# S01 — Test

## Results

| Run | Model ID | Date | Responsibility | Notes | Prompt revision | Condition revision | Skill git SHA · content | Evidence status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Without skill | `m` | 2026-09-07 | Rule not needed here | baseline note | `p1` · `h1` | `c1` · `h2` | not loaded | Current |
| With skill (round 2) | `m` | 2026-09-07 | **Rule works** | old note | `p1` · `h1` | `c1` · `h2` | `s1` · `h3` | Current |
EOF
}

teardown() { rm -rf "$TEST_TMP"; }

cell() { python3 "$W" "$SCEN" --show | awk -v r="$1" -v c="$2" '
  $0 == "Run: " r {found=1} found && $0 ~ "^" c ": " {sub("^" c ": ",""); print; exit}'; }

@test "writes the named column and nothing else" {
  run python3 "$W" "$SCEN" --run "With skill (round 2)" --set "Notes=new note"
  [ "$status" -eq 0 ]
  [ "$(cell 'With skill (round 2)' 'Notes')" = "new note" ]
  # the columns that were clobbered by hand both times
  [ "$(cell 'With skill (round 2)' 'Condition revision')" = '`c1` · `h2`' ]
  [ "$(cell 'With skill (round 2)' 'Skill git SHA · content')" = '`s1` · `h3`' ]
}

@test "an unknown column name is refused, and the file is untouched" {
  # Red if columns are addressed positionally: a wrong name then silently lands
  # in whatever cell that index happens to be.
  local before; before="$(cat "$SCEN")"
  run python3 "$W" "$SCEN" --run "With skill (round 2)" --set "Notez=oops"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such column"* ]]
  [ "$(cat "$SCEN")" = "$before" ]
}

@test "a value containing a pipe is refused rather than splitting the row" {
  local before; before="$(cat "$SCEN")"
  run python3 "$W" "$SCEN" --run "With skill (round 2)" --set "Notes=a | b"
  [ "$status" -eq 1 ]
  [ "$(cat "$SCEN")" = "$before" ]
}

@test "an unmatched Run value is refused rather than writing the wrong row" {
  local before; before="$(cat "$SCEN")"
  run python3 "$W" "$SCEN" --run "With skill (round 9)" --set "Notes=x"
  [ "$status" -eq 1 ]
  [ "$(cat "$SCEN")" = "$before" ]
}

@test "the baseline row is untouched when the with-skill row is written" {
  run python3 "$W" "$SCEN" --run "With skill (round 2)" --set "Evidence status=Expired"
  [ "$status" -eq 0 ]
  [ "$(cell 'Without skill' 'Evidence status')" = "Current" ]
  [ "$(cell 'Without skill' 'Notes')" = "baseline note" ]
}

@test "several columns update together and the rest keep their bytes" {
  run python3 "$W" "$SCEN" --run "With skill (round 2)" \
      --set "Run=With skill (round 3)" --set "Date=2026-09-08" \
      --set "Skill git SHA · content=\`s2\` · \`h9\`"
  [ "$status" -eq 0 ]
  [ "$(cell 'With skill (round 3)' 'Date')" = "2026-09-08" ]
  [ "$(cell 'With skill (round 3)' 'Condition revision')" = '`c1` · `h2`' ]
  [ "$(cell 'With skill (round 3)' 'Notes')" = "old note" ]
}

@test "naming the same column twice is refused" {
  local before; before="$(cat "$SCEN")"
  run python3 "$W" "$SCEN" --run "With skill (round 2)" --set "Notes=a" --set "Notes=b"
  [ "$status" -eq 1 ]
  [ "$(cat "$SCEN")" = "$before" ]
}

@test "a file with no Results table is refused" {
  printf '# nothing here\n' > "$TEST_TMP/empty.md"
  run python3 "$W" "$TEST_TMP/empty.md" --run "x" --set "Notes=y"
  [ "$status" -eq 1 ]
}


@test "add: appends a row and leaves every existing row byte-identical" {
  local before; before="$(grep '^| With skill (round 2)' "$SCEN")"
  run python3 "$W" "$SCEN" --add --run "With skill (round 4)" \
      --set "Model ID=\`claude-opus-5\`" --set "Date=2026-09-09" \
      --set "Responsibility=**Rule ineffective**"
  [ "$status" -eq 0 ]
  [ "$(grep '^| With skill (round 2)' "$SCEN")" = "$before" ]
  [ "$(cell 'With skill (round 4)' 'Responsibility')" = "**Rule ineffective**" ]
  [ "$(cell 'Without skill' 'Notes')" = "baseline note" ]
}

@test "add: a duplicate Run value is refused" {
  # Red if add appends blindly: two rows sharing a Run value make every later
  # update ambiguous, and the writer would silently pick the first.
  local before; before="$(cat "$SCEN")"
  run python3 "$W" "$SCEN" --add --run "With skill (round 2)" --set "Date=2026-09-09"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already"* ]]
  [ "$(cat "$SCEN")" = "$before" ]
}

@test "add: an unknown column is refused and nothing is written" {
  local before; before="$(cat "$SCEN")"
  run python3 "$W" "$SCEN" --add --run "With skill (round 4)" --set "Reviewer=someone"
  [ "$status" -ne 0 ]
  [ "$(cat "$SCEN")" = "$before" ]
}

@test "add: columns not named are left empty rather than guessed at" {
  run python3 "$W" "$SCEN" --add --run "With skill (round 4)" --set "Date=2026-09-09"
  [ "$status" -eq 0 ]
  [ "$(cell 'With skill (round 4)' 'Date')" = "2026-09-09" ]
  [ "$(cell 'With skill (round 4)' 'Notes')" = "" ]
}

@test "a value containing a newline is refused" {
  # Red while only '|' is rejected. A newline splits one row into two, and the
  # second half is not a table row at all, so the table silently loses its shape.
  local before; before="$(cat "$SCEN")"
  run python3 "$W" "$SCEN" --run "With skill (round 2)" --set "Notes=line one
line two"
  [ "$status" -ne 0 ]
  [ "$(cat "$SCEN")" = "$before" ]
}

@test "renaming a row onto an existing Run value is refused" {
  # Red while --set can write the Run column freely: two rows sharing a Run
  # value make every later update ambiguous, and the writer picks the first.
  local before; before="$(cat "$SCEN")"
  run python3 "$W" "$SCEN" --run "With skill (round 2)" --set "Run=Without skill"
  [ "$status" -ne 0 ]
  [ "$(cat "$SCEN")" = "$before" ]
}
