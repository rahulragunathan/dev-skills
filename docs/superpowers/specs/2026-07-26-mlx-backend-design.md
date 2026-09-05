# Design: MLX-LM backend for `localclaude:claude-toggle-backend`

**Date:** 2026-07-26
**Status:** Approved (design); pending implementation plan
**Scope:** Add a 4th local backend, `mlx`, to the `claude-toggle-backend` plugin, backed by a native-Anthropic MLX server on Apple Silicon. Additive — does not remove `anthropic`, `ollama`, or `llama-cpp`.

## 1. Motivation

MLX is Apple's native ML framework for Apple Silicon and generally delivers higher tokens/sec than llama.cpp Metal for comparable models. The user wants MLX available as a selectable Claude Code backend through the existing toggle plugin, with models downloaded from Hugging Face into the shared `~/Local-Models` directory (same as the llama.cpp backend).

## 2. Key constraint & server choice

Claude Code talks to a backend via `ANTHROPIC_BASE_URL`, which must serve the **Anthropic Messages API (`/v1/messages`)**. The existing `ollama` and `llama-cpp` backends work because each exposes that endpoint natively.

**Apple's official `mlx_lm.server` is OpenAI-compatible only** — no `/v1/messages`. So MLX needs either a translation shim (rejected: extra process, more moving parts) or a third-party MLX server that speaks Anthropic natively (chosen).

