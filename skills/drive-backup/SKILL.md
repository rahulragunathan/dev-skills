---
name: drive-backup
version: 1.0.0
description: Back up Claude Code and Cowork transcripts, plans, per-project memory and key config to the synced Google Drive Code/Claude-Projects folder, via a Stop hook that runs at the end of every turn plus an optional standalone scheduler. Use when setting up the backup on a machine, checking whether it is still running, or debugging a backup that has stopped.
license: MIT
---

# drive-backup

Snapshot Claude conversation transcripts, plans, per-project `memory/` and key config to the
synced `Code/Claude-Projects` folder, so sessions survive a machine and stay analyzable later.

The script ships with this plugin (`backup-projects.sh`, next to this file), so it arrives on
every machine once the plugin symlink exists — nothing to copy. `claude-setup` step 5 creates
that symlink; run it first on a new machine.

## What gets copied

| Source | Destination under `Claude-Projects/` |
| --- | --- |
| `~/.claude/projects` | `Code` (Claude Code transcripts + per-project `memory/`) |
| `~/.claude/plans` | `Plans` (approved plan-mode plan files) |
| `~/Claude/Projects` | `Cowork` (Cowork project files) |
| `~/Claude/Scheduled` | `Scheduled` (Cowork scheduled-task definitions) |
| `~/Library/Application Support/Claude/local-agent-mode-sessions` | `Cowork-Local/local-agent-mode-sessions` (~200 MB first sync, incremental after) |
| `~/Library/Application Support/Claude/claude-code-sessions` | `Cowork-Local/claude-code-sessions` |
| Config snapshot | `Config` |

The config snapshot is `~/.claude/CLAUDE.md`, `settings.json`, `history.jsonl`,
`projects-backup.dest`, `commands/`, `~/.claude.json` — which holds the invisible per-project
"always allow" state and is otherwise unrecoverable — and the Desktop app's
`claude_desktop_config.json` + `config.json`.

**Why rsync on Stop, not a symlink into Drive.** Claude appends to the live `.jsonl` many
times per turn. A symlinked directory would make Drive's watcher upload a half-written file
over and over: conflicted copies, wasted CPU, and a small corruption risk on the live file.
rsync writes each file atomically (temp + rename), so Drive only ever sees a complete file.
Loose skills are read-mostly and fine to symlink; transcripts are not.

**Append-only.** No `--delete`, so a transcript pruned locally stays in the backup and the
Drive copy grows into an archive.

## Install on a machine

### 1. Point it at this machine's Drive folder

The destination lives beside `Skills/` and `Plugins/` under the `CODE_ROOT` that `claude-setup`
step 4 detects. The script reads this `.dest` file first, so detection never has to guess:

```bash
BACKUP_DEST="$CODE_ROOT/Claude-Projects"
mkdir -p "$BACKUP_DEST/Code" "$BACKUP_DEST/Plans" "$BACKUP_DEST/Cowork" "$BACKUP_DEST/Scheduled" "$BACKUP_DEST/Cowork-Local" "$BACKUP_DEST/Config"
printf '# Absolute path to this machine%s Claude-Projects backup folder.\n%s\n' "'s" "$BACKUP_DEST" > "$HOME/.claude/projects-backup.dest"
```

**Destination resolution, first match wins:** `$CLAUDE_PROJECTS_BACKUP_DEST` →
`~/.claude/projects-backup.dest` → a glob of the common `…/Code/Claude-Projects` layouts → a
bounded `find`. The `.dest` file is what makes a machine with a different Drive layout
(`…/My Drive/Code` vs `…/My Drive/AnswerRocket/Code`) work without touching the hook or the
script — write it on every machine rather than relying on the glob.

### 2. Seed the first backup and confirm

```bash
bash "$HOME/.claude/localclaude-plugins/localclaude/skills/drive-backup/backup-projects.sh"
tail -n 2 "$HOME/.claude/projects-backup.log"     # expect: ok (rc=0) -> Code Cowork Scheduled -> <dest>
```

### 3. Add the `Stop` hook

Runs the script at the end of every turn. **Read `~/.claude/settings.json` first** and merge
the `hooks` key alongside `permissions` / `model` rather than clobbering existing hooks, then
validate with `python3 -m json.tool ~/.claude/settings.json`:

```json
"hooks": {
  "Stop": [
    { "hooks": [ { "type": "command",
      "command": "nohup bash \"$HOME/.claude/localclaude-plugins/localclaude/skills/drive-backup/backup-projects.sh\" >/dev/null 2>&1 &" } ] }
  ]
}
```

`nohup … &` detaches rsync so the turn never waits on it. The script self-locks with a `mkdir`
lock, so rapid turns do not race, and always exits 0 so a backup failure cannot break a turn.

