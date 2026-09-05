setup_mlx_env() {
  export TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP/home"
  export LOCAL_MODELS_DIR="$TEST_TMP/models"
  export HF_HOME="$LOCAL_MODELS_DIR"              # isolate the HF cache to the temp dir
  mkdir -p "$HOME/.claude" "$LOCAL_MODELS_DIR"
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export SCRIPT_DIR="$(dirname "$here")"          # skills/claude-toggle-backend
  export PATH="$here/fakes:$PATH"                 # fakes win over real binaries
  export MLX_READY_TRIES=2                        # fast readiness loop in tests
}
teardown_mlx_env() {
  # Reap any daemon a test left running (via the tracked pid) so bats never
  # hangs on a surviving background process, regardless of which subcommands exist.
  local pf="$HOME/.claude/mlx-server.pid"
  [ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null || true
  rm -rf "$TEST_TMP"
}
make_mlx_repo() {                                 # $1 = HF repo id (org/name) -> cached repo dir
  local d="$HF_HOME/hub/models--${1//\//--}/snapshots/deadbeef"
  mkdir -p "$d"; echo '{}' > "$d/config.json"; echo "$d"
}
