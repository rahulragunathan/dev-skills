---
name: claude-setup
version: 2.6.0
description: Set up or refresh Claude Code configuration on a machine — settings allowlist and denylist, plugin pruning, the global standards in ~/.claude/CLAUDE.md as a managed block, wiring to the synced Drive skills and this plugin, and a Stop-hook backup of transcripts and config to Drive. Use when configuring a new machine, updating the standards, or cutting down permission prompts.
license: MIT
---

# claude-setup

Bootstrap a machine's Claude Code config with the user's preferred conventions:

- A **fewer-prompts allowlist** + **destructive-command denylist** in `~/.claude/settings.json`. **It is not a security boundary and must not be described as one:** `cat`/`echo` redirection writes, formatters have fix modes, and `pytest` executes arbitrary project code. It is a list of commands already judged safe, so they stop prompting. Adding argument-level criteria would re-attempt the impossible — a prefix rule cannot inspect arguments.
- The user's **complete global standards** in `~/.claude/CLAUDE.md` (shell/path rules that stop spurious permission prompts on cloud-synced "My Drive" paths, git conventions, and the TDD + phase-workflow development process), carried in a **managed block** so a re-run reconciles a stale file up to the current standard.
- **Wiring this machine to the synced Drive**: a `~/.claude/skills` symlink (loose skills like `drawio`) and the **`localclaude`** plugin via a local marketplace — both derived from one detected `Code` root.
- **Backing up chat transcripts + memory** (Claude Code **and** Cowork) to the synced `Code/Claude-Projects` folder via a `Stop` hook, so sessions are backed up and analyzable later.

Idempotent — safe to re-run. It **merges** into existing config, never clobbers. See `REFERENCE.md` (next to this file) for the full rationale and troubleshooting.

## When to use

- Setting up Claude Code on a new computer.
- Replicating or refreshing this permission setup.
- Reducing repetitive permission prompts for read-only exploration commands.

## Steps — perform in order

### 1. Locate the config dir

`~/.claude`. All paths below are under it.

**`$CLAUDE_CONFIG_DIR` is not honoured**, here or in `backup-projects.sh`, which resolves
`$HOME/.claude` directly. Setting it relocates what Claude Code reads without relocating what
this skill writes, so the two would disagree. Do not set it on a machine this skill manages.
Supporting it is ENH-07.

### 2. Merge `~/.claude/settings.json` permissions

**Read the file first if it exists** — preserve `model`, `enabledPlugins`, `effortLevel`, prior `allow`/`deny`, etc. Ensure `permissions.allow` is the **union** (deduplicated) of its current entries and the list below, likewise `permissions.deny`. If the file doesn't exist, create it with just a `permissions` block.

`permissions.allow` must include:

```json
[
  "Grep", "Glob", "Read",
  "Bash(cd:*)", "Bash(ls:*)", "Bash(find:*)", "Bash(grep:*)", "Bash(head:*)",
  "Bash(tail:*)", "Bash(cat:*)", "Bash(diff:*)", "Bash(echo:*)", "Bash(ps:*)",
  "Bash(wc:*)", "Bash(sort:*)", "Bash(uniq:*)", "Bash(cut:*)", "Bash(tr:*)",
  "Bash(nl:*)", "Bash(column:*)", "Bash(jq:*)",
  "Bash(pytest:*)", "Bash(black:*)", "Bash(ruff:*)",
  "Bash(python -m pytest:*)", "Bash(python3 -m pytest:*)",
  "Bash(.venv/bin/python -m pytest:*)", "Bash(.venv/bin/pytest:*)",
  "Bash(.venv/bin/ruff:*)", "Bash(.venv/bin/black:*)",
  "Bash(uv venv:*)", "Bash(uv python install:*)", "Bash(uv python list:*)",
  "Bash(uv pip list:*)", "Bash(uv pip freeze:*)",
  "Bash(npm test:*)", "Bash(npx vitest:*)",
  "Bash(markdownlint-cli2:*)"
]
```

`permissions.deny` must include:

```json
[
  "Bash(rm -rf /:*)", "Bash(rm -fr /:*)", "Bash(rm -rf ~:*)", "Bash(rm -fr ~:*)",
  "Bash(rm -rf --no-preserve-root:*)", "Bash(mkfs:*)", "Bash(dd:*)",
  "Bash(shutdown:*)", "Bash(reboot:*)"
]
```

Rules that matter:

