# local-models — reference

Sizing math, quantization, and the delegation map. The always-loaded `SKILL.md` stays lean; pull this in when you need the numbers.

## Model-sizing cheat-sheet (64 GB unified memory, Apple M4 Max)

> Verified 2026-07-26: **M4 Max, 64 GB, 16 cores (12P/4E), 546 GB/s**. Earlier revisions of this file assumed 24 GB and capped recommendations at 14B — wrong by ~4x. Always re-detect with `sysctl -n hw.memsize` rather than trusting this heading.

Unified memory is shared between CPU and GPU — there is no separate VRAM. Leave **≥ 12–16 GB** for the OS, other apps, and the model's KV cache (which grows with context length). Rough footprint of model **weights** by quantization:

| Quant | Bytes/param | 14B | 27B | 32B | 35B | 70B |
| ------- | ------------- | ------ | ------ | ------ | ------ | ------ |
| F16 | ~2.0 | ~28 GB | ~55 GB | ~64 GB | ~70 GB | ~140 GB |
| Q8_0 / 8-bit | ~1.0 | ~15 GB | **~30 GB** | ~34 GB | ~38 GB | ~70 GB |
| 6-bit | ~0.8 | ~12 GB | **~23 GB** | ~26 GB | ~29 GB | ~56 GB |
| Q5_K_M / 5-bit | ~0.65 | ~10 GB | ~19 GB | ~23 GB | ~25 GB | ~46 GB |
| Q4_K_M / 4-bit | ~0.5 | ~9 GB | ~16 GB | ~20 GB | ~21 GB | ~40 GB |

Rule of thumb: usable budget ≈ RAM − 16 GB ≈ **~48 GB** on this machine. Add ~1–4 GB for KV cache depending on context length (more at long context, which is now affordable).

**Verdict for 64 GB:**

- **Sweet spot:** a dense **27B at 6-bit (~23 GB)** or **8-bit (~30 GB)** — ~25–40 GB headroom, long context comfortable.
- **Throughput option:** a **35B-A3B MoE at 8-bit (~38 GB)** — ~5x the tok/s of a dense 27B, at a real accuracy cost.
- **Reachable but tight:** 70B at 4-bit (~40 GB) — fits, but leaves little room for long-context KV.
- **Avoid:** anything ≥ 48 GB (e.g. 122B/128B-class at 4-bit ≈ 64 GB) — swaps.

Confirm a specific model with `huggingface-skills:hf-mem` before downloading.

## Quantization quality (pick the highest that fits)

- **F16 / Q8_0 / 8-bit** — near-lossless. On 64 GB this is genuinely affordable up to ~35B; prefer it when headroom allows.
- **6-bit** — ~1% loss, effectively free speed over 8-bit. **The default recommendation on this machine.**
- **Q5_K_M / 5-bit** — small loss (~1–2%).
- **Q4_K_M / 4-bit** — noticeable on code and long context (~3–5%); on 64 GB you rarely need to go here.
- **Q3 / Q2** — last resort; quality drops sharply.

## Speed math (why quant is a weak lever)

Decode is **memory-bandwidth-bound** — each token reads the weights it activates:

```text
tok/s ≈ (bandwidth × ~0.8) / GB-read-per-token      # 546 GB/s on this M4 Max
```

Dense models read **all** weights per token, so the entire 8-bit→4-bit ladder buys at most **~1.8x**:

| Qwen3.6-27B (dense) | Size | Est. tok/s | vs 8-bit |
| --- | --- | --- | --- |
| 8-bit | 29.5 GB | ~15 | 1.0x |
| 6-bit | 22.7 GB | ~19 | 1.3x |
| 5-bit | 19.4 GB | ~22 | 1.5x |
| 4-bit | 16.0 GB | ~27 | 1.8x |

MoE models read only active experts, so a **35B-A3B (3B active) hits ~70–90 tok/s (~5x)** at *larger* total size. **When asked for "far more tok/s", switch architecture, not quantization** — and state the accuracy cost (terminal-bench 51.5 vs 59.3).

## Use-case profiles → criteria

