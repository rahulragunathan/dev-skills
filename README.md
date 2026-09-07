# localclaude

A personal Claude Code plugin bundling seven skills for config bootstrap, development process, and local-LLM workflows on macOS (Apple Silicon).

## Skills

- **claude-setup** — read-only command allowlist + destructive denylist in `~/.claude/settings.json`, plugin-enablement pruning to canonical defaults, global `~/.claude/CLAUDE.md` standards (managed block), wiring this machine to the synced Drive (skills symlink + this plugin), and the Stop-hook backup of transcripts/plans/memory/config to Drive.
- **phase-workflow** — the phase-based development process for solo projects: the plan review (external review of the drafted plan, incorporated and tabled *before* the user approves it), phase start, the seven-step end-of-phase retrospective (confidence check, `/simplify` then `/code-review high`, test-validity audit, holistic doc pass with drift check and roadmap updates per the four bundled templates — ROADMAP, KNOWN_ISSUES, ENHANCEMENTS, OPEN_QUESTIONS — then the external review loop and a post-fix drift re-check), the hard phase gate (per-task commits on a draft PR, marked ready for review; sign-off authorizes the merge), and the post-sign-off merge cycle that cuts and tags a CHANGELOG release.
- **review-checkpoint** — the external-model review used at phase-workflow's checkpoints: OpenAI Codex (`codex exec`, agentic, pinned read-only) plus Google Gemini (`agy -p`, one-shot with the material inlined) over an approved plan, a branch diff, or a whole repo. Review-only; findings are verified against the repo, then presented in one standard table — every finding, confirmed and rejected alike, with a severity, a verdict, and a disposition, so nothing is lost between the review and the roadmap. Reviewers are told what is already tracked so they stop re-deriving the backlog. A phase review runs as a loop of up to three review→fix passes, each follow-up narrowed to the fixes just made, pausing on its table every time. A reviewer that fails on quota/auth/sandbox is reported plainly while the other one continues.
- **claude-toggle-backend** — switch the Claude Code backend between **anthropic** (the `opus[1m]` alias, High effort), **ollama**, **llama-cpp**, and **mlx** (Apple Silicon). For llama.cpp it auto-starts a Metal-accelerated `llama-server` on a flat GGUF; for mlx it auto-starts a `vllm-mlx` server on an MLX model referenced **by HF repo id** from the HF cache (native Anthropic `/v1/messages`, generally faster tok/s on Apple Silicon) — each on a free port, with the Anthropic base URL pointed at it. A `~/.claude/local-backend` marker records which local backend is active. No-arg `toggle` flips anthropic ⇄ mlx. Bundles `toggle.sh` + `llama-serve.sh` + `mlx-serve.sh` + `llama-autostart.sh`.
- **design-review** — the structural design pass. At plan time it produces the module table, the expected-change and shared-state lines, and verdicts on six named checks covering SOLID, DRY, KISS and separation of concerns, with a YAGNI cap graded by cost; at phase end it re-checks that structure against the code and diffs the regenerated diagrams. Its rules are pressure-tested against a fresh agent and the scenarios live beside it in `tests/`, with each rule's result recorded — including the ones a strong model already follows unaided.
- **local-models** — discover (by use case: coding / RAG & analysis), download, inventory, and remove local models, RAM-sized to the machine. Orchestrates the `huggingface-skills` plugin + Ollama CLI. Storage convention: **GGUFs** are flat files at the top level of `~/Local-Models` (llama.cpp); **MLX** models live in the HF cache at `~/Local-Models/hub` (`HF_HOME=~/Local-Models`, served by repo id, `hf cache ls`).
- **project-env** — build or repair a project's Python / Node environment outside Drive: the `~/Python-Envs` / `~/Node-Envs` layout with a symlinked `.venv` / `node_modules`, the `standardize-*-envs.sh` scripts for new repos and for migrating a real directory out, the dependency-file split, and which invocations are allow-listed (relative venv paths, `npm test`) versus deliberately not (`uv pip install`, `npm run`, bare `npm install`).

## Install

`/plugin marketplace add` can't parse the Drive path (spaces in "My Drive"), so register via a space-free symlink — see `../README.md` for the exact steps:

```bash
ln -sfn "<abs path to Code/Plugins>" "$HOME/.claude/localclaude-plugins"
```

```text
/plugin marketplace add /Users/<you>/.claude/localclaude-plugins
/plugin install localclaude@localclaude-marketplace
```

then Cmd+Q + reopen. Skills load as `/localclaude:<skill>`.

## External tools

The plugin itself needs nothing installed. Each skill checks the tools its current task needs and, if one is missing, stops and gives you the install command rather than failing mid-run — so install a tool when a skill asks for it, not up front. Only the path you actually use is checked: switching to the mlx backend never asks about `llama.cpp`.

| Tool | Needed by | Install |
| --- | --- | --- |
| `llama-server` | claude-toggle-backend, llama-cpp backend | `brew install llama.cpp` |
| `vllm-mlx` | claude-toggle-backend, mlx backend | `uv tool install vllm-mlx` |
| `ollama` | claude-toggle-backend, ollama backend | `brew install ollama` |
| `hf` + `huggingface-skills` plugin | local-models | `brew install huggingface-cli`; plugin via `/plugin` |
| `codex` | review-checkpoint (Codex reviewer) | OpenAI Codex CLI, then `codex login` |
| `agy` | review-checkpoint (Gemini reviewer) | Antigravity CLI |
| `gh` | phase-workflow (draft PR, checks, merge, tag) | `brew install gh`, then `gh auth login` |
| `drawio` skill | design-review (module and flow diagrams) | drop the skill into `~/.claude/skills/drawio/` |
| `bats` | running the test suite | `brew install bats-core`, then `bats skills/claude-toggle-backend/tests/` |

review-checkpoint runs two independent reviewers, so one missing CLI is not fatal: it names the reviewer it skipped and reviews with the other. If both are missing it skips the external review altogether and says so — phase-workflow treats that as a note in the hand-off, not a blocker.

`gh` is the one closest to required: phase-workflow cannot open or merge a phase PR without it, so it is checked before the first phase-start mutation rather than at merge time. `drawio` is best-effort — design-review records "no diagram" and carries on.

## Documentation

| Looking for | Read |
| --- | --- |
| What each skill does | this file |
| How the pieces fit together | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Conventions for working in this repo | [CLAUDE.md](CLAUDE.md) |
| What already shipped | [CHANGELOG.md](CHANGELOG.md) |
| What is planned, open or held | [docs/ROADMAP.md](docs/ROADMAP.md) |

macOS Apple Silicon is assumed for Metal (`-ngl 999`); the mlx backend is Apple-Silicon-only and errors clearly elsewhere.
