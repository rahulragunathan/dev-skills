#!/usr/bin/env bash
# One status line per review invocation of a pass, for the progress update the
# orchestrating agent posts every five minutes while reviewers run.
#
# Usage: progress.sh <scratch-dir> <pass>
#
# An invocation is a `<reviewer>_<mode>_p<pass>_c<chunk>_…txt` output file
# (prompt files are not). Non-empty output means done. Empty output means the
# reviewer is still writing: the line gives how long since it started (the
# output file is created then) and when its .log last changed. Past the
# 30-minute print timeout it says to check the run.
set -u
dir="$1"; pass="$2"
now="$(date +%s)"
mins() { echo $(( (now - $(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1")) / 60 )); }
found=0
for out in "$dir"/*_p"$pass"_c*.txt; do
  [ -e "$out" ] || continue
  name="$(basename "$out")"
  case "$name" in *_prompt_*) continue ;; esac
  found=1
  reviewer="${name%%_*}"
  chunk="$(printf '%s' "$name" | sed -E 's/.*_p[0-9]+_(c[0-9]+)_.*/\1/')"
  if [ -s "$out" ]; then
    echo "$reviewer $chunk: done, $(wc -c < "$out" | tr -d ' ') bytes"
    continue
  fi
  ran="$(mins "$out")"
  line="$reviewer $chunk: running ${ran}m"
  log="${out%.txt}.log"
  [ -e "$log" ] && line="$line, log written $(mins "$log")m ago"
  [ "$ran" -gt 30 ] && line="$line — past its timeout; check it"
  echo "$line"
done
[ "$found" = 1 ] || echo "no invocations for pass $pass in $dir"
