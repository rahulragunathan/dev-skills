# Shared fixture for the capture suite.
#
# Every test gets its own throwaway git repo plus an "outside" directory that
# sits beyond the repo root. The outside directory is what a symlink escape
# would reach, so its contents are the canary: if SECRET-CANARY ever appears in
# a bundle, capture let something out that it should have withheld.

setup_capture_env() {
  export TEST_TMP="$(mktemp -d)"
  export OUTSIDE="$TEST_TMP/outside"
  export REPO="$TEST_TMP/repo"
  export OUT="$TEST_TMP/out"
  mkdir -p "$OUTSIDE" "$REPO" "$OUT"
  printf 'SECRET-CANARY\n' > "$OUTSIDE/secret.txt"

  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export CAPTURE="$(dirname "$here")/capture.sh"

  cd "$REPO" || return 1
  git init -q -b main .
  git config user.email t@example.invalid
  git config user.name  Test
  printf 'hello\n' > kept.txt
  git add -A && git commit -qm base
}

teardown_capture_env() {
  cd / || true
  [ -n "${TEST_TMP:-}" ] && chmod -R u+w "$TEST_TMP" 2>/dev/null
  [ -n "${TEST_TMP:-}" ] && rm -rf "$TEST_TMP"
}

# Count NUL-delimited records in a file.
nulcount() { tr -cd '\0' < "$1" | wc -c | tr -d ' '; }

# True when the withheld list names $1 with reason substring $2.
withheld_for() {
  tr '\0' '\n' < "$OUT/withheld.txt" | grep -qF "$1" && \
  tr '\0' '\n' < "$OUT/withheld.txt" | grep -F "$1" | grep -qF "$2"
}
