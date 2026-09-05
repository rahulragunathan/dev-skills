# MLX-LM Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 4th local backend, `mlx`, to the `localclaude:claude-toggle-backend` plugin, serving MLX models on Apple Silicon via `vllm-mlx`'s native Anthropic `/v1/messages` endpoint.

**Architecture:** A new `mlx-serve.sh` (near-clone of the existing `llama-serve.sh`) manages one `vllm-mlx` process per model with pid/port/model state files and a `/v1/models` readiness probe. `toggle.sh` gains an `mlx` case, a `~/.claude/local-backend` marker file to disambiguate the two non-Ollama local backends, and a new anthropic⇄mlx blind-toggle default. Tests are blackbox bats, invoking each script as a subprocess with `vllm-mlx`/`curl`/`uname` faked on `PATH`.

**Tech Stack:** Bash, Python 3 (already used for JSON patching + port bind-tests), `bats-core` (dev-only test runner), `vllm-mlx` (runtime, user-installed).

## Global Constraints

- **Platform:** MLX runs on Apple Silicon only. `mlx-serve.sh start`/`foreground` MUST guard on `uname -s`=Darwin AND `uname -m`=arm64 and error otherwise.
- **Not a git repo / no auto-commits.** This plugin dir is not under git and the user never commits unprompted. Every task ends at a **green bats suite + a reviewable diff**, NOT a commit. The "Checkpoint" step is where a reviewer gates the task.
- **Paths:** always double-quote paths in bash. Never backslash-escape spaces.
- **`ANTHROPIC_BASE_URL` has NO `/v1` suffix** — the Anthropic SDK appends `/v1/messages` itself (same as ollama/llama-cpp).
- **`toggle.sh` patches ONLY** `model`, `effortLevel`, and `env.ANTHROPIC_*` keys in `~/.claude/settings.json`; `permissions` and all other keys MUST be preserved. It additionally writes the marker file `~/.claude/local-backend`.
- **State files (mlx):** `~/.claude/mlx-server.pid`, `~/.claude/mlx-server.port`, `~/.claude/mlx-server.model`, `~/.claude/mlx-last-model`, log `~/.claude/mlx-server.log`. Marker: `~/.claude/local-backend`.
- **Server binary:** `vllm-mlx` (override via `MLX_BIN`). Start invocation: `vllm-mlx serve "<model-dir>" --host 127.0.0.1 --port <port>`.
- **Readiness:** `GET http://127.0.0.1:<port>/v1/models` → HTTP 200. Retry loop bounded by `MLX_READY_TRIES` (default 120, ~60s at 0.5s/try) — a testability knob so tests set it low.
- **Ports:** honor `MLX_PORT`; else auto-pick a free uncommon port (reuse llama-serve's bind-test scanner). Saved to `mlx-server.port`.
- **Models dir:** `LOCAL_MODELS_DIR` (default `~/Local-Models`), shared with llama.cpp. MLX models are **directories** (contain `config.json` + `*.safetensors`), not `.gguf` files.
- **One local model at a time:** switching to `mlx` stops any `llama-server`; switching to `anthropic`/`ollama`/`llama-cpp` stops the mlx server.
- **Install is user-confirmed:** scripts only *check* for `vllm-mlx` and print the install command (`uv tool install vllm-mlx`) — never auto-install.

**Paths (relative to plugin root `skills/claude-toggle-backend/`):**

- `mlx-serve.sh` — new
- `toggle.sh` — modified
- `tests/` — new (bats suite + fakes)

---

## Task 1: Test harness + fakes + Apple-Silicon guard

**Files:**

- Create: `skills/claude-toggle-backend/mlx-serve.sh`
- Create: `skills/claude-toggle-backend/tests/helpers/setup.bash`
- Create: `skills/claude-toggle-backend/tests/mlx-serve.bats`
- Create: `skills/claude-toggle-backend/tests/fakes/uname` (fake), `tests/fakes/vllm-mlx` (fake), `tests/fakes/curl` (fake)

**Interfaces:**

- Produces: `mlx-serve.sh` CLI `start|stop|status|port|foreground`; test helper `setup_mlx_env` that exports `HOME`, `LOCAL_MODELS_DIR`, and a `PATH` prefixed with `tests/fakes`.

- [ ] **Step 1: Write the fakes**

`tests/fakes/uname`:

```bash
#!/bin/bash
# Fake uname: FAKE_UNAME_S / FAKE_UNAME_M control output.
case "${1:-}" in
  -s) echo "${FAKE_UNAME_S:-Darwin}" ;;
  -m) echo "${FAKE_UNAME_M:-arm64}" ;;
  *)  echo "${FAKE_UNAME_S:-Darwin}" ;;
esac
```

`tests/fakes/vllm-mlx`:

```bash
#!/bin/bash
# Fake vllm-mlx. FAKE_MLX_MODE=alive (default) → stay alive; crash → exit 1 now.
if [ "${FAKE_MLX_MODE:-alive}" = "crash" ]; then
  echo "fake vllm-mlx: simulated crash" >&2
  exit 1
fi
exec sleep 300
```

`tests/fakes/curl`:

```bash
#!/bin/bash
# Fake curl for the readiness probe. FAKE_CURL_READY=1 → success, else fail.
[ "${FAKE_CURL_READY:-0}" = "1" ] && exit 0 || exit 7
```

Make them executable: `chmod +x tests/fakes/*`.

- [ ] **Step 2: Write the test helper**

`tests/helpers/setup.bash`:

```bash
setup_mlx_env() {
  export TEST_TMP="$(mktemp -d)"
  export HOME="$TEST_TMP/home"
  export LOCAL_MODELS_DIR="$TEST_TMP/models"
  mkdir -p "$HOME/.claude" "$LOCAL_MODELS_DIR"
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export SCRIPT_DIR="$(dirname "$here")"          # skills/claude-toggle-backend
  export PATH="$here/fakes:$PATH"                 # fakes win over real binaries
  export MLX_READY_TRIES=2                        # fast readiness loop in tests
}
teardown_mlx_env() { rm -rf "$TEST_TMP"; }
make_mlx_model() {                                # $1 = dir name under LOCAL_MODELS_DIR
  local d="$LOCAL_MODELS_DIR/$1"; mkdir -p "$d"
  echo '{}' > "$d/config.json"; : > "$d/model.safetensors"; echo "$d"
}
```

- [ ] **Step 3: Write the failing test (Apple-Silicon guard)**

`tests/mlx-serve.bats`:

```bash
load helpers/setup
setup()    { setup_mlx_env; }
teardown() { teardown_mlx_env; }

@test "start errors on non-Apple-Silicon" {
  FAKE_UNAME_M=x86_64 run bash "$SCRIPT_DIR/mlx-serve.sh" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"Apple Silicon"* ]]
}
```

- [ ] **Step 4: Run it, verify it fails**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats`
Expected: FAIL (mlx-serve.sh does not exist yet).

- [ ] **Step 5: Create mlx-serve.sh with config + guard + dispatch skeleton**

`skills/claude-toggle-backend/mlx-serve.sh`:

```bash
#!/bin/bash
# Start / stop / inspect a local vllm-mlx server (native Anthropic /v1/messages)
# for use as a Claude Code backend on Apple Silicon. Mirrors llama-serve.sh.
#
# Usage: mlx-serve.sh [start [model]|foreground|stop|status|port]
# Env: LOCAL_MODELS_DIR, MLX_PORT, MLX_BIN, MLX_READY_TRIES (testing knob)
set -euo pipefail

LOCAL_MODELS_DIR="${LOCAL_MODELS_DIR:-$HOME/Local-Models}"
MLX_BIN="${MLX_BIN:-$(command -v vllm-mlx || true)}"
STATE_DIR="$HOME/.claude"
PID_FILE="$STATE_DIR/mlx-server.pid"
PORT_FILE="$STATE_DIR/mlx-server.port"
MODEL_FILE="$STATE_DIR/mlx-server.model"
LAST_MODEL_FILE="$STATE_DIR/mlx-last-model"
LOG_FILE="$STATE_DIR/mlx-server.log"
READY_TRIES="${MLX_READY_TRIES:-120}"

CMD="${1:-status}"
MODEL_ARG="${2:-}"
mkdir -p "$STATE_DIR"

require_apple_silicon() {
  if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
    echo "MLX requires Apple Silicon (Darwin/arm64). This machine is $(uname -s)/$(uname -m)." >&2
    exit 1
  fi
}

case "$CMD" in
  start) require_apple_silicon ;;   # more added in later tasks
  *) echo "usage: mlx-serve.sh [start [model]|foreground|stop|status|port]" >&2; exit 1 ;;
