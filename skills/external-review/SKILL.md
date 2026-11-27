---
name: external-review
description: Independent external review from OpenAI Codex and Google Gemini at the phase workflow's checkpoints — `plan` on a drafted plan, `phase` on a branch before hand-off, `repo` on current state. Reviewers never apply fixes; every finding is verified and given a disposition in one table. Use when an outside opinion on a plan, diff or codebase is wanted.
---

# external-review

Independent reviews from Codex and Gemini at three junctures: **plan** (before implementation), **phase** (branch diff before hand-off), **repo** (current state, no in-flight branch). Both eligible reviewers run each time; findings are verified, then presented in the standard findings table with a disposition for every row.

**Independence follows the diff's author.** A reviewer that authored the material under review
is disqualified from clearing its own work, regardless of whether it answers successfully.
For a Codex-authored diff, Codex is disqualified and Gemini supplies the independent review;
for a Gemini-authored diff, the reverse applies. The rule holds for any author, including
Claude: a second opinion from the author is not a second opinion. Changing the author's model
rung or reasoning effort does not remove the disqualification.

## Preflight — check the CLIs first

The blocks in this skill run under bash or zsh, the shell Claude Code's Bash tool may use, so
they avoid the constructs the two read differently.

```bash
command -v codex; command -v agy
```

Neither CLI is a hard requirement of this plugin. Check both **before** composing any prompt, so a missing tool surfaces as one clear line instead of a confusing failure halfway through:

- **Both present** → review with the independent reviewers.
- **One missing** → say which reviewer is unavailable and its install hint (`codex` → the OpenAI Codex CLI, then `codex login`; `agy` → the Antigravity CLI), then review with the other if it is independent. If the remaining reviewer is the author, report no coverage.
- **Both missing** → **skip the review entirely.** Report: *"External review skipped — neither `codex` nor `agy` is installed"*, with both install hints. Do not fall back to the material's author for an independent review. This is a skip, not a failure — never block the user's workflow on it.

### Coverage classification

Record an outcome for every required reviewer/chunk pair in each pass. An invocation succeeds
only when it exits zero and returns a non-empty findings list or `No findings.`. An empty or
absent output, or a failed invocation, leaves that pair uncovered. Preserve its error verbatim
and identify missing CLIs. An authoring reviewer leaves its pairs uncovered even with successful
output: record **Disqualified (author)** and the authorship reason, separately from **Failed**
or **Missing**. Do not describe it as unable to answer. Retries replace the outcome only for
the same pair and cannot remove an authorship disqualification.

| Required reviewer/chunk outcomes | Coverage |
| --- | --- |
| All pairs return successful independent output | **Full coverage** |
| Some pairs succeed independently; others are **Failed** or **Missing** | **Partial coverage** — name each gap and reason |
| Some pairs succeed independently; an authoring reviewer is **Disqualified (author)** | **Partial coverage** — name the author and disqualification reason |
| No pairs return successful independent output, whether failed, missing, or disqualified | **No coverage** |

**Skipped** applies only when both CLIs are missing and the step never ran. A failed, missing,
or disqualified reviewer permits partial coverage only when another independent invocation
succeeded. If both independent reviewers answer chunk 1 and fail chunk 2, the pass has partial
coverage and chunk 2 has no coverage. Report
both the pass outcome and each chunk's gaps. Never record incomplete coverage as a clean pass.
A phase with no coverage needs a successful re-run or the user's recorded decision to land
without external review.

Offer the install commands; never install a CLI or change the user's login state yourself.

## The two reviewers are NOT interchangeable — different invocation contracts

**Discover the ladder; never hard-code model names.** Entitlements differ per machine and per
signed-in account, and model generations turn over faster than this file gets edited. Both CLIs
publish what they offer, so read it at run time.

```bash
# fence: ladder-wrappers
# Codex — codex-ladder.py ranks the cache (see below) and emits slug:effort rungs.
codex_ladder() { python3 "$CLAUDE_PLUGIN_ROOT/skills/external-review/codex-ladder.py" \
  "$HOME/.codex/models_cache.json" "$@"; }

# Gemini — `agy models` publishes no ranking; gemini-ladder.py ranks the listing on its stdin.
agy_models() { agy models 2>"<scratchpad>/agy-models.err"; }
gemini_ladder() { python3 "$CLAUDE_PLUGIN_ROOT/skills/external-review/gemini-ladder.py" "$@"; }
```

**`codex-ladder.py` owns the Codex ranking**, and its docstring states the order; the family order
is its `FAMILIES`. The cache's `priority` field is OpenAI's default pick, not a capability rank,
so it is not used. Change the ranking there and verify it with `tests/codex-ladder.bats`.

**`gemini-ladder.py` owns the Gemini ranking**, and its docstring states the order; the family
order is its `FAMILIES`. It prints an empty line when nothing qualifies. Change the ranking
there and verify it with `tests/gemini-ladder.bats`.

**Only Gemini models through `agy`.** The `^gemini-` filter is not cosmetic: `agy` also offers
`claude-*` and `gpt-oss-*`. The filter keeps the run inside the Gemini subscription;
independence still depends on who authored the material, so Gemini is disqualified on its own work.

**At most three rungs, and the floor is a refusal.** The invocation loops below walk them — selecting only
the first rung would document a downshift that can never run. Downshift only when a model fails
with an **availability** error (`model ... is not supported`, unknown or retired model,
entitlement error). Quota, auth and timeout are **not** downshift triggers — see *Failure
handling*.

**Three is a ceiling on how far you may descend, not a promise that three exist.** Where the
discovered list is shorter, the floor arrives sooner; never pad it out by relaxing the filter to
reach a third name.

**Run the discovery block in the same shell as the loops** — the same Bash call, since variables do not carry from one call to the next. The loops read `CODEX_RUNGS` and
`GEMINI_RUNGS`, and refuse to start when a variable is unset rather than loop zero times. An
empty ladder, which discovery has already reported, leaves the other reviewer running.

**An empty ladder is a failure, not a clean review.** If discovery returns nothing — a missing
or malformed `models_cache.json`, an `agy models` that did not run — record that reviewer as
**Failed** with the reason, and run the other. Check the first `slug:effort` pair before
running:

```bash
# fence: discovery
EFFORT=high   # only when the user asks for another: EFFORT=max (or xhigh, medium)
CODEX_RUNGS="$(codex_ladder --effort "$EFFORT")" || CODEX_RUNGS=""
IFS=: read -r slug effort <<< "${CODEX_RUNGS%% *}"
[ -n "$slug" ] && [ -n "$effort" ] || { CODEX_RUNGS=""; echo "No Codex rung at $EFFORT (no model offers it, or no readable cache) — record no output for Codex, do not run"; }
# Listing and ranking run apart, so a failure names the program that failed.
if MODELS="$(agy_models)"; then
  if GEMINI_RUNGS="$(printf '%s\n' "$MODELS" | gemini_ladder --effort "$EFFORT")"; then
    [ -n "$GEMINI_RUNGS" ] || echo "No Gemini model offers $EFFORT effort — record no output for Gemini, do not run"
  else
    GEMINI_RUNGS=""; echo "gemini-ladder.py failed — record no output for Gemini, do not run"
  fi
else
  GEMINI_RUNGS=""; echo "agy models failed — record no output for Gemini, do not run; agy-models.err says why"
fi
```

**If all three rungs fail, that reviewer produces nothing. Never reach past the floor.** A review
from the weakest tier available is worse than no review: it arrives with the same authority as a
real one and the coverage line cannot carry the difference. Record the reviewer as **Failed**,
with the reason: it is installed, so it is not a missing CLI. Whether the pass is partial or no
coverage depends on what the *other* reviewer did.

**Reviews run at `high` effort, for both reviewers, on the strongest model available: the
model is chosen first (family, then version), then run at `high`.** A model that cannot run at
`high` is skipped, never run at another effort. Another effort runs only when the user asks for
it for that review: then pass it to both ladders, `codex-ladder.py --effort <level>` (`medium`,
`xhigh` or `max`) and `gemini-ladder.py --effort <level>` (`medium`, `xhigh` or `max`; Gemini lists no
`max` today, so that request skips every Gemini model). `ultra` is never chosen: it delegates tasks automatically, so the work may not come from
the recorded model. Each Codex rung is `slug:effort`. A Gemini id carries its effort: the ladder
offers each model's `-high` id, else its suffix-less id, run with `--effort high`. Set the Codex
effort explicitly, since `-m` alone does not: split the pair and pass `-m "$slug"` with
`-c model_reasoning_effort="$effort"`; the cache's default effort does not select the rung. Bare
slugs keep the explicit `high` fallback. Record the effort beside the slug — a `high` run and a
`max` run from one slug are different review configurations.

