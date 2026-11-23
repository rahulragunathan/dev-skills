#!/usr/bin/env bats
#
# phase-record.py reads one value from the first table of docs/PHASE_RECORD.md,
# which is this repository's phase. Every test names the condition that turns
# it red.

setup() {
  export PHASE_RECORD="$BATS_TEST_DIRNAME/../phase-record.py"
  export TEST_TMP="$(mktemp -d)"
}

teardown() { rm -rf "$TEST_TMP"; }

# get <key> <record text>: the value phase-record.py reads for <key>.
get() { printf '%b' "$2" | python3 "$PHASE_RECORD" get "$1"; }

TABLE='| Key | Value |\n| --- | --- |\n| `REPO` | `owner/name` |\n| `PR` | 9 |\n| Release | v2.1.0 |\n'

@test "reads a value and strips only enclosing backticks" {
  # Fails if backticks stay on the value, or ones inside it are removed.
  run get REPO "$TABLE"
  [ "$status" -eq 0 ] || false
  [ "$output" = "owner/name" ] || false
  run get Note '| Key | Value |\n| --- | --- |\n| Note | `a` and `b` |\n'
  [ "$output" = '`a` and `b`' ]
}

@test "a first table without the Key | Value header is refused" {
  # Fails if a first table headed otherwise lets a later Key | Value table answer.
  run get PR "| Field | Value |\n| --- | --- |\n| \`PR\` | 5 |\n\n$TABLE"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"Key | Value"* ]]
}

@test "a companion table below the first does not count" {
  # Fails if a key missing from the first table is read from the next one.
  run get Release "| Key | Value |\n| --- | --- |\n| \`PR\` | 9 |\n\n| Key | Value |\n| --- | --- |\n| Release | v1.1.0 |\n"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"Release"* ]]
}

@test "prose holding a pipe before the table is not a table" {
  # Fails if a prose line with a pipe is taken for a malformed first table.
  run get PR "Run a | b to see it.\n\n$TABLE"
  [ "$status" -eq 0 ] || false
  [ "$output" = 9 ]
}

@test "backtick and tilde fenced tables are skipped" {
  # Fails if an example table inside a fence is read as the first table.
  run get PR "\`\`\`\n| Key | Value |\n| --- | --- |\n| \`PR\` | 5 |\n\`\`\`\n~~~~\n| Key | Value |\n| --- | --- |\n| \`PR\` | 6 |\n~~~~\n$TABLE"
  [ "$status" -eq 0 ] || false
  [ "$output" = 9 ]
}

@test "tab-padded cells are trimmed" {
  # Fails if padding around a key or value stops it matching.
  run get PR '| Key | Value |\n| --- | --- |\n|\t`PR`\t|  9  |\n'
  [ "$status" -eq 0 ] || false
  [ "$output" = 9 ]
}

@test "a row with three cells is refused" {
  # Fails if a malformed row is read as a key and a value.
  run get PR '| Key | Value |\n| --- | --- |\n| `PR` | 9 | extra |\n'
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"two cells"* ]]
}

@test "a repeated key is refused" {
  # Fails if the first of two PR rows is taken.
  run get PR '| Key | Value |\n| --- | --- |\n| `PR` | 9 |\n| `PR` | 5 |\n'
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"PR"*"more than once"* ]]
}

@test "a missing key is refused" {
  # Fails if a missing key reads as an empty value with exit 0.
  run get MERGE_METHOD "$TABLE"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"MERGE_METHOD"* ]]
}

@test "no table at all is refused" {
  # Fails if a record with no table answers at all.
  run get PR 'No phase in flight.\n'
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"no table"* ]]
}

# --- external review pass 1 fixes ----------------------------------------------

@test "a first table without leading pipes is the first table" {
  # Fails if a pipe-less table is skipped and a companion table below answers (Codex 11).
  run get PR 'Key | Value\n--- | ---\nPR | 8\n\n| Key | Value |\n| --- | --- |\n| PR | 9 |\n'
  [ "$status" -eq 0 ] || false
  [ "$output" = 8 ]
}

@test "a delimiter row of single hyphens marks a table" {
  # Fails if a GFM table with `| - | - |` is skipped (Gemini 10).
  run get PR '| Key | Value |\n| - | - |\n| PR | 8 |\n\n| Key | Value |\n| --- | --- |\n| PR | 9 |\n'
  [ "$status" -eq 0 ] || false
  [ "$output" = 8 ]
}

@test "an indented code block is not a table, and an inline triple-backtick span opens no fence" {
  # Fails if a four-space example counts as the first table, or ```x``` on one line hides what follows.
  run get PR '    | Key | Value |\n    | --- | --- |\n    | PR | 5 |\n\nUse ```x``` inline.\n\n| Key | Value |\n| --- | --- |\n| PR | 9 |\n'
  [ "$status" -eq 0 ] || false
  [ "$output" = 9 ]
}

@test "a one-column first table is still the first table" {
  # Fails if a table one cell wide is invisible and a later Key | Value table answers (pass 2, Codex 9).
  run get PR '| Note |\n| --- |\n| hello |\n\n| Key | Value |\n| --- | --- |\n| PR | 9 |\n'
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"Key | Value"* ]]
}
