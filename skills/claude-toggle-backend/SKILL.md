---
name: claude-toggle-backend
version: 2.1.0
description: Switch the local Claude Code backend between the Anthropic API, a local Ollama server, a local llama.cpp (llama-server, Metal-accelerated) server, and a local MLX (vllm-mlx, Apple Silicon) server. Non-destructively patches only model + effortLevel + ANTHROPIC_* env keys in ~/.claude/settings.json (preserving the permission allowlist and everything else) via the bundled toggle.sh, and auto-manages the llama-server / vllm-mlx process for the llama-cpp / mlx backends. Use when the user wants to run Claude Code on local models (Ollama, llama.cpp, or MLX), switch back to Anthropic, work offline, or asks which backend is active.
license: MIT
---

# claude-toggle-backend

Switch the local Claude Code backend (VS Code extension + CLI) between four backends:

- **anthropic** (default, cloud) — `model: opus[1m]` (current Opus, 1M context), `effortLevel: high`, no `ANTHROPIC_BASE_URL`.
- **ollama** (local daemon) — points `ANTHROPIC_BASE_URL` at the Ollama server's Anthropic-compatible `/v1/messages` endpoint (`:11434`). Assumes `ollama serve` is up.
- **llama-cpp** (local, Metal) — **auto-starts a `llama-server`** for a GGUF model and points `ANTHROPIC_BASE_URL` at its native Anthropic `/v1/messages` endpoint. Stops the server when you switch away.
- **mlx** (local, Apple Silicon) — **auto-starts a `vllm-mlx` server** for an MLX model (given by **HF repo id**, resolved from the HF cache) and points `ANTHROPIC_BASE_URL` at its native Anthropic `/v1/messages` endpoint. Generally faster tok/s than llama.cpp on Apple Silicon. Stops the server when you switch away.

Only one local model is resident at a time (24 GB constraint): switching to `mlx` stops any `llama-server`, and switching to any other backend stops the mlx server.

