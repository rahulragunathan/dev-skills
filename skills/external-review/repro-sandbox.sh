#!/bin/sh
# Run synthetic reviewer steps with the fixture as their only writable host directory.
set -eu
if [ "$#" -lt 3 ] || [ "$2" != -- ]; then
  echo 'Usage: repro-sandbox.sh FIXTURE -- CMD [ARG...]' >&2
  exit 2
fi
fixture=$(CDPATH= cd -P -- "$1" && pwd -P)
[ "$fixture" != / ] || { echo 'Use a disposable fixture directory' >&2; exit 2; }
shift 2
cd "$fixture"

unavailable() {
  echo 'NO SANDBOX — verify by reading' >&2
  exit 3
}

case "$(uname -s)" in
  Darwin)
    sandbox=$(command -v sandbox-exec) || unavailable
    profile='(version 1)
      (deny default)
      (allow process-fork process-exec sysctl-read)
      (allow file-read* (subpath (param "FIXTURE"))
        (subpath "/usr") (subpath "/bin") (subpath "/System")
        (subpath "/Library") (subpath "/opt/homebrew") (subpath "/private/etc"))
      (allow file-write* (subpath (param "FIXTURE")))'
    run_confined() {
      /usr/bin/env -i HOME="$fixture" TMPDIR="$fixture" PATH=/usr/bin:/bin:/opt/homebrew/bin \
        "$sandbox" -D "FIXTURE=$fixture" -p "$profile" -- "$@" </dev/null
    }
    run_confined /usr/bin/true || unavailable
    run_confined "$@"
    ;;
  *)
    command -v docker >/dev/null || unavailable
    # Docker's volume syntax treats a colon as the start of another field.
    case "$fixture" in *:*) echo 'Use a fixture path without a colon' >&2; exit 2 ;; esac
    run_confined() {
      docker run --rm --pull=never --network none --read-only --cap-drop=ALL \
        --security-opt=no-new-privileges --user "$(id -u):$(id -g)" \
        --volume "$fixture:$fixture:rw" --workdir "$fixture" \
        --env HOME="$fixture" --env TMPDIR="$fixture" python:3-alpine "$@"
    }
    run_confined true || unavailable
    run_confined "$@"
    ;;
esac
