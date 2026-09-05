#!/bin/bash
# Start / stop / inspect a local llama.cpp `llama-server` for use as a Claude Code backend.
# Used by toggle.sh for the `llama-cpp` backend; can also be run directly.
#
# Usage:
#   llama-serve.sh start [model.gguf]   # launch (auto-selects model + free port), wait until /health
#   llama-serve.sh stop                 # stop the managed server
#   llama-serve.sh status               # is it running? which model/port?
#   llama-serve.sh port                 # print the active port (for scripts)
#
# Config via env:
#   LOCAL_MODELS_DIR  GGUF directory (default ~/Local-Models)
#   LLAMACPP_PORT     force a specific port (default: auto-pick a free, uncommon port)
#   LLAMA_BIN         path to llama-server (default: first on PATH)
set -euo pipefail

LOCAL_MODELS_DIR="${LOCAL_MODELS_DIR:-$HOME/Local-Models}"
LLAMA_BIN="${LLAMA_BIN:-$(command -v llama-server || true)}"
STATE_DIR="$HOME/.claude"
PID_FILE="$STATE_DIR/llama-server.pid"
PORT_FILE="$STATE_DIR/llama-server.port"
MODEL_FILE="$STATE_DIR/llama-server.model"
LAST_MODEL_FILE="$STATE_DIR/llama-last-model"
LOG_FILE="$STATE_DIR/llama-server.log"

CMD="${1:-status}"
MODEL_ARG="${2:-}"

mkdir -p "$STATE_DIR"

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
    # give it a moment, then hard-kill if still up
    for _ in 1 2 3 4 5; do kill -0 "$pid" 2>/dev/null || break; sleep 0.4; done
    kill -9 "$pid" 2>/dev/null || true
    echo "Stopped llama-server (pid $pid)."
    did=1
  fi
  rm -f "$PID_FILE" "$PORT_FILE" "$MODEL_FILE"
  # Sweep any stray/orphan llama-server processes so nothing is ever left hanging
  # (e.g. one launched outside this script, or after a pid-file desync).
  local stray; stray="$(pgrep -f 'llama-server -m' 2>/dev/null || true)"
  if [ -n "$stray" ]; then
    echo "Cleaning up stray llama-server process(es): $(echo "$stray" | tr '\n' ' ')"
    for p in $stray; do kill "$p" 2>/dev/null || true; done
    sleep 0.5
    for p in $(pgrep -f 'llama-server -m' 2>/dev/null || true); do kill -9 "$p" 2>/dev/null || true; done
    did=1
  fi
  [ "$did" -eq 0 ] && echo "llama-server not running."
  return 0
}

