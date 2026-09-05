#!/bin/bash
# Switch the local Claude Code backend between Anthropic, local Ollama, local llama.cpp, and local MLX.
# NON-DESTRUCTIVE: patches only `model`, `effortLevel`, and the `env.ANTHROPIC_*` keys in
# ~/.claude/settings.json — permissions (allow/deny), plugins, and everything else are preserved.
# Also writes ~/.claude/local-backend (marker: which local backend is active).
#
# Usage: toggle.sh [anthropic|ollama|llama-cpp [model.gguf]|mlx [repo-id]|toggle|status]   (default: toggle)
#   toggle (no arg) flips anthropic <-> mlx.
# Overrides via env: OLLAMA_MODEL=... ANTHROPIC_MODEL=... LLAMACPP_PORT=... MLX_PORT=... LOCAL_MODELS_DIR=...
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
MARKER="$HOME/.claude/local-backend"   # which local backend is active (mlx vs llama-cpp)
OLLAMA_MODEL="${OLLAMA_MODEL:-gemma4:latest}"    # fits 24GB w/ headroom; see local-models for stronger fits
ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-opus[1m]}"   # Opus 4.8, 1M context
OLLAMA_URL="http://localhost:11434"
TARGET="${1:-toggle}"
MODEL_ARG="${2:-}"

[ -f "$SETTINGS" ] || { echo "No $SETTINGS found." >&2; exit 1; }

current_backend() {
  # anthropic: no base url. ollama: url has :11434. Otherwise a local server
  # (mlx or llama-cpp) — disambiguated by the marker file, defaulting to
  # llama-cpp for backward compatibility when the marker is missing/unknown.
  python3 - "$SETTINGS" "$MARKER" <<'PY'
import json, sys
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

if [ "$TARGET" = "__detect" ]; then current_backend; exit 0; fi

if [ "$TARGET" = "status" ]; then
  BK="$(current_backend)"
  MODEL="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("model"))' "$SETTINGS")"
  echo "current backend: $BK (model: $MODEL)"
  bash "$SCRIPT_DIR/llama-serve.sh" status
  bash "$SCRIPT_DIR/mlx-serve.sh" status
  exit 0
fi

if [ "$TARGET" = "toggle" ]; then
  # simple flip: any local backend -> anthropic; anthropic -> mlx (default local driver)
  [ "$(current_backend)" = "anthropic" ] && TARGET="mlx" || TARGET="anthropic"
fi

# Compute the values to write, and manage the llama-server process lifecycle.
EFFORT=""
case "$TARGET" in
  anthropic)
    bash "$SCRIPT_DIR/llama-serve.sh" stop >/dev/null 2>&1 || true
    bash "$SCRIPT_DIR/mlx-serve.sh"   stop >/dev/null 2>&1 || true
    MODEL="$ANTHROPIC_MODEL"; BASE_URL=""; TOKEN=""; EFFORT="high"
    ;;
  ollama)
    bash "$SCRIPT_DIR/llama-serve.sh" stop >/dev/null 2>&1 || true
    bash "$SCRIPT_DIR/mlx-serve.sh"   stop >/dev/null 2>&1 || true
    MODEL="$OLLAMA_MODEL"; BASE_URL="$OLLAMA_URL"; TOKEN="ollama"
    ;;
  llama-cpp|llamacpp|llama)
    TARGET="llama-cpp"
    bash "$SCRIPT_DIR/mlx-serve.sh" stop >/dev/null 2>&1 || true
    bash "$SCRIPT_DIR/llama-serve.sh" start "$MODEL_ARG"   # selects model+port, waits for /health
    PORT="$(bash "$SCRIPT_DIR/llama-serve.sh" port)"
    MODEL="$(basename "$(cat "$HOME/.claude/llama-server.model")")"
    BASE_URL="http://127.0.0.1:$PORT"   # NO /v1 — the Anthropic SDK appends /v1/messages itself
    TOKEN="llamacpp"
    ;;
  mlx)
    bash "$SCRIPT_DIR/llama-serve.sh" stop >/dev/null 2>&1 || true
    bash "$SCRIPT_DIR/mlx-serve.sh" start "$MODEL_ARG"     # resolves repo-id from HF cache, waits for /v1/models
    PORT="$(bash "$SCRIPT_DIR/mlx-serve.sh" port)"
    MODEL="$(cat "$HOME/.claude/mlx-server.model")"        # HF repo id (org/name)
    BASE_URL="http://127.0.0.1:$PORT"   # NO /v1 — the Anthropic SDK appends /v1/messages itself
    TOKEN="mlx"
    ;;
  *)
    echo "usage: toggle.sh [anthropic|ollama|llama-cpp [model.gguf]|mlx [repo-id]|toggle|status]" >&2
    exit 1
    ;;
esac

python3 - "$SETTINGS" "$TARGET" "$MODEL" "$BASE_URL" "$TOKEN" "$EFFORT" <<'PY'
import json, sys
path, target, model, base_url, token, effort = sys.argv[1:7]
cfg = json.load(open(path))
env = cfg.get("env", {})

cfg["model"] = model
if target == "anthropic":
    for k in ("ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY"):
        env.pop(k, None)
    if env:
        cfg["env"] = env
    else:
        cfg.pop("env", None)
    if effort:
        cfg["effortLevel"] = effort
else:  # ollama / llama-cpp / mlx
    env.update({"ANTHROPIC_BASE_URL": base_url,
                "ANTHROPIC_AUTH_TOKEN": token,
                "ANTHROPIC_API_KEY": ""})
    cfg["env"] = env

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
print("switched to", target, "(model:", cfg.get("model"), ")")
PY

write_marker "$TARGET"   # record which backend is active (source of truth for detection)

echo "Reload to apply: fully quit Claude Code (Cmd+Q) and reopen — Reload Window only resumes the stale process."
