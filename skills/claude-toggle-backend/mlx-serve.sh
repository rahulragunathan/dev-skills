#!/bin/bash
# Start / stop / inspect a local vllm-mlx server (native Anthropic /v1/messages)
# for use as a Claude Code backend on Apple Silicon. Mirrors llama-serve.sh.
#
# MLX models are served by Hugging Face REPO ID and resolved from the HF cache
# (HF_HOME=$LOCAL_MODELS_DIR, i.e. ~/Local-Models/hub/models--org--name). Pull one with
#   HF_HOME=~/Local-Models hf download <org>/<name>     (or /localclaude:local-models)
# and list them with `hf cache ls`. (GGUFs for the llama-cpp backend are flat files
# at the top level of ~/Local-Models instead — different mechanism, see llama-serve.sh.)
#
# Usage: mlx-serve.sh [start [repo-id]|foreground|stop|status|port]
# Env: LOCAL_MODELS_DIR, HF_HOME, MLX_PORT, MLX_BIN, MLX_READY_TRIES (testing knob)
set -euo pipefail

LOCAL_MODELS_DIR="${LOCAL_MODELS_DIR:-$HOME/Local-Models}"
export HF_HOME="${HF_HOME:-$LOCAL_MODELS_DIR}"        # MLX models live in the HF cache under here
MLX_BIN="${MLX_BIN-$(command -v vllm-mlx || true)}"  # no-colon: explicit MLX_BIN="" means "not installed"
STATE_DIR="$HOME/.claude"
PID_FILE="$STATE_DIR/mlx-server.pid"
PORT_FILE="$STATE_DIR/mlx-server.port"
MODEL_FILE="$STATE_DIR/mlx-server.model"             # stores a HF repo id (org/name)
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

resolve_model() {
  # Echoes a HF repo id (org/name): 1) explicit arg  2) last-used  3) empty.
  if [ -n "$MODEL_ARG" ]; then echo "$MODEL_ARG"; return; fi
  if [ -f "$LAST_MODEL_FILE" ]; then
    local last; last="$(cat "$LAST_MODEL_FILE" 2>/dev/null || true)"
    [ -n "$last" ] && { echo "$last"; return; }
  fi
  echo ""
}

repo_cache_dir() {   # org/name -> $HF_HOME/hub/models--org--name
  echo "$HF_HOME/hub/models--${1//\//--}"
}

is_alive() {
  [ -f "$PID_FILE" ] || return 1
  local pid; pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

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
  # Sweep any stray/orphan vllm-mlx server processes so nothing is left hanging.
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

start_mlx() {   # shared by `start` (background) and `foreground` (exec)
  require_apple_silicon
  [ -n "$MLX_BIN" ] || { echo "vllm-mlx not found. Install with: uv tool install vllm-mlx (or: pip install vllm-mlx)" >&2; exit 1; }
  REPO="$(resolve_model)"
  if [ -z "$REPO" ]; then
    echo "No MLX model specified. Pass a Hugging Face repo id (org/name), e.g.:
  mlx-serve.sh start mlx-community/Qwen2.5-Coder-14B-Instruct-4bit
List cached models with: hf cache ls   (or use /localclaude:local-models)." >&2
    exit 1
  fi
  CACHE_DIR="$(repo_cache_dir "$REPO")"
  if [ ! -d "$CACHE_DIR" ]; then
    echo "MLX model '$REPO' is not in the HF cache ($CACHE_DIR).
  Pull it:  HF_HOME=$HF_HOME hf download $REPO
  Or use /localclaude:local-models." >&2
    exit 1
  fi
}

case "$CMD" in
  start)
    start_mlx
    do_stop >/dev/null
    PORT="$(pick_port)"
    echo "Starting vllm-mlx: repo=$REPO port=$PORT (HF_HOME=$HF_HOME)"
    # Detach fully: stdin from /dev/null, stdout/stderr to log, and close fd 3
    # (harmless no-op normally; lets the daemon detach cleanly under a supervisor/bats).
    nohup env HF_HOME="$HF_HOME" "$MLX_BIN" serve "$REPO" --host 127.0.0.1 --port "$PORT" \
      </dev/null > "$LOG_FILE" 2>&1 3>&- &
    SRV_PID=$!
    echo "$SRV_PID" > "$PID_FILE"
    echo "$PORT"    > "$PORT_FILE"
    echo "$REPO"    > "$MODEL_FILE"
    echo "$REPO"    > "$LAST_MODEL_FILE"
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
  stop) do_stop ;;
  port) [ -f "$PORT_FILE" ] && cat "$PORT_FILE" || { echo "not running" >&2; exit 1; } ;;
  status)
    if is_alive; then
      echo "vllm-mlx: RUNNING (pid $(cat "$PID_FILE"), port $(cat "$PORT_FILE" 2>/dev/null), repo $(cat "$MODEL_FILE" 2>/dev/null))"
    else
      echo "vllm-mlx: stopped (no tracked process)"
    fi
    N="$(pgrep -f 'vllm-mlx serve' 2>/dev/null | wc -l | tr -d ' ')" || true
    if [ "${N:-0}" -gt 1 ]; then
      echo "WARNING: $N vllm-mlx processes detected — run 'mlx-serve.sh stop' to clean up:"
      pgrep -fl 'vllm-mlx serve' 2>/dev/null
    fi
    ;;
  foreground)
    # Run vllm-mlx in the FOREGROUND for a supervisor (e.g. launchd). Writes the state
    # files so status/stop stay consistent, then execs the server so this pid IS the server.
    start_mlx
    PORT="$(pick_port)"
    echo "$$"    > "$PID_FILE"
    echo "$PORT" > "$PORT_FILE"
    echo "$REPO" > "$MODEL_FILE"
    echo "$REPO" > "$LAST_MODEL_FILE"
    echo "foreground: repo=$REPO port=$PORT (HF_HOME=$HF_HOME)"
    exec env HF_HOME="$HF_HOME" "$MLX_BIN" serve "$REPO" --host 127.0.0.1 --port "$PORT"
    ;;
  __resolve) resolve_model ;;
  __port) pick_port ;;
  *) echo "usage: mlx-serve.sh [start [repo-id]|foreground|stop|status|port]" >&2; exit 1 ;;
esac
