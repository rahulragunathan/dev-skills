#!/usr/bin/env bash
# One status line per review invocation of a pass, for the progress update the
# orchestrating agent posts every five minutes while reviewers run.
#
# Usage: progress.sh <scratch-dir> <pass>
#
# An invocation is a `<reviewer>_<mode>_p<pass>_c<chunk>_…txt` output file
# (prompt files are not), or a Gemini answer still streaming into `.part`, or one
# set aside as `.partial`. Non-empty output means done, unless its state says
# it failed. Empty output means the reviewer is still writing: the line gives
# how long since it started (the output file is created then) and when its .log
# last changed. Past the 25-minute print timeout it says to check the run.
#
# Both loops write `.state` (how the attempt ended) beside each output; an output
# whose state is failed or unavailable is reported from it, empty or not. The Gemini loop
# also writes `.start` (the attempt's epoch), which dates a run where it exists,
# since stderr can change at any time. An unfinished attempt with a later attempt
# of the same chunk is reported as superseded, not running.
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
  case "$att" in ''|*[!0-9]*) return 1 ;; esac
  for f in "$dir/${stem}"_a*; do
    [ -e "$f" ] || continue
    other="$(basename "$f" | sed -E 's/.*_c[0-9]+_a([0-9]+)_.*/\1/')"
    case "$other" in ''|*[!0-9]*) continue ;; esac
    [ "$other" -gt "$att" ] && return 0
  done
  return 1
}
# say_superseded: the line for an attempt a later one replaced.
say_superseded() { echo "$reviewer $chunk $att: superseded by a later attempt"; }
# rung_answered: another rung of the same attempt left a non-empty answer, so this
# rung's `unavailable` is old news.
rung_answered() {
  local f
  for f in "$dir/${reviewer}"_*_p"$pass"_"$chunk"_"$att"_*.txt; do [ -s "$f" ] && return 0; done
  return 1
}
found=0
for out in "$dir"/*_p"$pass"_c*.txt "$dir"/*_p"$pass"_c*.part "$dir"/*_p"$pass"_c*.partial "$dir"/*_p"$pass"_c*.state; do
  [ -e "$out" ] || continue
  name="$(basename "$out")"
  case "$name" in *_prompt_*) continue ;; esac
  found=1
  reviewer="${name%%_*}"
  chunk="$(printf '%s' "$name" | sed -E 's/.*_p[0-9]+_(c[0-9]+)_.*/\1/')"
  att="$(printf '%s' "$name" | sed -E 's/.*_c[0-9]+_(a[0-9]+)_.*/\1/')"
  bytes="$(wc -c < "$out" | tr -d ' ')"
  state=""; [ -r "${out%.*}.state" ] && IFS= read -r state < "${out%.*}.state"
  case "$name" in
    *.state)
      # Only an attempt that left nothing else, such as an unavailable rung, is reported from here.
      base="${out%.state}"
      [ -e "$base.txt" ] || [ -e "$base.part" ] || [ -e "$base.partial" ] && continue
      if superseded "$name"; then say_superseded; continue; fi
      [ "$state" = unavailable ] && rung_answered && continue
      echo "$reviewer $chunk: ${state:-unknown}"; continue ;;
    *.partial)
      if superseded "$name"; then
        say_superseded
        continue
      fi
      case "$state" in
        failed) echo "$reviewer $chunk: failed — $bytes bytes set aside" ;;
        cut-off) echo "$reviewer $chunk: failed — answer cut off, $bytes bytes set aside" ;;
        *) echo "$reviewer $chunk: failed — $bytes bytes set aside, reason not recorded" ;;
      esac
      continue ;;
    *.part) if superseded "$name"; then
              say_superseded
              continue
            fi
            # A final state is authoritative: the run stopped before moving its answer aside.
            case "$state" in failed|cut-off|unavailable)
              echo "$reviewer $chunk: $state — $bytes bytes left in .part"; continue ;;
            esac
            err="${out%.part}.err"
            ran="$(started "${out%.part}" "$([ -e "$err" ] && echo "$err" || echo "$out")")"
            line="$reviewer $chunk: running ${ran}m, last write $(mins "$out")m ago, $bytes bytes so far"
            [ "$ran" -gt 25 ] && line="$line — past its timeout; check it"
            echo "$line"; continue ;;
  esac
  # A failed or unavailable state outranks any output the run left behind.
  case "$state" in failed|unavailable)
    if superseded "$name"; then say_superseded; continue; fi
    [ "$state" = unavailable ] && rung_answered && continue
    if [ -s "$out" ]; then echo "$reviewer $chunk: $state — $bytes bytes, not an answer"
    else echo "$reviewer $chunk: $state — no answer"; fi
    continue ;;
  esac
  if [ -s "$out" ]; then
    echo "$reviewer $chunk: done, $bytes bytes"
    continue
  fi
  if superseded "$name"; then
    say_superseded
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