- **Bash rule syntax MUST use the colon form `Bash(cmd:*)`.** `Bash(cmd*)` (no colon) silently never matches — the #1 reason an allowlist "doesn't work."
- **Do NOT add `sed`, `awk`, `tee`, `xargs`, or a blanket `Bash(*)`.** They can modify files; leaving them to prompt is intentional.
- **`pytest`/`black`/`ruff` are a deliberate exception to the read-only rule** — they run project code / rewrite files, but they're the everyday dev loop and project-scoped, so they're allow-listed on purpose. Note `Bash(ruff:*)` also permits `ruff check --fix` (edits code); that's accepted, since `ruff format` and `ruff check` share the `ruff` prefix and can't be split cleanly.
- **The venv forms are allow-listed too** (`.venv/bin/python -m pytest`, `.venv/bin/pytest`, `.venv/bin/ruff`, `.venv/bin/black`, plus bare `python -m pytest`). A bare `Bash(pytest:*)` never matches the venv-path invocation the Python convention actually uses, so the everyday test run still prompted — and stayed exposed to permission-classifier outages. These prefixes make routine test/format runs prompt-free.
- **uv is allow-listed for env creation and inspection only** (`uv venv`, `uv python install`, `uv python list`, `uv pip list`, `uv pip freeze`). These build or read an env and never install code, so the documented new-project setup in `localclaude:project-env` runs without a prompt. `uv pip install` is deliberately left out: installing packages stays a conscious approval.
- **Node's everyday test loop is allow-listed the same way** (`npm test`, `npx vitest`), run from the project root through the `node_modules` symlink. `npm run` is deliberately left out: it executes whatever a project's `package.json` defines, so it stays a conscious approval. So does `npm install`, which additionally replaces the symlink with a real directory on Drive (see `localclaude:project-env`).
- **`markdownlint-cli2` is allow-listed on the same terms as `ruff`.** It reads by default but rewrites files with `--fix`, and the two share one prefix that can't be split. It's the everyday docs loop, so the write case is accepted rather than prompted. Step 3b sets it up.
- **Deliberately no leading `*`.** Bash rules do accept `*` anywhere, so `Bash(*.venv/bin/python -m pytest*)` would also catch absolute paths — but a leading wildcard in an **allow** rule matches arbitrary text before the venv path, which is a wider grant than intended. The relative prefixes are exact, so the standard is: run tests and formatters from the project root with the relative path (recorded in the CLAUDE.md `### Project environments` section, with the detail in `localclaude:project-env`). An absolute venv path prompts, by design.
- **Validate after writing:** `python3 -m json.tool ~/.claude/settings.json`. Malformed JSON silently disables **all** settings in the file.

### 2b. Reconcile plugin enablement + remove stale artifacts

Every enabled plugin's skill descriptions sit in **every** session's context (skill bodies load on invoke, but routing = the in-context description), so unused plugins are a permanent token tax. Normalize this machine to the canonical defaults; per-machine overrides are legitimate — the user can flip any back on for a work session (`/plugin` → enable → full Cmd+Q restart).

**Canonical default-OFF list** — for each of these *present* in `settings.json` → `enabledPlugins`, set its value to `false` (merge: never touch plugins not installed on this machine, never remove keys, never clobber other settings; validate with `python3 -m json.tool` after):

| Plugin | Re-enable when |
| --- | --- |
| `huggingface-skills@claude-plugins-official` | doing local-model / HF work (`localclaude:local-models` orchestrates it) — the biggest context win, ~25 skills with long descriptions |
| `firebase@claude-plugins-official` | working on a Firebase project |
| `mcp-server-dev@claude-plugins-official` | building an MCP server |
| `feature-dev@claude-plugins-official` | (generally stays off — overlaps the superpowers workflow) |
| `code-simplifier@claude-plugins-official` | (stays off — not a coverage overlap. It is an autonomous editing agent whose coding standards are hardcoded to ES modules/React/TypeScript rather than this stack, and its "refine proactively without explicit requests" posture fights the phase gate. Built-in `/simplify` is diff-scoped and invoked; its guardrail lives in `phase-workflow` §3 step 2) |
| `pr-review-toolkit@claude-plugins-official` | wanting its specialized PR-review agents (zero uses in first month; its agent descriptions cost ~1.6k est. resident tokens) |
| `claude-md-management@claude-plugins-official` | auditing CLAUDE.md files (zero uses; `/doctor` covers the audit) |
| `skill-creator@claude-plugins-official` | running skill evals/benchmarks (zero uses; `superpowers:writing-skills` covers authoring) |
| `frontend-design@claude-plugins-official` | doing UI/visual design work (zero uses so far) |
| `github@claude-plugins-official` | wanting its GitHub commands (zero uses; the `gh` CLI is used directly instead) |

**Canonical stale-artifact removal list** — delete if present (use `rm` without `-f`, per the delete conventions):

- `~/.claude/commands/use-anthropic.md`, `~/.claude/commands/use-ollama.md` — superseded by `claude-toggle-backend`; their `cp settings.*.json → settings.json` would clobber the allowlist/hooks, and the source files they copy no longer exist.

**Background auto-updates ON** — ensure `"autoUpdates": true` in `~/.claude.json` (top level). This file holds machine state and per-project permission grants, so edit it **key-scoped** (jq/python setting just that key — never rewrite or template the whole file). A legacy `autoUpdates: false` leaves the install silently going stale; the user's standard is auto-update on.

Finish with the usual reminder: changes take effect only after a full Cmd+Q + reopen.

### 3. Reconcile `~/.claude/CLAUDE.md` to the complete standards

This is the user's **complete global standard** — the goal is that a re-run brings a *stale* file **up to date**, not merely appends the sections when they're absent. So **reconcile**, don't just check-for-presence. The canonical block below is wrapped in managed markers (same pattern as the `.zshrc` block in step 7) so re-runs can replace it cleanly.

**Read the file first if it exists**, then install the canonical block verbatim between the markers.

**Take the canonical text from inside the fenced block below, not by searching this file for a marker.** This section discusses the markers, so a prefix search finds prose before it finds the real delimiters. Match **whole marker lines only**, and take the *last* opening marker in any file that has more than one.

- **Markers already present** → replace everything between them with the current canonical block. This is how a stale copy gets refreshed: a file missing the whole `## Development process` section, or one whose `Co-Authored-By` trailer still names a fixed model instead of the model that wrote the commit.
- **Standards present without markers** (an older machine — e.g. bare `## Shell commands` / `## Git` and nothing else) → replace those sections in place with the marked block, preserving any unrelated content the user keeps elsewhere in the file.
- **Neither** (missing file, or unrelated content only) → create or append the marked block.

Preserve any non-standard content the user keeps **outside** the managed block.

