#!/usr/bin/env bats
#
# The Gemini ladder: which models the external review tries, in order.
# Every test names the condition that turns it red.

setup() {
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export LADDER="$(dirname "$here")/gemini-ladder.py"
  export FIXTURE="$here/fixtures/agy-models-2026-11-20.txt"
}

# rank <model id>...: the ladder for a list of ids, one per line.
rank() { printf '%s\n' "$@" | python3 "$LADDER"; }

@test "today's list gives argon-high, neon-xhigh, neon-high" {
  # Fails if orchestrators, effort or family are ranked wrongly on the real 2026-11-20 list.
  run python3 "$LADDER" < "$FIXTURE"
  [ "$status" -eq 0 ] || false
  [ "$output" = "gemini-4-argon-high gemini-4-neon-xhigh gemini-4-neon-high" ]
}

@test "only orchestrators gives an empty ladder" {
  # Fails if an orchestrator model is offered as a reviewer.
  run rank gemini-pro-orchestrator-neon gemini-pro-orchestrator-g1-pro claude-opus-5-5-high
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "carbon outranks argon" {
  # Fails if the family order Carbon > Argon > Neon > Hydrogen is not applied.
  run rank gemini-4-argon-high gemini-4-carbon-high
  [ "$output" = "gemini-4-carbon-high gemini-4-argon-high" ]
}

@test "an unlisted family ranks below hydrogen" {
  # Fails if a family missing from the list outranks a listed one.
  run rank gemini-4-boron-xhigh gemini-4-hydrogen-high
  [ "$output" = "gemini-4-hydrogen-high gemini-4-boron-xhigh" ]
}

@test "a newer version outranks an older one" {
  # Fails if versions compare as text or floats, or if effort outranks version.
  run rank gemini-3.9-pro-high gemini-3.10-pro-high
  [ "$output" = "gemini-3.10-pro-high gemini-3.9-pro-high" ] || false
  run rank gemini-3.9-pro-high gemini-4-neon-medium
  [ "$output" = "gemini-4-neon-medium gemini-3.9-pro-high" ]
}

@test "a full model outranks flash at the same version" {
  # Fails if a light tier is ranked as a full model.
  run rank gemini-4-flash-xhigh gemini-4-neon-high
  [ "$output" = "gemini-4-neon-high gemini-4-flash-xhigh" ]
}

@test "medium ranks below every review-grade rung of the same version and tier" {
  # Fails if a stronger family's medium outranks a weaker family's high.
  run rank gemini-4-argon-medium gemini-4-hydrogen-high
  [ "$output" = "gemini-4-hydrogen-high gemini-4-argon-medium" ]
}

@test "an unknown suffix ranks below medium" {
  # Fails if an unrecognised effort suffix is treated as review grade.
  run rank gemini-4-neon-minimal gemini-4-neon-medium
  [ "$output" = "gemini-4-neon-medium gemini-4-neon-minimal" ]
}

@test "an unparsable version does not crash" {
  # Fails if a model id without a numeric version raises instead of ranking last.
  run rank gemini-exp-neon-high gemini-4-neon-high
  [ "$status" -eq 0 ] || false
  [ "$output" = "gemini-4-neon-high gemini-exp-neon-high" ]
}

@test "a model with no effort suffix ranks below medium" {
  # Fails if a model whose effort agy cannot be told is ranked as review grade.
  run rank gemini-4-neon gemini-4-neon-medium
  [ "$output" = "gemini-4-neon-medium gemini-4-neon" ]
}

@test "a point release outranks its major version" {
  # Fails if version tuples compare by length, so 4 sorts above 4.1.
  run rank gemini-4-neon-high gemini-4.1-neon-high
  [ "$output" = "gemini-4.1-neon-high gemini-4-neon-high" ]
}
