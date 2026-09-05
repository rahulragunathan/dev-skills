---
name: local-models
version: 1.2.0
description: Discover, recommend, download, inventory, and remove local LLMs for the llama.cpp, Ollama, and MLX (Apple Silicon / vllm-mlx) Claude Code backends — sized to this machine's RAM and chosen by use case (coding, or document-retrieval/RAG & analysis). Orchestrates the huggingface-skills plugin (huggingface-best, huggingface-local-models, hf-cli, hf-mem), the Ollama CLI, and the HF cache; keeps GGUFs as flat files under ~/Local-Models and MLX models in the HF cache at ~/Local-Models/hub. Use when the user wants to find the best local model for a task, pull/remove a GGUF, MLX, or Ollama model, see what's installed, or pick a model to serve via claude-toggle-backend.
license: MIT
---

# local-models

A router/orchestrator for the local-model lifecycle. It **delegates** the heavy lifting to the installed `huggingface-skills` plugin and the Ollama CLI rather than reimplementing them, and keeps models in one place (`$LOCAL_MODELS_DIR`, default `~/Local-Models`) that `claude-toggle-backend` also reads:

- **GGUFs** (llama.cpp) → flat files at the top level of `$LOCAL_MODELS_DIR`.
- **MLX models** (mlx / `vllm-mlx`) → the **HF cache** at `$LOCAL_MODELS_DIR/hub`, addressed by repo id.

Both share **`HF_HOME=$LOCAL_MODELS_DIR`** (set globally in `~/.zshrc`), so every `hf` command in this skill runs with that `HF_HOME` — explicitly, so it stays correct even in a shell that hasn't loaded the profile.

See `REFERENCE.md` for the model-sizing cheat-sheet, quantization table, and the full delegation map.

## Dependencies — check first, and WARN before installing anything

This skill orchestrates other tools. At the start, check what's present; if something's missing, **tell the user exactly what you'd install and why, and get their OK before installing — never install silently.**