**Record which model and effort actually ran**, using `slug:effort` for Codex in the coverage
line and the findings table's Model column.
Note a downshift plainly there: a lighter model changes how much weight a finding deserves.
The authoring reviewer's rung and effort still get recorded in the coverage line as diff
provenance, even when disqualified: who wrote the diff matters. If the probe or review uses
a different rung or effort from the authoring run, record those separately.

- **Top-tier availability is a PLAN issue, not an auth-method one.** The strongest Codex tiers need a paid ChatGPT subscription; the **free** tier does not include them. The CLI's error is misleading — it says *"not supported when using Codex with a ChatGPT account"* when the real cause is the account's plan. Diagnose with `codex login status`, which reports the plan without opening the token store. **Do not read `~/.codex/auth.json`** — it holds credentials, and the do-not-read rule in the rubric applies to us as much as to the reviewers. If it reads `free`, say so, and that `codex logout && codex login` switches accounts; Codex auth is global per machine.
- If every rung is rejected, the cached list is likely stale. `agy models` is live and `codex` refreshes `models_cache.json` itself, so re-run discovery before concluding.

**Codex is agentic.** First prepare `ROOT` with `codex-root.sh` as described under
[Modes](#modes), applying every scope exclusion. Use that root for reviews and diagnostic
probes. Pin writes off at the tool level:

```bash
# fence: codex-loop
: "${CODEX_RUNGS?run the ladder discovery block first}"
[ -z "$CODEX_RUNGS" ] || : "${ROOT:?prepare the review root with codex-root.sh first}"
for m in $(printf '%s' "$CODEX_RUNGS"); do
  slug="${m%%:*}"
  case "$m" in *:*) effort="${m#*:}";; *) effort=high;; esac
  OUT="<scratchpad>/codex_<mode>_p<n>_c<chunk>_a<attempt>_${slug}_${effort}.txt"
  LOG="${OUT%.txt}.log"; STATE="${OUT%.txt}.state"
  rm -f "$OUT" "$LOG" "$STATE"   # never inherit a previous attempt's answer
  rc=0
  codex exec -C "$ROOT" --sandbox read-only --skip-git-repo-check \
    -m "$slug" -c model_reasoning_effort="$effort" \
    -o "$OUT" "<prompt>" > "$LOG" 2>&1 < /dev/null || rc=$?
  if [ "$rc" = 0 ] && [ -s "$OUT" ]; then echo done > "$STATE"; break; fi   # it answered; keep this rung
  if grep -E '^ERROR:' "$LOG" | grep -F "$slug" | grep -qiE 'not supported|unknown model|is not available|entitle'; then
    # The log can quote a refusal from the material under review, so a probe of this rung confirms it.
    CONFIRMED=""
    while read -r who model result; do
      if [ "$who" = codex ] && [ "$model" = "$slug:$effort" ]; then CONFIRMED="$result"; fi
    done <<< "$(bash "$CLAUDE_PLUGIN_ROOT/skills/external-review/preflight.sh" \
      --codex-model "$slug:$effort" --root "$ROOT" --timeout 120 2>&1 || true)"
    case "$CONFIRMED" in
      UNAVAILABLE*) echo unavailable > "$STATE"; echo "unavailable: $slug:$effort — trying the next rung"; continue ;;
    esac
    echo failed > "$STATE"
    echo "$slug:$effort failed, and a probe did not confirm it unavailable (${CONFIRMED:-the probe gave no codex row}) — classify per Failure handling"; break
  fi
  echo failed > "$STATE"
  echo "$slug:$effort failed for a reason that is not availability — classify per Failure handling"; break
done
```

- **Each attempt leaves its end.** The loop writes `.state` (`done`, `failed` or `unavailable`) beside the output, so `progress.sh` reports a run that failed before answering as failed, not running.
- **`-o` captures the final message and nothing else.** A quota, auth or availability failure never reaches it, so the file is absent or empty and says nothing about why. The `.log` beside it holds stderr; the hand-off quotes its error lines verbatim, and the PR copy of the record does not.
- **Downshift only on an `ERROR:` line that names this rung's own model, confirmed by a probe.**
  Codex writes the prompt and its whole transcript to stderr, so a run that fails mid-review
  leaves a log quoting the material under review, which can hold an earlier refusal of the same
  model. A refusal names the model it refused (`ERROR: The '<slug>' model is not supported …`);
  the loop then probes that rung with `preflight.sh` and downshifts only when the probe's own
  `codex` row says `UNAVAILABLE`.
- **Codex can exit zero on a quota failure.** Require the output artifact as specified in
  [Coverage classification](#coverage-classification), and retain the diagnostic log.
- **Name every invocation uniquely: mode, pass, chunk, attempt, model and effort.**
  `codex_<mode>_p<n>_c<chunk>_a<attempt>_<slug>_<effort>.txt`. Pass and model alone are not enough once
  a bundle is chunked or a rung is retried: chunk 2 overwrites chunk 1's findings, and a retry
  that produces nothing leaves the previous attempt's non-empty file standing, which then
  satisfies the success check and is reported as this attempt's answer. Reconcile the coverage
  line against the individual invocation files, not against one name per reviewer.
- **Number the output files by pass.** `phase-workflow` §3 step 7 cites these paths and byte counts as the evidence step 5 ran. One reused filename lets pass 1's output stand in for a pass 2 that never happened.

**Gemini (`agy -p`) is one-shot print mode — it cannot prompt for tool permissions.** Any prompt asking it to "review this repository" gets its tool calls auto-denied and fails. **Always inline the material in the prompt** and state: *"REVIEW ONLY: do not attempt to use any tools; answer purely from the text below."*

```bash
# fence: gemini-loop
: "${GEMINI_RUNGS?run the ladder discovery block first}"
for m in $(printf '%s' "$GEMINI_RUNGS"); do
  OUT="<scratchpad>/gemini_<mode>_p<n>_c<chunk>_a<attempt>_$m.txt"
  PART="${OUT%.txt}.part"; ERR="${OUT%.txt}.err"; STATE="${OUT%.txt}.state"
  rm -f "$OUT" "$PART" "${OUT%.txt}.partial" "$ERR" "$STATE"   # never inherit a previous attempt
  PROMPT="$(cat "<scratchpad>/gemini_prompt_p<n>_c<chunk>.txt")" && [ -n "$PROMPT" ] \
    || { echo "no prompt for this chunk — not run"; break; }
  # agy cuts a longer prompt short and still exits 0. Measure what is sent, in bytes. wc
  # ends the pipeline, so its status is the one checked; zsh's [ reads an empty count as 0,
  # so a count that is not a number stops the run too.
  SIZE="$(printf '%s' "$PROMPT" | wc -c)" || SIZE=""
  SIZE="${SIZE//[[:space:]]/}"
  case "$SIZE" in ''|*[!0-9]*) echo "cannot measure the prompt — not run"; break ;; esac
  [ "$SIZE" -le 120000 ] \
    || { echo "prompt over 120000 bytes — split the chunk; agy would truncate it"; break; }
  # An id with an effort suffix carries its effort; a suffix-less one is told high.
  case "$m" in *-high|*-xhigh|*-max|*-medium) EFFORT_FLAG=() ;; *) EFFORT_FLAG=(--effort high) ;; esac
  rc=0
  date +%s > "${OUT%.txt}.start"   # progress.sh dates the attempt from this, not from stderr
  agy -p "$PROMPT" --model "$m" ${EFFORT_FLAG[@]+"${EFFORT_FLAG[@]}"} --print-timeout 25m > "$PART" 2> "$ERR" || rc=$?
  if [ "$rc" = 0 ] && [ -s "$PART" ]; then
    # agy's own cut-off notice, not any line that mentions the print timeout.
    cut=0; grep -q '^\[agy\] print timeout after .*returning partial output' "$ERR" || cut=$?   # 0 cut off, 1 finished, 2 unreadable
    if [ "$cut" = 1 ]; then mv "$PART" "$OUT"; echo done > "$STATE"; break; fi
    # The state goes first, so the set-aside answer is never seen without it.
    if [ "$cut" = 0 ]; then echo cut-off > "$STATE"; else echo failed > "$STATE"; fi
    mv "$PART" "${OUT%.txt}.partial"   # a cut-off answer is not coverage
    echo "$m: incomplete answer (print timeout or unreadable stderr) — the pair is Failed; classify per Failure handling"; break
  fi
  if grep -qiE 'not supported|unknown model|is not available|entitle' "$ERR"; then
    rm -f "$PART"; echo unavailable > "$STATE"
    echo "unavailable: $m — trying the next rung"; continue
  fi
  echo failed > "$STATE"
  mv "$PART" "${OUT%.txt}.partial"     # kept, even empty, so the failed attempt stays visible
  echo "$m failed for a reason that is not availability — classify per Failure handling"; break
done
```

- Build each chunk's prompt in its own file (rubric + inlined material), named by pass and
  chunk, so a retry or a parallel run cannot answer another chunk's material. Use the print
  timeout in the invocation above.
- **Each attempt leaves its start and its end.** The loop writes `.start` (the attempt's
  epoch) and `.state` (`done`, `cut-off`, `failed` or `unavailable`) beside the output, and
  `progress.sh` reports from them.
- **Only a finished answer gets the output name.** `agy` streams its answer, so the loop writes
  to `.part` and renames it when the run ends well; until then `progress.sh` reports the run as
  running. On a print timeout `agy` exits 0 and returns the partial answer, saying so only on
  stderr; that answer, and any answer from a failed run, is set aside as `.partial`, so the
  pair stays uncovered.
- **Pass `--effort` only for a suffix-less id.** An id with a suffix carries its effort
  (`gemini-4-neon-xhigh`), and `agy` refuses a second one:
  `--model gemini-4-neon-xhigh conflicts with --effort=high`. A suffix-less id gets
  `--effort high`.

**Classify availability only after a failed invocation, and keep stderr in its own file.**
Grepping a combined stream for `not supported` misreads a *successful* review whose findings
contain that phrase as an unavailable model — the good answer is discarded and the next rung
overwrites it. Check exit status and a non-empty answer first; only then read the error stream.

**Both:** run as background tasks; **capture to scratchpad files and Read them — never pipe through `tail`/`head`**, which truncates the top of the findings list (the highest-severity items).

**Post a progress line every five minutes while a pass runs.** A review takes many minutes, and
silence looks the same as a dead process. Each update is one line per invocation, from:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/external-review/progress.sh" "<scratchpad>" <n>
```

It reports each invocation as done with its byte count, or running with its elapsed minutes and
when its log last changed, and flags a run past the 25-minute print timeout. In Claude Code, start
a Monitor that runs it every 300 seconds until no invocation is running; elsewhere, check at that
interval. Change it in `progress.sh` and verify it with `tests/progress.bats`.

**A machine that sleeps pauses the review.** The reviewers' network connections drop, the
updates stop, and a log stops changing; after waking, a run can hang rather than resume. Judge it
from after the wake (`pmset -g log` on macOS shows the sleeps). A run whose log and answer have
not changed in the ten minutes since is a reason to look, not to kill: check its process. Stop it
and run it again as the next attempt only when its process is gone, or it is past its deadline
(Gemini's 25-minute print timeout; for Codex, the same 25 minutes with no log change).

**Probe each reviewer before committing a pass.**

```bash
# fence: probe
: "${CODEX_RUNGS?run the ladder discovery block first}" "${GEMINI_RUNGS?run the ladder discovery block first}"
PROBE_ARGS=()
for m in $(printf '%s' "$CODEX_RUNGS"); do
  slug="${m%%:*}"
  case "$m" in *:*) effort="${m#*:}";; *) effort=high;; esac
  PROBE_ARGS+=(--codex-model "$slug:$effort")