**Then verify, because a wrong slice here corrupts the file that governs every session.** The result must start with the opening marker, end with the closing marker, contain exactly one of each, and carry no stray code fence. Diff the installed block against the canonical text and confirm they match, that no section was dropped, and that the trailer wording is the dynamic-model-name form.

```markdown
<!-- >>> localclaude standards (managed — edit here + re-run claude-setup to sync every machine) >>> -->
# Global standards

## Communication

- Neutral, positive tone. No automatic evaluative reactions to my input: no validating preambles ("Great question", "You're absolutely right") and no reflexive mid-conversation praise ("Good idea", "Great catch"). Respond to suggestions and feedback with substance first. Praise or criticism needs a specific reason behind it, stated constructively. Objective analysis, including disagreement, beats agreement by default, because ungrounded agreement erodes trust in the grounded assessments. Don't manufacture criticism to fill the space either.
- When context grows long, compact at natural task boundaries (between phases or features), never mid-task. Compacting live working state only re-summarizes it and loses fidelity.
- Write in Simplified Technical English, following Zinsser's four principles: clarity, simplicity, brevity, humanity. Familiar precise words, active voice, short direct sentences, one idea at a time. Cut needless words and jargon, but keep the technical detail, nuance, and natural tone that make the answer accurate and useful. This covers chat replies **and** every artifact you write: README, ARCHITECTURE, ROADMAP, CLAUDE.md, code comments, commit messages, plans. My explicit requests, required artifact conventions, quotations, and real domain terms outrank this default. Even then, pick the simplest wording that carries the meaning.
- Caveats must earn their place. Before adding a hedge, exception, or aside, ask whether the main point is wrong without it. Keep it in the main line only if it is material; otherwise demote it to a sub-bullet or a parenthetical. Cut caveats that guard against a misreading no careful reader would make.
- Avoid the constructions that mark machine-written prose. Vary sentence shape instead of reaching for the em-dash; aim for one per paragraph at most, since a period, comma, or colon usually reads better. Drop antithesis templates ("it's not X, it's Y", "X isn't just Y, it's Z") and pseudo-technical filler (load-bearing, no-op, delve, leverage, robust, seamless, "at its core", "the key insight"). State the point plainly.

## Shell commands

- **Always double-quote file paths** passed to Bash, e.g. `"/Users/.../My Drive/Clients/.../file.py"`, never backslash-escaped spaces (`My\ Drive`). Escaped spaces get mis-tokenized and break Claude Code's workspace-boundary path check, which raises spurious permission prompts even for allow-listed read-only commands. Most projects live under cloud-synced "My Drive" folders whose absolute paths contain spaces, so this applies almost everywhere.
- Prefer absolute double-quoted paths over `cd "…" && <relative-path>`. A `cd` inside a compound command can trip a permission prompt, and it defeats the in-scope check for the relative paths that follow.
- For searching and reading code, prefer the built-in Grep / Glob / Read tools over `grep`/`find`/`ls`/`cat`/`cut` pipelines in Bash, because the native tools never trigger permission prompts. Reserve Bash for what those tools can't do, and run single commands rather than long `&&`/`;`/`echo`-banner chains.

## Git

- **Never merge or land on your own.** Inside a phase, commit per task and push to the phase branch as `localclaude:phase-workflow` directs — that is the workflow, not an exception. Outside a phase, make edits, verify, then stop and hand off. Nothing reaches the default branch without my sign-off, and a PR outside an approved merge cycle still needs me to ask for it.
- **Every phase lands by pull request.** `phase-workflow` §2 opens it as a draft and §4 merges it; branch protection no longer changes the route. Read the repo's allowed merge methods when the branch is created, since the wrong one is rejected at merge time.
- Branch naming: `feature/<slug>` for new features, `bugfix/<ticket>-<slug>` (or `bugfix/<short-desc>`) for defect fixes. Never a personal `rahulragunathan/…` prefix. Keep each PR small and single-purpose.
- Branch creation: always `--no-track` off the repo's **detected default branch**, never a hardcoded `main`. Without `--no-track` the upstream auto-sets to the default branch, so a later `push` or `pull` hits "divergent branches". Branch off the default branch, not off another open feature branch, and publish it to origin immediately so it tracks `origin/<branch>`. `localclaude:phase-workflow` §2 has the detection, the fetch and the preflight checks.
- Staging hygiene: stage only the files for your change. Leave unrelated working-tree noise out, such as a pre-existing `web/package-lock.json` change.
- Trailers: end commit messages with a `Co-Authored-By` trailer naming **the model that wrote that commit** — not the session's model, which differs once a subagent commits its own task under model tiering. `Co-Authored-By: Claude Fable 5` (no email). End PR bodies with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- **Take the model name from what the harness states, and nowhere else.** `~/.claude/settings.json` holds an alias (`opus`) with no version and goes stale the moment `/model` switches mid-session, and a model asked to identify itself unprompted will answer from training data — confidently, and a generation behind. If the harness does not state it, ask; a wrong trailer is worse than a missing one because nothing flags it.

## Development process

- TDD via the `superpowers:test-driven-development` skill for every feature and bugfix where the layer is deterministically testable: one minimal failing test → watch it fail for the right reason → minimal code to pass → watch it pass → refactor while green. No production code without a failing test first, and a bug gets a reproducing test before the fix.
- **Name each test's failure condition before you write it** — the specific thing that turns it red. *"Fails if a `<script>` survives sanitization"*, never *"tests the parser"*. Then check the red you got is that one: an import, collection or fixture error is not the red you wanted, and a test that never went red for its stated reason is evidence of nothing. **Check the fixture carries the property under test** — no mutation will fail a test whose input never had it. A test written after its fix has its reason checked retroactively by mutation; `localclaude:phase-workflow` §3 step 3 has that procedure.
- **`/simplify` runs at the refactor step**, while green, on the change just made — in a one-off edit as much as inside a phase. **Once per red-green-refactor cycle**, so three tasks get three runs, never one pass at the end. Re-run the tests and confirm green before the next task, since it edits the working tree. **Simpler, not shorter**; `localclaude:phase-workflow` §3 step 2 has the guardrail on what to reject.
- **A layer is deterministically testable when a test can control its inputs and observe its outputs, including through a fake at the process boundary.** Filesystem, database and clock all qualify — they are controllable. Only genuine non-determinism is exempt: model output, live network, wall-clock races. A layer claimed exempt says so in the plan, in writing, rather than by assumption.
- Exempt layers get integration or eval coverage instead, faked at the network or system boundary so real client code paths run, or manual verification. Don't mock internals. If a project has no test harness, set one up before the first behavior change. Where a repo has no CI, its documented verify gate (e.g. a `verify.sh`) is the bar.
- Automated tests are the primary verification and Claude runs them. I do manual verification (e.g. in the browser) as final sign-off before anything is merged. Run the project's configured formatter on modified files before hand-off, matching whatever the repo already uses rather than imposing a different one.
- **Lint markdown before hand-off**, the same way code gets formatted: `markdownlint-cli2 --config ~/.markdownlint.jsonc <paths>` over the docs you touched. **Pass `--config` every time** — without it the CLI finds the global config only when the target sits under `~`. Fix what it reports on your own files; leave untouched files alone unless I ask for a sweep. `localclaude:claude-setup` step 3b installs and pins it.
- **Structural design is decided at plan time**, via `localclaude:design-review`, which owns the checks and their thresholds. The cap, which belongs here because it outranks them: **YAGNI outranks SOLID.** Grade an abstraction by cost — a protocol or type alias naming a shape is cheap and fine with one implementation; discovery, config-driven registration, per-variant subpackages, factories and plugin loaders need a second implementation that exists or is scheduled. Rule of three for DRY: three occurrences justify *creating* a shared home, two may move into one that already exists.
- **Work runs as a phase when `superpowers:brainstorming` classifies it architectural.** Spike and bounded run under the normal workflow, and the one-way ratchet applies, so a bounded task that turns out architectural becomes a phase mid-flight. Call a phase on bounded work whenever you want the retrospective — a security-sensitive path, a change to a rule other work depends on, or simply because I say so.
- Phases follow the `localclaude:phase-workflow` skill, one feature branch per phase. Invoke it at every phase boundary: plan review, plan approval, end-of-phase retrospective, post-sign-off merge cycle. **Completing phase N never rolls into phase N+1: present phase N for my review and stop; my approval is the only trigger for the next phase.**
- **The phase gate is a PR ready for review.** At hand-off the phase's commits are pushed, the working tree is clean, and the draft PR has been marked ready. Sign-off authorizes the merge and nothing else. Committed work is recoverable from the reflog; uncommitted work is not, and the retrospective points `git checkout`, worktree and stash operations at the tree.
- **Any edit while waiting for sign-off is a new commit on the PR, named in a follow-up message.** Re-request review unless it is a typo. The control is visibility, not category.
- **Sign-off is my approval of the finished phase**: "looks good", "approved", "go ahead and merge". Approval to *start* a phase is not sign-off on it. When one message does both ("merge this and start the next phase"), it authorizes the merge cycle for phase N and the implementation of N+1, never the merge of N+1.
- Docs and code comments stay true to the code. Check them **holistically**: read each doc against the code as it now stands and fix drift from earlier phases, not only the part you just changed.
- Two boundaries. **Before every commit hand-off:** update the comments in the files you touched and any doc the change invalidated. **At every phase end:** sweep README.md, project CLAUDE.md, CHANGELOG.md, docs/ARCHITECTURE.md with its drawio diagram, and the roadmap files (docs/ROADMAP.md, KNOWN_ISSUES.md, ENHANCEMENTS.md, OPEN_QUESTIONS.md), per the `localclaude:phase-workflow` skill.
- **One fact, one place, and docs split by tense.** CHANGELOG.md is the past (versioned; a released section is never edited); README, ARCHITECTURE and the project CLAUDE.md are the present; the roadmap files are the future. An item moves between them and never copies: it enters ROADMAP and its supporting file together, and on completion is *deleted* from both and written into CHANGELOG `[Unreleased]`. Dropped ideas move to "Decisions taken and not taken" in the project CLAUDE.md. If a sentence would be true in two of these files, it belongs in exactly one; pick by tense.
- **Roadmap files live under `docs/`**: ROADMAP.md is the index, with Known Issues, Enhancements and Open Questions inline until a section passes five entries and splits into its own file. IDs (`KI-nn`, `ENH-nn`, `UNK-nn`) are stable, used in branch names and CHANGELOG entries, and never reused. `localclaude:phase-workflow` and the bundled templates define the rest — rating scales, entry format, anchors, and what a good entry contains.
- **Anything that lands cuts a release; semver decides the number.** Version by what changed, never by how the work was classified: a bounded fix is a patch, a bounded new flag a minor, a break major. Spikes land nothing. Phase releases carry the phase name in the heading and bounded ones do not, so **the release history is the change history** — ROADMAP keeps no table of completed phases.
- **Repo root holds README.md, CLAUDE.md, CHANGELOG.md, LICENSE. Everything else goes in `docs/`.** CLAUDE.md is only auto-loaded from root, and CHANGELOG stays there for the Keep a Changelog and release-tooling conventions.
- Drift check, not a re-read: confirm every identifier, file path, command, flag, and config key a doc names still exists. A comment or doc line the code outgrew is worse than none, so delete it or fix it.
- Comments say *why*, not *what*. Don't narrate self-evident code.

### Subagents

- Three uses, and only three. **Parallel implementation** of independent tasks — where the plan's module table and Interfaces blocks define the boundaries, dispatch one implementer per module via `superpowers:dispatching-parallel-agents`; they return changed files, test results and concerns, and I integrate. **Fresh-context probes**, where the subagent is the subject or the audience: pressure-testing a skill's wording, or reading a module map cold to check it is legible without the conversation. **Read-only search fan-out.** Don't delegate what the main agent can finish in a handful of tool calls.
- **Never to verify correctness.** A subagent is a copy of me and shares my blind spots, so it confirms rather than checks. Outside opinion comes from a different model via `localclaude:external-review`, never another instance of the same one.
- **Pressure-test a skill on the model that will read it.** `design-review` is invoked in the main session, so its tests run on the main model, not on a cheaper one picked for cost.
- **Subagents may commit their own task. They never push, merge, tag, or touch the default branch.** One task, one commit, on the phase branch. Everything that reaches origin goes through the main agent at my approved checkpoints, which keeps a single point of contact with the remote and one place that tracks overall status. `superpowers:subagent-driven-development` works as built under this rule — its review packages, ledger and crash recovery are all commit-range based.
- **Serialize subagents that share a branch.** Two agents committing to one branch at once will race. Run them one at a time, or give each its own worktree via `superpowers:dispatching-parallel-agents`.
### Secrets

- **Don't read files that are likely to hold secrets** — `.env` and `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `credentials*`, `.netrc`, `.npmrc`, `id_rsa*`, `id_ed25519*` — unless I ask for it. If a task looks like it needs one, name the file and say why instead of opening it. Reading a secret into the transcript has already sent it.
- This is a habit, not a sandbox. A broad `grep -r` or a directory dump can surface the same content incidentally, so narrow the search rather than filtering the output afterwards.

