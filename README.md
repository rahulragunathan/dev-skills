# dev-skills

Agent skills for a phase-based development process: plan review, phase gates, structural design
review, and outside review from other models. They are written as standard Agent Skills, so the
same folders work in Claude Code and in Codex.

## Skills

- **phase-workflow** — the phase-based development process for solo projects: the plan review (external review of the drafted plan, incorporated and tabled *before* the user approves it), phase start, the seven-step end-of-phase retrospective (confidence check, `design-review phase`, `/simplify` then `/code-review high`, test-validity audit, holistic doc pass with drift check and roadmap updates per the four bundled templates — ROADMAP, KNOWN_ISSUES, ENHANCEMENTS, OPEN_QUESTIONS — then the external review loop and a post-fix drift re-check), the hard phase gate (per-task commits on a draft PR, marked ready for review; sign-off authorizes the merge), and the post-sign-off merge cycle, which merges and publishes the tag for the release prepared before the gate.
- **external-review** — the external-model review used at phase-workflow's checkpoints: OpenAI Codex (`codex exec`, agentic, pinned read-only) plus Google Gemini (`agy -p`, one-shot with the material inlined) over a drafted plan, a branch diff, or a whole repo. Review-only; findings are verified against the repo, then presented in one standard table — every finding, confirmed and rejected alike, with a severity, a verdict, and a disposition, so nothing is lost between the review and the roadmap. Reviewers are told what is already tracked so they stop re-deriving the backlog. A phase review runs as a review→fix loop with no pass ceiling, each follow-up narrowed to the fixes just made, pausing on its table every time for the user to decide whether to continue. A reviewer that fails on quota/auth/sandbox is reported plainly while the other one continues.
- **design-review** — the structural design pass. At plan time it produces the module table, the expected-change and shared-state lines, and resolutions for whichever of six named checks fire covering SOLID, DRY, KISS and separation of concerns, with a YAGNI cap graded by cost; at phase end it re-checks that structure against the code and diffs the regenerated diagrams. Its rules are pressure-tested against a fresh agent and the scenarios live beside it in `tests/`, with each rule's result recorded — including the ones a strong model already follows unaided.

## Install

**Claude Code**, from GitHub:

```text
/plugin marketplace add rahulragunathan/dev-skills
/plugin install dev-skills@dev-skills
```

From a local checkout, pass its absolute path to `/plugin marketplace add` instead. The slash
command cannot parse a path with spaces, so link the checkout to a space-free path first. Then
Cmd+Q and reopen. Skills load as `/dev-skills:<skill>`.

**Codex** reads skills as plain folders. Link each folder under `skills/` into Codex's skills
directory.

## External tools

The plugin itself needs nothing installed. Each skill checks the tools its current task needs and, if one is missing, stops and gives you the install command rather than failing mid-run — so install a tool when a skill asks for it, not up front.

| Tool | Needed by | Install |
| --- | --- | --- |
| `bash` 5 (optional) | phase-workflow, to reproduce the mid-test assertion measurement | `brew install bash` |
| `codex` | external-review (Codex reviewer) | OpenAI Codex CLI, then `codex login` |
| `agy` | external-review (Gemini reviewer) | Antigravity CLI |
| `gh` | phase-workflow (draft PR, checks, merge, tag) | `brew install gh`, then `gh auth login` |
| `drawio` skill | design-review (module and flow diagrams) | drop the skill into `~/.claude/skills/drawio/` |
| `bats` | running the test suite | `brew install bats-core`, then `bats skills/*/tests/` and `python3 -m unittest discover tests` |

external-review runs two independent reviewers, so one missing CLI is not fatal: it names the reviewer it skipped and reviews with the other. If both are missing it skips the external review altogether and says so — phase-workflow treats that as a note in the hand-off, not a blocker.

`gh` is the one closest to required: phase-workflow cannot open or merge a phase PR without it, so it is checked before the first phase-start mutation rather than at merge time. `drawio` is best-effort — design-review records "no diagram" and carries on.

## Documentation

| Looking for | Read |
| --- | --- |
| What each skill does | this file |
| How the pieces fit together | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Conventions for working in this repo | [AGENTS.md](AGENTS.md) |
| What already shipped | [CHANGELOG.md](CHANGELOG.md) |
| What is planned or open | [docs/ROADMAP.md](docs/ROADMAP.md) |