done
for m in $(printf '%s' "$GEMINI_RUNGS"); do PROBE_ARGS+=(--gemini-model "$m"); done
[ "${#PROBE_ARGS[@]}" -gt 0 ] || { echo "No discovered models to probe"; exit 1; }
PROBE_ARGS+=(--timeout 120)
if [ -n "$CODEX_RUNGS" ]; then   # Codex probes in the prepared review root, never the caller's folder
  [ -n "${ROOT:-}" ] || { echo "ROOT is not set — prepare the review root with codex-root.sh first"; exit 1; }
  PROBE_ARGS+=(--root "$ROOT")
fi
bash "$CLAUDE_PLUGIN_ROOT/skills/external-review/preflight.sh" "${PROBE_ARGS[@]}"
```

The Codex probe splits each `slug:effort` rung and uses the real pass's effort; a bare
`--codex-model <slug>` defaults to `high`. The Gemini probe passes `--effort high` for a suffix-less id, as the review does, and no `--effort` for an id that carries its own. Codex console output is
kept separate from stderr; configuration names containing `timeout` do not indicate a timeout.
A deadline or explicit incomplete-turn diagnostic still overrides a partial readiness token.

When Codex or Gemini authored the diff, append `--authored-by codex` or `--authored-by gemini`
to the preflight command. Only those two values are accepted. The author is still probed and
its rung and probe result are reported as **AUTHOR — disqualified**, but it contributes no
readiness or coverage and is excluded from the `cannot answer` list. Both probes answering
therefore means **partial coverage** when one is the author; if no independent reviewer can
answer, preflight reports `NO REVIEWER CAN ANSWER` and exits non-zero.

Supply the discovered candidates in ladder order. It tries the next candidate on availability
failure. Each subprocess has a deadline and process-group cleanup, so a hung Codex cannot
prevent the Gemini probe. It asks each CLI one cheap question and reports `READY`, `QUOTA` with the reset
window, `UNAVAILABLE`, `TIMEOUT`, `NO ANSWER`, `MISSING`, or `AUTHOR` with its probe result.
Exit 0 means at least one independent reviewer can answer; exit 1 means none can and the pass does not
start. Those outcomes are not interchangeable: quota is account-wide so a
downshift cannot help and the only options are waiting or proceeding partial;
availability is per model so the next rung may answer; a timeout is
inconclusive and says to retry with a longer print timeout.

A failed probe or authorship disqualification leaves that reviewer uncovered. Report partial
coverage only if another independent required invocation succeeded; otherwise report no coverage. Change probe behavior in
`preflight.sh` and verify it with `tests/preflight.bats`.

## Shared rubric — both reviewers get this text VERBATIM

Prompt drift between the two reviewers corrupts the agree/disagree triage. Compose once, per mode:

1. **Repo-facts preamble (mandatory, ~5 lines):** what the project is, where tests live and how they run (e.g. "a pytest suite exists under `tests/` — read it before commenting on coverage"), which doc files exist, anything a cold reviewer predictably gets wrong. This prevents false findings (a reviewer confidently reporting "no tests" costs a wasted round trip).
2. **Already-tracked list (mandatory where the roadmap files exist):** every current entry in `docs/KNOWN_ISSUES.md`, `docs/ENHANCEMENTS.md` and `docs/OPEN_QUESTIONS.md` as **ID + title + rating + the entry's first sentence** — IDs, not full bodies, so the prompt stays small. Head it:

   > *Already tracked — do not re-report these. Do say so if you think one is mis-rated, filed in the wrong place, or has a cause different from the one recorded.*

   Without this the reviewers re-derive the whole backlog and the duplicates swamp the genuinely new findings. With it they stay on what the phase actually changed.

   **Send only the entries in scope for this phase.** Where a component is being rebuilt or is otherwise off the table, its entries are noise: the reviewers spend the pass re-deriving bugs in code nobody is going to touch, and the real findings compete with them. Name the excluded area in the preamble — *"`billing` and `export` are being rebuilt; their open issues are out of scope, do not report on those two modules"* — rather than silently dropping the IDs, so a reviewer that finds something there can still say so in one line. Scope exclusions are per-review; nothing leaves the roadmap files.

   **Keep an excluded area out of the bundle as well as out of the preamble.** A reviewer reads what it is given, and an instruction not to report on a skill whose files sit in front of it does not hold — that was measured, not assumed. Pass `--exclude <path>` to `capture.sh` once per excluded area, and keep the preamble sentence too, so a reviewer meeting a reference to the area elsewhere can still say so in one line. The excluded files leave the manifest and appear in the excluded count, so the reconciliation still names them. `--exclude` is refused in `plan` mode, which captures a single named file.
3. **Focus list** by mode:
   - *plan*: gaps and missing steps, risks and failure modes, sequencing problems, simpler approaches missed, anything underspecified.
   - *phase / repo*: real bugs (report everything, do not self-filter for severity), silent failures, security issues, design choices that will not hold up, code duplication/consolidation opportunities, genuinely missing test coverage; plus doc-vs-code contradictions (README, ARCHITECTURE, AGENTS.md or CLAUDE.md, the roadmap files where the repo has them, CHANGELOG).
4. **Security (both reviewers, every mode):**

   > **Security.** Look for security problems on purpose, not in passing.
   > *plan*: trust boundaries and untrusted inputs, including text that reaches another agent's
   > prompt (bundles, tool output, review records); authentication and authorization; privilege
   > and sandbox boundaries; where secrets live and where they could leak (logs, bundles,
   > records, URLs, command lines); data sent to outside services; and any new dependency or
   > tool the plan adds.
   > *phase / repo*: trace each untrusted input to the command, file, query, page or outbound
   > request it reaches, and name the missing control: injection (shell, SQL, path, template,
   > XSS), SSRF, path traversal and symlink following, unsafe parsing or deserialization, weak
   > crypto or disabled TLS checks, unsafe file and temp-file permissions, secret exposure, and
   > missing auth checks. Treat a dependency change (a new or upgraded package, an unpinned
   > version, an install script) as a prompt to inspect it; report it with a concrete consequence.

5. **Test-discrimination question** (*phase / repo* only): *"For each test in the material below, say whether it would still pass with the change it covers reverted. Name any test that asserts on a mock, on a constant, or on something true before the change."* This is a backstop — phase-workflow §3 step 3 already checks that every new test has a recorded red, and **mutates** the named behaviour of a test written after its fix, which a reviewer cannot do. Ask anyway: a reviewer reading the assertion catches a different class than a mutation catches.
6. **Do-not-read instruction (mandatory, both reviewers):**

   > Do not open `.env`, `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `credentials*`, `.netrc`, `.npmrc`, `.pypirc`, `id_rsa*`, `id_ed25519*`, `id_ecdsa*`, or anything else shaped like a secret. If a finding depends on one, name the file and say what you would need rather than reading it.

