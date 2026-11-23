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
#
# The Gemini loop also writes `.start` (the attempt's epoch) and `.state` (how it
# ended) beside each output. A run is dated from `.start` where it exists, since
# stderr can change at any time, and a `.part` with a later attempt of the same
# chunk is reported as superseded, not running.
set -u
dir="$1"; pass="$2"
now="$(date +%s)"
mins() { echo $(( (now - $(stat -f %m "$1" 2>/dev/null || stat -c %Y "$1")) / 60 )); }
# started <base> <fallback file>: minutes since the attempt began.
started() {
  local s; s="$(cat "$1.start" 2>/dev/null)"
  case "$s" in ''|*[!0-9]*) mins "$2" ;; *) echo $(( (now - s) / 60 )) ;; esac
}
# superseded <name>: a later attempt of the same reviewer, pass and chunk exists.
superseded() {
  local stem att f other
  stem="${1%%_a[0-9]*}"
  att="$(printf '%s' "$1" | sed -E 's/.*_c[0-9]+_a([0-9]+)_.*/\1/')"
  for f in "$dir/${stem}"_a*; do
    [ -e "$f" ] || continue
    other="$(basename "$f" | sed -E 's/.*_c[0-9]+_a([0-9]+)_.*/\1/')"
    case "$other" in ''|*[!0-9]*) continue ;; esac
    [ "$other" -gt "$att" ] && return 0
  done
  return 1
}
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
    *.partial)
      case "$(cat "${out%.partial}.state" 2>/dev/null)" in
        failed) echo "$reviewer $chunk: failed — $bytes bytes set aside" ;;
        *) echo "$reviewer $chunk: failed — answer cut off, $bytes bytes set aside" ;;
      esac
      continue ;;
    *.part) if superseded "$name"; then
              echo "$reviewer $chunk $(printf '%s' "$name" | sed -E 's/.*_c[0-9]+_(a[0-9]+)_.*/\1/'): superseded by a later attempt"
              continue
            fi
            err="${out%.part}.err"
            ran="$(started "${out%.part}" "$([ -e "$err" ] && echo "$err" || echo "$out")")"
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
