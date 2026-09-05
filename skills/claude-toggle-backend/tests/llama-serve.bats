load helpers/setup
setup()    { setup_mlx_env; }
teardown() { teardown_mlx_env; }

# Regression: under `set -euo pipefail`, pgrep exiting 1 on no-match must not
# trip set -e and make `status` exit non-zero (which also breaks toggle.sh status).
@test "status returns 0 and reports stopped when nothing running" {
  run bash "$SCRIPT_DIR/llama-serve.sh" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"stopped"* ]]
}

@test "port errors when not running" {
  run bash "$SCRIPT_DIR/llama-serve.sh" port
  [ "$status" -ne 0 ]
}

@test "resolve_model: newest flat *.gguf wins" {
  : > "$LOCAL_MODELS_DIR/a.gguf"; sleep 1; : > "$LOCAL_MODELS_DIR/b.gguf"
  run bash "$SCRIPT_DIR/llama-serve.sh" __resolve
  [ "$status" -eq 0 ]
  [[ "$output" == "$LOCAL_MODELS_DIR/b.gguf" ]]
}

@test "resolve_model: ignores GGUF nested in HF hub cache (flat convention)" {
  mkdir -p "$LOCAL_MODELS_DIR/hub/models--x--y/snapshots/deadbeef"
  : > "$LOCAL_MODELS_DIR/hub/models--x--y/snapshots/deadbeef/model.gguf"
  run bash "$SCRIPT_DIR/llama-serve.sh" __resolve
  [ "$status" -eq 0 ]
  [ -z "$output" ]                       # nested cache GGUF is not selected
}