esac
```

- [ ] **Step 6: Run test, verify it passes**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats`
Expected: PASS.

- [ ] **Step 7: Checkpoint** — suite green; hand off diff for review (no commit; not a git repo).

---

## Task 2: vllm-mlx binary presence check

**Files:**

- Modify: `skills/claude-toggle-backend/mlx-serve.sh` (start path)
- Test: `skills/claude-toggle-backend/tests/mlx-serve.bats`

**Interfaces:**

- Consumes: `MLX_BIN`, `require_apple_silicon` from Task 1.
- Produces: `start` exits non-zero with an install hint when `vllm-mlx` is absent.

- [ ] **Step 1: Write the failing test**

Add to `tests/mlx-serve.bats`:

```bash
@test "start errors with install hint when vllm-mlx missing" {
  # Shadow the fake vllm-mlx by pointing MLX_BIN at nothing and stripping fakes dir isn't
  # possible (curl/uname needed); instead force MLX_BIN empty.
  MLX_BIN="" run bash "$SCRIPT_DIR/mlx-serve.sh" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"uv tool install vllm-mlx"* ]]
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats -f "install hint"`
Expected: FAIL (no such message yet; guard passes then falls through).

- [ ] **Step 3: Add the binary check to the `start` case**

In `mlx-serve.sh`, replace the `start)` case line with:

```bash
  start)
    require_apple_silicon
    [ -n "$MLX_BIN" ] || { echo "vllm-mlx not found. Install with: uv tool install vllm-mlx (or: pip install vllm-mlx)" >&2; exit 1; }
    ;;
```