### Model tiering

- Model tiering to save cost: Haiku for read-only Explore and search fan-out, Sonnet for general implementation, the strong model for reasoning-heavy work (code review, architecture, debugging). Don't downgrade the tasks you spawned an agent *because* they are hard.

### Project environments

- **No virtualenv and no `node_modules` ever lives inside Drive**, and **never run a bare `npm install`** in a project — it silently replaces the symlinked tree with a real directory there. Either way you get constant sync churn and conflicted copies.
- Use `localclaude:project-env` to create or repair one. It carries the layout, the naming, the scripts, the dependency files, and which invocations run without a prompt.

<!-- <<< localclaude standards <<< -->
```

**Keeping this in sync going forward:** this canonical block is the single source of truth for the global `CLAUDE.md`. When the standards change, edit *this* block (and the live `~/.claude/CLAUDE.md` markers) — the marker wrapper is what lets every other machine pick up the change on its next `claude-setup` run.

### 3b. Markdown lint — install the CLI, pin one global config

The standards in step 3 say to lint the markdown you touched before hand-off. That needs a linter and, more to the point, **one config the editor and the CLI both obey**. Out of the box they disagree, so a shared config is required, not a refinement.

1. **Install the CLI** (Homebrew; pulls `node` as a dependency):

   ```bash
   brew install markdownlint-cli2
   ```

2. **Write `~/.markdownlint.jsonc`** if it isn't there. Four rules have to be set — each is a real conflict with the house conventions, not a preference:

   ```jsonc
   {
     // Long prose lines are the house style. The VS Code extension turns this
     // rule off by default and the CLI leaves it on, so pin it off for parity.
     "MD013": false,

     // Roadmap files use explicit <a id="ki-01"></a> anchors rather than
     // derived heading slugs, per localclaude:phase-workflow.
     "MD033": { "allowed_elements": ["a"] },

     // Keep a Changelog repeats Added/Changed/Fixed/Removed under every version.
     "MD024": { "siblings_only": true },

     // Numbered steps deliberately continue across headings (phase-workflow §4
     // splits one 1-7 sequence into Path A and Path B). Auto-renumbering breaks
     // cross-references such as "step 5 already removed the remote branch".
     "MD029": false
   }
   ```

3. **Point the VS Code extension at that same file**, or the editor keeps its own defaults and the two tools disagree forever. Merge this one key into `~/Library/Application Support/Code/User/settings.json` — key-scoped, never rewrite the file:

   ```json
   "markdownlint.configFile": "${userHome}/.markdownlint.jsonc"
   ```

4. **Verify** from any repo root. Both sides should now agree, and a clean tree exits 0:

   ```bash
   markdownlint-cli2 --config ~/.markdownlint.jsonc "**/*.md" \
     "!**/.venv/**" "!**/node_modules/**" "!**/.pytest_cache/**"
   ```

**Always exclude the vendor directories.** A bare `**/*.md` walks into `.venv` and `node_modules` and lints third-party package docs — which must never be edited, and which drown the real findings. Both are symlinks under this setup, so the glob follows them off into `~/Python-Envs` and `~/Node-Envs`. Tool caches like `.pytest_cache` ship a `README.md` too.

**`--fix` is safe only with this config, and only on files you touched.** Without `MD029: false` it renumbers ordered lists that deliberately continue across headings, which silently invalidates every "see step N" reference in the file. Read the diff after any `--fix` run rather than trusting the issue count.

**Indent fenced blocks inside a numbered step.** A fence at column 0 ends the list, so the next item restarts at 1. Indent it three spaces to keep the step numbering intact — the blocks in this section show the shape.

**Always pass `--config` explicitly.** The CLI finds a config by walking up from each file, so `~/.markdownlint.jsonc` is picked up only when the target sits under `~` — and silently ignored when it doesn't. Naming the file removes the guess and makes the command portable.

**Keep the VS Code extension installed.** It's the same rule engine as the CLI, so once both read this config they never contradict each other. The extension gives live feedback while editing and surfaces diagnostics to Claude through the IDE; the CLI is the batch gate over a whole repo. They cover different moments, not the same one.

### 4. Locate the synced `Code` folder, then symlink `Skills`

Everything this skill wires — `Skills/`, `Plugins/`, `Claude-Projects/` — lives side-by-side under **one synced `Code` folder**. Its parent differs per machine (e.g. `…/My Drive/AnswerRocket/Code` on one, `…/My Drive/Code` on another) and Google Drive mounts differ (CloudStorage vs classic `~/Google Drive`). So detect the `Code` folder **once** and derive all three siblings from it. Set `CODE_ROOT` by hand if the helper finds nothing (the `while … read` loop is space-safe — every "My Drive" path has a space):

```bash
# The Code folder = a dir named "Code" under a My Drive root that already contains Skills/ or Plugins/.
CODE_ROOT=""
while IFS= read -r d; do
  { [ -d "$d/Skills" ] || [ -d "$d/Plugins" ]; } && { CODE_ROOT="$d"; break; }
done < <(find "$HOME/Library/CloudStorage/"GoogleDrive-*/"My Drive" "$HOME/Google Drive/My Drive" -maxdepth 3 -type d -name Code 2>/dev/null)
echo "CODE_ROOT=$CODE_ROOT"   # set by hand if empty, e.g. CODE_ROOT="$HOME/.../My Drive/Code"
```

Then symlink the loose-skills folder (every subfolder with a top-level `SKILL.md` auto-loads, e.g. `drawio`):

```bash
SKILLS_SRC="$CODE_ROOT/Skills"
mkdir -p "$HOME/.claude"
[ -e "$HOME/.claude/skills" ] && [ ! -L "$HOME/.claude/skills" ] && mv "$HOME/.claude/skills" "$HOME/.claude/skills.local.bak"
ln -sfn "$SKILLS_SRC" "$HOME/.claude/skills"
```

Only subfolders with a `SKILL.md` load; `RCLONE_TEST`/`.DS_Store` and the plugin folder are ignored. (The `localclaude` plugin is **not** loaded this way — it loads via the marketplace in step 5, and won't double-load because it has no top-level `SKILL.md`.)

### 5. Register the `localclaude` plugin (local marketplace)

The bundled skills (`claude-setup`, `claude-toggle-backend`, `local-models`, `phase-workflow`, `external-review`, `design-review`) ship as the `localclaude` plugin in the sibling `Code/Plugins` folder.

**Gotcha:** `/plugin marketplace add` **cannot parse the Drive path** — "My Drive" has a space, the slash-command parser doesn't honor quotes, and it falls back to treating the arg as a GitHub `owner/repo`. So point it at a **space-free symlink** instead — derived from `CODE_ROOT` (step 4; set `PLUGINS_SRC` by hand if `CODE_ROOT` was empty):

```bash
PLUGINS_SRC="$CODE_ROOT/Plugins"
ln -sfn "$PLUGINS_SRC" "$HOME/.claude/localclaude-plugins"
```

Then in Claude Code, using the **literal absolute path** (no quotes, no spaces, and not `~` — the slash command won't expand it):

```text
/plugin marketplace add /Users/<you>/.claude/localclaude-plugins
/plugin install localclaude@localclaude-marketplace
```

`enabledPlugins` is written to this machine's `settings.json` (not synced), so each machine enables independently. **After install, skills are namespaced** `/localclaude:<skill>` (e.g. `/localclaude:claude-toggle-backend ollama`).

### 6. Back up chat transcripts + memory to Drive (Claude Code **and** Cowork)

Snapshot conversation transcripts, plans, per-project `memory/`, and key config to the synced `Code/Claude-Projects` folder so they're backed up and analyzable later. The backup script ships **with this plugin** (`backup-projects.sh`, next to this file), so it auto-arrives on every machine once step 5's plugin symlink exists — nothing to copy. It rsyncs these sources:

- `~/.claude/projects` → `Claude-Projects/Code`      (Claude Code transcripts + `memory/`)
- `~/.claude/plans`    → `Claude-Projects/Plans`     (approved plan-mode plan files)
- `~/Claude/Projects`  → `Claude-Projects/Cowork`    (Cowork project files)
- `~/Claude/Scheduled` → `Claude-Projects/Scheduled` (Cowork scheduled-task definitions)
- `~/Library/Application Support/Claude/local-agent-mode-sessions` → `Claude-Projects/Cowork-Local/local-agent-mode-sessions` (Cowork local-agent session transcripts + audit logs; ~200 MB on first sync, incremental after)
- `~/Library/Application Support/Claude/claude-code-sessions` → `Claude-Projects/Cowork-Local/claude-code-sessions` (Cowork-managed Claude Code session/scheduled-task state)
- A **Config snapshot** → `Claude-Projects/Config`: `~/.claude/CLAUDE.md`, `settings.json`, `history.jsonl`, `projects-backup.dest`, `commands/`, `~/.claude.json` (holds the invisible per-project "always allow" state — otherwise unrecoverable), and the Desktop app's `claude_desktop_config.json` + `config.json`.

**Why rsync-on-Stop, not a symlink into Drive:** Claude appends to the live `.jsonl` many times per turn; a symlinked dir would make Google Drive repeatedly upload a half-written file → conflicted-copy churn. rsync writes each file atomically (temp + rename), so Drive only ever sees complete files. It's append-only (no `--delete`) — transcripts pruned locally stay archived.

**a) Point it at this machine's Drive folder** (dest lives beside Skills/Plugins under `CODE_ROOT`). The script reads this `.dest` file first, so detection never has to guess:

```bash
BACKUP_DEST="$CODE_ROOT/Claude-Projects"          # from step 4
mkdir -p "$BACKUP_DEST/Code" "$BACKUP_DEST/Plans" "$BACKUP_DEST/Cowork" "$BACKUP_DEST/Scheduled" "$BACKUP_DEST/Cowork-Local" "$BACKUP_DEST/Config"
printf '# Absolute path to this machine%s Claude-Projects backup folder.\n%s\n' "'s" "$BACKUP_DEST" > "$HOME/.claude/projects-backup.dest"
```

(The script also auto-detects common layouts and honors a `CLAUDE_PROJECTS_BACKUP_DEST` env override, but the `.dest` file is the reliable per-machine anchor — use it on machines where the path isn't `…/Code/Claude-Projects`.)

**b) Seed the first backup and confirm:**

```bash
bash "$HOME/.claude/localclaude-plugins/localclaude/skills/claude-setup/backup-projects.sh"
tail -n 2 "$HOME/.claude/projects-backup.log"     # expect: ok (rc=0) -> Code Cowork Scheduled -> <dest>
```

**c) Add the `Stop` hook** to `~/.claude/settings.json` so it runs at the end of every turn. **Read the file first** and merge the `hooks` key alongside `permissions`/`model` (don't clobber existing hooks); then validate with `python3 -m json.tool ~/.claude/settings.json`:

```json
"hooks": {
  "Stop": [
    { "hooks": [ { "type": "command",
      "command": "nohup bash \"$HOME/.claude/localclaude-plugins/localclaude/skills/claude-setup/backup-projects.sh\" >/dev/null 2>&1 &" } ] }
  ]
}
```

`nohup … &` detaches rsync so the turn never waits; the script self-locks (mkdir lock) so rapid turns don't race, and always exits 0 so a backup failure can't break a turn.

**Idempotent check — already set up iff all three hold:** `~/.claude/projects-backup.dest` exists, `settings.json`'s `Stop` hook calls `backup-projects.sh`, and the log's last line shows `rc=0`. If so, just re-seed with the 6b command.

**Cowork standalone (optional) — GUI, one-time per machine.** The Stop hook only fires while you're in Claude Code, so Cowork-only sessions back up on your next Claude Code turn. For independent coverage, schedule the script with **Automator + Shortcuts** — a one-time click-through per machine that's more secure than cron (see the TCC note). Walk the user through it:

> **Why not launchd or cron.** A background **LaunchAgent can't read/write the Google Drive** (`~/Library/CloudStorage/…` FileProvider) path — it fails `Operation not permitted` — and can't be granted Full Disk Access cleanly. **cron** works but only after granting FDA to `/usr/sbin/cron`, a *shared system binary* — so every scheduled job on the machine inherits full-disk access (broad). **Automator + Shortcuts** scopes the grant to one app you built (least privilege). The `Stop` hook needs none of this: it runs inside Claude Code's logged-in session, which already has Drive access.

**Worker — a tiny Automator app that runs the script (grant *this* Full Disk Access):**

> **Give the user these steps to do by hand — do NOT build the app for them.** Creating it programmatically (an `osacompile` applet, or a hand-rolled `.app` bundle) is a dead end: those don't reliably register with Launch Services, so the app **never shows up in the Shortcuts "Open App" picker** (step 8) — confirmed the hard way. Automator's editor, the Full Disk Access grant, and Shortcuts automations are all GUI-only surfaces a background/non-interactive process can't drive anyway. Walk the user through the clicks; don't try to shortcut it.

1. **Automator** → New Document → **Application**.
2. Add the **Run Shell Script** action; set Shell to `/bin/bash`; body (**hardcode the absolute path — Automator's env may not carry `$HOME`**, so substitute the real home dir):
   `/bin/bash "/Users/<you>/.claude/localclaude-plugins/localclaude/skills/claude-setup/backup-projects.sh"`
3. **File → Save** as **`Backup Claude Projects`** into top-level **`/Applications`** (not `~/Applications`) — apps there register with Launch Services most reliably, which is what makes the app appear in the Shortcuts picker in step 8. Format stays **Application**.
4. **System Settings → Privacy & Security → Full Disk Access → `+`** → select that app → enable. (Only this app gets FDA.)
5. Double-click the app once to confirm — check `tail -n 2 ~/.claude/projects-backup.log` for a fresh `ok (rc=0)` (not `Operation not permitted`, which means the FDA toggle didn't take).

**Scheduler — a Shortcuts automation that just opens the app (needs no disk access):**

1. **Shortcuts** → **Automation** tab → **New Automation** → **Time of Day**.
2. Pick a time and **Daily** (add 2–3 automations, e.g. 12pm/6pm, for more frequent coverage — "every 30 min" isn't offered, and isn't needed for a safety net).
3. Action: **Open App** → choose **Backup Claude Projects**. Turn **off "Ask Before Running."**

**If the app still isn't in the "Open App" list** (Launch Services hasn't indexed it), force a reindex, then reopen the picker:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Backup Claude Projects.app"
```