**Already set up iff all three hold:** `~/.claude/projects-backup.dest` exists, the `Stop` hook
in `settings.json` calls `backup-projects.sh`, and the log's last line shows `rc=0`. If so,
just re-seed with the step 2 command.

**Migrating from a pre-1.0 layout.** The hook used to point at
`skills/claude-setup/backup-projects.sh`. A hook still on that path silently backs nothing up —
the log stops growing rather than reporting an error. Rewrite the path and re-seed.

## Optional: back up when Claude Code is not running

The `Stop` hook only fires while you are in Claude Code, so Cowork-only sessions get backed up
on your next Claude Code turn. That is usually enough. For independent coverage, schedule the
script with **Automator + Shortcuts** — a one-time click-through per machine.

**Why not launchd or cron.** All three hit the same wall: the Google Drive
`~/Library/CloudStorage/…` FileProvider path needs Full Disk Access, and they differ in how
contained that grant is.

- **launchd — will not work.** A background LaunchAgent fails `Operation not permitted` on the
  Drive path and cannot be granted FDA cleanly.
- **cron — works, but broad.** Needs FDA on `/usr/sbin/cron`, a *shared system binary*, so
  every scheduled job on the machine inherits full-disk access.
- **Automator app + Shortcuts — least privilege, recommended.** The grant covers one app you
  built, and Shortcuts only opens it, so Shortcuts itself needs no disk access.

The `Stop` hook needs none of this: it runs inside Claude Code's logged-in session, which
already has Drive access.

**Worker — a tiny Automator app that runs the script.**

> **Give the user these steps to do by hand — do NOT build the app for them.** Creating it
> programmatically (an `osacompile` applet, or a hand-rolled `.app` bundle) is a dead end:
> those do not reliably register with Launch Services, so the app **never appears in the
> Shortcuts "Open App" picker** — confirmed the hard way. Automator's editor, the Full Disk
> Access grant and Shortcuts automations are GUI-only surfaces a background process cannot
> drive anyway.

1. **Automator** → New Document → **Application**.
2. Add the **Run Shell Script** action, shell `/bin/bash`, body — **hardcode the absolute path,
   because Automator's environment may not carry `$HOME`**:
   `/bin/bash "/Users/<you>/.claude/localclaude-plugins/localclaude/skills/drive-backup/backup-projects.sh"`
3. **File → Save** as **`Backup Claude Projects`** into top-level **`/Applications`**, not
   `~/Applications` — apps there register with Launch Services most reliably, which is what
   makes the app appear in the Shortcuts picker. Format stays **Application**.
4. **System Settings → Privacy & Security → Full Disk Access → `+`** → select that app →
   enable. Only this app gets FDA.
5. Double-click the app once, then check `tail -n 2 ~/.claude/projects-backup.log` for a fresh
   `ok (rc=0)`. `Operation not permitted` means the FDA toggle did not take.

**Scheduler — a Shortcuts automation that just opens the app.**

1. **Shortcuts** → **Automation** → **New Automation** → **Time of Day**.
2. Pick a time and **Daily**. Add two or three automations (12pm, 6pm) for more coverage —
   "every 30 minutes" is not offered, and is not needed for a safety net.
3. Action: **Open App** → **Backup Claude Projects**. Turn **off "Ask Before Running."**

**If the app is not in the "Open App" list,** Launch Services has not indexed it. Force a
reindex and reopen the picker:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Backup Claude Projects.app"
```

## Operating notes

- **rsync flags: `-rt`, not `-a`.** Recurse and preserve mtimes, but skip perms/owner/group —
  Google Drive mounts reject `chmod`/`chown` and would spam errors. Exit code 24 ("file changed
  as we read it", i.e. a live `.jsonl` grew mid-copy) is treated as success.
- **Log:** `~/.claude/projects-backup.log`, auto-trimmed to the last 300 lines once it passes
  1000. Safe to delete at any time.
- **Exiting 0 is deliberate; logging `ok` regardless is not.** The two are separate and only
  the first is a feature. Every failure currently reaches the log as `ok`, so a backup that has
  silently stopped looks identical to one that is working. That is **KI-14**, and it is what
  hides KI-06 and KI-08 as well. The fix keeps the exit code and corrects the log line.
- **A stale lock disables every later run** through that same silent path, after a `SIGKILL` or
  a power loss (**KI-06**).
- **`$CLAUDE_CONFIG_DIR` is not honoured** — the script resolves `$HOME/.claude` directly.
  Supporting it is ENH-07.

The script has no tests. That is **ENH-03**, and the reason the four open issues above are
still open: they are being fixed against a `bats` harness rather than one at a time.