7. **Don't explain the tools:**

   > This is a workflow document, not a git tutorial. Flag any passage that explains standard behaviour of `git`, `gh`, `pytest` or the shell rather than stating this project's policy. Genuine nuances that people get wrong are in scope; plain feature descriptions are not.

8. **Suggested remediation:** for each finding, add one or two sentences on how you would fix it. A sketch, not a patch — enough to show what change you have in mind.

9. **Path, ratings and steps (every mode):**

   > For every finding, give its **Path**: `Happy Path`, `Unusual Input` or `External Interference`. Happy Path is the documented workflow, run normally, with ordinary inputs; Unusual Input is odd but legal data or a rarely used option; External Interference is another process or user writing the same files, a crash or kill mid-run, a hostile local writer, or a filesystem quirk. Give its **Area**: `Code`, `Docs` or `Tests`, the kind of file that holds the defect. Rate its **Severity** (Critical, High, Medium or Low: the harm if it fires) and its **Likelihood** (Almost Always, Likely or Rare: how often someone following the documented workflow hits it).
   > *phase / repo*: add numbered **Steps To Reproduce** from a clean checkout or a fresh fixture, with synthetic inputs, ending with what you see against what you should see. For a documentation finding, name the workflow step, its input and the wording that fails.
   > *plan*: no numbered steps; instead say concretely what goes wrong, and when.
   > Report everything you find, on any Path. Never drop a finding because of its Path.

10. **Output contract — always a list, even an empty one:**

    > Return a numbered list of findings, each with file/function references, its Path, Area, Severity and Likelihood, and in phase and repo mode its Steps To Reproduce. Return the list **even when you found nothing**: emit the heading and the single line `No findings.` Never answer with prose instead of the list.

    The empty list is what separates a reviewer that ran and found nothing from one that never ran. **Absent output means the review did not happen — nothing else does.** An independent reviewer that returns `No findings.` has covered the material; a reviewer that returns nothing at all has not, and the coverage line must say which. An author's output remains disqualified regardless of its findings.

## Modes

**Every mode bundles through the same procedure below.** The exclusions, the symlink test, the binary test and the reconciled count are not phase-mode details — they are what stops source and secrets reaching a third party, and they apply whenever anything is inlined. Only the *selection* differs by mode.

**`plan <plan-file>`** — **name the plan file explicitly.** Fall back to the newest file in `~/.claude/plans/` only when the user gave no path and you have confirmed the newest file is this phase's plan; say which file you selected. Newest-in-directory silently reviews an unrelated plan when a plan was drafted for other work in between. Inline the plan text for BOTH reviewers (Codex may also explore the prepared export for context; Gemini gets text only). A plan can quote configuration and connection strings, so run it through the same exclusion check before inlining.

**`phase [base-branch]`** — detect base via `git remote show origin` if not given. Codex: rooted at the prepared export, with the captured phase diff inlined for change context. Gemini: the change bundle below, written to a scratchpad file and inlined into the prompt.

### Capturing the phase's changes

The phase's work is committed per task, so `git diff "<base>"...HEAD` is the right command and
the bundle is built around it. **Three dots, not two** — two compares against a moving tip and
inverts upstream commits once the base advances.

Untracked files should be rare at a review point, since a task is committed before it is
reviewed. The loop below still sweeps them, because a review can be requested mid-task and a diff
never contains untracked files: the reviewer would see calls into a module it cannot read and
report the module as missing.

Build the bundle with the bundled script rather than by pasting shell:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/external-review/capture.sh" phase "<scratchpad>" "<base>"
bash "$CLAUDE_PLUGIN_ROOT/skills/external-review/capture.sh" \
  --exclude <out-of-scope-path> phase "<scratchpad>" "<base>"
```

It writes `bundle.txt`, a NUL-delimited `withheld.txt`, `manifest.z`, `all.z`, `captured.z` and
`counts.txt` into the scratchpad, prints the reconciled count line, and **exits non-zero when the
bundle is incomplete** — an enumeration failure, or any file it could not read. A non-zero exit
means do not send.

`repo` and `plan` modes take the same first two arguments; `plan` takes the plan file as its
third and adds that file's directory to the allowed roots, because plans live in
`~/.claude/plans` by design.

Change capture behavior in `capture.sh` and verify it with `tests/capture.bats`.

**Write the bundle outside the repo.** The untracked sweep lists whatever is untracked, so a
bundle written inside the working tree is listed, appended to itself, and reported with counts
that no longer reconcile. `capture.sh` refuses an output directory inside the repository for that
reason. Use the scratchpad.

**Classify tracked paths before building the diff.** The script applies the same symlink,
binary and allowed-root checks to tracked and untracked paths. It also checks both committed
blobs for binary content and non-regular file modes. It excludes withheld tracked
paths from the diff with literal pathspecs and records each reason in `withheld.txt`. Rename
sides are enumerated separately. A path absent from the worktree is withheld unless the diff is
what deleted it, in which case the patch carries the old blob and the blob checks are the whole
defence — withholding deletions hides exactly what a review needs to see. Absolute inputs keep
their root; tracked and untracked paths come from git and resolve from the repository root, so
capture covers the whole repository from any working directory inside it. A relative plan
argument resolves from the working directory that named it.

**Turn conversion off for the tracked diff.** A repo that configures `textconv` or an external
diff driver — for PDFs, notebooks, or an encrypted-file helper — otherwise runs it during capture,
and the converted plaintext lands in the bundle for a file the exclusions were written to keep
out.

Repository file classification applies credential-name checks within the repository root;
ancestors above it do not exclude the checkout. External plan files retain full physical-path
classification because they have no repository boundary. Any file read failure makes capture
fail, regardless of how many other paths were withheld.

**Bundling sends your source to a third party.** Exclude credential-shaped files from **both** lists — a tracked `.env` reaches the reviewer through `git diff` just as easily as an untracked one. **Every pattern needs a leading `*` and `icase`**: without them a pathspec anchors at the repo root and is case-sensitive, so `config/credentials.json` and `Credentials.yaml` both pass.

**Bundle filtering and export pruning are separate controls.** Pass the same scope exclusions
to both scripts. Codex's read-only sandbox limits writes; it does not isolate filesystem reads.
The export reduces accidental exposure inside the review root, but the reviewer could still
read the original repository by absolute path. Keep secrets outside its accessible filesystem
when read isolation is required. Retain the credential instruction in the rubric.

Use Git pathspecs for bundle filtering rather than a host-dependent `grep` wrapper.
Do **not** use `git add -N` to include untracked files. Capture must leave the index unchanged.

**Prepare the Codex root before invoking it, in every mode.** `--exclude` removes paths from
the bundle Gemini reads; repeat each exclusion when building the export Codex explores.
Keep the preamble's scope instruction too. Omit the exclusion flag when the review has none.

```bash
ROOT="$(bash "$CLAUDE_PLUGIN_ROOT/skills/external-review/codex-root.sh" \
  "<scratchpad>/codex-root" --exclude <out-of-scope-path>)" || exit 1
