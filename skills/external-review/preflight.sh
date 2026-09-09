#!/usr/bin/env bash
# preflight.sh — ask each reviewer one cheap question before committing a pass.
#
# Usage:
#   preflight.sh [--codex-model M] [--gemini-model M]
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

CODEX_MODEL="gpt-6-astra"
GEMINI_MODEL="gemini-3.1-pro-high"
while [ $# -gt 0 ]; do
  case "$1" in
    --codex-model)  CODEX_MODEL="${2:?--codex-model needs a value}"; shift 2 ;;
    --gemini-model) GEMINI_MODEL="${2:?--gemini-model needs a value}"; shift 2 ;;
    *) echo "unknown argument: $1"; exit 1 ;;
  esac
done

TMP="$(mktemp -d)" || { echo "CANNOT CREATE TEMP DIR"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

PROBE='Reply with the single word: ready'
READY_COUNT=0
DOWN=()

# Classify a failed probe from its error text. Quota and availability read alike
# to a bare exit status and demand opposite responses, so they are separated
# here rather than at each call site.
classify_error() {
  local err="$1"
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
  if grep -qiE 'timeout|timed out' "$err"; then
    printf 'TIMEOUT — inconclusive; raise the print timeout and retry'; return 0
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

# --- codex ------------------------------------------------------------------
if ! command -v codex >/dev/null 2>&1; then
  report codex "$CODEX_MODEL" "MISSING"
else
  OUT="$TMP/codex.txt"; ERR="$TMP/codex.err"
  codex exec --sandbox read-only -m "$CODEX_MODEL" -o "$OUT" "$PROBE" \
    > "$ERR" 2>&1 < /dev/null
  rc=$?
  if [ "$rc" = 0 ] && [ -s "$OUT" ]; then
    report codex "$CODEX_MODEL" "READY"
  elif [ "$rc" = 0 ]; then
    report codex "$CODEX_MODEL" "$(silent_zero "$ERR")"
  else
    report codex "$CODEX_MODEL" "$(classify_error "$ERR")"
  fi
fi

# --- gemini -----------------------------------------------------------------
if ! command -v agy >/dev/null 2>&1; then
  report gemini "$GEMINI_MODEL" "MISSING"
else
  OUT="$TMP/agy.txt"; ERR="$TMP/agy.err"
  agy -p "$PROBE" --model "$GEMINI_MODEL" --print-timeout 2m \
    > "$OUT" 2> "$ERR"
  rc=$?
  if [ "$rc" = 0 ] && [ -s "$OUT" ]; then
    report gemini "$GEMINI_MODEL" "READY"
  elif [ "$rc" = 0 ]; then
    report gemini "$GEMINI_MODEL" "$(silent_zero "$ERR")"
  else
    report gemini "$GEMINI_MODEL" "$(classify_error "$ERR")"
  fi
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