Because Shortcuts only *opens* the app and the app carries its own FDA, neither the scheduler nor any shared binary gets broad disk access.

### 7. (Optional, any machine) Local llama.cpp server aliases

Convenience controls for the llama.cpp backend. Installed as a **managed block** between markers so re-running replaces it cleanly without clobbering other `~/.zshrc` lines (path = the space-free plugin symlink; port pinned to `8730` so the toggle and aliases agree on one port):

**Require both markers before stripping anything.** A block with only its opening marker — the
user tidied the file by hand and deleted the closing line — makes a naive strip delete
everything from that marker to the end of the file. Everything below it goes: `PATH` edits,
exports, other tools' managed blocks. Back up first, refuse on a mismatch, and never write
through a fixed temporary path a concurrent shell could be using.

```bash
set -euo pipefail
ZS="$HOME/.zshrc"
OPEN='# >>> localclaude aliases'
CLOSE='# <<< localclaude aliases'

if [ -f "$ZS" ]; then
  n_open="$(grep -c "^$OPEN" "$ZS" || true)"
  n_close="$(grep -c "^$CLOSE" "$ZS" || true)"
  [ "$n_open" = "$n_close" ] || {
    echo "MARKER MISMATCH in $ZS — $n_open opening, $n_close closing."
    echo "Repair the block by hand; refusing to edit."; exit 1; }
  cp -p "$ZS" "$ZS.localclaude.bak"
  if [ "$n_open" != "0" ]; then
    TMP="$(mktemp "${TMPDIR:-/tmp}/zshrc.XXXXXX")"
    awk -v o="$OPEN" -v c="$CLOSE" '
      index($0, o) == 1 { s = 1; next }
      index($0, c) == 1 { s = 0; next }
      !s' "$ZS" > "$TMP"
    mv "$TMP" "$ZS"
  fi
fi

cat >> "$ZS" <<'EOF'

# >>> localclaude aliases (managed) >>>
# Pin the llama.cpp port so the toggle and aliases use the same server.
export LLAMACPP_PORT=8730
alias llama-cpp-up='LLAMACPP_PORT=8730 bash "$HOME/.claude/localclaude-plugins/localclaude/skills/claude-toggle-backend/llama-serve.sh" start'
alias llama-cpp-down='bash "$HOME/.claude/localclaude-plugins/localclaude/skills/claude-toggle-backend/llama-serve.sh" stop'
alias llama-cpp-status='bash "$HOME/.claude/localclaude-plugins/localclaude/skills/claude-toggle-backend/llama-serve.sh" status'
# <<< localclaude aliases <<<
EOF
```

