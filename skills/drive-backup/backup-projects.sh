#!/usr/bin/env bash
# backup-projects.sh — snapshot Claude Code + Cowork project transcripts to Google Drive.
#
# Invoked by a Claude Code `Stop` hook (fires at the end of every turn), and optionally by an
# Automator app on a Shortcuts schedule. Not launchd: a LaunchAgent cannot be granted the Full
# Disk Access the Google Drive FileProvider path needs, and fails `Operation not permitted`.
# Backs up:
#   ~/.claude/projects  ->  <Claude-Projects>/Code       (Claude Code transcripts + per-project memory/)
#   ~/.claude/plans     ->  <Claude-Projects>/Plans      (approved plan-mode plan files)
#   ~/Claude/Projects   ->  <Claude-Projects>/Cowork     (Cowork project files)
#   ~/Claude/Scheduled  ->  <Claude-Projects>/Scheduled  (Cowork scheduled-task definitions)
#   ~/Library/Application Support/Claude/local-agent-mode-sessions
#                       ->  <Claude-Projects>/Cowork-Local/local-agent-mode-sessions
#                                                        (Cowork local-agent session transcripts + audit logs)
#   ~/Library/Application Support/Claude/claude-code-sessions
#                       ->  <Claude-Projects>/Cowork-Local/claude-code-sessions
#                                                        (Cowork-managed Claude Code session/scheduled-task state)
#   plus a Config snapshot (see cfg_files below) -> <Claude-Projects>/Config
#                                                        (global CLAUDE.md, settings.json, commands/, history,
#                                                         ~/.claude.json per-project allow-state, Desktop configs)
#
# Design notes:
#   * rsync writes each file atomically (temp file + rename), so Google Drive for Desktop only ever
#     uploads COMPLETE files — no "conflicted copy" churn from live-appended .jsonl transcripts.
#     (This is the whole reason to rsync-on-Stop instead of symlinking the live dir into Drive.)
#   * Append-only archive: NO --delete, so transcripts pruned locally stay backed up for analysis.
#   * A mkdir lock (macOS has no flock) makes overlapping runs from rapid turns no-ops, not races.
#   * ALWAYS exits 0 — a backup failure must never break the Claude turn.
#
# Destination resolution (first match wins) — the Claude-Projects folder lives in different
# relative spots per machine (e.g. .../My Drive/AnswerRocket/Code vs .../My Drive/Code), so:
#   1. $CLAUDE_PROJECTS_BACKUP_DEST if set (explicit escape hatch)
#   2. ~/.claude/projects-backup.dest  (one line; written once per machine by claude-setup)
#   3. Glob the common .../My Drive/[AnswerRocket/]Code/Claude-Projects layouts
#   4. Bounded `find` for any dir named Claude-Projects under a My Drive root (last resort)

set -u

# Harden PATH — scheduled/GUI launch contexts (cron, Automator, Shortcuts) start with a minimal
# PATH, so name the tools' dirs explicitly (rsync/find/grep/date all live in these).
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

log="${CLAUDE_PROJECTS_BACKUP_LOG:-$HOME/.claude/projects-backup.log}"
mkdir -p "$(dirname "$log")" 2>/dev/null
ts() { date '+%Y-%m-%d %H:%M:%S'; }

# --- resolve destination -----------------------------------------------------
destfile="$HOME/.claude/projects-backup.dest"
dest="${CLAUDE_PROJECTS_BACKUP_DEST:-}"
# 2. per-machine config file (first non-empty, non-comment line)
if [ -z "$dest" ] && [ -f "$destfile" ]; then
  dest="$(grep -v '^[[:space:]]*#' "$destfile" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1)"
fi
# 3. glob the common layouts
if [ -z "$dest" ]; then
  for c in "$HOME/Library/CloudStorage/"GoogleDrive-*"/My Drive/AnswerRocket/Code/Claude-Projects" \
           "$HOME/Library/CloudStorage/"GoogleDrive-*"/My Drive/Code/Claude-Projects" \
           "$HOME/Library/CloudStorage/"GoogleDrive-*"/My Drive/Claude-Projects" \
           "$HOME/Google Drive/My Drive/AnswerRocket/Code/Claude-Projects" \
           "$HOME/Google Drive/My Drive/Code/Claude-Projects"; do
    [ -d "$c" ] && { dest="$c"; break; }
  done