codex exec -C "$ROOT" --sandbox read-only --skip-git-repo-check ...
rm -r "<scratchpad>/codex-root"    # when the review is done
```

**`--skip-git-repo-check` is required here, and it is the export's own doing.** `codex exec`
refuses to start outside a git repository — *"Not inside a trusted directory and
--skip-git-repo-check was not specified"* — and the export deliberately has no `.git`. Without
the flag every invocation fails before it reads a byte. The check exists to stop an agent
working loose in unversioned files; the export is a read-only sandbox over a throwaway copy of a
commit, so waiving it costs nothing that matters.

The script copies regular-file blobs from the repository root at HEAD, ignoring archive
attributes that could remove files or substitute their content. It omits symlinks and submodules,
listing each omission on stderr; include those gaps in the coverage report. It then removes
literal root-relative exclusion paths and verifies each deletion. Its stdout contains only
the successful export root; refusal diagnostics go to stderr. Preserve the export log.

The export has no `.git` and no history. Inline the captured diff in phase prompts, including
follow-up passes, so the reviewer can see deletions and the exact changes under review. Inline
the captured plan in plan mode. Do not ask the reviewer to run Git commands in the export.

The script refuses a dirty tree or a failed status query. Commit first when the review must
include pending work, or explicitly narrow the review to HEAD with the user's agreement.
Exclusions must name tracked paths relative to the repository root. Run tests with
`bats skills/external-review/tests/codex-root.bats` when changing the exporter.

The export is a scope aid, not filesystem read isolation. Credential-shaped files that were
not explicitly excluded remain readable to Codex, as does material elsewhere on the machine.

**Reconcile the bundle.** Use the script's `counts.txt` in the prompt and coverage line.
`all.z` records scope before exclusions; `manifest.z` records the selected paths; `captured.z`
records included paths. Selected paths must reconcile as captured plus withheld. Report
excluded paths separately, and name withheld paths with their reasons. These lists are
NUL-delimited, including filenames that contain newlines.

**Phase capture covers commits plus untracked files, not staged or unstaged edits to tracked
files.** At a proper review point the tree is clean and that is complete. If a review is
requested mid-task, say so and either commit first or state in the report that working-tree
edits to tracked files were not captured — never let the diff silently stand in for them.

Give Codex the same manifest and count so both reviewers have the same scope.

**`repo`** — no in-flight branch; review current state (workflow adoption, periodic health check). Codex: rooted at the prepared export as above. Gemini: one bundle of the source, inlined.

**Build the `repo` bundle from `git ls-files`, never from a filesystem walk.** A walk that
follows symlinks goes straight out through `node_modules` and `.venv` into the environment root
and sweeps in every ignored file. `capture.sh repo` does this correctly:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/external-review/capture.sh" repo "<scratchpad>"
```

Same outputs, same exclusions, same symlink, binary and read-failure handling as `phase`. One
capture procedure serves every mode; none rolls its own.

**Measure before sending and chunk large bundles.** Keep each complete prompt, with its rubric
and repeated context, at **120,000 bytes** or less; the Gemini loop refuses a larger one, since
`agy` cuts it short without an error. Use the timeout in the Gemini invocation above. A timeout
can leave no answer.

```bash
# What the loop sends: the capture drops trailing newlines, so measure it, not the file.
PROMPT="$(cat "<scratchpad>/gemini_prompt_p<n>_c<chunk>.txt")" && [ -n "$PROMPT" ] \
  && printf '%s' "$PROMPT" | wc -c || echo "cannot read or measure the prompt"   # split if over 120000
```

**Split on a seam, and repeat the shared context in every chunk.** Cross-file contradiction is the main thing a review of prose is for, and chunking is exactly what hides it — so the files every other file must agree with (the project instructions file, `AGENTS.md` or `CLAUDE.md`, then `README.md` and `docs/ARCHITECTURE.md`) go into *each* chunk, and each prompt says which chunk it is and that the others cover the rest, so nothing is reported missing merely because it is elsewhere.

