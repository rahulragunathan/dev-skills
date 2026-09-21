#!/usr/bin/env bash
# preflight.sh — ask each reviewer one cheap question before committing a pass.
#
# Usage:
#   preflight.sh [--codex-model SLUG[:EFFORT]] [--gemini-model M]
# Codex pairs probe at the supplied effort; a bare slug defaults to high.
#
# Pass 9 spent about 100 minutes learning, one chunk at a time, that the Gemini
# account had been out of quota from the start and would stay out for another
# 110 hours. Every chunk returned zero bytes. One probe answers that before the
# first real invocation.
#
# Per reviewer it prints one of:
#   READY        answered the probe
#   QUOTA        the account is exhausted; the window is printed with it.
#                Quota is account-wide, so downshifting the model will not help.
#   UNAVAILABLE  this model is not available; a lower rung may still answer.
#   NO ANSWER    exited 0 but produced nothing — the documented Codex trap,
#                where exit status alone cannot tell a finished review from an
#                exhausted account.
#   MISSING      the CLI is not on PATH.
#   FAILED       anything else; the message is printed.
#
# Exit 0 when at least one reviewer can answer, 1 when none can. Exit 0 with a
# reviewer down is a real result: the pass runs, and its coverage is PARTIAL.

set -uo pipefail

CODEX_MODELS=()
GEMINI_MODELS=()
DEADLINE="${PREFLIGHT_TIMEOUT:-120}"
while [ $# -gt 0 ]; do
  case "$1" in
    --codex-model) CODEX_MODELS+=("${2:?model required}"); shift 2 ;;
    --gemini-model) GEMINI_MODELS+=("${2:?model required}"); shift 2 ;;
    --timeout) DEADLINE="${2:?timeout required}"; shift 2 ;;
    *) echo "unknown argument: $1"; exit 1 ;;
  esac
done
if [ "${#CODEX_MODELS[@]}" -eq 0 ] && [ "${#GEMINI_MODELS[@]}" -eq 0 ]; then
  echo "supply discovered candidates with --codex-model / --gemini-model (repeatable)"
  exit 1
fi
case "$DEADLINE" in ''|*[!0-9]*|0) echo "timeout must be a positive integer"; exit 1;; esac
RUNNER="$(cd -- "$(dirname -- "$0")" && pwd)/deadline.py"

TMP="$(mktemp -d)" || { echo "CANNOT CREATE TEMP DIR"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

PROBE='Reply with the single word: ready'
READY_COUNT=0
DOWN=()

# Classify a failed probe from its error text. Quota and availability read alike
# to a bare exit status and demand opposite responses, so they are separated
# here rather than at each call site.
timed_out() { grep -qiE 'probe timeout|print timeout|timed out|turn in progress' "$1"; }

classify_error() {
  local err="$1"
  if timed_out "$err"; then
    printf 'TIMEOUT — inconclusive; raise the print timeout and retry'; return 0
  fi
  if grep -qiE 'quota|rate limit|limits|upgrade your subscription' "$err"; then
    local window
    window="$(grep -oiE 'resets in [0-9hms ]+' "$err" | head -1)"
    printf 'QUOTA'
    [ -n "$window" ] && printf ' (%s)' "$window"
    return 0
  fi
  if grep -qiE 'not supported|unknown model|is not available|entitle' "$err"; then
    printf 'UNAVAILABLE'; return 0
  fi
  printf 'FAILED — %s' "$(head -c 160 "$err" | tr '\n' ' ')"
}

# A silent success is the trap both CLIs share: exit 0 with nothing produced.
# The reason is on stderr, and quota, availability and timeout each call for a
# different response, so read it rather than reporting a bare "no answer".
silent_zero() {
  local err="$1" reason
  reason="$(classify_error "$err")"
  case "$reason" in
    FAILED*) printf 'NO ANSWER — exited 0 and wrote nothing' ;;
    *)       printf '%s (exit 0, no output)' "$reason" ;;
  esac
}

report() {
  printf '%-8s %-24s %s\n' "$1" "$2" "$3"
  case "$3" in
    READY) READY_COUNT=$((READY_COUNT + 1)) ;;
    *) DOWN+=("$1") ;;
  esac
}

# Each reviewer gets its own deadline; availability follows the supplied ladder.
probe() {
  local reviewer="$1" cli="$2" model slug effort rc result
  shift 2
  if ! command -v "$cli" >/dev/null 2>&1; then
    report "$reviewer" "—" MISSING; return
  fi
  if [ "$#" -eq 0 ]; then
    report "$reviewer" "—" "UNAVAILABLE — no discovered candidates supplied"; return
  fi
  local remaining="$#"
  for model in "$@"; do
    remaining=$((remaining - 1))
    OUT="$TMP/$reviewer.txt"; ERR="$TMP/$reviewer.err"
    : > "$OUT"
    if [ "$reviewer" = codex ]; then
      slug="${model%%:*}"
      case "$model" in *:*) effort="${model#*:}";; *) effort=high;; esac
      model="$slug:$effort"
      python3 "$RUNNER" "$DEADLINE" codex exec --skip-git-repo-check --sandbox read-only \
        -m "$slug" -c model_reasoning_effort="$effort" -o "$OUT" "$PROBE" > "$TMP/codex.stdout" 2> "$ERR" < /dev/null
    else
      python3 "$RUNNER" "$DEADLINE" agy -p "$PROBE" --model "$model" --effort high \
        --print-timeout "${DEADLINE}s" > "$OUT" 2> "$ERR" < /dev/null
    fi
    rc=$?
    if [ "$rc" = 124 ] || timed_out "$ERR"; then
      result="TIMEOUT — inconclusive"
    elif [ "$rc" = 0 ] && [ "$(tr -d '\r\n' < "$OUT")" = ready ]; then
      result=READY
    elif [ "$rc" = 0 ] && [ -s "$OUT" ]; then
      result="NO ANSWER — expected the single word ready"
    elif [ "$rc" = 0 ]; then
      result="$(silent_zero "$ERR")"
    else
      result="$(classify_error "$ERR")"
    fi
    case "$result" in
      UNAVAILABLE*) [ "$remaining" -eq 0 ] || printf '%-8s %-24s %s\n' "$reviewer" "$model" "$result" ;;
      *) break ;;
    esac
  done
  report "$reviewer" "$model" "$result"
}
if [ "${#CODEX_MODELS[@]}" -gt 0 ]; then
  probe codex codex "${CODEX_MODELS[@]}"
else
  probe codex codex
fi
if [ "${#GEMINI_MODELS[@]}" -gt 0 ]; then
  probe gemini agy "${GEMINI_MODELS[@]}"
else
  probe gemini agy
fi

echo
if [ "$READY_COUNT" -eq 0 ]; then
  echo "NO REVIEWER CAN ANSWER — do not start the pass"
  exit 1
fi
if [ "${#DOWN[@]}" -gt 0 ]; then
  echo "PARTIAL COVERAGE if you proceed — ${DOWN[*]} cannot answer"
  echo "Say so on the coverage line; a reviewer that produced nothing is not a clean pass."
fi
exit 0