It edits **only** `model`, `effortLevel`, and the `env.ANTHROPIC_*` keys in `~/.claude/settings.json`, so `permissions` allow/deny and everything else are preserved. (The naive "copy a whole settings file over settings.json" approach would clobber them — don't.)

## How to run it

```bash
TB="$CLAUDE_PLUGIN_ROOT/skills/claude-toggle-backend/toggle.sh"   # inside the plugin
bash "$TB" status                       # show current backend + llama-server state
bash "$TB" anthropic                    # switch to Anthropic (opus[1m], High effort)
bash "$TB" ollama                       # switch to local Ollama
bash "$TB" llama-cpp                     # start llama-server on newest/last GGUF + switch to it
bash "$TB" llama-cpp qwen2.5-coder-14b-instruct-q4_k_m.gguf   # pick a specific GGUF
bash "$TB" mlx                          # start vllm-mlx on last-used MLX repo + switch to it
bash "$TB" mlx mlx-community/Qwen2.5-Coder-14B-Instruct-4bit   # pick a specific MLX repo (must be cached)
bash "$TB"                              # toggle: any local -> anthropic, anthropic -> mlx
```

`$CLAUDE_PLUGIN_ROOT` is set by Claude Code when the skill runs inside the `localclaude` plugin. If running by hand, use the absolute path to `toggle.sh`.

After switching, **fully quit Claude Code (Cmd+Q) and reopen** — config is read at process start; "Reload Window" only resumes the stale process. Only `status` is meaningful without a restart.

## When invoked as a skill

1. Run `toggle.sh status` to see the current backend and whether a llama-server / vllm-mlx is running.
2. Switch per the user's request (`anthropic` / `ollama` / `llama-cpp [model.gguf]` / `mlx [repo-id]`), or flip with no argument (anthropic ⇄ mlx).
3. For `llama-cpp`, the script blocks until `llama-server` answers `/health`; for `mlx`, until `vllm-mlx` answers `/v1/models`. If a GGUF/cached MLX repo isn't found it points the user at `/localclaude:local-models`.
4. Confirm `python3 -m json.tool ~/.claude/settings.json` stays valid (toggle.sh writes valid JSON).
5. Tell the user which backend is active and that a full **Cmd+Q + reopen** is required.

## Backends in detail

### llama-cpp (auto-managed `llama-server`)

`toggle.sh llama-cpp` delegates to `llama-serve.sh`, which:

- **Selects the model**: explicit arg → last-used (`~/.claude/llama-last-model`) → newest `*.gguf` in `$LOCAL_MODELS_DIR` (default `~/Local-Models`).
- **Picks a free port**: honors `$LLAMACPP_PORT`, else scans upward from `8730` skipping common dev ports (8080/8000, 5000/5001, 3000, 5173, 4200, 8888, 9000, 5432, 3306, 6379, 27017, 11434) and bind-tests it. The chosen port is saved to `~/.claude/llama-server.port`.
- **Enables Metal**: on Apple Silicon (`uname -s`=Darwin, `uname -m`=arm64) it adds `-ngl 999` (full GPU offload). Always passes `--jinja` so tool-use works.
- Launches in the background (PID in `~/.claude/llama-server.pid`, log in `~/.claude/llama-server.log`) and waits for `/health`.
- `ANTHROPIC_BASE_URL` is set to `http://127.0.0.1:<port>` **without** `/v1` — the Anthropic SDK appends `/v1/messages` itself (same convention the Ollama backend uses).

Manage the server directly if needed:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/claude-toggle-backend/llama-serve.sh" status|stop|port
```

### mlx (auto-managed `vllm-mlx`)

`toggle.sh mlx` delegates to `mlx-serve.sh`, which:

- **Requires Apple Silicon** (`uname -s`=Darwin, `uname -m`=arm64) — errors clearly otherwise. MLX uses the GPU automatically (no `-ngl` flag).
- **Selects the model by HF repo id**: explicit arg (e.g. `mlx-community/Qwen2.5-Coder-14B-Instruct-4bit`) → last-used (`~/.claude/mlx-last-model`). The repo must already be in the **HF cache** at `$HF_HOME/hub` (`HF_HOME` defaults to `$LOCAL_MODELS_DIR`); if it isn't, the script prints the `hf download` command and stops. Unlike GGUFs (flat files), MLX models live in the content-addressed HF cache and are served by repo id — the server is launched as `HF_HOME=… vllm-mlx serve <repo-id>`.
- **Picks a free port**: honors `$MLX_PORT`, else scans upward from `8740` (skipping common dev ports) and bind-tests it. Saved to `~/.claude/mlx-server.port`.
- **Checks `vllm-mlx` is installed** (`uv tool install vllm-mlx`); if missing it prints the install command and stops.
- Launches in the background (PID in `~/.claude/mlx-server.pid`, log in `~/.claude/mlx-server.log`) and waits for `GET /v1/models` (vllm-mlx has no `/health`).
- `ANTHROPIC_BASE_URL` is set to `http://127.0.0.1:<port>` **without** `/v1` — the Anthropic SDK appends `/v1/messages` itself (same convention as the other local backends). The settings `model` is set to the repo id.

Manage the server directly if needed:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/claude-toggle-backend/mlx-serve.sh" status|stop|port
```

### Detection (port-agnostic)

`status`/`toggle` read `env.ANTHROPIC_BASE_URL`: absent ⇒ anthropic; contains `11434` ⇒ ollama; any other non-empty value ⇒ a local server (**mlx** or **llama-cpp**), disambiguated by the marker file `~/.claude/local-backend` (written on every switch), defaulting to `llama-cpp` when the marker is missing/unknown.

## Config (override without editing scripts)

- `OLLAMA_MODEL` (default `gemma4:latest` — fits 24 GB with headroom; see notes)
- `ANTHROPIC_MODEL` (default `opus[1m]`)
- `LLAMACPP_PORT` (default: auto-picked free port)
- `MLX_PORT` (default: auto-picked free port), `MLX_BIN` (default: `vllm-mlx` on PATH)
- `HF_HOME` (default: `$LOCAL_MODELS_DIR` — the HF cache root the mlx backend serves from; set globally in `~/.zshrc`)
- `LOCAL_MODELS_DIR` (default `~/Local-Models`)

e.g. `OLLAMA_MODEL=qwen2.5-coder:14b bash "$TB" ollama`

## Optional: terminal aliases

```bash
alias claude-anthropic='bash "<abs>/toggle.sh" anthropic'
alias claude-ollama='bash "<abs>/toggle.sh" ollama'
alias claude-llama='bash "<abs>/toggle.sh" llama-cpp'
alias claude-mlx='bash "<abs>/toggle.sh" mlx'
alias claude-backend='bash "<abs>/toggle.sh" status'
```

## Prerequisites

- **Ollama backend**: `ollama serve` running (`curl -s http://localhost:11434/api/version`), models pulled (`ollama list`). Ollama exposes Anthropic-style `/v1/messages` at `:11434`.
- **llama-cpp backend**: `llama-server` on PATH (`brew install llama.cpp`; Metal on by default on Apple Silicon). At least one `*.gguf` in `~/Local-Models` (use `/localclaude:local-models` to fetch one).
- **mlx backend**: Apple Silicon Mac; `vllm-mlx` on PATH (`uv tool install vllm-mlx`, or `pip install vllm-mlx`). At least one MLX model in the **HF cache** — pull by repo id: `HF_HOME=~/Local-Models hf download mlx-community/<name>` (or use `/localclaude:local-models`); list with `hf cache ls`. `HF_HOME=~/Local-Models` should be set globally in `~/.zshrc`.

## Notes

- **Machine sizing (24 GB unified memory):** `gemma4:latest` (~9.6 GB) and 14B-class Q4 models (~9 GB) leave healthy headroom. The previously-installed `qwen3.6:latest` is **~23 GB** — it leaves ~1 GB free and will swap/OOM, so it's a poor default; only use it when you dedicate the machine. Use `/localclaude:local-models` to find/download right-sized models.
- Local models are weaker at tool-use and long context than Opus — expect quality degradation on complex agentic coding tasks.
- The local backends set `ANTHROPIC_API_KEY=""` to avoid conflicts with a real key in the environment.
