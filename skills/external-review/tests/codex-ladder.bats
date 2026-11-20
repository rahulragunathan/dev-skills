#!/usr/bin/env bats
#
# The Codex ladder: which models the external review tries, in order.
# Every test names the condition that turns it red.

setup() {
  export TEST_TMP="$(mktemp -d)"
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export LADDER="$(dirname "$here")/codex-ladder.py"
  export FIXTURE="$here/fixtures/codex-models-2026-11-20.json"
}

teardown() { rm -rf "$TEST_TMP"; }

# cache <slug>:<priority>[:<visibility>]...: a cache whose models support low to ultra.
cache() {
  python3 - "$TEST_TMP/cache.json" "$@" <<'PY'
import json, sys
models = []
for spec in sys.argv[2:]:
    slug, priority, *rest = spec.split(":")
    models.append({"slug": slug, "priority": int(priority), "visibility": rest[0] if rest else "list",
                   "supported_reasoning_levels": [{"effort": e} for e in ("low", "high", "max", "ultra")]})
json.dump({"models": models}, open(sys.argv[1], "w"))
PY
}

@test "today's cache gives 6.2-astra, 6.2-sol, 6.1-sol" {
  # Fails if the cache's priority field, OpenAI's default pick, decides the order.
  run python3 "$LADDER" "$FIXTURE"
  [ "$status" -eq 0 ] || false
  [ "$output" = "gpt-6.2-astra:max gpt-6.2-sol:max gpt-6.1-sol:max" ]
}

@test "a hidden model never appears" {
  # Fails if a model the cache hides is offered as a reviewer.
  cache gpt-reserve:1:hide gpt-6-luna:2
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-6-luna:max" ]
}

@test "an unlisted family ranks below luna" {
  # Fails if a family missing from the list outranks a listed one.
  cache gpt-6-nova:1 gpt-6-luna:2
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-6-luna:max gpt-6-nova:max" ]
}

@test "a newer version outranks a stronger family" {
  # Fails if family is ranked before version.
  cache gpt-6.2-astra:1 gpt-7-sol:2
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-7-sol:max gpt-6.2-astra:max" ]
}

@test "ultra is never chosen" {
  # Fails if the highest listed effort, ultra, which delegates work, is picked.
  cache gpt-6-sol:1
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-6-sol:max" ]
}

@test "a missing cache exits 1 with no output" {
  # Fails if a missing cache prints a ladder or exits 0, which the skill reads as rungs.
  run python3 "$LADDER" "$TEST_TMP/none.json"
  [ "$status" -eq 1 ] || false
  [ -z "$output" ]
}

@test "a malformed model entry exits 1 with no output" {
  # Fails if an entry without a slug, or one that is not an object, crashes with a traceback.
  printf '{"models": [{"visibility": "list"}, "oops"]}' > "$TEST_TMP/bad.json"
  run python3 "$LADDER" "$TEST_TMP/bad.json"
  [ "$status" -eq 1 ] || false
  [ -z "$output" ]
}