- `export LLAMACPP_PORT=8730` — makes `claude-toggle-backend llama-cpp` use the same fixed port (8730) as the aliases, instead of auto-scanning. (8730 is an unregistered port; nothing standard uses it.)
- `llama-cpp-up` — start the server (single-instance: sweeps any stray first; port pinned 8730).
- `llama-cpp-down` — stop it and clean up any orphans.
- `llama-cpp-status` — show whether it's running (pid/port/model) and warn if >1 process.

(New shell or `source ~/.zshrc` to use them in an open terminal.)

### 8. (Optional, OFF by default) Auto-start llama-server at login

The server is **manual by default** (`llama-cpp-up`). **Only set this up if the user explicitly asks.** To auto-start it from login via a launchd LaunchAgent:

```bash
bash "$HOME/.claude/localclaude-plugins/localclaude/skills/claude-toggle-backend/llama-autostart.sh" install
```

- `RunAtLoad` + `KeepAlive=false`: starts once at login on port 8730, but `llama-cpp-down` still works and it won't respawn until the next login (so it coexists with the manual aliases).
- **Caveats:** holds ~14 GB resident from login on — don't pair with Ollama on a 24 GB machine; macOS shows a one-time "background item added" (Login Items) notification.
- **Alias lifecycle:** `install` also adds a `llama-cpp-autostart` alias (→ `llama-autostart.sh`) to `~/.zshrc`; `uninstall` **removes** it again — so the alias exists only while auto-start is enabled, and this skill / `llama-autostart.sh install` stays the single obvious way to re-enable it. (It's never created on a machine that hasn't enabled auto-start.)
- Manage: `llama-autostart.sh status` / `llama-autostart.sh uninstall` (uninstall removes the plist + alias; it leaves any running server alone — stop that with `llama-cpp-down`).

