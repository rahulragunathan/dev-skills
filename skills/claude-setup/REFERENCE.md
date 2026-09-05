# claude-setup — reference & troubleshooting

Why each rule in `SKILL.md` exists, and how to debug "I allow-listed it but still get prompted." Derived empirically on macOS with the Claude Code VS Code extension, projects living under Google Drive (`…/My Drive/…`).

## The permission model in one paragraph

`~/.claude/settings.json` (`permissions.allow` / `deny`) is the declarative, cross-project allowlist — it applies to every project. A Bash command is auto-approved only when **every** segment of the command (split on `&&`, `||`, `|`, `;`) matches an allow rule, the command has no risky construct, **and** every file path it touches is inside a trusted root. Anything not allow-listed prompts (that's the safety net for file-modifying commands). A `deny` rule is un-appealable — it blocks even at an approval prompt and in accept-edits/bypass modes — so reserve it for catastrophes.

## Gotchas that cause "still prompting" despite an allowlist

1. **Wrong Bash rule syntax.** Use `Bash(cmd:*)` (colon). `Bash(cmd*)` (no colon) silently never matches. Most common mistake.

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

- **Allowed (read-only):** `cd ls find grep head tail cat diff echo ps wc sort uniq cut tr nl column jq` + the `Grep`/`Glob`/`Read` tools. None modify files without an explicit `> file` redirect (itself gated as a write).
- **Denied (catastrophic):** root/home recursive force-deletes, `--no-preserve-root`, `mkfs`, `dd`, `shutdown`, `reboot`. Prefix matching is literal — `rm --recursive --force /` or flag reordering won't match, so the real protection is still the default prompt on everything non-allow-listed.
- **Deliberately NOT allowed (so they still prompt):** `sed` (`-i` writes), `awk`, `tee`, `xargs` (`find | xargs rm` would bypass the "ask before file changes" intent), and any `> realfile` redirect. **`rm` is never allow-listed** — deletes always prompt; to delete use `rm -r` (no `-f`), `rmdir`, or Finder (`rm -rf` on home/abs paths is denied outright).

## Transcript & memory backup (`backup-projects.sh`)

- **What/where.** A `Stop` hook runs `backup-projects.sh` at the end of every turn, rsyncing `~/.claude/projects` → `Claude-Projects/Code`, `~/Claude/Projects` → `Claude-Projects/Cowork`, and `~/Claude/Scheduled` → `Claude-Projects/Scheduled` (Cowork scheduled-task definitions). Claude Code's per-project `memory/` lives *inside* `~/.claude/projects`, so it's captured in the same pass.
- **Why a Stop hook, not a live symlink.** `~/.claude/projects` is written continuously during a session (the active `.jsonl` is appended many times per turn). Symlinking that dir into Google Drive would make Drive's watcher upload half-written files → "conflicted copy" duplicates, wasted CPU, and a small corruption risk on the live file. rsync instead writes each file atomically (temp + rename), so Drive only ever uploads a *complete* file. (Same reason loose skills — read-mostly — are fine to symlink, but transcripts are not.)
- **Append-only.** No `--delete`: a transcript pruned locally stays in the backup, so the Drive copy is a growing archive for later analysis.
- **rsync flags.** `-rt` only (not `-a`): recurse + preserve mtimes, but skip perms/owner/group — Google Drive mounts reject chmod/chown and would spam errors. Exit code 24 ("file changed as we read it," i.e. a live `.jsonl` grew mid-copy) is treated as success.
- **Concurrency & safety.** A `mkdir` lock (macOS ships no `flock`) makes overlapping runs from rapid turns no-ops. The script **always exits 0** so a backup failure can never break a turn; the hook backgrounds it with `nohup … &` so the turn never waits on rsync.
- **Destination resolution (first match wins).** `$CLAUDE_PROJECTS_BACKUP_DEST` → `~/.claude/projects-backup.dest` (one line, written per machine in step 6) → glob of common `…/Code/Claude-Projects` layouts → bounded `find`. The `.dest` file is what makes machines with a different Drive layout (`…/My Drive/Code` vs `…/My Drive/AnswerRocket/Code`) Just Work without touching the hook or script.
- **Log.** `~/.claude/projects-backup.log`, auto-trimmed to the last 300 lines once it exceeds 1000. Safe to delete anytime.
- **Cowork coverage & the TCC gotcha.** The Stop hook only fires while you're in Claude Code (it runs *inside* the app's logged-in session, which has Drive access), so Cowork-only sessions back up on your next Claude Code turn. Independent scheduling hits a TCC wall on the `~/Library/CloudStorage/…` (Google Drive FileProvider) path, and the mechanisms differ by **how contained** the required Full Disk Access grant is:
  - **launchd — ✗ won't work.** A background LaunchAgent fails `Operation not permitted` on the Drive path and can't be granted FDA cleanly.
  - **cron — works, but broad.** Requires FDA on `/usr/sbin/cron`, a *shared system binary*, so every scheduled job on the machine inherits full-disk access.
  - **Automator app + Shortcuts — recommended (least privilege).** Wrap the script in an Automator **Application**, grant FDA to *just that app*, and trigger it from a Shortcuts **Time of Day** automation via an **Open App** action (so Shortcuts itself needs no disk access). Downside: Shortcuts schedules daily/weekly, not every-30-min — fine for a safety net. This is the GUI, one-time-per-machine path in step 6.

## Other useful facts

- VS Code extension sessions run `--permission-mode acceptEdits`, which auto-applies Edit/Write file edits. Cycle with **Shift+Tab** to approve edits too. (Deny rules still hard-block destructive bash regardless of mode.)
- A broken `settings.json` (invalid JSON) silently disables **all** settings in that file — always validate after editing.
- Settings precedence: managed → user (`~/.claude/settings.json`) → project (`.claude/settings.json`) → local (`.claude/settings.local.json`) → CLI flags. Allow/deny arrays merge across sources.

## Second-machine bootstrap (summary)

1. Detect `CODE_ROOT` — the synced `Code` folder holding `Skills/`, `Plugins/`, `Claude-Projects/`. Its parent can differ per machine (`…/My Drive/Code` vs `…/My Drive/AnswerRocket/Code`) (step 4).
2. Symlink `~/.claude/skills` → `$CODE_ROOT/Skills` (step 4) and `~/.claude/localclaude-plugins` → `$CODE_ROOT/Plugins`, then `/plugin marketplace add /Users/<you>/.claude/localclaude-plugins` + `/plugin install localclaude@localclaude-marketplace` (step 5).
3. Backup: `mkdir -p "$CODE_ROOT/Claude-Projects"/{Code,Cowork,Scheduled}`, write that path to `~/.claude/projects-backup.dest`, seed once, and merge the `Stop` hook into `settings.json` (step 6).
4. Cmd+Q + reopen.