**Chosen server: [`vllm-mlx`](https://github.com/waybarrios/vllm-mlx)** (`waybarrios/vllm-mlx`).

| Factor | vllm-mlx (chosen) | mlx-serve (fallback) |
| --- | --- | --- |
| Install | `uv tool install vllm-mlx` / pip (Python 3.10+) | `brew`, no Python |
| Start | `vllm-mlx serve <model-path> --port N` — explicit model, one process per model | `mlx-serve run <name>` — daemon / on-demand |
| Anthropic `/v1/messages` | native (tool-use, streaming) | native (tool-use, extended thinking) |
| Readiness probe | `GET /v1/models` | undocumented |
| Maturity | 1.4k★, active (v0.4.0, Jun 2026) | newer, macOS-app-centric |
| Fit to plugin | **near-clone of `llama-serve.sh`** | resembles the Ollama backend |

Rationale: vllm-mlx's "launch one process for an explicit model path, wait for readiness, stop on switch-away" lifecycle is structurally identical to the existing `llama-serve.sh`, so the new backend is a disciplined clone rather than a new paradigm. `mlx-serve` remains the documented fallback if a Python-free install is preferred later.

## 3. Architecture

Add backend `mlx` to `toggle.sh`, backed by a new **`mlx-serve.sh`** (start / stop / status / port / foreground) that is a near-clone of `llama-serve.sh`. `ANTHROPIC_BASE_URL` points directly at vllm-mlx's native Anthropic endpoint — no translation layer, exactly like llama.cpp.

**One local model resident at a time** (24 GB unified-memory constraint): switching to `mlx` stops any `llama-server`; switching to any other backend stops the mlx server. Enforced in `toggle.sh`.

## 4. `mlx-serve.sh` — new script

Near-clone of `llama-serve.sh`, with these differences:

- **Binary:** `vllm-mlx serve <model-dir> --host 127.0.0.1 --port <port>`. Check `command -v vllm-mlx`; if missing, error with install instructions (`uv tool install vllm-mlx`, isolated — mirrors how `llama-serve.sh` errors with `brew install llama.cpp`). Actual install stays a **user-confirmed action**, never run silently.
- **Binary override:** honor `MLX_BIN` env (default: first `vllm-mlx` on PATH), mirroring `LLAMA_BIN`.
- **Model format & storage:** MLX models are HF **repo directories** (from `mlx-community/`), not `.gguf` files — `config.json` + `*.safetensors` + tokenizer files. They live under `~/Local-Models/<model-dir>/`, coexisting with GGUFs (dirs vs files).
- **Model resolution** (differs from llama's "newest `*.gguf`"): explicit arg (absolute path, or dir-name resolved under `$LOCAL_MODELS_DIR`) → last-used (`~/.claude/mlx-last-model`) → **newest directory containing `config.json`** in `$LOCAL_MODELS_DIR`. If none found, error pointing at `/localclaude:local-models`.
- **Readiness:** wait on `GET http://127.0.0.1:<port>/v1/models` returning 200 (universal for OpenAI-compat servers; vllm-mlx has no documented `/health`). Same ~60s timeout + log-tail-on-failure behavior as llama-serve.
- **Apple Silicon guard:** MLX runs only on Apple Silicon. If `uname -s` != Darwin or `uname -m` != arm64, error clearly. No `-ngl` flag (MLX uses the GPU automatically).
- **Port picking:** reuse llama-serve's `pick_port` logic (scan upward from an uncommon high port, skip common dev ports, bind-test). Honor `MLX_PORT` override. Chosen port saved to `~/.claude/mlx-server.port`.
- **State files:** `~/.claude/mlx-server.{pid,port,model}`, `~/.claude/mlx-last-model`, log `~/.claude/mlx-server.log`. Same `is_alive` / `do_stop` (with stray-process sweep matching `vllm-mlx serve`) / `foreground` structure as llama-serve.
- **`foreground` subcommand:** kept for symmetry / optional future LaunchAgent, but no autostart script is shipped in this scope (see §8).

## 5. `toggle.sh` changes

- **New `mlx` case:** delegate to `mlx-serve.sh start [model]`, read `port`, set `BASE_URL=http://127.0.0.1:<port>` (no `/v1` — the SDK appends `/v1/messages`), `TOKEN=mlx`, `MODEL=<dir basename>`.
- **Stop the other local servers on every switch** (one-model-at-a-time): `mlx` stops `llama-serve`; `anthropic`/`ollama`/`llama-cpp` stop `mlx-serve` (and llama-serve as today).
- **Detection — marker file.** Today: `11434→ollama, other-url→llama-cpp, empty→anthropic`. With two non-ollama local URLs, the URL alone cannot distinguish `llama-cpp` from `mlx`. Fix: `toggle.sh` writes a marker file **`~/.claude/local-backend`** on every switch (`anthropic|ollama|llama-cpp|mlx`) as the source of truth for *which* backend. `current_backend()` logic:
  1. If `ANTHROPIC_BASE_URL` empty → `anthropic`.
  2. Else if URL contains `11434` → `ollama`.
  3. Else read `~/.claude/local-backend`; if it says `mlx` or `llama-cpp`, trust it; if missing/ambiguous, corroborate via live pid files (`mlx-server.pid` vs `llama-server.pid`), defaulting to `llama-cpp` for backward compatibility.
  The marker is also updated for `anthropic`/`ollama` so it never goes stale.
- **No-arg blind `toggle` flip → anthropic ⇄ mlx** (was anthropic ⇄ ollama). Any local backend → `anthropic`; `anthropic` → `mlx`. Makes MLX the default local driver.
- **`status`** additionally prints mlx-serve status (calls `mlx-serve.sh status`), alongside the existing llama-serve status line.
- **Config env:** add `MLX_MODEL` (optional explicit model dir/name) and `MLX_PORT`, documented alongside the existing `OLLAMA_MODEL` / `LLAMACPP_PORT` / `LOCAL_MODELS_DIR`.

## 6. `local-models` skill — MLX download path

Add an MLX branch to `local-models/SKILL.md` (and the delegation map in `REFERENCE.md`):

- **Model source:** MLX-format models from the `mlx-community` Hugging Face org (e.g. `mlx-community/Qwen2.5-Coder-14B-Instruct-4bit`). These are pre-quantized to MLX format; pick 4-bit for the 24 GB sweet spot (~8–9 GB for a 14B).
- **Download into `~/Local-Models` as a directory:**

  ```bash
  hf download mlx-community/<Model>-4bit --local-dir "${LOCAL_MODELS_DIR:-$HOME/Local-Models}/<Model>-4bit"
  ```

- **Hand to the backend:** `/localclaude:claude-toggle-backend mlx <Model>-4bit`.
- The existing `huggingface-local-models` delegate is GGUF-specific, so MLX gets its own short recipe rather than routing through it. `hf-mem` still applies for footprint estimation.
- Note the backend-choice menu now includes **mlx** (Apple-Silicon, MLX-native) alongside llama.cpp / Ollama; MLX and llama.cpp are mutually exclusive at runtime (one model resident).

## 7. Docs & versioning

- `claude-toggle-backend/SKILL.md` — document the 4th backend, the `mlx` invocation, `MLX_MODEL`/`MLX_PORT`, the marker-file detection, and the anthropic⇄mlx blind-toggle change. Bump skill `version`.
- `README.md` (plugin root) — mention the mlx backend.
- `.claude-plugin/plugin.json` — bump plugin version.
- Optional alias block parity: add a `claude-mlx` alias example in SKILL.md (mirrors `claude-llama`).

## 8. Out of scope (YAGNI)

- **mlx autostart LaunchAgent** — the `mlx-serve.sh foreground` subcommand exists for symmetry, but no `mlx-autostart.sh` is shipped now; the llama autostart already documents that pattern if wanted later.
- **mlx-serve (ddalcu) fallback wiring** — documented as an alternative, not implemented.
- **Retrofitting tests onto the untouched existing scripts.**

## 9. Testing strategy

The plugin currently has **no test harness**. Per project conventions (TDD; set up a harness before behavior changes), introduce a proportionate **bats-core** harness covering the new and changed **pure logic**, with external boundaries **faked**:

- **Fakes:** a stub `vllm-mlx` executable placed on a test `PATH` (records args, simulates a server), and a fake readiness probe (stub `curl` or a controllable local responder) so `GET /v1/models` can be made to pass/fail deterministically. No real model or inference in tests.
- **Covered:**
  - `mlx-serve.sh` model resolution (explicit path / dir-name / last-used / newest-`config.json`-dir / none-found error).
  - `mlx-serve.sh` port picking honoring `MLX_PORT` and skipping busy ports.
  - `mlx-serve.sh` Apple-Silicon guard (fake `uname`).
  - `mlx-serve.sh` readiness success + timeout/exit-on-crash paths (fast-forwarded via fakes).
  - `toggle.sh` `current_backend()` detection across all four states incl. marker-file + pid-file corroboration and backward-compat default.
  - `toggle.sh` JSON patching writes valid JSON and touches only `model` / `effortLevel` / `env.ANTHROPIC_*` (+ marker), preserving `permissions` and other keys.
- **Not covered by automated tests:** real model download, real inference, real tool-use — these are **manual sign-off**: a first-run smoke test in Claude Code (switch to `mlx`, restart, confirm a tool-using task completes).
- **Verify gate:** `bats` suite green + `python3 -m json.tool ~/.claude/settings.json` valid after a switch.

## 10. Prerequisites (documented, not auto-installed)

- Apple Silicon Mac.
- `vllm-mlx` on PATH (`uv tool install vllm-mlx` or `pip install vllm-mlx`) — surfaced by `mlx-serve.sh` with the install command; user confirms.
- `hf` CLI for downloads (already required by `local-models`).
- At least one MLX model directory under `~/Local-Models` (via `/localclaude:local-models`).
- `bats-core` for running the test suite (`brew install bats-core`) — dev-only.

## 11. Risks / least-confident areas

- **vllm-mlx Anthropic tool-use fidelity** under Claude Code's heavy tool traffic — mitigated by the manual smoke test as a gate before declaring done.
- **vllm-mlx readiness semantics** — assuming `GET /v1/models` returns 200 only once the model is loaded; if it returns early, add a follow-up probe (a tiny `/v1/messages` completion) — to confirm during implementation.
- **Marker-file drift** if the user hand-edits `settings.json` — mitigated by pid-file corroboration and the backward-compat default to `llama-cpp`.