resolve_model() {
  # 1) explicit arg  2) last-used  3) newest *.gguf in LOCAL_MODELS_DIR
  if [ -n "$MODEL_ARG" ]; then
    case "$MODEL_ARG" in
      /*) echo "$MODEL_ARG" ;;
      *)  echo "$LOCAL_MODELS_DIR/$MODEL_ARG" ;;
    esac
    return
  fi
  if [ -f "$LAST_MODEL_FILE" ]; then
    local last; last="$(cat "$LAST_MODEL_FILE")"
    [ -f "$last" ] && { echo "$last"; return; }
  fi
  # newest gguf (find, sort by mtime, no external sort dependency on stat format).
  # Convention: flat GGUFs directly under LOCAL_MODELS_DIR — -maxdepth 1 deliberately
  # ignores any HF hub cache tree (hub/models--*/snapshots/<hash>/*.gguf lives deeper).
  local newest
  newest="$(/usr/bin/find "$LOCAL_MODELS_DIR" -maxdepth 1 -type f -name '*.gguf' -print0 2>/dev/null \
            | xargs -0 ls -t 2>/dev/null | head -n1 || true)"
  echo "$newest"
}

pick_port() {
  if [ -n "${LLAMACPP_PORT:-}" ]; then echo "$LLAMACPP_PORT"; return; fi
  # Scan upward from an uncommon high port, skipping common dev defaults, and bind-test each.
  python3 - <<'PY'
import socket
BLOCK = {8080,8000,5000,5001,3000,5173,4200,8888,9000,5432,3306,6379,27017,11434}
p = 8730
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
    raise SystemExit("no free port found in 8730-9998")
PY
}

case "$CMD" in
  __resolve) resolve_model ;;
  stop) do_stop ;;
  port) [ -f "$PORT_FILE" ] && cat "$PORT_FILE" || { echo "not running" >&2; exit 1; } ;;
  status)
    if is_alive; then
      echo "llama-server: RUNNING (pid $(cat "$PID_FILE"), port $(cat "$PORT_FILE" 2>/dev/null), model $(basename "$(cat "$MODEL_FILE" 2>/dev/null)" 2>/dev/null))"
    else
      echo "llama-server: stopped (no tracked process)"
    fi
    N="$(pgrep -f 'llama-server -m' 2>/dev/null | wc -l | tr -d ' ')" || true
    if [ "${N:-0}" -gt 1 ]; then
      echo "WARNING: $N llama-server processes detected — run 'llama-serve.sh stop' to clean up:"
      pgrep -fl 'llama-server -m' 2>/dev/null
    fi
    ;;
  start)
    [ -n "$LLAMA_BIN" ] || { echo "llama-server not found. Install with: brew install llama.cpp" >&2; exit 1; }
    MODEL="$(resolve_model)"
    if [ -z "$MODEL" ] || [ ! -f "$MODEL" ]; then
      echo "No GGUF model found.
  - Pass one:        llama-serve.sh start <model.gguf>
  - Or put a .gguf in: $LOCAL_MODELS_DIR
  - Or use /localclaude:local-models to download one." >&2
      exit 1
    fi
    # Clean slate first — stop the tracked server AND sweep any orphans, so exactly one runs.
    do_stop >/dev/null
    PORT="$(pick_port)"

    # Metal: full GPU offload on Apple Silicon; otherwise let llama.cpp decide.
    NGL=()
    if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then
      NGL=(-ngl 999)
    fi

    echo "Starting llama-server: model=$(basename "$MODEL") port=$PORT ${NGL:+(Metal -ngl 999)}"
    nohup "$LLAMA_BIN" -m "$MODEL" --host 127.0.0.1 --port "$PORT" "${NGL[@]}" --jinja \
      > "$LOG_FILE" 2>&1 &
    SRV_PID=$!
    echo "$SRV_PID" > "$PID_FILE"
    echo "$PORT"      > "$PORT_FILE"
    echo "$MODEL"     > "$MODEL_FILE"
    echo "$MODEL"     > "$LAST_MODEL_FILE"

    # wait for readiness (up to ~60s)
    for _ in $(seq 1 120); do
      if ! kill -0 "$SRV_PID" 2>/dev/null; then
        echo "llama-server exited during startup. Last log lines:" >&2
        tail -n 20 "$LOG_FILE" >&2 || true
        rm -f "$PID_FILE" "$PORT_FILE" "$MODEL_FILE"
        exit 1
      fi
      if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
        echo "Ready: http://127.0.0.1:$PORT (log: $LOG_FILE)"
        exit 0
      fi
      sleep 0.5
    done
    echo "Timed out waiting for llama-server /health. Last log lines:" >&2
    tail -n 20 "$LOG_FILE" >&2 || true
    do_stop
    exit 1
    ;;
  foreground)
    # Run llama-server in the FOREGROUND for a supervisor (launchd LaunchAgent). Writes the
    # state files so status/stop stay consistent, then exec's the server so this pid
    # IS the server (launchd handles logging via StandardOutPath, and restart policy via KeepAlive).
    [ -n "$LLAMA_BIN" ] || { echo "llama-server not found. Install: brew install llama.cpp" >&2; exit 1; }
    MODEL="$(resolve_model)"
    if [ -z "$MODEL" ] || [ ! -f "$MODEL" ]; then
      echo "No GGUF model found in $LOCAL_MODELS_DIR" >&2; exit 1
    fi
    PORT="$(pick_port)"
    NGL=()
    if [ "$(uname -s)" = "Darwin" ] && [ "$(uname -m)" = "arm64" ]; then NGL=(-ngl 999); fi
    echo "$$"    > "$PID_FILE"
    echo "$PORT" > "$PORT_FILE"
    echo "$MODEL" > "$MODEL_FILE"
    echo "$MODEL" > "$LAST_MODEL_FILE"
    echo "foreground: model=$(basename "$MODEL") port=$PORT ${NGL:+(Metal -ngl 999)}"
    exec "$LLAMA_BIN" -m "$MODEL" --host 127.0.0.1 --port "$PORT" "${NGL[@]}" --jinja
    ;;
  *)
    echo "usage: llama-serve.sh [start [model.gguf]|foreground|stop|status|port]" >&2
    exit 1
    ;;
esac