fi
# 4. last resort: bounded find under any My Drive root
if [ -z "$dest" ]; then
  dest="$(find "$HOME/Library/CloudStorage/"GoogleDrive-*/"My Drive" "$HOME/Google Drive/My Drive" \
          -maxdepth 4 -type d -name Claude-Projects 2>/dev/null | head -1)"
fi
if [ -z "$dest" ] || [ ! -d "$dest" ]; then
  echo "$(ts) ERROR: no backup dest found — create a Claude-Projects folder, or write its path to $destfile, or set CLAUDE_PROJECTS_BACKUP_DEST" >> "$log"
  exit 0
fi

# --- single-run lock ---------------------------------------------------------
lock="${TMPDIR:-/tmp}/claude-projects-backup.lock"
if ! mkdir "$lock" 2>/dev/null; then
  exit 0   # a run is already in progress; it will capture the latest state
fi
trap 'rmdir "$lock" 2>/dev/null' EXIT

# --- sync each source that exists -> its dest subfolder ----------------------
# "<source dir>|<dest subfolder>"
pairs=(
  "$HOME/.claude/projects|Code"
  "$HOME/.claude/plans|Plans"
  "$HOME/Claude/Projects|Cowork"
  "$HOME/Claude/Scheduled|Scheduled"
  "$HOME/Library/Application Support/Claude/local-agent-mode-sessions|Cowork-Local/local-agent-mode-sessions"
  "$HOME/Library/Application Support/Claude/claude-code-sessions|Cowork-Local/claude-code-sessions"
)

rc_any=0
synced=""
for pair in "${pairs[@]}"; do
  src="${pair%%|*}"
  sub="${pair##*|}"
  [ -d "$src" ] || continue
  mkdir -p "$dest/$sub" 2>/dev/null
  # -rt: recurse + preserve mtimes only. We skip perms/owner/group (-a) because Google Drive
  # mounts reject chmod/chown and would spam errors. Trailing slash copies CONTENTS into dest/sub.
  rsync -rt --exclude='.DS_Store' --exclude='RCLONE_TEST' --exclude='*.lock' \
        "$src/" "$dest/$sub/" 2>>"$log"
  rc=$?
  # rsync 24 = "file vanished/changed as we read it" (a live .jsonl grew mid-copy) — benign.
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 24 ]; then rc_any="$rc"; fi
  synced="$synced $sub"
done

# --- config snapshot: individual files -> Config/ ----------------------------
# Small per-machine state that is otherwise unrecoverable (esp. ~/.claude.json,
# which holds the invisible per-project "always allow" permission state).
cfg_files=(
  "$HOME/.claude/CLAUDE.md"
  "$HOME/.claude/settings.json"
  "$HOME/.claude/history.jsonl"
  "$HOME/.claude/projects-backup.dest"
  "$HOME/.claude.json"
  "$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  "$HOME/Library/Application Support/Claude/config.json"
)
mkdir -p "$dest/Config" 2>/dev/null
for f in "${cfg_files[@]}"; do
  [ -f "$f" ] || continue
  rsync -t "$f" "$dest/Config/" 2>>"$log"
  rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 24 ]; then rc_any="$rc"; fi
done
if [ -d "$HOME/.claude/commands" ]; then
  rsync -rt --exclude='.DS_Store' "$HOME/.claude/commands/" "$dest/Config/commands/" 2>>"$log"
  rc=$?
  if [ "$rc" -ne 0 ] && [ "$rc" -ne 24 ]; then rc_any="$rc"; fi
fi
synced="$synced Config"

echo "$(ts) ok (rc=$rc_any) ->$synced -> $dest" >> "$log"

# --- keep the log bounded ----------------------------------------------------
if [ -f "$log" ] && [ "$(wc -l < "$log" 2>/dev/null || echo 0)" -gt 1000 ]; then
  tail -n 300 "$log" > "$log.tmp" 2>/dev/null && mv "$log.tmp" "$log" 2>/dev/null
fi

exit 0
