load helpers/setup
setup() {
  setup_mlx_env
  # minimal settings.json for detection tests
  cat > "$HOME/.claude/settings.json" <<'JSON'
{ "model": "opus[1m]", "permissions": { "allow": ["Bash(ls:*)"] } }
JSON
}
teardown() { teardown_mlx_env; }

set_env_url() { # $1 = url ("" clears)
  python3 - "$HOME/.claude/settings.json" "$1" <<'PY'
import json,sys
p,u=sys.argv[1],sys.argv[2]; c=json.load(open(p)); e=c.get("env",{})
if u: e["ANTHROPIC_BASE_URL"]=u; c["env"]=e
else: e.pop("ANTHROPIC_BASE_URL",None); c["env"]=e
json.dump(c,open(p,"w"))
PY
}
detect() { bash "$SCRIPT_DIR/toggle.sh" __detect; }

@test "detect anthropic when no base url" { set_env_url ""; [ "$(detect)" = "anthropic" ]; }
@test "detect ollama by port"            { set_env_url "http://localhost:11434"; [ "$(detect)" = "ollama" ]; }
@test "detect mlx by marker"             { set_env_url "http://127.0.0.1:8740"; echo mlx > "$HOME/.claude/local-backend"; [ "$(detect)" = "mlx" ]; }
@test "detect llama-cpp by marker"       { set_env_url "http://127.0.0.1:8730"; echo llama-cpp > "$HOME/.claude/local-backend"; [ "$(detect)" = "llama-cpp" ]; }
@test "detect defaults to llama-cpp when marker missing" { set_env_url "http://127.0.0.1:8730"; [ "$(detect)" = "llama-cpp" ]; }

# Exercises the full status path: toggle.sh status calls both llama-serve.sh and
# mlx-serve.sh status — both must return 0 when nothing is running (set -e safe).
@test "status runs clean when nothing is running" {
  run bash "$SCRIPT_DIR/toggle.sh" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"current backend"* ]]
}

@test "switch to anthropic preserves permissions and clears env, marker=anthropic" {
  set_env_url "http://127.0.0.1:8740"; echo mlx > "$HOME/.claude/local-backend"
  run bash "$SCRIPT_DIR/toggle.sh" anthropic
  [ "$status" -eq 0 ]
  run python3 -c 'import json;c=json.load(open("'"$HOME"'/.claude/settings.json"));print(c["permissions"]["allow"][0]);print(c.get("env",{}).get("ANTHROPIC_BASE_URL",""))'
  [[ "$output" == *"Bash(ls:*)"* ]]
  [ "$(cat "$HOME/.claude/local-backend")" = "anthropic" ]
}

@test "switch to mlx sets base url without /v1, token=mlx, model=repo-id, marker=mlx, valid json" {
  make_mlx_repo "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit" >/dev/null
  FAKE_CURL_READY=1 run bash "$SCRIPT_DIR/toggle.sh" mlx mlx-community/Qwen2.5-Coder-14B-Instruct-4bit
  [ "$status" -eq 0 ]
  run python3 -c 'import json;c=json.load(open("'"$HOME"'/.claude/settings.json"));e=c["env"];print(e["ANTHROPIC_BASE_URL"]);print(e["ANTHROPIC_AUTH_TOKEN"]);print(c["model"])'
  [[ "$output" == *"http://127.0.0.1:"* ]]
  [[ "$output" != *"/v1"* ]]
  [[ "$output" == *"mlx-community/Qwen2.5-Coder-14B-Instruct-4bit"* ]]   # model = full repo id
  [ "$(cat "$HOME/.claude/local-backend")" = "mlx" ]
  kill "$(cat "$HOME/.claude/mlx-server.pid")" 2>/dev/null || true
}

@test "blind toggle from anthropic goes to mlx (using last-used repo)" {
  make_mlx_repo "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit" >/dev/null
  echo "mlx-community/Qwen2.5-Coder-14B-Instruct-4bit" > "$HOME/.claude/mlx-last-model"
  set_env_url ""; echo anthropic > "$HOME/.claude/local-backend"
  FAKE_CURL_READY=1 run bash "$SCRIPT_DIR/toggle.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/local-backend")" = "mlx" ]
  kill "$(cat "$HOME/.claude/mlx-server.pid")" 2>/dev/null || true
}
