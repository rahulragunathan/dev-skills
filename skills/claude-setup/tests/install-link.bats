#!/usr/bin/env bats
setup() {
  T="$(mktemp -d)"
  SCRIPT="$BATS_TEST_DIRNAME/../install-link.sh"
  mkdir "$T/source" "$T/link"
  echo original > "$T/link/keep"
}
teardown() { rm -rf "$T"; }
@test "missing source leaves the existing setup directory enabled" {
  run bash "$SCRIPT" "$T/missing" "$T/link"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SOURCE"* ]]
  [ -f "$T/link/keep" ]
  [ ! -e "$T/link.local.bak" ]
}
@test "link failure restores the original setup directory" {
  mkdir "$T/bin"
  printf '#!/bin/sh\nexit 1\n' > "$T/bin/ln"
  chmod +x "$T/bin/ln"
  PATH="$T/bin:$PATH" run bash "$SCRIPT" "$T/source" "$T/link"
  [ "$status" -eq 1 ]
  [[ "$output" == *"LINK FAILED"* ]]
  [ -f "$T/link/keep" ]
}
@test "successful link keeps original backup and resolves to physical source" {
  run bash "$SCRIPT" "$T/source" "$T/link"
  [ "$status" -eq 0 ]
  [ -L "$T/link" ]
  [ -f "$T/link.local.bak/keep" ]
  [ "$(cd "$T/link" && pwd -P)" = "$(cd "$T/source" && pwd -P)" ]
}
@test "rerunning a correct link succeeds and retains the original backup" {
  bash "$SCRIPT" "$T/source" "$T/link"
  run bash "$SCRIPT" "$T/source" "$T/link"
  [ "$status" -eq 0 ]
  [ -f "$T/link.local.bak/keep" ]
}
