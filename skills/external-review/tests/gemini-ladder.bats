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

@test "today's list gives neon-high, hydrogen-high, argon-high" {
  # Fails if orchestrators, effort or family are ranked wrongly on the real 2026-11-20 list.
  run python3 "$LADDER" < "$FIXTURE"
  [ "$status" -eq 0 ] || false
  [ "$output" = "gemini-4-neon-high gemini-4-hydrogen-high gemini-4-argon-high" ]
}

@test "the model class comes first, then its high variant" {
  # Fails if effort outranks the model: a weaker family's high would come before a stronger one.
  run rank gemini-4-hydrogen-high gemini-4-carbon-medium gemini-4-carbon-xhigh gemini-4-carbon-high
  [ "$output" = "gemini-4-carbon-high gemini-4-hydrogen-high" ] || false
  # A class without a high variant is skipped: xhigh and medium only when the user asks.
  run rank gemini-4-hydrogen-high gemini-4-carbon-medium gemini-4-carbon-xhigh
  [ "$output" = "gemini-4-hydrogen-high" ]
}

@test "low, minimal and none are never offered" {
  # Fails if an effort below medium reaches the ladder.
  run rank gemini-4-neon-low gemini-4-neon-minimal gemini-4-neon-none
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "the rank key itself orders otherwise tied classes by name" {
  # Fails if the final class-name key is removed: set order then decides, by hash seed.
  run python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("g", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.rank("gemini-4-boron") < m.rank("gemini-4-cobalt"))' "$LADDER"
  [ "$output" = "True" ]
}

@test "a tie is broken by model id, not by input order" {
  # Fails if two unlisted families at one grade keep agy's print order.
  for order in "cobalt boron zinc" "zinc cobalt boron" "boron zinc cobalt"; do
    set -- $order
    run rank "gemini-4-$1-high" "gemini-4-$2-high" "gemini-4-$3-high"
    [ "$output" = "gemini-4-boron-high gemini-4-cobalt-high gemini-4-zinc-high" ] || false
  done
}

@test "a repeated id takes one rung" {
  # Fails if duplicates are cut to three before they are made distinct.
  run rank gemini-4-neon-high gemini-4-neon-high gemini-4-neon-high gemini-4-hydrogen-high
  [ "$output" = "gemini-4-neon-high gemini-4-hydrogen-high" ]
}

@test "only orchestrators gives an empty ladder" {
  # Fails if an orchestrator model is offered as a reviewer.
  run rank gemini-pro-orchestrator-neon gemini-pro-orchestrator-g1-pro claude-opus-5-5-high
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "carbon outranks argon" {
  # Fails if the family order Carbon > Neon > Hydrogen, then the rest, is not applied.
  run rank gemini-4-argon-high gemini-4-carbon-high
  [ "$output" = "gemini-4-carbon-high gemini-4-argon-high" ]
}

@test "an unlisted family ranks below hydrogen" {
  # Fails if a family missing from the list outranks a listed one.
  run rank gemini-4-boron-high gemini-4-hydrogen-high
  [ "$output" = "gemini-4-hydrogen-high gemini-4-boron-high" ]
}

@test "a newer version outranks an older one" {
  # Fails if versions compare as text or floats, or if effort outranks version.
  run rank gemini-3.9-pro-high gemini-3.10-pro-high
  [ "$output" = "gemini-3.10-pro-high gemini-3.9-pro-high" ] || false
  run rank gemini-3.9-pro-high gemini-4-neon-high
  [ "$output" = "gemini-4-neon-high gemini-3.9-pro-high" ]
}

@test "family comes before version" {
  # Fails if a newer version of a weaker family outranks an older version of a stronger one.
  run rank gemini-4.1-hydrogen-high gemini-4-carbon-high
  [ "$output" = "gemini-4-carbon-high gemini-4.1-hydrogen-high" ]
}

@test "flash and lite get no tier rule: they rank as unlisted families, newest first" {
  # Fails if the old light-tier rule still ranks a flash model below another unlisted one of
  # the same version; without it, the class name decides.
  run rank gemini-4-zinc-high gemini-4-flash-high
  [ "$output" = "gemini-4-flash-high gemini-4-zinc-high" ] || false
  run rank gemini-3.8-flash-high gemini-4-hydrogen-high
  [ "$output" = "gemini-4-hydrogen-high gemini-3.8-flash-high" ]
}

@test "one rung per model class, at high when it has one" {
  # Fails if a class fills several rungs, or if xhigh or medium is picked over high.
  run rank gemini-4-neon-medium gemini-4-neon-xhigh gemini-4-neon-high gemini-4-argon-medium
  [ "$output" = "gemini-4-neon-high" ]
}

@test "an unknown suffix names its own class" {
  # Fails if a variant name is read as an effort and merged into the base class.
  run rank gemini-4-neon-preview gemini-4-neon-high
  [ "$output" = "gemini-4-neon-high gemini-4-neon-preview" ]
}

@test "an unparsable version does not crash" {
  # Fails if a model id without a numeric version raises instead of ranking last.
  run rank gemini-exp-neon-high gemini-4-neon-high
  [ "$status" -eq 0 ] || false
  [ "$output" = "gemini-4-neon-high gemini-exp-neon-high" ]
}

@test "a suffix-less id is that class's high rung when no -high exists" {
  # Fails if a suffix-less id, which the loop runs with --effort high, loses to medium or xhigh.
  run rank gemini-4-neon-medium gemini-4-neon gemini-4-neon-xhigh
  [ "$output" = "gemini-4-neon" ] || false
  run rank gemini-4-neon-medium gemini-4-neon-xhigh
  [ -z "$output" ] || false
  run rank gemini-4-neon gemini-4-neon-high
  [ "$output" = "gemini-4-neon-high" ]
}

@test "a point release outranks its major version" {
  # Fails if version tuples compare by length, so 4 sorts above 4.1.
  run rank gemini-4-neon-high gemini-4.1-neon-high
  [ "$output" = "gemini-4.1-neon-high gemini-4-neon-high" ]
}

@test "an ultra id is never offered" {
  # Fails if an -ultra id, which delegates work, reaches the ladder.
  run rank gemini-4-neon-ultra
  [ "$status" -eq 0 ] || false
  [ -z "$output" ]
}

@test "an effort the user asks for picks that variant instead of high" {
  # Fails if --effort is ignored, or a class without that variant is offered.
  run bash -c 'printf "%s\n" gemini-4-neon-high gemini-4-neon-xhigh gemini-4-argon-high | python3 "$LADDER" --effort xhigh'
  [ "$output" = "gemini-4-neon-xhigh" ]
}

@test "a -max id is an effort variant of its model, offered only when asked" {
  # Fails if -max is read as a separate model that takes a second rung at the default (F-131).
  run rank gemini-4-neon-high gemini-4-neon-max gemini-4-hydrogen-high
  [ "$output" = "gemini-4-neon-high gemini-4-hydrogen-high" ] || false
  run bash -c 'printf "%s\n" gemini-4-neon-high gemini-4-neon-max | python3 "$LADDER" --effort max'
  [ "$output" = "gemini-4-neon-max" ]
}

@test "argon, superseded, ranks after hydrogen" {
  # Fails if Argon keeps a place in the family order above Neon or Hydrogen (the user's order:
  # Carbon > Neon > Hydrogen).
  run rank gemini-4-argon-high gemini-4-hydrogen-high gemini-4-neon-high gemini-4-carbon-high
  [ "$output" = "gemini-4-carbon-high gemini-4-neon-high gemini-4-hydrogen-high" ] || false
  # With a slot free, Argon sits after Hydrogen, among the unlisted lines, not above them.
  run rank gemini-4-zinc-high gemini-4-argon-high gemini-4-hydrogen-high
  [ "$output" = "gemini-4-hydrogen-high gemini-4-argon-high gemini-4-zinc-high" ]
}

@test "an id holding a shell pattern character is never offered" {
  # Fails if an id such as gemini-4-*-high reaches the loops, whose word list a shell could expand.
  run rank 'gemini-4-*-high' 'gemini-4-ne?n-high' 'gemini-4-[x]-high' gemini-4-hydrogen-high
  [ "$status" -eq 0 ] || false
  [ "$output" = "gemini-4-hydrogen-high" ]
}
