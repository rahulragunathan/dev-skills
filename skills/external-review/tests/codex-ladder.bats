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

# cache <slug>:<priority>[:<visibility>[:<effort,...>]]...: a cache of models.
# Efforts default to low, high, max and ultra.
cache() {
  python3 - "$TEST_TMP/cache.json" "$@" <<'PY'
import json, sys
models = []
for spec in sys.argv[2:]:
    slug, priority, *rest = spec.split(":")
    efforts = rest[1].split(",") if len(rest) > 1 else ("low", "high", "max", "ultra")
    models.append({"slug": slug, "priority": int(priority), "visibility": rest[0] if rest else "list",
                   "supported_reasoning_levels": [{"effort": e} for e in efforts]})
json.dump({"models": models}, open(sys.argv[1], "w"))
PY
}

@test "today's cache gives 6.2-astra, 6.2-sol, 6.1-sol at high" {
  # Fails if the cache's priority field, OpenAI's default pick, decides the order.
  run python3 "$LADDER" "$FIXTURE"
  [ "$status" -eq 0 ] || false
  [ "$output" = "gpt-6.2-astra:high gpt-6.2-sol:high gpt-6.1-sol:high" ]
}

@test "a hidden model never appears" {
  # Fails if a model the cache hides is offered as a reviewer.
  cache gpt-reserve:1:hide gpt-6-luna:2
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-6-luna:high" ]
}

@test "an unlisted family ranks below luna" {
  # Fails if a family missing from the list outranks a listed one.
  cache gpt-6-nova:1 gpt-6-luna:2
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-6-luna:high gpt-6-nova:high" ]
}

@test "a newer version outranks a stronger family" {
  # Fails if family is ranked before version.
  cache gpt-6.2-astra:1 gpt-7-sol:2
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-7-sol:high gpt-6.2-astra:high" ]
}

@test "ultra is never chosen" {
  # Fails if ultra, which delegates work, is picked over a lower supported effort.
  cache gpt-6-sol:1:list:low,ultra gpt-6-luna:2:list:ultra
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "a missing cache exits 1 with no output" {
  # Fails if a missing cache prints a ladder or exits 0, which the skill reads as rungs.
  run python3 "$LADDER" "$TEST_TMP/none.json"
  [ "$status" -eq 1 ] || false
  [ -z "$output" ]
}

@test "an entry without a slug is skipped and the rest still rank" {
  # Fails if one malformed entry crashes the ladder or empties it.
  printf '{"models": [{"visibility": "list"}, {"slug": "gpt-6-sol", "visibility": "list", "supported_reasoning_levels": [{"effort": "high"}]}]}' > "$TEST_TMP/bad.json"
  run python3 "$LADDER" "$TEST_TMP/bad.json"
  [ "$status" -eq 0 ] || false
  [ "$output" = "gpt-6-sol:high" ]
}

@test "an entry that is not an object is skipped and the rest still rank" {
  # Fails if a non-object entry crashes the ladder or empties it.
  printf '{"models": ["oops", {"slug": "gpt-6-sol", "visibility": "list", "supported_reasoning_levels": [{"effort": "high"}]}]}' > "$TEST_TMP/bad.json"
  run python3 "$LADDER" "$TEST_TMP/bad.json"
  [ "$status" -eq 0 ] || false
  [ "$output" = "gpt-6-sol:high" ]
}

@test "a cache without a models list exits 1 with no output" {
  # Fails if a cache of the wrong shape prints a ladder or a traceback.
  printf '{"models": {"slug": "gpt-6-sol"}}' > "$TEST_TMP/bad.json"
  run python3 "$LADDER" "$TEST_TMP/bad.json"
  [ "$status" -eq 1 ] || false
  [ -z "$output" ]
}

@test "high is the default effort, then xhigh, max and medium" {
  # Fails if a rung takes the highest supported effort instead of high first.
  cache gpt-6-sol:1:list:medium,high,xhigh,max gpt-6-terra:2:list:medium,xhigh,max gpt-6-luna:3:list:medium,max
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-6-sol:high gpt-6-terra:xhigh gpt-6-luna:max" ] || false
  cache gpt-6-sol:1:list:low,medium
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-6-sol:medium" ]
}

@test "a model supporting nothing above low gives no rung" {
  # Fails if a below-review effort such as low or none is offered.
  cache gpt-7-sol:1:list:none,minimal,low gpt-6-sol:2
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-6-sol:high" ]
}

@test "terra outranks luna at the same version" {
  # Fails if family is ignored, since the slugs alone sort luna first.
  cache gpt-7-luna:1 gpt-7-terra:2
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-7-terra:high gpt-7-luna:high" ]
}

@test "a date in a slug is not read as its version" {
  # Fails if any numeric word, such as a year, is taken as the model version.
  cache o4-mini-2025-04-16:1 gpt-6.2-sol:2
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-6.2-sol:high o4-mini-2025-04-16:high" ]
}

@test "a repeated slug takes one rung" {
  # Fails if duplicates are cut to three before they are made distinct.
  cache gpt-7-sol:1 gpt-7-sol:2 gpt-7-sol:3 gpt-6-sol:4
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-7-sol:high gpt-6-sol:high" ]
}

@test "a dated slug with no gpt- name is not versioned by its date" {
  # Fails if a year after any name is read as the model version.
  cache o3-2025-04-16:1 gpt-7-sol:2
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-7-sol:high o3-2025-04-16:high" ]
}

@test "one slug listed at several efforts takes one rung, at high" {
  # Fails if repeated entries for one slug fill the ladder at different efforts.
  cache gpt-7-sol:1:list:medium gpt-7-sol:2:list:max gpt-7-sol:3:list:high gpt-6-sol:4
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-7-sol:high gpt-6-sol:high" ]
}

@test "an empty or malformed slug gives no rung" {
  # Fails if an empty slug yields ":high", which the discovery check reads as no ladder.
  cache ":1" "gpt 6:2" gpt-6-sol:3
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-6-sol:high" ]
}

@test "the model class comes first, then its effort" {
  # Fails if effort outranks family, so a weaker family at high beats a stronger one at medium.
  cache gpt-7-sol:1:list:high gpt-7-astra:2:list:low,medium
  run python3 "$LADDER" "$TEST_TMP/cache.json"
  [ "$output" = "gpt-7-astra:medium gpt-7-sol:high" ]
}