- [ ] **Step 4: Run test, verify it passes**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats -f "install hint"`
Expected: PASS.

- [ ] **Step 5: Checkpoint** — full suite green; hand off for review.

---

## Task 3: Model resolution

**Files:**

- Modify: `skills/claude-toggle-backend/mlx-serve.sh`
- Test: `skills/claude-toggle-backend/tests/mlx-serve.bats`

**Interfaces:**

- Produces: `resolve_model()` echoing an absolute model dir, using: explicit arg (abs path, or name under `LOCAL_MODELS_DIR`) → `LAST_MODEL_FILE` → newest dir containing `config.json` under `LOCAL_MODELS_DIR`. Empty output when none.

- [ ] **Step 1: Write the failing tests**

Add to `tests/mlx-serve.bats`:

```bash
resolve() { bash -c 'source "$1"; resolve_model' _ "$SCRIPT_DIR/mlx-serve.sh"; }

@test "resolve_model: explicit dir-name under models dir" {
  make_mlx_model "Qwen-4bit" >/dev/null
  MODEL_ARG="Qwen-4bit" run bash "$SCRIPT_DIR/mlx-serve.sh" __resolve
  [ "$status" -eq 0 ]
  [[ "$output" == "$LOCAL_MODELS_DIR/Qwen-4bit" ]]
}

@test "resolve_model: newest config.json dir wins" {
  a="$(make_mlx_model A)"; sleep 1; b="$(make_mlx_model B)"
  run bash "$SCRIPT_DIR/mlx-serve.sh" __resolve
  [ "$status" -eq 0 ]
  [[ "$output" == "$b" ]]
}