- **`huggingface-skills` plugin** (provides `huggingface-best`, `huggingface-local-models`, `hf-cli`, `hf-mem`) — required to recommend/find models. **`claude-setup` disables this plugin by default to save context** (its ~25 skill descriptions load into every session), so the usual state is *installed but off*: check `enabledPlugins`, and if it's `false`, tell the user to re-enable via `/plugin` → enable `huggingface-skills` → full Cmd+Q restart for this session's model work (and that they can turn it back off after). If it's not installed at all, surface and confirm before: `/plugin install huggingface-skills@claude-plugins-official` (a plugin install + restart is a **user action** — give the command and the reason, don't assume).
- **`hf` CLI** (Hugging Face Hub CLI) — required to download GGUFs and MLX models, and to inventory/remove MLX models (`hf cache ls`/`rm`). Check `command -v hf`. If missing, confirm then: `brew install huggingface-cli`.
- **`ollama`** — only if the user chose the Ollama backend. Check `command -v ollama` (or `curl -fsS http://localhost:11434/api/version`). If missing, confirm then: `brew install ollama`.
- **`llama-server`** (llama.cpp) — only needed to *serve* a GGUF; `claude-toggle-backend` checks it and prompts `brew install llama.cpp`. Not needed just to download.
- **`vllm-mlx`** (MLX backend, Apple Silicon) — only if the user chose the mlx backend, and only needed to *serve*; `claude-toggle-backend` checks it and prompts `uv tool install vllm-mlx`. Not needed just to download.
- **`HF_HOME=$LOCAL_MODELS_DIR`** — the plugin's `~/.zshrc` block sets this globally; verify with `echo $HF_HOME`. This skill also passes it explicitly on every `hf` command, so MLX downloads/inventory land in `$LOCAL_MODELS_DIR/hub` regardless.
- **⚠️ HF auth is per-`HF_HOME` — check it before any download.** The `hf` CLI reads its token from **`$HF_HOME/token`**. Because this skill forces `HF_HOME=$LOCAL_MODELS_DIR`, a normal `hf auth login` (which writes `~/.cache/huggingface/token`) is **invisible here** — `hf auth whoami` reports `Not logged in` and downloads then **stall at 0 bytes** (Xet throttles unauthenticated transfers) with no clear error. Diagnose by comparing both homes:

  ```bash
  HF_HOME="${LOCAL_MODELS_DIR:-$HOME/Local-Models}" hf auth whoami   # skill's view
  HF_HOME="$HOME/.cache/huggingface"                 hf auth whoami   # default view
  ```

  If the first fails and the second succeeds, copy the token across (no re-login needed):

  ```bash
  cp "$HOME/.cache/huggingface/token" "${LOCAL_MODELS_DIR:-$HOME/Local-Models}/token"
  chmod 600 "${LOCAL_MODELS_DIR:-$HOME/Local-Models}/token"
  ```

  If *both* fail, the user must run `hf auth login` themselves (interactive — paste a read token from <https://huggingface.co/settings/tokens>). Note that a successful `curl` against HF leaderboard/dataset APIs is **not** proof of auth — those endpoints are public.

CLI installs (brew) the agent may run **after the user confirms**; the `huggingface-skills` plugin install + restart is the user's to do — present the command and why.

## Machine context (always establish first)

Recommendations must fit this machine. Detect and feed RAM into the recommendation step:

```bash
echo "RAM: $(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) GB, cores: $(sysctl -n hw.ncpu), arch: $(uname -m)"
```

**Always trust the detected value over anything written here** — this line has been wrong before. As of 2026-07-26 this Mac is an **Apple M4 Max, 64 GB unified memory**, 16 cores (12P/4E), **546 GB/s** memory bandwidth.

Target models that leave **≥ 12–16 GB** free for the OS + KV cache: **~30–48 GB** on disk/RAM is the sweet spot (e.g. a dense 27B at 6–8 bit ≈ 23–30 GB, or a 35B-A3B MoE at 8-bit ≈ 38 GB). See `REFERENCE.md` for the exact math. Use `huggingface-skills:hf-mem` to estimate a specific model's footprint before downloading.

### Speed math — quantization is a weak lever, architecture is the strong one

Decode is **memory-bandwidth-bound**: each token reads the weights it activates, so
`tok/s ≈ (bandwidth × ~0.8) / GB-read-per-token`. On this 546 GB/s machine:

- **Dense** models read *everything* every token. Dropping quant only shrinks the bytes, so the whole 8-bit→4-bit ladder buys at most **~1.8x** — and 4-bit costs real coding accuracy. Measured sizes for Qwen3.6-27B: 8-bit 29.5 GB ≈ 15 tok/s, 6-bit 22.7 GB ≈ 19, 5-bit 19.4 GB ≈ 22, 4-bit 16.0 GB ≈ 27.
- **MoE** models read only the active experts. A 35B-A3B (3B active) runs **~5x** a dense 27B at similar total size.

So when a user asks for "far more tok/s", **don't reach for a lower quant** — that caps out at 1.8x. Offer the MoE, and state the quality cost explicitly. Conversely 8-bit→6-bit is near-lossless (~1%) and free-ish speed, so it's a good default.

## Choose backend(s) — ask first, default llama.cpp only

Before recommending/downloading, ask which local backend(s) the user wants. **Default to llama.cpp only** unless they say otherwise:

- **llama.cpp (default, recommended)** — Metal-accelerated, efficient, single-instance; drives the Claude Code `llama-cpp` backend. GGUFs live in `$LOCAL_MODELS_DIR`.
- **Ollama** — convenient daemon, native Raycast support. **Check it's running before using it** (the user may have disabled it from startup):

  ```bash
  curl -fsS http://localhost:11434/api/version >/dev/null 2>&1 && echo "Ollama: running" || echo "Ollama: NOT running"
  ```

  ⚠️ `ollama` CLI commands (`list`/`pull`/`run`/`rm`) **auto-start the daemon** even if it was disabled — so don't run them unless the user opted into Ollama. If Ollama is off and they want it, confirm before starting it.
- **mlx (Apple Silicon, MLX-native)** — Metal-native serving via `vllm-mlx`; drives the Claude Code `mlx` backend. MLX models are served by **HF repo id** and live in the **HF cache** at `$LOCAL_MODELS_DIR/hub` (`HF_HOME=$LOCAL_MODELS_DIR`) — inspect with `hf cache ls`. Generally faster tok/s than llama.cpp on Apple Silicon. Mutually exclusive with llama.cpp at runtime (one model resident).
- **Multiple** — set up more than one (e.g. llama.cpp + mlx). They coexist on disk but are mutually exclusive at runtime (one model resident).

Do Ollama steps (pull/list/rm) only if the user opted into Ollama. The mlx backend needs `vllm-mlx` (`uv tool install vllm-mlx`) and an Apple-Silicon Mac; `claude-toggle-backend` checks it and prompts to install — not needed just to download.

## Recommend a model — by use case

Drive `huggingface-skills:huggingface-best` (it parses task → benchmarks → device filter) with one of these **profiles**, passing the detected RAM so it only suggests models that fit:

1. **Coding / agentic (default for the Claude Code backend).** Ask for top *code & tool-use* models. The benchmarks that actually matter here are **`SWE-bench/SWE-bench_Verified`** (code fixing) and **`harborframework/terminal-bench-2.0`** (agentic tool use — weight this highest for a Claude Code backend); `ScaleAI/SWE-bench_Pro` and `LiquidAI/ifstruct-v1.0` (structured output / function-calling) are useful secondaries.

   ⚠️ These leaderboards are topped by 250B–400B models that **cannot fit in 64 GB** — always filter to the RAM budget before recommending, and don't be surprised when a small model beats a huge one (Qwen3.6-27B's SWE-V 77.2 beats Qwen3.5-397B-A17B's 76.4).

   Known-good picks for this machine as of 2026-07-26 (re-verify, don't assume):
   - **`Qwen/Qwen3.6-27B`** — dense 27B, Apache 2.0. SWE-V **77.2**, terminal-bench **59.3** (7th overall). Best agentic quality that fits. 6-bit (22.7 GB) is the sweet spot; 8-bit (29.5 GB) if you want max quality.
   - **`Qwen/Qwen3.6-35B-A3B`** — MoE, 3B active. terminal-bench 51.5 — ~8 points worse, but **~5x the tok/s**. Pick this only when throughput beats accuracy.

   `huggingface-best` recommends the model *family*; then pick the right **artifact for the chosen backend**:
   - **llama.cpp / Ollama** → a **GGUF** build (use `huggingface-skills:huggingface-local-models` for the exact file + quant).
   - **mlx** → the **`mlx-community/<Model>` MLX build** (e.g. `mlx-community/Qwen3.6-27B-6bit`) — browse the `mlx-community` org. Prefer the plain `-4bit`/`-5bit`/`-6bit`/`-8bit` repos; the org also carries abliterated/uncensored/MTP/OptiQ variants that are **not** what you want for a coding backend.
2. **Document retrieval / RAG & analysis.** Recommend a **pair**:
   - an **embedding model** for retrieval — e.g. `nomic-embed-text`, `bge-m3`, or a top MTEB model that fits; and
   - a **long-context instruct model** for synthesis/analysis — surface the context window as a first-class criterion.

Profiles are extensible — add chat / OCR / math by giving `huggingface-best` the matching task term. Keep the profile→criteria table in `REFERENCE.md`.

## Download

**Storage convention (two mechanisms — this is deliberate):**

- **GGUF (llama.cpp)** → **flat files** at the top level of `$LOCAL_MODELS_DIR` (pulled with `--local-dir`, which bypasses the HF cache). Inventory: `ls $LOCAL_MODELS_DIR/*.gguf`.
- **MLX (vllm-mlx)** → the **HF cache** at `$LOCAL_MODELS_DIR/hub` (pulled by repo id into the cache; `HF_HOME=$LOCAL_MODELS_DIR`). Inventory: `hf cache ls`. Served by repo id, never by path.

`HF_HOME=$LOCAL_MODELS_DIR` should be set globally (the plugin's `~/.zshrc` block does this) so every HF tool caches to one place and models aren't duplicated in `~/.cache/huggingface`.

**GGUF for llama.cpp** → flat file in `$LOCAL_MODELS_DIR`. Use `huggingface-skills:hf-cli`:

```bash
mkdir -p "${LOCAL_MODELS_DIR:-$HOME/Local-Models}"
hf download <repo-id> <exact-file.gguf> --local-dir "${LOCAL_MODELS_DIR:-$HOME/Local-Models}"
```

(Use `huggingface-skills:huggingface-local-models` to find the exact GGUF filename + recommended quant for a repo.) Then hand it to the backend: `/localclaude:claude-toggle-backend llama-cpp <file.gguf>`.

**MLX model for the `mlx` backend** → into the HF cache (no `--local-dir`):

```bash
HF_HOME="${LOCAL_MODELS_DIR:-$HOME/Local-Models}" hf download mlx-community/<Model>-6bit
```

Pick a **6-bit or 8-bit** MLX build (e.g. `mlx-community/Qwen3.6-27B-6bit`, 22.7 GB) for the 64 GB sweet spot of ~30–48 GB — 4-bit is leaving quality on the table on this machine. Then hand it to the backend **by repo id**: `/localclaude:claude-toggle-backend mlx mlx-community/<Model>-6bit`.

These pulls are 20–40 GB and take a while. Run them with `run_in_background: true`, then confirm real progress (`du -sh` on the repo dir) rather than assuming — a stalled auth failure looks identical to a slow start. Note `du` lags behind sparse `.incomplete` blob allocation, so also check the `hf` process is alive before concluding it stalled. MLX models come pre-quantized, so the GGUF-specific `huggingface-local-models` delegate does not apply — browse the `mlx-community` org directly. (`hf-mem` still estimates footprint.)

**Ollama model**:

```bash
ollama pull <model>      # e.g. ollama pull qwen2.5-coder:14b
```

## Inventory & disk

```bash
echo "== GGUFs (flat, llama.cpp) in ${LOCAL_MODELS_DIR:-$HOME/Local-Models} =="
ls -lh "${LOCAL_MODELS_DIR:-$HOME/Local-Models}"/*.gguf 2>/dev/null || echo "(none)"
echo "== MLX / cached HF models (vllm-mlx) =="
HF_HOME="${LOCAL_MODELS_DIR:-$HOME/Local-Models}" hf cache ls 2>/dev/null || echo "(none)"
echo "== Ollama models =="; ollama list
echo "== Free space =="; df -h "$HOME" | tail -1
echo "== RAM =="; echo "$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 )) GB"
```

## Remove models (follow the denylist — never `rm -rf` home/abs paths)

- **GGUF (flat file):** delete a specific file with `rm -i "<path>.gguf"` (single file is fine), or move to Trash via Finder. **Do not** `rm -rf` the directory.
- **MLX / cached HF model:** `HF_HOME=$LOCAL_MODELS_DIR hf cache rm model/<org>/<name> --yes` (uses the cache's own tooling — safe, content-addressed).
  ⚠️ **The `model/` prefix is required.** Passing a bare `<org>/<name>` prints `Could not find in cache: … Nothing to delete.` and **exits 0** — a silent no-op that looks like success. Use the id exactly as `hf cache ls` prints it in its `id` column.
  `HF_HOME=$LOCAL_MODELS_DIR hf cache prune --yes` clears detached/incomplete revisions — worth running after any interrupted download (reclaimed 1.3 GB of leftovers on 2026-07-26).
- **Ollama:** `ollama rm <model>`.

## When invoked as a skill

1. Check **dependencies** (see above) — warn the user and confirm before installing anything. Establish machine context (RAM/cores/arch).
2. Ask which **backend(s)** to set up — llama.cpp / Ollama / mlx (Apple Silicon) / both (**default llama.cpp only**). For Ollama, first check the daemon is running (see *Choose backend(s)*) and don't auto-start it if the user disabled it. For mlx, download a model **by repo id** from `mlx-community` into the HF cache (see *Download*). Then clarify the **use case** (coding vs RAG/analysis vs other).
3. Recommend via `huggingface-best` (RAM-filtered); confirm fit with `hf-mem`. Pick the artifact for the chosen backend (GGUF vs `mlx-community` MLX build).
4. Download into the right place (GGUF → flat file; MLX → HF cache via `HF_HOME=$LOCAL_MODELS_DIR hf download …`); report the exact GGUF path or MLX repo id.
5. **After a download, ask the user whether to start it now.** If yes, make it the Claude Code backend:
   - **GGUF:** `/localclaude:claude-toggle-backend llama-cpp <file.gguf>` (or `llama-serve.sh start <file.gguf>` to serve standalone).
   - **MLX:** `/localclaude:claude-toggle-backend mlx <repo-id>` (or `mlx-serve.sh start <repo-id>` standalone).
   If no, leave it on disk — don't start a server they didn't ask for. The local backends are **single-instance** (starting `mlx` sweeps any `llama-server` and vice-versa), so this won't leave multiple models resident.
6. If you switched the Claude Code backend, remind the user a full **Cmd+Q + reopen** is required for it to take effect (see `claude-toggle-backend`).

## Notes

- **One local model at a time.** Even on 64 GB, llama.cpp / mlx / an Ollama model loaded *simultaneously* (each 20–38 GB) exceed what the machine can hold and push it into heavy swap → the whole system slows down. `claude-toggle-backend` enforces this: switching to `mlx` stops any `llama-server`, and switching to any other backend stops the mlx server. llama.cpp holds its model until stopped; Ollama idle-unloads after ~5 min. So before calling an Ollama model, `llama-cpp-down` first (and vice-versa) — don't keep both resident.
- **Daily driver:** dense **Qwen3.6-27B at 6-bit** for agentic coding accuracy; switch to the **35B-A3B MoE** only when you'd trade ~8 terminal-bench points for ~5x throughput. See the speed math under *Machine context* before offering a lower quant as a speed fix.
- `$LOCAL_MODELS_DIR` is shared with `claude-toggle-backend`: GGUFs flat at the top level (llama.cpp auto-discovers the newest); MLX models in `$LOCAL_MODELS_DIR/hub` (the HF cache), served by repo id.
- Requires the `huggingface-skills` plugin and the `hf` CLI (and `ollama` if using Ollama) — see **Dependencies** above; check and prompt before installing.
- Embedding models are for retrieval pipelines, not for the Claude Code chat backend — don't point `claude-toggle-backend` at one.
