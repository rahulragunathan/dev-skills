#!/usr/bin/env bash
# One status line per review invocation of a pass, for the progress update the
# orchestrating agent posts every five minutes while reviewers run.
#
# Usage: progress.sh <scratch-dir> <pass>
#
# An invocation is a `<reviewer>_<mode>_p<pass>_c<chunk>_…txt` output file
# (prompt files are not), or a Gemini answer still streaming into `.part`, or one
# set aside as `.partial`. Non-empty output means done. Empty output means the
# reviewer is still writing: the line gives how long since it started (the
# output file is created then) and when its .log last changed. Past the
# 25-minute print timeout it says to check the run.
set -u
dir="$1"; pass="$2"
now="$(date +%s)"
mins() { echo $(( (now - $(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1")) / 60 )); }
found=0
for out in "$dir"/*_p"$pass"_c*.txt "$dir"/*_p"$pass"_c*.part "$dir"/*_p"$pass"_c*.partial; do
  [ -e "$out" ] || continue
  name="$(basename "$out")"
  case "$name" in *_prompt_*) continue ;; esac
  found=1
  reviewer="${name%%_*}"
  chunk="$(printf '%s' "$name" | sed -E 's/.*_p[0-9]+_(c[0-9]+)_.*/\1/')"
  bytes="$(wc -c < "$out" | tr -d ' ')"
  case "$name" in
    *.partial) echo "$reviewer $chunk: failed — answer cut off, $bytes bytes set aside"; continue ;;
    *.part) err="${out%.part}.err"
            ran="$(mins "$([ -e "$err" ] && echo "$err" || echo "$out")")"
            line="$reviewer $chunk: running ${ran}m, last write $(mins "$out")m ago, $bytes bytes so far"
            [ "$ran" -gt 25 ] && line="$line — past its timeout; check it"
            echo "$line"; continue ;;
  esac
  if [ -s "$out" ]; then
    echo "$reviewer $chunk: done, $bytes bytes"
    continue
  fi
  ran="$(mins "$out")"
  line="$reviewer $chunk: running ${ran}m"
  log="${out%.txt}.log"
  [ -e "$log" ] && line="$line, log written $(mins "$log")m ago"
  [ "$ran" -gt 25 ] && line="$line — past its timeout; check it"
  echo "$line"
done
[ "$found" = 1 ] || echo "no invocations for pass $pass in $dir"
