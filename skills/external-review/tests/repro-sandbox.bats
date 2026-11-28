#!/usr/bin/env bats

setup() {
  helper="$BATS_TEST_DIRNAME/../repro-sandbox.sh"
  fixture="$BATS_TEST_TMPDIR/fixture with spaces"
  mkdir "$fixture"
}

require_backend() {
  if [[ "$(uname -s)" = Darwin ]]; then
    command -v sandbox-exec >/dev/null || skip "sandbox-exec is absent"
    sandbox-exec -p '(version 1)(allow default)' /usr/bin/true ||
      skip "sandbox-exec cannot start inside the host sandbox"
  else
    command -v docker >/dev/null || skip "Docker is absent"
    docker run --rm --pull=never --network none python:3-alpine true ||
      skip "Docker cannot start the local python:3-alpine image"
  fi
}

@test "repro: a child cannot read or write a sibling file" {
  # Fails if the child can read the outside marker or create a sibling.
  require_backend
  printf 'outside\n' > "$BATS_TEST_TMPDIR/marker"
  run "$helper" "$fixture" -- sh -c '
    if cat "$1/marker"; then exit 10; fi
    if (echo changed > "$1/written"); then exit 11; fi
    echo confined
  ' sh "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *confined* && "$output" != *$'\noutside'* ]] || false
  [ ! -e "$BATS_TEST_TMPDIR/written" ]
}

@test "repro: a child can work inside the fixture" {
  # Fails if an ordinary fixture command cannot read, write or use its scratch HOME.
  require_backend
  echo inside > "$fixture/input"
  SYNTHETIC_CREDENTIAL=canary run "$helper" "$fixture" -- sh -ec '
    test -z "${SYNTHETIC_CREDENTIAL+x}"
    cat input > "$HOME/output"
    cat "$HOME/output"
  '
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = inside ]
}

@test "repro: a child cannot connect to a live host loopback listener" {
  # Fails if the sandbox can reach a port proven reachable by an unsandboxed client.
  require_backend
  python3 - "$BATS_TEST_TMPDIR/port" 3>&- <<'PY' &
import pathlib, socket, sys, time
with socket.socket() as listener:
    listener.bind(("127.0.0.1", 0))
    listener.listen()
    pathlib.Path(sys.argv[1]).write_text(str(listener.getsockname()[1]))
    time.sleep(30)
PY
  listener_pid=$!
  for i in {1..100}; do [ -s "$BATS_TEST_TMPDIR/port" ] && break; sleep .05; done
  port="$(cat "$BATS_TEST_TMPDIR/port")"
  client='import socket,sys; socket.create_connection(("127.0.0.1", int(sys.argv[1])), 2).close()'
  python3 -c "$client" "$port" || false
  run "$helper" "$fixture" -- python3 -c '
import socket, sys
try:
    socket.create_connection(("127.0.0.1", int(sys.argv[1])), 2).close()
except OSError:
    print("connection denied")
' "$port"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "connection denied" ]
}

teardown() {
  if [ -n "${listener_pid:-}" ]; then kill "$listener_pid" 2>/dev/null || true; wait "$listener_pid" || true; fi
}

@test "repro: no backend exits three without running the command" {
  # Fails if an unavailable sandbox runs the command or gives no reading fallback.
  mkdir "$BATS_TEST_TMPDIR/bin"
  ln -s "$(command -v uname)" "$BATS_TEST_TMPDIR/bin/uname"
  PATH="$BATS_TEST_TMPDIR/bin" run /bin/sh "$helper" "$fixture" -- /usr/bin/touch "$fixture/ran"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$output" = "NO SANDBOX — verify by reading" ] || false
  [ ! -e "$fixture/ran" ]
}

@test "repro: Docker launches the requested argv with only the fixture mounted" {
  # Fails if Docker gets network access, another bind mount or a shell-expanded command.
  fake="$BATS_TEST_TMPDIR/bin"
  mkdir "$fake"
  printf '#!/bin/sh\necho Linux\n' > "$fake/uname"
  cat > "$fake/docker" <<'SH'
#!/bin/sh
printf '%s\n' "$@" > "$DOCKER_ARGS"
SH
  chmod +x "$fake/uname" "$fake/docker"
  export DOCKER_ARGS="$BATS_TEST_TMPDIR/args"
  PATH="$fake:$PATH" run "$helper" "$fixture" -- printf '%s' 'two words'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -s "$DOCKER_ARGS" ] || false
  python3 - "$DOCKER_ARGS" "$fixture" <<'PY'
from pathlib import Path
import sys
args = Path(sys.argv[1]).read_text().splitlines()
fixture = Path(sys.argv[2]).resolve()
assert args[0] == "run" and args[-3:] == ["printf", "%s", "two words"], args
assert args[args.index("--network") + 1] == "none", args
mounts = [args[i+1] for i, arg in enumerate(args) if arg in ("--mount", "-v", "--volume")]
assert mounts == [f"{fixture}:{fixture}:rw"], mounts
assert args[args.index("--workdir") + 1] == str(fixture), args
PY
}

@test "repro: macOS passes a deny-default profile and a clean environment" {
  # Fails if the launcher grants host access, inherits credentials or parses the command as sandbox options.
  fake="$BATS_TEST_TMPDIR/bin"
  mkdir "$fake"
  printf '#!/bin/sh\necho Darwin\n' > "$fake/uname"
  cat > "$fake/sandbox-exec" <<'SH'
#!/bin/sh
set -eu
[ "$1" = -D ] && [ "$2" = "FIXTURE=$(pwd -P)" ] && [ "$3" = -p ] || exit 1
[ "$HOME" = "$(pwd -P)" ] && [ -z "${SYNTHETIC_CREDENTIAL+x}" ] || exit 2
printf '%s\n' "$4" > profile
[ "$5" = -- ] || exit 2
shift 5
printf '%s\n' "$@" > command
SH
  chmod +x "$fake/uname" "$fake/sandbox-exec"
  PATH="$fake:$PATH" SYNTHETIC_CREDENTIAL=canary run "$helper" "$fixture" -- echo 'two words'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -s "$fixture/profile" ] || false
  grep -Fq '(deny default)' "$fixture/profile" || false
  grep -Fq '(allow file-write* (subpath (param "FIXTURE")))' "$fixture/profile" || false
  ! grep -Eq '\(allow (default|network)' "$fixture/profile" || false
  [ "$(cat "$fixture/command")" = $'echo\ntwo words' ]
}