| Profile | Benchmarks / signal | Model shape | Example (fits 64 GB) |
| --------- | -------------------- | ------------- | ---------------------- |
| **Coding / agentic** | `harborframework/terminal-bench-2.0` (weight highest for a Claude Code backend), `SWE-bench/SWE-bench_Verified`, `ScaleAI/SWE-bench_Pro`, `LiquidAI/ifstruct-v1.0` (function-calling) | code-tuned instruct, strong function-calling | MLX: `mlx-community/Qwen3.6-27B-6bit` (23 GB) · throughput: `mlx-community/Qwen3.6-35B-A3B-8bit` (38 GB) |
| **RAG: retrieval** | MTEB (retrieval), context length | embedding model | `bge-m3`, `nomic-embed-text` |
| **RAG: analysis** | long-context, reasoning, citation faithfulness | long-context instruct | a 27B-class instruct w/ ≥32k ctx |
| **Chat (general)** | Arena / IFEval | instruct | 27–35B instruct |
| **OCR / vision** | OCR / doc benchmarks | VLM (often heavier) | `mlx-community/Qwen3-VL-30B-A3B-Instruct-8bit` (33.5 GB) |

Live benchmark leaderboards (public endpoints, but see the auth caveat in SKILL.md — a working curl here is **not** proof the `hf` CLI is logged in):

```bash
tok=$(cat ~/.cache/huggingface/token)
curl -s -H "Authorization: Bearer $tok" "https://huggingface.co/api/datasets?filter=benchmark:official&limit=500" | jq -r '.[].id'
curl -s -H "Authorization: Bearer $tok" "https://huggingface.co/api/datasets/<ns>/<repo>/leaderboard" | jq -r '.[:15][] | "\(.rank)\t\(.modelId)\t\(.value)"'
```

## Delegation map (what to call)

| Task | Delegate to |
| ------ | ------------- |
| "best model for X", recommend by benchmark, device filter | `huggingface-skills:huggingface-best` |
| find exact GGUF filename + recommended quant for a repo; llama.cpp serving notes | `huggingface-skills:huggingface-local-models` |
| find MLX-format models (pre-quantized, for the `mlx` backend) | browse the `mlx-community` HF org directly |
| download an MLX model into the HF cache | `HF_HOME=$LOCAL_MODELS_DIR hf download mlx-community/<name>` |
| list / remove cached MLX (HF) models | `HF_HOME=$LOCAL_MODELS_DIR hf cache ls` / `hf cache rm model/<org>/<name> --yes` (the `model/` prefix is **required** — a bare `<org>/<name>` is a silent no-op that exits 0) |
| clear incomplete revisions after an interrupted pull | `HF_HOME=$LOCAL_MODELS_DIR hf cache prune --yes` |
| verify `hf` CLI auth before a download (per-`HF_HOME`!) | `HF_HOME=$LOCAL_MODELS_DIR hf auth whoami` — see the auth warning in SKILL.md |
| download / upload / cache management (`hf download … --local-dir`) | `huggingface-skills:hf-cli` |
| estimate memory footprint of a model | `huggingface-skills:hf-mem` |
| pull / list / remove Ollama models | `ollama pull` / `list` / `rm` |
| serve a GGUF as the Claude Code backend | `/localclaude:claude-toggle-backend llama-cpp <file>` |
| serve an MLX model as the Claude Code backend | `/localclaude:claude-toggle-backend mlx <repo-id>` |

## Locations

- GGUFs (llama.cpp): **flat files** at the top level of `$LOCAL_MODELS_DIR` (default `~/Local-Models`) — pulled with `--local-dir`, bypass the HF cache.
- MLX models (mlx): the **HF cache** at `$LOCAL_MODELS_DIR/hub/models--org--name/` (content-addressed) — `HF_HOME=$LOCAL_MODELS_DIR`, served by repo id, inspected with `hf cache ls`.
- `HF_HOME=$LOCAL_MODELS_DIR` is set globally in `~/.zshrc` so all HF tools share this one cache (avoids duplicate downloads into `~/.cache/huggingface`).
- Ollama models: `~/.ollama/models` (or `$OLLAMA_MODELS`).
