load helpers/setup
setup()    { setup_mlx_env; }
teardown() { teardown_mlx_env; }

REPO="mlx-community/Qwen2.5-Coder-14B-Instruct-4bit"

@test "start errors on non-Apple-Silicon" {
  FAKE_UNAME_M=x86_64 run bash "$SCRIPT_DIR/mlx-serve.sh" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"Apple Silicon"* ]]
}

@test "start errors with install hint when vllm-mlx missing" {
  MLX_BIN="" run bash "$SCRIPT_DIR/mlx-serve.sh" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"uv tool install vllm-mlx"* ]]
}

@test "resolve_model: echoes the explicit repo id" {
  run bash "$SCRIPT_DIR/mlx-serve.sh" __resolve "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == "$REPO" ]]
}

@test "resolve_model: falls back to last-used repo id" {
  echo "$REPO" > "$HOME/.claude/mlx-last-model"
  run bash "$SCRIPT_DIR/mlx-serve.sh" __resolve
  [ "$status" -eq 0 ]
  [[ "$output" == "$REPO" ]]
}

@test "resolve_model: none is empty" {
  run bash "$SCRIPT_DIR/mlx-serve.sh" __resolve
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pick_port honors MLX_PORT" {
  MLX_PORT=8791 run bash "$SCRIPT_DIR/mlx-serve.sh" __port
  [ "$status" -eq 0 ]; [[ "$output" == "8791" ]]
}

@test "pick_port auto-picks a numeric free port" {
  run bash "$SCRIPT_DIR/mlx-serve.sh" __port
  [ "$status" -eq 0 ]; [[ "$output" =~ ^[0-9]+$ ]]
}

@test "start errors when no repo specified" {
  FAKE_CURL_READY=1 run bash "$SCRIPT_DIR/mlx-serve.sh" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"repo id"* ]]
}

@test "start errors when repo not in HF cache" {
  FAKE_CURL_READY=1 run bash "$SCRIPT_DIR/mlx-serve.sh" start "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not in the HF cache"* ]]
  [[ "$output" == *"hf download $REPO"* ]]
}

@test "start succeeds when repo is cached and server becomes ready" {
  make_mlx_repo "$REPO" >/dev/null
  FAKE_CURL_READY=1 run bash "$SCRIPT_DIR/mlx-serve.sh" start "$REPO"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/mlx-server.pid" ]
  [ "$(cat "$HOME/.claude/mlx-server.model")" = "$REPO" ]
  [ "$(cat "$HOME/.claude/mlx-last-model")" = "$REPO" ]
  kill "$(cat "$HOME/.claude/mlx-server.pid")" 2>/dev/null || true
}

@test "start fails and cleans up when server never ready" {
  make_mlx_repo "$REPO" >/dev/null
  FAKE_CURL_READY=0 MLX_READY_TRIES=2 run bash "$SCRIPT_DIR/mlx-serve.sh" start "$REPO"
  [ "$status" -ne 0 ]
  [ ! -f "$HOME/.claude/mlx-server.pid" ]
}

@test "start fails fast when server crashes on launch" {
  make_mlx_repo "$REPO" >/dev/null
  FAKE_MLX_MODE=crash run bash "$SCRIPT_DIR/mlx-serve.sh" start "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exited during startup"* ]]
}

@test "stop removes state and reports" {
  make_mlx_repo "$REPO" >/dev/null
  FAKE_CURL_READY=1 bash "$SCRIPT_DIR/mlx-serve.sh" start "$REPO"
  run bash "$SCRIPT_DIR/mlx-serve.sh" stop
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.claude/mlx-server.pid" ]
}

@test "status reports stopped when nothing tracked" {
  run bash "$SCRIPT_DIR/mlx-serve.sh" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"stopped"* ]]
}

@test "port errors when not running" {
  run bash "$SCRIPT_DIR/mlx-serve.sh" port
  [ "$status" -ne 0 ]
}

@test "foreground writes state files then execs the server" {
  make_mlx_repo "$REPO" >/dev/null
  bash "$SCRIPT_DIR/mlx-serve.sh" foreground "$REPO" </dev/null >/dev/null 2>&1 3>&- &
  bg=$!
  for _ in $(seq 1 20); do [ -f "$HOME/.claude/mlx-server.model" ] && break; sleep 0.1; done
  [ "$(cat "$HOME/.claude/mlx-server.model")" = "$REPO" ]
  kill "$bg" 2>/dev/null || true
  pkill -f 'sleep 300' 2>/dev/null || true
}