### 9. Tell the user to fully restart

Config (and plugin enablement) is read at **process start**. In the VS Code extension each chat tab is a long-lived `claude` process; "Developer: Reload Window" only *resumes* it. The user must fully **quit (Cmd+Q) and reopen** for changes to take effect. (CLI: start a new `claude` invocation.)

### 10. Confirm and point to the reference

Report what was added/merged and which skills now load, then point at `REFERENCE.md`.

## Quick reference

- Read-only commands → allowlisted (no prompt). File-modifying commands → still prompt, by design.
- Always double-quote paths; never `My\ Drive`. Prefer absolute paths over `cd "…" && relative`.
- Loose skills (drawio) load via the `~/.claude/skills` symlink; bundled skills load via the `localclaude` plugin (`/localclaude:<skill>`). Both, plus the transcript-backup dest, derive from one detected `Code` root.
- Transcripts + plans + memory + config (Claude Code & Cowork, incl. Cowork local-agent sessions) back up to `Code/Claude-Projects` at the end of every turn via a `Stop` hook (`backup-projects.sh`). Dest is recorded in `~/.claude/projects-backup.dest`; activity log at `~/.claude/projects-backup.log`.
- Context-heavy plugins (huggingface-skills, firebase, mcp-server-dev, feature-dev, code-simplifier) default OFF per step 2b — re-enable per session when needed.
