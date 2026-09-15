# claude-setup — reference & troubleshooting

Why each rule in `SKILL.md` exists, and how to debug "I allow-listed it but still get prompted." Derived empirically on macOS with the Claude Code VS Code extension, projects living under Google Drive (`…/My Drive/…`).

## The permission model in one paragraph

`~/.claude/settings.json` (`permissions.allow` / `deny`) is the declarative, cross-project allowlist — it applies to every project. A Bash command is auto-approved only when **every** segment of the command (split on `&&`, `||`, `|`, `;`) matches an allow rule, the command has no risky construct, **and** every file path it touches is inside a trusted root. Built-in read-only commands and the selected permission mode also affect approval; this allowlist alone does not determine every prompt. A `deny` rule is un-appealable — it blocks even at an approval prompt and in accept-edits/bypass modes — so reserve it for catastrophes.

## Gotchas that cause "still prompting" despite an allowlist

1. **Overbroad Bash rule syntax.** `Bash(cmd:*)` and `Bash(cmd *)` preserve a command boundary.
   `Bash(cmd*)` matches longer command names too. The
   [permission reference](https://code.claude.com/docs/en/permissions) documents both forms.

2. **Edits don't apply until a full restart.** Config is read at process start. The VS Code extension runs one long-lived `claude` process per chat tab, several launched with `--resume`. "Developer: Reload Window" *resumes* those same processes with stale in-memory config. Only **`Cmd+Q` + reopen** (or a brand-new session) re-reads the file. A "new chat" in the same window is often not enough. Check with `ps -ax | grep "[c]laude"`.

3. **Workspace-boundary gate.** An allow-listed command STILL prompts if it touches a path **outside** the trusted roots = the project cwd plus any `--add-dir` directories. Home dir, `/tmp`, a sibling repo are out of scope. Widen with `permissions.additionalDirectories` if genuinely needed.

4. **Backslash-escaped spaces break the boundary check.** `…/My\ Drive/…` gets mis-tokenized, so path extraction for gate #3 fails → an in-scope path is treated as out-of-scope → prompt, even for a clean allow-listed `grep`. **Always double-quote paths:** `"…/My Drive/…"`. Since repos live under `My Drive`, every absolute path has a space. With quoted paths, `2>/dev/null` redirects and regex metacharacters do NOT prompt.

5. **`cd` in a compound command can trip a prompt** even with `Bash(cd:*)` allowed: after `cd "…"`, the relative paths that follow can't be statically verified as in-scope. Prefer absolute double-quoted paths and avoid long `cd && … && …` chains. Best of all, prefer the native **Grep / Glob / Read** tools — they never go through Bash permissions.

6. **"Always allow" clicks are invisible and non-portable.** They persist in `~/.claude.json` (per-project `allowedTools`), NOT in `settings.json`. The durable, portable allowlist is `~/.claude/settings.json`.

## Plugin & skills loading (this toolkit)

- **Two load paths.** Loose skills (e.g. `drawio`) load via the `~/.claude/skills` → Drive `Skills/` **symlink** (every subfolder with a top-level `SKILL.md`). The bundled skills load via the **`localclaude` plugin** registered from a **local marketplace** (Drive `Plugins/`). A plugin folder is NOT picked up by the skills symlink because it has no top-level `SKILL.md` (its skills live under `localclaude/skills/`), so there's no double-loading even if both trees are reachable.
- **Plugin skills are namespaced.** After installing `localclaude`, invoke as `/localclaude:claude-toggle-backend`, etc. — not bare `/claude-toggle-backend`.
- **`enabledPlugins` is machine-local.** It lives in that machine's `settings.json` and is not synced — so each machine runs `/plugin marketplace add` + `/plugin install` once. This is intentional (lets a machine opt out).
- **Local marketplace.** `Code/Plugins/.claude-plugin/marketplace.json` declares the `localclaude-marketplace` and lists the `localclaude` plugin by relative `source: "./localclaude"`. Re-run `/plugin marketplace add` after moving the folder.

## Why these specific commands

- **Allowed for routine exploration:** `cd ls find grep head tail cat diff echo ps wc sort uniq cut tr nl column jq` + the `Grep`/`Glob`/`Read` tools. This is a prompt-reduction list, not a security boundary. Test runners and formatters in the allowlist can execute code and write files.
- **Allowed despite writing — the everyday dev loop.** `pytest`, `black`, `ruff` and `markdownlint-cli2` run project code or rewrite files, and are allow-listed anyway because they are invoked constantly and are project-scoped. `ruff check --fix` and `markdownlint-cli2 --fix` are covered by deliberately broad shared prefixes; that is accepted, not overlooked. The venv forms (`.venv/bin/python -m pytest`, `.venv/bin/ruff`, …) are listed separately because a bare `pytest` rule never matches them. `uv` is allowed for env creation, interpreter installation and inspection; it can download Python. `uv pip install` and the external environment scripts are not allow-listed. `npm test` and `npx vitest` are allowed; `npm run` and `npm install` are not.
- **Denied (catastrophic):** root/home recursive force-deletes, `--no-preserve-root`, `mkfs`, `dd`, `shutdown`, `reboot`. Prefix matching is literal — `rm --recursive --force /` or flag reordering won't match, so the real protection is still the default prompt on everything non-allow-listed.
- **Deliberately NOT allowed (so they still prompt):** `sed` (`-i` writes), `awk`, `tee`, `xargs` (`find | xargs rm` would bypass the "ask before file changes" intent), and any `> realfile` redirect. **`rm` is never allow-listed**; to delete use `rm -r` (no `-f`), `rmdir`, or Finder (`rm -rf` on home/abs paths is denied outright).

## What this skill no longer owns

Two concerns moved out, so troubleshooting for them lives with their skill rather than here:

- **The Drive backup** — `/localclaude:drive-backup`. The Stop hook, `backup-projects.sh`, the
  destination resolution order, the rsync flag choices, and the Full Disk Access / Automator /
  Shortcuts path are all documented there.
- **The llama.cpp shell aliases and login auto-start** — `/localclaude:claude-toggle-backend`,
  which owns the managed `~/.zshrc` block. `claude-setup` no longer writes `~/.zshrc` at all,
  and it advises on the VS Code markdownlint key rather than writing it.

## Other useful facts

- VS Code extension sessions run `--permission-mode acceptEdits`, which auto-applies Edit/Write file edits. Cycle with **Shift+Tab** to approve edits too. (Deny rules still hard-block destructive bash regardless of mode.)
- A broken `settings.json` (invalid JSON) silently disables **all** settings in that file — always validate after editing.
- Settings precedence: managed → user (`~/.claude/settings.json`) → project (`.claude/settings.json`) → local (`.claude/settings.local.json`) → CLI flags. Allow/deny arrays merge across sources.

## Second-machine bootstrap (summary)

1. Detect `CODE_ROOT` — the synced `Code` folder holding `Skills/`, `Plugins/`, `Claude-Projects/`. Its parent can differ per machine (`…/My Drive/Code` vs `…/My Drive/AnswerRocket/Code`) (step 4).
2. Symlink `~/.claude/skills` → `$CODE_ROOT/Skills` (step 4) and `~/.claude/localclaude-plugins` → `$CODE_ROOT/Plugins`, then `/plugin marketplace add /Users/<you>/.claude/localclaude-plugins` + `/plugin install localclaude@localclaude-marketplace` (step 5).
3. Backup: run `/localclaude:drive-backup` — it creates the destination folders, writes `~/.claude/projects-backup.dest`, seeds once, and merges the `Stop` hook into `settings.json` (step 6).
4. Cmd+Q + reopen.