@test "resolve_model: none found is empty" {
  run bash "$SCRIPT_DIR/mlx-serve.sh" __resolve
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

(The `__resolve` hidden subcommand exists purely to exercise `resolve_model` in isolation.)

- [ ] **Step 2: Run, verify failure**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats -f resolve_model`
Expected: FAIL (`__resolve` unknown → usage error, non-zero).

- [ ] **Step 3: Implement `resolve_model` + `__resolve` subcommand**

Add before the `case` in `mlx-serve.sh`:

```bash
resolve_model() {
  if [ -n "$MODEL_ARG" ]; then
    case "$MODEL_ARG" in
      /*) echo "$MODEL_ARG" ;;
      *)  echo "$LOCAL_MODELS_DIR/$MODEL_ARG" ;;
    esac
    return
  fi
  if [ -f "$LAST_MODEL_FILE" ]; then
    local last; last="$(cat "$LAST_MODEL_FILE")"
    [ -d "$last" ] && { echo "$last"; return; }
  fi
  # newest directory containing config.json (MLX model dir)
  local newest
  newest="$(/usr/bin/find "$LOCAL_MODELS_DIR" -type f -name config.json -print0 2>/dev/null \
            | xargs -0 -I{} dirname {} 2>/dev/null \
            | while read -r d; do echo "$(stat -f '%m' "$d/config.json") $d"; done \
            | sort -rn | head -n1 | cut -d' ' -f2- || true)"
  echo "$newest"
}
```

Add a `__resolve)` branch to the `case`:

```bash
  __resolve) resolve_model ;;
```

- [ ] **Step 4: Run, verify pass**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats -f resolve_model`
Expected: PASS (all three).

- [ ] **Step 5: Checkpoint** — full suite green; review.

---

## Task 4: Port picking

**Files:**

- Modify: `skills/claude-toggle-backend/mlx-serve.sh`
- Test: `skills/claude-toggle-backend/tests/mlx-serve.bats`

**Interfaces:**

- Produces: `pick_port()` echoing `MLX_PORT` if set, else a free port from an upward scan skipping common dev ports.

- [ ] **Step 1: Write the failing tests**

```bash
@test "pick_port honors MLX_PORT" {
  MLX_PORT=8791 run bash "$SCRIPT_DIR/mlx-serve.sh" __port
  [ "$status" -eq 0 ]; [[ "$output" == "8791" ]]
}

@test "pick_port auto-picks a numeric free port" {
  run bash "$SCRIPT_DIR/mlx-serve.sh" __port
  [ "$status" -eq 0 ]; [[ "$output" =~ ^[0-9]+$ ]]
}
```

- [ ] **Step 2: Run, verify failure**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats -f pick_port`
Expected: FAIL (`__port` unknown).

- [ ] **Step 3: Implement `pick_port` + `__port`**

Add `pick_port` (identical scanner to llama-serve.sh, honoring `MLX_PORT`):

```bash
pick_port() {
  if [ -n "${MLX_PORT:-}" ]; then echo "$MLX_PORT"; return; fi
  python3 - <<'PY'
import socket
BLOCK = {8080,8000,5000,5001,3000,5173,4200,8888,9000,5432,3306,6379,27017,11434}
p = 8740
while p < 9999:
    if p not in BLOCK:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            s.bind(("127.0.0.1", p)); s.close(); print(p); break
        except OSError:
            pass
        finally:
            try: s.close()
            except OSError: pass
    p += 1
else:
    raise SystemExit("no free port found in 8740-9998")
PY
}
```

(Base port `8740` to avoid colliding with llama-serve's `8730`.) Add `__port) pick_port ;;` to the `case`.

- [ ] **Step 4: Run, verify pass**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats -f pick_port`
Expected: PASS.

- [ ] **Step 5: Checkpoint** — suite green; review.

---

## Task 5: `start` — launch, readiness, state files

**Files:**

- Modify: `skills/claude-toggle-backend/mlx-serve.sh`
- Test: `skills/claude-toggle-backend/tests/mlx-serve.bats`

**Interfaces:**

- Consumes: `resolve_model`, `pick_port`, `require_apple_silicon`, binary check.
- Produces: `start [model]` that launches `vllm-mlx serve`, waits for `/v1/models`, writes `PID/PORT/MODEL/LAST_MODEL` files; exit 0 on ready, non-zero + log tail on crash/timeout; needs helpers `is_alive`, `do_stop` (added here, expanded in Task 6).

- [ ] **Step 1: Write the failing tests**

```bash
@test "start succeeds when server becomes ready" {
  make_mlx_model "M" >/dev/null
  FAKE_CURL_READY=1 run bash "$SCRIPT_DIR/mlx-serve.sh" start M
  [ "$status" -eq 0 ]
  [ -f "$HOME/.claude/mlx-server.pid" ]
  [ "$(cat "$HOME/.claude/mlx-server.model")" = "$LOCAL_MODELS_DIR/M" ]
  [ "$(cat "$HOME/.claude/mlx-last-model")" = "$LOCAL_MODELS_DIR/M" ]
  bash "$SCRIPT_DIR/mlx-serve.sh" stop || true
}

@test "start fails and cleans up when server never ready" {
  make_mlx_model "M" >/dev/null
  FAKE_CURL_READY=0 MLX_READY_TRIES=2 run bash "$SCRIPT_DIR/mlx-serve.sh" start M
  [ "$status" -ne 0 ]
  [ ! -f "$HOME/.claude/mlx-server.pid" ]
}

@test "start fails fast when server crashes on launch" {
  make_mlx_model "M" >/dev/null
  FAKE_MLX_MODE=crash run bash "$SCRIPT_DIR/mlx-serve.sh" start M
  [ "$status" -ne 0 ]
  [[ "$output" == *"exited during startup"* ]]
}

@test "start errors clearly when no model found" {
  FAKE_CURL_READY=1 run bash "$SCRIPT_DIR/mlx-serve.sh" start
  [ "$status" -ne 0 ]
  [[ "$output" == *"local-models"* ]]
}
```

- [ ] **Step 2: Run, verify failure**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats -f start`
Expected: FAIL (start case is a no-op stub).

- [ ] **Step 3: Add `is_alive`, minimal `do_stop`, and the full `start` body**

Add helpers before `case`:

```bash
is_alive() {
  [ -f "$PID_FILE" ] || return 1
  local pid; pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}
do_stop() {   # expanded with stray-sweep in Task 6
  if is_alive; then
    local pid; pid="$(cat "$PID_FILE")"
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE" "$PORT_FILE" "$MODEL_FILE"
}
```

Replace the `start)` case body with:

```bash
  start)
    require_apple_silicon
    [ -n "$MLX_BIN" ] || { echo "vllm-mlx not found. Install with: uv tool install vllm-mlx (or: pip install vllm-mlx)" >&2; exit 1; }
    MODEL="$(resolve_model)"
    if [ -z "$MODEL" ] || [ ! -d "$MODEL" ]; then
      echo "No MLX model directory found.
  - Pass one:        mlx-serve.sh start <model-dir>
  - Or put an MLX model dir (config.json + *.safetensors) in: $LOCAL_MODELS_DIR
  - Or use /localclaude:local-models to download one." >&2
      exit 1
    fi
    do_stop >/dev/null
    PORT="$(pick_port)"
    echo "Starting vllm-mlx: model=$(basename "$MODEL") port=$PORT"
    nohup "$MLX_BIN" serve "$MODEL" --host 127.0.0.1 --port "$PORT" > "$LOG_FILE" 2>&1 &
    SRV_PID=$!
    echo "$SRV_PID" > "$PID_FILE"
    echo "$PORT"    > "$PORT_FILE"
    echo "$MODEL"   > "$MODEL_FILE"
    echo "$MODEL"   > "$LAST_MODEL_FILE"
    for _ in $(seq 1 "$READY_TRIES"); do
      if ! kill -0 "$SRV_PID" 2>/dev/null; then
        echo "vllm-mlx exited during startup. Last log lines:" >&2
        tail -n 20 "$LOG_FILE" >&2 || true
        rm -f "$PID_FILE" "$PORT_FILE" "$MODEL_FILE"
        exit 1
      fi
      if curl -fsS "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1; then
        echo "Ready: http://127.0.0.1:$PORT (log: $LOG_FILE)"
        exit 0
      fi
      sleep 0.5
    done
    echo "Timed out waiting for vllm-mlx /v1/models. Last log lines:" >&2
    tail -n 20 "$LOG_FILE" >&2 || true
    do_stop
    exit 1
    ;;
```

- [ ] **Step 4: Run, verify pass**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats -f start`
Expected: PASS (all four).

- [ ] **Step 5: Checkpoint** — full suite green; review.

---

## Task 6: `stop` / `status` / `port` subcommands + stray sweep

**Files:**

- Modify: `skills/claude-toggle-backend/mlx-serve.sh`
- Test: `skills/claude-toggle-backend/tests/mlx-serve.bats`

**Interfaces:**

- Produces: `stop` (kills tracked pid, removes state, sweeps stray `vllm-mlx serve`), `status` (RUNNING/stopped + multi-process warning), `port` (prints active port or errors).

- [ ] **Step 1: Write the failing tests**

```bash
@test "stop removes state and reports" {
  make_mlx_model "M" >/dev/null
  FAKE_CURL_READY=1 bash "$SCRIPT_DIR/mlx-serve.sh" start M
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
```

- [ ] **Step 2: Run, verify failure**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats -f "stop\|status\|port"`
Expected: FAIL (`stop`/`status`/`port` hit the usage default).

- [ ] **Step 3: Expand `do_stop` with stray sweep and add the three cases**

Replace `do_stop` body's trailing `rm -f ...` region with the full version:

```bash
do_stop() {
  local did=0
  if is_alive; then
    local pid; pid="$(cat "$PID_FILE")"
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 0.2; done
    kill -9 "$pid" 2>/dev/null || true
    echo "Stopped vllm-mlx (pid $pid)."; did=1
  fi
  rm -f "$PID_FILE" "$PORT_FILE" "$MODEL_FILE"
  local stray; stray="$(pgrep -f 'vllm-mlx serve' 2>/dev/null || true)"
  if [ -n "$stray" ]; then
    echo "Cleaning up stray vllm-mlx process(es): $(echo "$stray" | tr '\n' ' ')"
    for p in $stray; do kill "$p" 2>/dev/null || true; done
    sleep 0.3
    for p in $(pgrep -f 'vllm-mlx serve' 2>/dev/null || true); do kill -9 "$p" 2>/dev/null || true; done
    did=1
  fi
  [ "$did" -eq 0 ] && echo "vllm-mlx not running."
  return 0
}
```

Add cases to the `case` block:

```bash
  stop) do_stop ;;
  port) [ -f "$PORT_FILE" ] && cat "$PORT_FILE" || { echo "not running" >&2; exit 1; } ;;
  status)
    if is_alive; then
      echo "vllm-mlx: RUNNING (pid $(cat "$PID_FILE"), port $(cat "$PORT_FILE" 2>/dev/null), model $(basename "$(cat "$MODEL_FILE" 2>/dev/null)" 2>/dev/null))"
    else
      echo "vllm-mlx: stopped (no tracked process)"
    fi
    N="$(pgrep -f 'vllm-mlx serve' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${N:-0}" -gt 1 ]; then
      echo "WARNING: $N vllm-mlx processes detected — run 'mlx-serve.sh stop' to clean up:"
      pgrep -fl 'vllm-mlx serve' 2>/dev/null
    fi
    ;;
```

- [ ] **Step 4: Run, verify pass**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats`
Expected: PASS (whole file).

- [ ] **Step 5: Checkpoint** — suite green; review.

---

## Task 7: `foreground` subcommand

**Files:**

- Modify: `skills/claude-toggle-backend/mlx-serve.sh`
- Test: `skills/claude-toggle-backend/tests/mlx-serve.bats`

**Interfaces:**

- Produces: `foreground` — writes state files then `exec`s `vllm-mlx serve` in the foreground (for a future supervisor). Kept for symmetry with llama-serve; no autostart script ships.

- [ ] **Step 1: Write the failing test**

The fake `vllm-mlx` `exec sleep 300`s, so assert state files are written before exec by running it backgrounded and checking, then killing it.

```bash
@test "foreground writes state files then execs the server" {
  make_mlx_model "M" >/dev/null
  bash "$SCRIPT_DIR/mlx-serve.sh" foreground M &
  bg=$!
  for _ in $(seq 1 20); do [ -f "$HOME/.claude/mlx-server.model" ] && break; sleep 0.1; done
  [ "$(cat "$HOME/.claude/mlx-server.model")" = "$LOCAL_MODELS_DIR/M" ]
  kill "$bg" 2>/dev/null || true
  pkill -f 'sleep 300' 2>/dev/null || true
}
```

- [ ] **Step 2: Run, verify failure**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats -f foreground`
Expected: FAIL (`foreground` hits usage default).

- [ ] **Step 3: Add the `foreground` case**

```bash
  foreground)
    require_apple_silicon
    [ -n "$MLX_BIN" ] || { echo "vllm-mlx not found. Install: uv tool install vllm-mlx" >&2; exit 1; }
    MODEL="$(resolve_model)"
    if [ -z "$MODEL" ] || [ ! -d "$MODEL" ]; then echo "No MLX model dir in $LOCAL_MODELS_DIR" >&2; exit 1; fi
    PORT="$(pick_port)"
    echo "$$"     > "$PID_FILE"
    echo "$PORT"  > "$PORT_FILE"
    echo "$MODEL" > "$MODEL_FILE"
    echo "$MODEL" > "$LAST_MODEL_FILE"
    echo "foreground: model=$(basename "$MODEL") port=$PORT"
    exec "$MLX_BIN" serve "$MODEL" --host 127.0.0.1 --port "$PORT"
    ;;
```

- [ ] **Step 4: Run, verify pass**

Run: `bats skills/claude-toggle-backend/tests/mlx-serve.bats -f foreground`
Expected: PASS.

- [ ] **Step 5: Checkpoint** — `mlx-serve.sh` complete; full suite green; review.

---

## Task 8: `toggle.sh` — marker file + `current_backend` detection

**Files:**

- Modify: `skills/claude-toggle-backend/toggle.sh`
- Create: `skills/claude-toggle-backend/tests/toggle.bats`
- Reuse: `tests/helpers/setup.bash`

**Interfaces:**

- Produces: marker path `$HOME/.claude/local-backend`; rewritten `current_backend()` returning `anthropic|ollama|llama-cpp|mlx`; helper `write_marker <backend>`.

- [ ] **Step 1: Write the failing tests**

`tests/toggle.bats`:

```bash
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
```

- [ ] **Step 2: Run, verify failure**

Run: `bats skills/claude-toggle-backend/tests/toggle.bats`
Expected: FAIL (`__detect` unknown / old logic).

- [ ] **Step 3: Rewrite `current_backend()`, add `write_marker` + `__detect`**

In `toggle.sh`, define the marker path near the top (after `SETTINGS=`):

```bash
MARKER="$HOME/.claude/local-backend"
```

Replace `current_backend()` with:

```bash
current_backend() {
  python3 - "$SETTINGS" "$MARKER" <<'PY'
import json, os, sys
cfg = json.load(open(sys.argv[1]))
url = str(cfg.get("env", {}).get("ANTHROPIC_BASE_URL", ""))
if not url:
    print("anthropic")
elif "11434" in url:
    print("ollama")
else:
    marker = ""
    try: marker = open(sys.argv[2]).read().strip()
    except OSError: pass
    print(marker if marker in ("mlx", "llama-cpp") else "llama-cpp")
PY
}
write_marker() { echo "$1" > "$MARKER"; }
```

Add a `__detect` short-circuit right after argument parsing (before the `status` block):

```bash
if [ "$TARGET" = "__detect" ]; then current_backend; exit 0; fi
```

- [ ] **Step 4: Run, verify pass**

Run: `bats skills/claude-toggle-backend/tests/toggle.bats`
Expected: PASS (all five).

- [ ] **Step 5: Checkpoint** — suite green; review.

---

## Task 9: `toggle.sh` — `mlx` case, stop-others, blind toggle, status

**Files:**

- Modify: `skills/claude-toggle-backend/toggle.sh`
- Test: `skills/claude-toggle-backend/tests/toggle.bats`

**Interfaces:**

- Consumes: `current_backend`, `write_marker`, `mlx-serve.sh`, `llama-serve.sh`.
- Produces: `toggle.sh mlx [model]`; blind `toggle` → anthropic⇄mlx; every switch writes the marker and stops the other local servers; `status` prints mlx-serve status.

- [ ] **Step 1: Write the failing tests**

```bash
@test "switch to anthropic preserves permissions and clears env, marker=anthropic" {
  set_env_url "http://127.0.0.1:8740"; echo mlx > "$HOME/.claude/local-backend"
  run bash "$SCRIPT_DIR/toggle.sh" anthropic
  [ "$status" -eq 0 ]
  run python3 -c 'import json;c=json.load(open("'"$HOME"'/.claude/settings.json"));print(c["permissions"]["allow"][0]); print("env" in c and c.get("env",{}).get("ANTHROPIC_BASE_URL",""))'
  [[ "$output" == *"Bash(ls:*)"* ]]
  [ "$(cat "$HOME/.claude/local-backend")" = "anthropic" ]
}

@test "switch to mlx sets base url without /v1, token, marker=mlx, valid json" {
  make_mlx_model "M" >/dev/null
  FAKE_CURL_READY=1 run bash "$SCRIPT_DIR/toggle.sh" mlx M
  [ "$status" -eq 0 ]
  run python3 -c 'import json;c=json.load(open("'"$HOME"'/.claude/settings.json"));e=c["env"];print(e["ANTHROPIC_BASE_URL"]); print(e["ANTHROPIC_AUTH_TOKEN"]); print(c["model"])'
  [[ "$output" == *"http://127.0.0.1:"* ]]
  [[ "$output" != *"/v1"* ]]
  [[ "$output" == *"mlx"* ]]
  [[ "$output" == *"M"* ]]
  [ "$(cat "$HOME/.claude/local-backend")" = "mlx" ]
  bash "$SCRIPT_DIR/mlx-serve.sh" stop || true
}

@test "blind toggle from anthropic goes to mlx" {
  make_mlx_model "M" >/dev/null; set_env_url ""; echo anthropic > "$HOME/.claude/local-backend"
  FAKE_CURL_READY=1 run bash "$SCRIPT_DIR/toggle.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.claude/local-backend")" = "mlx" ]
  bash "$SCRIPT_DIR/mlx-serve.sh" stop || true
}
```

- [ ] **Step 2: Run, verify failure**

Run: `bats skills/claude-toggle-backend/tests/toggle.bats -f "mlx\|blind\|anthropic preserves"`
Expected: FAIL (no `mlx` case; blind toggle still targets ollama; no marker writes).

- [ ] **Step 3: Implement the changes in `toggle.sh`**

(a) Blind toggle default — replace the toggle line:

```bash
if [ "$TARGET" = "toggle" ]; then
  [ "$(current_backend)" = "anthropic" ] && TARGET="mlx" || TARGET="anthropic"
fi
```

(b) Add the `mlx` case and stop-others to the `case "$TARGET"` block. Update `anthropic` and `ollama` cases to also stop the mlx server, and add the `mlx` case:

```bash
  anthropic)
    bash "$SCRIPT_DIR/llama-serve.sh" stop >/dev/null 2>&1 || true
    bash "$SCRIPT_DIR/mlx-serve.sh" stop  >/dev/null 2>&1 || true
    MODEL="$ANTHROPIC_MODEL"; BASE_URL=""; TOKEN=""; EFFORT="high"
    ;;
  ollama)
    bash "$SCRIPT_DIR/llama-serve.sh" stop >/dev/null 2>&1 || true
    bash "$SCRIPT_DIR/mlx-serve.sh" stop  >/dev/null 2>&1 || true
    MODEL="$OLLAMA_MODEL"; BASE_URL="$OLLAMA_URL"; TOKEN="ollama"
    ;;
  llama-cpp|llamacpp|llama)
    TARGET="llama-cpp"
    bash "$SCRIPT_DIR/mlx-serve.sh" stop >/dev/null 2>&1 || true
    bash "$SCRIPT_DIR/llama-serve.sh" start "$MODEL_ARG"
    PORT="$(bash "$SCRIPT_DIR/llama-serve.sh" port)"
    MODEL="$(basename "$(cat "$HOME/.claude/llama-server.model")")"
    BASE_URL="http://127.0.0.1:$PORT"; TOKEN="llamacpp"
    ;;
  mlx)
    bash "$SCRIPT_DIR/llama-serve.sh" stop >/dev/null 2>&1 || true
    bash "$SCRIPT_DIR/mlx-serve.sh" start "$MODEL_ARG"
    PORT="$(bash "$SCRIPT_DIR/mlx-serve.sh" port)"
    MODEL="$(basename "$(cat "$HOME/.claude/mlx-server.model")")"
    BASE_URL="http://127.0.0.1:$PORT"; TOKEN="mlx"
    ;;
```

(c) Update the usage string to include `mlx [model]`.
(d) Write the marker at the end of the Python patch block. After the `print("switched to"...)` line, add (still in bash, after the heredoc):

```bash
write_marker "$TARGET"
```

(e) In the `status` block, add after the llama line:

```bash
  bash "$SCRIPT_DIR/mlx-serve.sh" status
```

- [ ] **Step 4: Run, verify pass**

Run: `bats skills/claude-toggle-backend/tests/toggle.bats`
Expected: PASS (whole file).

- [ ] **Step 5: Full-suite regression**

Run: `bats skills/claude-toggle-backend/tests/`
Expected: PASS (mlx-serve.bats + toggle.bats).

- [ ] **Step 6: Checkpoint** — all tests green; review.

---

## Task 10: `local-models` skill — MLX download path

**Files:**

- Modify: `skills/local-models/SKILL.md`
- Modify: `skills/local-models/REFERENCE.md`

**Interfaces:** Docs only — no automated test.

- [ ] **Step 1: Add an MLX branch to the backend menu**

In `local-models/SKILL.md`, under "Choose backend(s)", add a bullet:

```markdown
- **mlx (Apple Silicon, MLX-native)** — Metal-native via `vllm-mlx`; drives the Claude Code `mlx` backend. Models are MLX-format **directories** from the `mlx-community` HF org, stored under `$LOCAL_MODELS_DIR`. Mutually exclusive with llama.cpp at runtime (one model resident).
```

- [ ] **Step 2: Add the MLX download recipe**

Under "Download", add a subsection:

````markdown
**MLX model for the `mlx` backend** → a *directory* under `$LOCAL_MODELS_DIR`:
```bash
mkdir -p "${LOCAL_MODELS_DIR:-$HOME/Local-Models}"
hf download mlx-community/<Model>-4bit \
  --local-dir "${LOCAL_MODELS_DIR:-$HOME/Local-Models}/<Model>-4bit"
```

Pick a 4-bit MLX build (e.g. `mlx-community/Qwen2.5-Coder-14B-Instruct-4bit`) for the 24 GB sweet spot (~8–9 GB). Then: `/localclaude:claude-toggle-backend mlx <Model>-4bit`.
(MLX models come pre-quantized; the GGUF-specific `huggingface-local-models` delegate does not apply — browse the `mlx-community` org directly.)

````

- [ ] **Step 3: Update the delegation map + locations in REFERENCE.md**

Add rows to the delegation-map table:

```markdown
| find MLX-format model dirs (pre-quantized) | browse the `mlx-community` HF org directly |
| serve an MLX model dir as the Claude Code backend | `/localclaude:claude-toggle-backend mlx <dir>` |
```

And to "Locations":

```markdown
- MLX models (managed): `$LOCAL_MODELS_DIR/<model-dir>/` (directory, not a file) — shared with the mlx backend.
```

- [ ] **Step 4: Verify** — re-read both files; confirm the mlx backend is discoverable and the recipe stores into `~/Local-Models`.

- [ ] **Step 5: Checkpoint** — docs consistent; review.

---

## Task 11: Backend skill docs, README, version bumps

**Files:**

- Modify: `skills/claude-toggle-backend/SKILL.md`
- Modify: `README.md` (plugin root)
- Modify: `.claude-plugin/plugin.json`

**Interfaces:** Docs/metadata only.

- [ ] **Step 1: Update `claude-toggle-backend/SKILL.md`**

- Bump `version:` in frontmatter (2.0.0 → 2.1.0) and extend the `description:` to mention the `mlx` (vllm-mlx) backend.
- Add `mlx` to the backend list, the "How to run it" examples (`bash "$TB" mlx` and `bash "$TB" mlx <Model-4bit>`), and a "Backends in detail → mlx" subsection describing: `vllm-mlx serve`, MLX model *directories* under `~/Local-Models`, `/v1/models` readiness, Apple-Silicon-only, state files, `MLX_MODEL`/`MLX_PORT`/`MLX_BIN` env.
- Update the "Detection" note to describe the `~/.claude/local-backend` marker (URL → local-vs-anthropic and 11434→ollama; marker → mlx vs llama-cpp).
- Update the blind-`toggle` description: now flips anthropic⇄**mlx**.
- Add an optional alias: `alias claude-mlx='bash "<abs>/toggle.sh" mlx'`.
- Add to Prerequisites: **mlx backend** — Apple Silicon + `vllm-mlx` (`uv tool install vllm-mlx`), MLX model dir in `~/Local-Models`.

- [ ] **Step 2: Update `README.md`**

Add the `mlx` backend to the plugin's backend list / feature summary wherever `llama-cpp` is described.

- [ ] **Step 3: Bump `.claude-plugin/plugin.json`**

Increment the plugin `version` (e.g. patch/minor bump consistent with existing scheme).

- [ ] **Step 4: Verify** — `python3 -m json.tool .claude-plugin/plugin.json` valid; skim SKILL.md for accuracy against the shipped scripts.

- [ ] **Step 5: Checkpoint** — docs/version consistent; review.

---

## Task 12: Manual end-to-end verification (sign-off gate)

**Files:** none (manual). This is the user's sign-off; not automated.

- [ ] **Step 1:** Confirm `vllm-mlx` installed: `command -v vllm-mlx` (else `uv tool install vllm-mlx`).
- [ ] **Step 2:** Download a real MLX model via `/localclaude:local-models` (or `hf download mlx-community/Qwen2.5-Coder-14B-Instruct-4bit --local-dir ~/Local-Models/Qwen2.5-Coder-14B-Instruct-4bit`).
- [ ] **Step 3:** `bash skills/claude-toggle-backend/toggle.sh mlx Qwen2.5-Coder-14B-Instruct-4bit` → expect "Ready" + `switched to mlx`.
- [ ] **Step 4:** `python3 -m json.tool ~/.claude/settings.json` valid; `bash skills/claude-toggle-backend/toggle.sh status` shows `mlx`.
- [ ] **Step 5:** Fully quit Claude Code (Cmd+Q) and reopen. Run a **tool-using** task (edit a file / run a command) and confirm it completes — validates vllm-mlx's Anthropic tool-use fidelity (the §11 risk).
- [ ] **Step 6:** `toggle.sh anthropic` → confirm mlx server stops (`mlx-serve.sh status` = stopped), settings reverts, marker=anthropic.
- [ ] **Step 7:** Sign off.

---

## Self-Review

**Spec coverage:**

- §2 server choice (vllm-mlx) → Tasks 5,9 (invocation), 11 (docs). ✓
- §4 mlx-serve.sh (binary check, storage, resolution, readiness, guard, ports, state, foreground) → Tasks 1–7. ✓
- §5 toggle.sh (mlx case, stop-others, marker detection, blind toggle→mlx, status, env) → Tasks 8–9, 11 (env docs). ✓
- §6 local-models MLX path → Task 10. ✓
- §7 docs/versioning → Task 11. ✓
- §8 out-of-scope (no autostart) → honored (foreground kept, no autostart script). ✓
- §9 testing (faked boundaries, covered logic list) → Tasks 1–9 bats. ✓
- §10 prerequisites → Task 11 docs + Task 12 manual. ✓
- §11 risks (tool-use, readiness) → Task 12 Step 5 + `/v1/models` probe in Task 5. ✓

**Placeholder scan:** `<Model>` tokens are intentional user-supplied names in doc recipes, not plan gaps. No TBD/TODO. ✓

**Type/name consistency:** state-file vars (`PID_FILE`/`PORT_FILE`/`MODEL_FILE`/`LAST_MODEL_FILE`/`LOG_FILE`), `resolve_model`/`pick_port`/`is_alive`/`do_stop`, marker `$HOME/.claude/local-backend`, `write_marker`, base port `8740`, readiness path `/v1/models`, token `mlx` — used consistently across Tasks 1–9. ✓