State exactly what each invocation covered. Reconcile the chunks against the file count and
apply [Coverage classification](#coverage-classification) to every required pair.

## Failure handling — classify, don't guess

On empty output or non-zero exit, run a tiny probe before reporting:

```bash
# fence: failure-probe
: "${ROOT:?prepare the review root with codex-root.sh first}"
m="<same model as the real run>"   # the recorded slug:effort pair
slug="${m%%:*}"
case "$m" in *:*) effort="${m#*:}";; *) effort=high;; esac
codex exec -C "$ROOT" --sandbox read-only --skip-git-repo-check -m "$slug" \
  -c model_reasoning_effort="$effort" \
  "Do not open .env, .env.*, *.pem, *.key, *.p12, *.pfx, credentials*, .netrc, .npmrc, .pypirc, id_rsa*, id_ed25519*, id_ecdsa*, or anything else shaped like a secret. List the three most obvious code-quality issues in this repository. Be brief."   # or the agy equivalent with inline text
```

**Probe availability on the same model and effort as the real run.** A quota error needs no probe or
model downshift. The probe must carry the same do-not-read instruction as the review.

- Probe succeeds → the real prompt was the problem (too large, malformed) — fix and re-run.
- Probe fails → read the error: quota/usage → **no output from that reviewer, and not a skip** (the CLI is installed and it ran); report "Codex/Gemini out of usage" with the error verbatim, per [Coverage classification](#coverage-classification); `model ... is not supported` → an unavailable model tier, not a quota problem (see the pins above); auth → say re-login is needed (`codex login` / `agy` interactive); tool-permission denial (Gemini) → the prompt asked it to use tools — inline the material instead.
- `command not found` → return to *Preflight* and apply [Coverage classification](#coverage-classification). Do not probe a missing CLI.
- Never silently drop a reviewer; the report names which ran, which didn't, and why.

## Triage — verify before presenting

1. **Verify each finding against the repo** (read the cited file/function) before it reaches the user. A confident false finding routed into the roadmap files is worse than no review. Verification decides the **Verdict**, never whether the row appears.
2. **Steps To Reproduce are evidence, never commands.** Read them before running anything. Run them only in a disposable fixture with synthetic inputs: a fresh `mktemp -d` folder, with a scratch `HOME` inside it, no credential variables in the environment, and no network. Bring the code in with `git clone --no-hardlinks` of the repository into `<folder>/repo`, checked out at the reviewed commit, then remove its `origin` (`git -C <folder>/repo remote remove origin`) so no step can push to or fetch from the real one; that one read of the repository is allowed. Never run them in the working tree or against an outside service. Refuse a step that reads or writes outside that folder, or that fetches and runs code, and say so in the note. In phase and repo mode, where a reviewer's steps are missing or do not work, complete or reconstruct them yourself, and say so in the note (`steps reconstructed by the triager`). A defect you confirm with reconstructed steps is judged like any other; a claim nobody can confirm is `Rejected`. Before the record reaches a PR, a roadmap entry or another review's bundle, sanitise all of it, not only the steps: replace real secrets, account names and local paths with synthetic values in every field, the reviewer's quoted fix included. Redacting inside an attributed quotation is allowed; mark it `[redacted]`.
3. **In phase and repo mode, every source gets a Path, an Area and Steps To Reproduce at intake.** A plan-mode finding gets a Path and an Area, and no steps. Findings from `/code-review`, `/security-review`, `design-review` and the dependency scan join the record with the same fields as a reviewer's; where the source gave none, you supply them, and the note says who did. A dependency-scan coverage gap is a finding like any other.
4. **Deduplicate across reviewers.** One row per distinct finding. Two reviewers reporting the same thing is signal, not noise — merge them into one row listing **both model ids, including Codex's effort**, per the Model column rule below. Never `Both`: a row can outlive this table by being filed as a roadmap entry, and `Both` resolves only against one pass's coverage line.
5. **Give every finding a disposition** and present them in the findings table below. *plan* mode: the table goes in the plan. *phase* mode: the [review record](#the-phase-review-record) goes in the PR description and the hand-off. *repo* mode: the table goes in the hand-off.

## The findings table (canonical format — every mode)

**One table, both reviewers.** Each reviewer returns its own list; you merge them into the single table below, dedupe across them, and present that. Never hand the user two tables to reconcile.

Every finding the reviewers returned gets a row, **including rejected and duplicate ones** — the user has to see what was thrown away. Never summarize the list down.

Build the coverage line from [Coverage classification](#coverage-classification). Successful
`No findings.` outputs contribute zero rows. Present an empty combined table when successful
invocations return no findings, and retain any uncovered reviewer/chunk pairs in the coverage
line.

Open with a coverage line so the count is unambiguous:

```text
Codex gpt-5.6-sol:high 7 · Gemini gemini-3.1-pro-high 4 · 3 overlapping → 8 unique findings
```

Name the **exact model and effort that ran**, not the CLI — the ladder is discovered at run time and downshifts on availability, so "Codex" alone hides whether the findings came from the top tier or a lighter rung. If a downshift happened, say so here too: `Codex gpt-5.6-terra:high 5 (gpt-5.6-sol:high unavailable) · …`.

If neither CLI is installed, print the skip line in its place — `External review skipped — neither codex nor agy is installed` — so a missing table is never mistaken for a clean review.

**Format: a compact table, then keyed notes.** Commentary lives below the table, keyed by finding ID.

| # | Finding | Files | Model | Path | Area | Likelihood | Severity | Verdict | Disposition |
| --- | --------- | ------- | ------- | ---- | ---- | ---------- | ---------- | --------- | ------------- |
| F-01 | No rollback if the migration half-applies | `migrate.py:88-140` | gpt-5.6-sol:high | External Interference | Code | Rare | Critical | Confirmed | Incorporated — new step 6 |
| F-02 | Token refresh races on concurrent runs | `auth/token.py`, `worker.py:41` | gpt-5.6-sol:high, gemini-3.1-pro-high | Happy Path | Code | Likely | Medium | Confirmed | Filed KI-08 |
| F-03 | Add a caching layer for lookups | `lookup.py` | gemini-3.1-pro-high | Happy Path | Code | Almost Always | Medium | Rejected | Not Incorporated |

*The dispositions above are **plan** mode; phase and repo mode use the vocabulary further down. A phase review adds `Pass` and `Commit` columns; see [the phase review record](#the-phase-review-record).*

**F-01** — *Non-Blocking* · *Disposition:* Incorporated — new step 6 — *When It Fires:* `the
condition that has to hold` *What Happens:* `the observable consequence, concretely`
*Reviewer's Fix:* `the remediation the reviewer proposed, in its own words` *Commentary:* `what
you found verifying it, and why the disposition follows`

**Every keyed note opens with *Blocking* or *Non-Blocking*, by [the blocking
rule](#the-blocking-rule), then its Disposition**, so the note reads without the table. The
first is a bare word with no label. A `Rejected` row is *Non-Blocking*: only a confirmed finding
can block. In plan mode the word says whether the finding would block once built. Then come
*When It Fires*, *What Happens*, *Reviewer's Fix* and *Commentary*; in phase and repo mode,
*Steps To Reproduce* follows *What Happens*. The examples here are plan mode, so they have
none. *When It Fires* and *What Happens* are the pair that makes a `KNOWN_ISSUES` entry assessable, and a findings row without them asks the
reader to take the severity on trust. *Steps To Reproduce* lets the next reader see it happen.
All three travel: a row filed as `KI-nn` inherits them, as its *What Happens* and *Steps To
Reproduce* sections. A KI filed from a plan review has no steps to inherit: its *Steps To
Reproduce* section gives the concrete failure from *When It Fires*, and says no run reproduced
it. A plan has no code to run, so in plan mode the note has no *Steps To
Reproduce*, and *When It Fires* carries the concrete failure.

**Carry the reviewer's fix through, in the reviewer's words.** The rubric's suggested-remediation item asks every finding
for a remediation sketch, so one comes back with each; summarizing it into your own commentary
loses the thing the user is deciding about. Two sentences at most, and where they disagree with
what you would do, say so in the commentary rather than replacing the sketch. Write
`None Offered` when the reviewer gave none — that is itself worth seeing, because a finding
whose author cannot say how to fix it is usually underspecified.

**F-02** — *Non-Blocking* · *Disposition:* Filed KI-08 — *When It Fires:* … *What Happens:* … *Reviewer's Fix:* … *Commentary:* …

Column rules:

- **#** — `F-01`, `F-02`, … Stable within this review only; they exist so the user can say "also fix F-03" without quoting titles.
- **Finding** — one short line. Not a summary of the explanation.
- **Files** — where the finding lives, as `path` or `path:start-end`, comma-separated when it spans more than one. **Take the reviewer's own reference and verify it against the repo during triage** — a wrong path is itself a signal the finding was not verified. Two or three paths is the cap; a finding touching more than that is really a finding about the design, so name the area (`skills/*/SKILL.md — every skill`) rather than listing every file. Use `—` only where the finding genuinely has no location, such as a missing file or an absent test. This column is what makes a filed `KI-nn`/`ENH-nn` entry actionable from cold, since the roadmap entry inherits it.
- **Model** — the **model id that produced the finding, with Codex's effort**, not the CLI that ran it: `gpt-5.6-sol:high`, `gemini-3.1-pro-high`. Which rung of the ladder actually answered changes how much weight a finding deserves, and that is per-run state the CLI name cannot carry. When both reviewers found the same thing, **list both ids, retaining the effort** — `gpt-5.6-sol:high, gemini-3.1-pro-high` — never `Both`: a row can outlive this table by being filed as a `KI-nn`/`ENH-nn`/`UNK-nn` entry, and `Both` resolves only against one pass's coverage line. Two ids in one cell is also the agreement signal, stated so it survives the move. Never write `Codex` or `Gemini` alone in this column.
- **Path** — `Happy Path` | `Unusual Input` | `External Interference`, the KI template's scale:
  what kind of use reaches the defect. The reviewer's own, attributed like Severity when two
  disagree. A row has one Path per reviewer: where a finding reaches more than one, take the one
  that blocks first (Happy Path, then Unusual Input, then External Interference), and name the
  others in the commentary. Where a reviewer gave none, it is yours, and the commentary says
  so.
- **Area** — `Code` | `Docs` | `Tests`: what kind of file holds the defect. A README step that
  breaks the workflow is `Docs` on the `Happy Path`. Area does not enter the blocking rule.
- **Likelihood** — `Rare` | `Likely` | `Almost Always`. **How often a user following the
  documented workflow actually hits the harm**, not how often the code path runs. The two come
  apart: a bad count computed on every run is `Rare` if it only misleads when something else has
  already failed. **A defect that is always present but harmful only in combination is `Rare`.**
  Judge it against the workflow as written — if a step tells the user to do the thing that
  triggers it, that is `Almost Always` for everyone who follows the step, however unusual it
  looks. This is the reviewer's estimate where they gave one; where they did not, it is yours,
  and the commentary says so. When the two reviewers disagree on Likelihood, record both,
  attributed like Severity: `Likely (gpt-5.6-sol:high) / Rare (gemini-3.1-pro-high)`.
- **Severity** — **the consequence if it does fire, and nothing about how often.** Take the
  reviewer's own rating verbatim, attributed by **model id with Codex's effort** and never by CLI name:
  `High (gpt-5.6-sol:high)`. **Two columns, because one number cannot carry both.** A rare defect
  that exfiltrates source is `Rare · Critical`; friction on every run is
  `Almost Always · Low`. They are different kinds of work, and a single rating hides which. Where a reviewer's rating obviously folded in likelihood, keep their word in
  the cell and say so in the commentary rather than silently re-rating it. Never renormalize it: the same pass decides disposition, so quietly downgrading an inconvenient Critical would hide the decision. **When the two reviewers disagree, record both and order by the higher** — `High (gpt-5.6-sol:high) / Medium (gemini-3.1-pro-high)`. If you disagree with a rating yourself, say so in the commentary, where the user can see the disagreement. [The blocking rule](#the-blocking-rule) judges each reviewer's ratings on their own.
- **Verdict** — `Confirmed` | `Partly` | `Rejected`, from step 1. Separate from Disposition on purpose: *valid but deferred* and *invalid so dropped* are different states, and one column cannot carry both.
- **Disposition** — what actually happened; vocabulary differs by mode (below).

**Order: descending criticality**, mapping the reviewers' scales onto the KNOWN_ISSUES severity scale (Critical / High / Medium / Low). Tiebreak Confirmed above Rejected, so the actionable rows sit at the top.

### The blocking rule

A confirmed finding blocks the phase when its Severity is Critical or High, **and** at least one of these holds: its Path is Happy Path; its Likelihood is Likely or Almost Always.

It applies in phase and repo mode, to every row whose Verdict is `Confirmed` or `Partly`, whatever its source, regressions this phase introduced included. For a `Partly` row, your verified ratings of the confirmed part decide; the reviewer's own stay in the row for attribution. A blocking row is fixed in the phase; the rest are filed, and the user can pull any of them back in at the gate.

**When reviewers disagree, judge each reviewer's own Severity, Path and Likelihood.** A `Confirmed` merged row blocks only if one reviewer's three ratings block, or your own verified ratings do, and then the commentary says why; a `Partly` merged row is decided by your verified ratings alone, as above. Never combine one reviewer's ratings with another's: a High from one and a Happy Path from the other do not make a blocker. A filed merged row takes one whole set of three ratings, never a mix: your verified ones where you have them, else the set that decided a blocking disposition, else the set of the reviewer with the higher Severity. On a tie, take the set with the higher Likelihood, then the Path that blocks first, and say in the commentary which set was filed. Its Source line names each reviewer's own ratings.

| Severity | Path | Likelihood | Blocks |
| --- | --- | --- | --- |
| Medium | Happy Path | Likely | No: filed |
| High | Happy Path | Rare | Yes |
| High | External Interference | Rare | No: filed |
| Critical | Unusual Input | Likely | Yes |

### Disposition vocabulary — *plan* mode

`Incorporated — <where>` | `Already Covered — <where>` | `Filed KI-nn / ENH-nn / UNK-nn` | `Recorded Only: No Roadmap Files` | `Not Incorporated` (Verdict `Rejected`).

A valid finding that is out of scope for this phase is **kept, not dropped**. Where the repository has the four roadmap files, it is filed through `project-docs` as a `KI-nn`, `ENH-nn` or `UNK-nn` entry with its ROADMAP pointer row. Where it does not, the row stays in this table as `Recorded Only: No Roadmap Files`; nothing creates roadmap files unless the user asks. **A reviewer reading a plan often finds a real defect in the existing code; that is a `KI-nn`.** Use `UNK-nn` only for unsettled questions, per the `OPEN_QUESTIONS` template. Present the whole table in one pass regardless of severity: a confirmed Critical does not block the plan reaching the user, who is in plan mode and can send it back.

### Disposition vocabulary — *phase / repo* mode

`Fixed In Phase` | `Unfixed Blocker` | `Filed KI-nn` | `Filed ENH-nn` | `Filed UNK-nn` | `Confirmed: Accepted, No Work Planned` | `Recorded Only: No Roadmap Files` | `Rejected`.

**Every row lands in exactly one** — that is what guarantees nothing is quietly lost.

**Disposition order.** First verify, which sets the Verdict; a row that fails verification is `Rejected`. For a confirmed row, apply [the blocking rule](#the-blocking-rule): a blocking row is `Fixed In Phase`, or `Unfixed Blocker` when the loop has stopped or an incomplete pass awaits its retry; a row that does not block is filed, or `Recorded Only: No Roadmap Files`, or `Confirmed: Accepted, No Work Planned`. In repo mode there is no loop, so a blocking row is `Unfixed Blocker` and the user decides. The user can change any row at the gate; write it as `<new> — was <old>, the user's call`. The definitions below describe the default a row gets from the rule, not a row the user changed.

- `Fixed In Phase` — a blocking row, fixed on the branch, with a failing test written first.
- `Unfixed Blocker` — *not fixed.* A blocking row that waits for the user: from the pass the loop stopped on, from an incomplete pass whose retry is pending, or from a repo review, which has no loop. The loop stops before fixing its last pass's findings, since each fix needs another review pass, so the row reaches the gate unfixed and the user decides: fix it, which costs another pass, or file it.
- `Filed …` — valid and not blocking, filed through `project-docs` as a rated entry with its ROADMAP pointer row. Only where the repository has all four roadmap files; run `roadmap.py check` after filing, and fix any drift it reports. A `docs/ROADMAP.md` of another shape is the project's own document, not consent to file.
- `Confirmed: Accepted, No Work Planned` — valid, and accepted as it is: nothing will be built and nothing is filed. Its note says why.
- `Recorded Only: No Roadmap Files` — valid and not blocking, in a repository without the four roadmap files, which the skills never create unasked. The review record is where it stays.
- `Rejected` — failed verification. It is a real disposition, not a gap: it produces no artifact, and forcing it into the roadmap would pollute it.

Give each filed entry a provenance line carrying the same model ids and Codex effort as the Model column — `Source: gpt-5.6-sol:high, gemini-3.1-pro-high — phase review, phase 4` — so the attribution survives the move into a durable doc. Do not write a per-phase review file under `docs/`: it would be a backward-looking doc outside CHANGELOG, breaking the tense split.

### The phase review record

One record covers every pass of a phase review. It goes in the PR description (`gh pr edit
--body-file`) and the hand-off, and it has no times in it.

**One table across all passes**: the findings table's columns, plus `Pass` and `Commit`, in the
same severity order:

| # | Pass | Finding | Files | Model | Path | Area | Likelihood | Severity | Verdict | Disposition | Commit |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| F-01 | 1 | Token refresh races on concurrent runs | `auth/token.py` | gpt-5.6-sol:high, gemini-3.1-pro-high | Happy Path | Code | Likely | High | Confirmed | Fixed In Phase | `a1b2c3d` |
| F-03 | 2 | The F-01 fix drops the retry count | `auth/token.py:40-52` | gpt-5.6-sol:high | Unusual Input | Code | Almost Always | Medium | Confirmed | Filed KI-09 | — |
| F-02 | 1 | README names a removed flag | `README.md` | gemini-3.1-pro-high | Happy Path | Docs | Almost Always | Low | Confirmed | Confirmed: Accepted, No Work Planned | — |

The column rules above apply. `Commit` is the fix commit, or `—`. A finding from the phase's own
checks rather than an external reviewer (`/code-review high`, `/security-review`, `design-review`, the dependency scan) names that check
in the Model column and `—` in Pass.

**Under the table, a keyed note for every row** — it opens with *Blocking* or *Non-Blocking* and its Disposition, then *When It Fires*, *What Happens*, *Steps To Reproduce*, *Reviewer's Fix* and *Commentary*, as above. A fixed row adds:

- *Fix:* the change, in one line.
- *Scenarios:* each scenario the failing test covered, with the red you observed before the fix and the green after.

**Then a short block per pass:** the commit it reviewed; its coverage line with each
invocation's output file name and byte count; its findings counted by severity; how many were
in code an earlier fix of this review wrote; how many were documentation drift; and how many
were accepted without work. The PR copy names output files by name only: full scratchpad
paths, and raw error text, stay in the hand-off, since they show local account and folder
names to anyone who can read the PR.

## Follow-up passes — *phase* mode only

**This section is canonical for the review loop.** `phase-workflow` §3 step 5 states only what is phase-specific and delegates the rest here.

A first review changes the code, and those changes have been reviewed by no one — so a phase review is a loop, not one shot. `plan` and `repo` modes stay single-pass: a plan already loops through the user's approval, and a `repo` review takes stock of the code rather than gating a hand-off.

### The loop

Run up to three passes without checking in. Pass 1 is full scope; every later pass is narrow (below). Record the commit each pass reviewed.

**A pass is complete when every installed, independent reviewer covered every chunk, at least
one such reviewer exists, and no pair Failed.** A reviewer that was Missing (preflight found no
CLI) or Disqualified (the diff's author) is named in each pass's coverage line and does not
count against completion. A **Failed** pair keeps a pass incomplete: a
timeout, a quota error, a partial answer, an empty ladder, every rung unavailable. With no
independent reviewer at all, no pass is complete: the review is **Skipped** or **No coverage**,
and the gate takes the user's recorded decision instead.

1. **Run the pass and triage it.** Verify every finding and give it a disposition. A finding
   that an earlier pass's fix did not work gets a new row in this pass that names the earlier ID
   (`F-12 — the F-03 fix is partial`), and counts as new at its own severity. Earlier rows keep
   their pass and finding, and per-pass counts never change. Later, only the user changes a row:
   its Disposition, written as `<new> — was <old>, the user's call`, and, for a row reopened for
   a fix, its Commit and test evidence.
2. **Apply the stop rule before fixing anything, and only to a complete pass.** Count verified
   findings only; `Rejected` rows do not count. Stop after pass 3. Stop when a pass has no blocking
   finding ([the blocking rule](#the-blocking-rule)): its other rows are filed, no row would be
   `Fixed In Phase`, and the next pass would review an empty diff. **An incomplete pass triggers none of these**: re-run its failed pairs
   once their reviewer can answer, or take it to the user, and keep the reviewed commit where it
   was. While it waits, a confirmed blocking row from it is `Unfixed Blocker`. When the retry
   completes, those rows are settled as for any complete pass, and that is not a change by the
   user: the loop continues or stops as usual. It never ends the loop on its own — see
   [Coverage classification](#coverage-classification).
3. **If the loop continues:** fix the blocking rows, each with a failing test first,
   re-check the docs those fixes touch (`phase-workflow` §3 step 6), file the deferred rows, run the full suite, and commit. The next pass reviews only
   `<commit the last pass reviewed>..HEAD`. If that commit is no longer an ancestor of `HEAD`
   (an amend or a rebase), the next pass is full scope: the one case a follow-up widens.
4. **If it stops:** that pass's findings are not fixed. Deferred rows are filed before the gate;
   blocking rows go to the gate as `Unfixed Blocker`. A fix the user then
   asks for needs another pass, and so does any pass past three: both are the user's call.

**After the last pass, only bookkeeping lands:** new roadmap entries and pointer rows for the
deferred rows, the phase record's PR number and release version, and document fixes a reviewer
found in the release's bookkeeping files: `CHANGELOG.md`'s entry for this release, the roadmap
files and the phase record. Verify each such finding as usual; where you agree with it, fix it.
Make them without another pass: each row is `Fixed In Phase` with its commit, and its note says it
landed after the last pass. Anything else, such as a change to a skill, code, a test, README or a
regenerated diagram, needs a narrow pass of its own. At
the gate, run `phase-workflow`'s post-review check (§3 step 7): it lists both sides of every change
since the reviewed commit, refuses anything outside the bookkeeping files, and prints their patch,
which is read in full because a filing and a fix can share one file. The hand-off names what
landed.

### What the user sees at the gate

The review record, then a short assessment:

- **A Steps To Reproduce Summary** — one line per confirmed row, grouped by Path, Happy Path
  first.
- **The Trend** — one row per pass, so the blocking count is read beside the total:

  | Pass | Rows | Blocking | Outcome |
  | --- | --- | --- | --- |
  | 1 | 12 | 2 | Fixed in `a1b2c3d`; the rest filed |
  | 2 | 4 | 0 | All filed; the loop stopped |

- **What The New Findings Are About** — fresh defects in untouched code, defects in an earlier pass's own fixes, or documentation drift. A count that holds steady while the *kind* changes is a different situation from one that holds steady on the same kind.
- **Your Recommendation** — land what is here, or another pass, with the reason.

Every disposition is the user's to change: they can pull a deferred or accepted row back into the phase, or overturn a rejection, before signing off. Everything deferred is filed before the gate, or stays `Recorded Only: No Roadmap Files` in the record, since a commit after sign-off would be unreviewed. Nothing is fixed-and-unreviewed.

### What "narrow" means

Scope each follow-up prompt to exactly three things, while the reviewed commit is still an ancestor of `HEAD` (otherwise the pass is full scope, with the full-phase prompt and base):

- The diff of the fixes made **since the previous pass** — captured the same way, untracked files included, count reconciled.
- The finding IDs that pass claimed to resolve, quoted, with *"confirm each of these is actually resolved."*
- The refreshed already-tracked list, now including whatever was filed in between.

State the boundary in the prompt: **"Do not re-review the rest of the phase. Comment only on the changes below and on whether the listed findings are resolved."**

### Spotlight the fixes your own verification cannot settle

Name, in the follow-up prompt, any fix where your verification is the weakest evidence available, and ask for an adversarial read of that one specifically. The trigger is not "this was hard" — it is:

- a security-sensitive path, especially one with a known historical failure mode (a decode step downstream of a sanitizer, a path-traversal guard, an auth check);
- a fix you validated mainly by reasoning about the code rather than by a test that fails without it;
- a change whose correctness depends on a claim about a library's behavior rather than about your own code.

Say what you checked and why it may not be enough. *"I verified this `html.unescape` is classification-only and never writes the decoded value back, and that the output still carries the encoded form — but this exact function has been a sanitizer bypass before, and my own reading is the weakest evidence on precisely the thing that went wrong last time."* That framing gets a genuine adversarial read; "please double-check this" gets agreement.

### Numbering across passes

Finding IDs run in **one sequence for the whole phase** — pass 1 ends at `F-08`, pass 2 opens at `F-09`. A row can outlive the table by being filed as a roadmap entry, and per-pass numbering would make `F-01` ambiguous the moment it moves. The `Pass` column says which pass found each one.

## Hard rules

- **The reviewers never write.** Codex is held to that by `--sandbox read-only`, not by prompt wording; Gemini gets text and no tools. Neither is restricted from *reading* — see the bundle section — so "read-only" here means it cannot change the repo, never that it cannot see a file.
- **Who acts on a finding differs by mode, and both are review-only in the sense that matters — no fix is applied straight from review output.**
  - *plan*: the agent revises the plan itself, then presents the revision and the findings table together. This is deliberate: phase-workflow §1 says the plan the user sees is the revised one, so waiting for a disposition first would defeat the checkpoint.
  - *phase*: the agent dispositions and fixes within [the loop](#the-loop), and the user reviews every disposition at the gate before signing off.
  - *repo*: the user dispositions every finding **before any code is touched**. A disposition you assigned yourself is a proposal until they say so. The pause after the table is blocking: present, stop, wait.
- **Never widen a follow-up pass back to full scope**, except when the reviewed commit is no longer an ancestor of `HEAD` ([the loop](#the-loop), step 3). If pass 2 looks thin, that is the loop working, not a reason to re-review the phase.
- **Never report a bundle without its reconciled file count.** An unstated count is how a reviewer ends up reviewing half a phase and nobody notices.
- The Codex stop-time review gate (`/codex:setup`) stays **off** — it reviews every turn and burns quota; these checkpoints are the intended cadence.
- **Triage subagents gather evidence, never verdicts.** A subagent returns the quoted file lines or command output a finding turns on; the judgement stays with the main agent. A subagent is a copy of the main agent with the same blind spots, so it never decides whether a finding is right; outside opinion comes from the other models. Where the user's or the project's own standards say something different, theirs win; otherwise both apply.
