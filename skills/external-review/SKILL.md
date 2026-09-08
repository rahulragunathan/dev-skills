---
name: external-review
description: External review from non-Claude models (OpenAI Codex, Google Gemini) at the phase workflow's checkpoints — `plan` on a drafted plan, `phase` on a branch before hand-off, `repo` on current state. Reviewers never apply fixes; every finding is verified and given a disposition in one table. Use when an outside opinion on a plan, diff or codebase is wanted.
---

# external-review

Independent reviews from non-Claude models at three junctures: **plan** (before implementation), **phase** (branch diff before hand-off), **repo** (current state, no in-flight branch). Both reviewers run each time; findings are verified, then presented in the standard findings table with a disposition for every row.

## Preflight — check the CLIs first

```bash
command -v codex; command -v agy
```

Neither CLI is a hard requirement of this plugin. Check both **before** composing any prompt, so a missing tool surfaces as one clear line instead of a confusing failure halfway through:

- **Both present** → normal run.
- **One missing** → say which reviewer is unavailable and its install hint (`codex` → the OpenAI Codex CLI, then `codex login`; `agy` → the Antigravity CLI), then review with the other.
- **Both missing** → **skip the review entirely.** Report: *"External review skipped — neither `codex` nor `agy` is installed"*, with both install hints. Do not fall back to a Claude-run review: a second opinion from the same model is not a second opinion, and presenting one as this checkpoint's output would be misleading. This is a skip, not a failure — never block the user's workflow on it.

### A skip and partial coverage are different things

**The step is skipped only when it did not run.** That is the both-missing case above, and nothing else.

**Classify by how many reviewers produced output, not by how many are installed.** Count the
reviewers that returned a findings list — `No findings.` counts, an empty or absent file does
not — and read the outcome off that count:

| Reviewers that produced output | Outcome |
| --- | --- |
| Both | **Full coverage** |
| Exactly one | **Partial coverage** — name the other and give its error verbatim |
| Neither | **No coverage** |

*Skipped* is the one case that is not about output at all: **both CLIs missing**, so the step
never ran. Everything else with zero output is **no coverage** — including one CLI missing and
the other out of quota, which the earlier both-installed wording let slip through as "partial"
while nothing had been reviewed. No coverage is emphatically not a skip, must never be recorded
as a clean pass, and a phase cannot reach its gate on one.

**A reviewer that ran and produced nothing is a failed reviewer, not automatically partial coverage.** Record that outcome per reviewer; the aggregate is then read off the table below, and it is *partial* only when some other reviewer did produce output. A CLI that is installed and then fails on **quota**, **auth**, **timeout** or **sandbox denial** did not cause a skip — it ran and came back empty. Say so in the coverage line, name the reviewer, and give the reason verbatim:

> *Coverage: Codex `gpt-5.6-sol` 9 findings. Gemini installed but returned `Individual quota reached` (resets 23h26m) — no findings this pass. Single-reviewer coverage, not a clean review.*

Never record partial coverage as "both reviewers clean". A single-reviewer report has no agree/disagree axis, so its findings carry less weight, and the hand-off must say which reviewer is missing and why.

Offer the install commands; never install a CLI or change the user's login state yourself.

## The two reviewers are NOT interchangeable — different invocation contracts

**Discover the ladder; never hard-code model names.** Entitlements differ per machine and per
signed-in account, and model generations turn over faster than this file gets edited. Both CLIs
publish what they offer, so read it at run time.

```bash
# Codex — its own cache ranks capability in `priority`, ascending.
codex_ladder() { python3 - "$HOME/.codex/models_cache.json" <<'EOF'
import json,sys
try: models=json.load(open(sys.argv[1]))["models"]
except Exception: sys.exit(1)
vis=[m for m in models if m.get("visibility")=="list" and m.get("priority") is not None]
print(" ".join(m["slug"] for m in sorted(vis,key=lambda m:m["priority"])[:3]))
EOF
}

# Gemini — `agy models` publishes no ranking, so rank by family, then effort, then version.
gemini_ladder() { agy models 2>/dev/null | awk '$1 ~ /^gemini-/ {print $1}' | python3 -c '
import sys,re
def rank(s):
    fam = 0 if "-pro" in s else 1
    m = re.search(r"gemini-(\d+)(?:\.(\d+))?", s)
    ver = (-int(m.group(1)), -int(m.group(2) or 0)) if m else (0, 0)   # tuple, not float: 3.10 outranks 3.9
    eff = {"high":0,"medium":1,"low":2}.get(s.rsplit("-",1)[-1], 3)
    return (fam, eff, ver)
ms=[l.strip() for l in sys.stdin if l.strip()]
ms=[m for m in ms if not m.endswith("-low")]
print(" ".join(sorted(ms,key=rank)[:3]))'
}
```

**Only Gemini models through `agy`.** The `^gemini-` filter is not cosmetic: `agy` also offers
`claude-*` and `gpt-oss-*`. A Claude model is not a second opinion on Claude's work, and the
filter keeps the run inside the Gemini subscription.

**At most three rungs, and the floor is a refusal.** The loops above walk them — selecting only
the first rung would document a downshift that can never run. Downshift only when a model fails
with an **availability** error (`model ... is not supported`, unknown or retired model,
entitlement error). Quota, auth and timeout are **not** downshift triggers — see *Failure
handling*.

**Three is a ceiling on how far you may descend, not a promise that three exist.** Where the
discovered list is shorter, the floor arrives sooner; never pad it out by relaxing the filter to
reach a third name.

**An empty ladder is a failure, not an empty loop.** If discovery returns nothing — a missing or
malformed `models_cache.json`, an `agy models` that did not run — `for m in $(…)` iterates zero
times and the reviewer silently produces no output, which reads downstream as a clean review.
Check before running, and record that reviewer as having produced no output:

```bash
[ -n "$(codex_ladder)" ] || echo "Codex ladder discovery returned nothing — record no output for Codex, do not run"
```

**If all three rungs fail, that reviewer produces nothing. Never reach past the floor.** A review
from the weakest tier available is worse than no review: it arrives with the same authority as a
real one and the coverage line cannot carry the difference. Report it exactly as you would a
missing CLI for that reviewer — no output from it, named, with the reason. Whether the pass is partial or no coverage depends on what the *other* reviewer did.

**Set reasoning effort explicitly; `-m` alone does not.** Every Codex model supports low through
max and the strongest defaults to **low**, so naming only the slug gets the weakest setting of
the strongest model while the run reads as stronger than it was. Pass
`-c model_reasoning_effort="high"`, and record the effort beside the slug — a `low` run and a
`high` run from one slug deserve different weight and the slug alone cannot tell them apart.

**Record which model actually ran**, in the coverage line and the findings table's Model column.
Note a downshift plainly there: a lighter model changes how much weight a finding deserves.

- **Top-tier availability is a PLAN issue, not an auth-method one.** The strongest Codex tiers need a paid ChatGPT subscription; the **free** tier does not include them. The CLI's error is misleading — it says *"not supported when using Codex with a ChatGPT account"* when the real cause is the account's plan. Diagnose with `codex login status`, which reports the plan without opening the token store. **Do not read `~/.codex/auth.json`** — it holds credentials, and the do-not-read rule in the rubric applies to us as much as to the reviewers. If it reads `free`, say so, and that `codex logout && codex login` switches accounts; Codex auth is global per machine.
- If every rung is rejected, the cached list is likely stale. `agy models` is live and `codex` refreshes `models_cache.json` itself, so re-run discovery before concluding.

**Codex is agentic** — it explores the repo itself. Point it at the repo root and pin it read-only at the tool level (never rely on prompt wording alone):

```bash
for m in $(codex_ladder); do
  OUT="<scratchpad>/codex_<mode>_p<n>_c<chunk>_a<attempt>_$m.txt"
  LOG="${OUT%.txt}.log"
  rm -f "$OUT" "$LOG"          # never inherit a previous attempt's answer
  codex exec -C "<repo-root>" --sandbox read-only \
    -m "$m" -c model_reasoning_effort="high" \
    -o "$OUT" "<prompt>" > "$LOG" 2>&1 < /dev/null
  rc=$?
  [ "$rc" = 0 ] && [ -s "$OUT" ] && break                      # it answered; keep this rung
  if grep -qiE 'not supported|unknown model|is not available|entitle' "$LOG"; then
    echo "unavailable: $m — trying the next rung"; continue
  fi
  echo "$m failed for a reason that is not availability — classify per Failure handling"; break
done
```

- `-C` replaces `cd "…" &&` (which the global shell rules prohibit); `--sandbox read-only` makes review-only enforced, not requested; `-o` writes only the final message (no event noise).
- **`-o` captures the final message and nothing else.** A quota, auth or availability failure never reaches it, so the file is absent or empty and says nothing about why. The `.log` beside it holds stderr, and it is what the coverage line quotes verbatim.
- **`codex exec` exits 0 on a quota failure.** Verified 2026-09-08: it printed
  `ERROR: You've hit your usage limit … try again at 4:06 AM` and still returned status 0, with
  no `-o` file written at all. **Exit status alone cannot tell a finished review from an
  exhausted account**, which is why the loop above requires a non-empty output file before it
  accepts a rung. A caller that trusts `$?` records an empty quota failure as a clean review.
- **Name every invocation uniquely: mode, pass, chunk, attempt and model.**
  `codex_<mode>_p<n>_c<chunk>_a<attempt>_<model>.txt`. Pass and model alone are not enough once
  a bundle is chunked or a rung is retried: chunk 2 overwrites chunk 1's findings, and a retry
  that produces nothing leaves the previous attempt's non-empty file standing, which then
  satisfies the success check and is reported as this attempt's answer. Reconcile the coverage
  line against the individual invocation files, not against one name per reviewer.
- **Number the output files by pass.** `phase-workflow` §3 step 7 cites these paths and byte counts as the evidence step 5 ran. One reused filename lets pass 1's output stand in for a pass 2 that never happened.

**Gemini (`agy -p`) is one-shot print mode — it cannot prompt for tool permissions.** Any prompt asking it to "review this repository" gets its tool calls auto-denied and fails. **Always inline the material in the prompt** and state: *"REVIEW ONLY: do not attempt to use any tools; answer purely from the text below."*

```bash
for m in $(gemini_ladder); do
  OUT="<scratchpad>/gemini_<mode>_p<n>_c<chunk>_a<attempt>_$m.txt"
  rm -f "$OUT" "${OUT%.txt}.err"   # never inherit a previous attempt's answer
  agy -p "$(cat "<scratchpad>/gemini_prompt_p<n>.txt")" --model "$m" --effort high \
      --print-timeout 25m > "$OUT" 2> "${OUT%.txt}.err"
  rc=$?
  [ "$rc" = 0 ] && [ -s "$OUT" ] && break
  if grep -qiE 'not supported|unknown model|is not available|entitle' \
       "${OUT%.txt}.err"; then
    echo "unavailable: $m — trying the next rung"; continue
  fi
  echo "$m failed for a reason that is not availability — classify per Failure handling"; break
done
```

- Build the prompt in a file (rubric + inlined material); the default 5m print-timeout is too short for big inputs — set ~15m.

**Classify availability only after a failed invocation, and keep stderr in its own file.**
Grepping a combined stream for `not supported` misreads a *successful* review whose findings
contain that phrase as an unavailable model — the good answer is discarded and the next rung
overwrites it. Check exit status and a non-empty answer first; only then read the error stream.

**Both:** run as background tasks; **capture to scratchpad files and Read them — never pipe through `tail`/`head`**, which truncates the top of the findings list (the highest-severity items).

## Shared rubric — both reviewers get this text VERBATIM

Prompt drift between the two reviewers corrupts the agree/disagree triage. Compose once, per mode:

1. **Repo-facts preamble (mandatory, ~5 lines):** what the project is, where tests live and how they run (e.g. "a pytest suite exists under `tests/` — read it before commenting on coverage"), which doc files exist, anything a cold reviewer predictably gets wrong. This prevents false findings (a reviewer confidently reporting "no tests" costs a wasted round trip).
2. **Already-tracked list (mandatory where the roadmap files exist):** every current entry in `docs/KNOWN_ISSUES.md`, `docs/ENHANCEMENTS.md` and `docs/OPEN_QUESTIONS.md` as **ID + title + rating + the entry's first sentence** — IDs, not full bodies, so the prompt stays small. Head it:

   > *Already tracked — do not re-report these. Do say so if you think one is mis-rated, filed in the wrong place, or has a cause different from the one recorded.*

   Without this the reviewers re-derive the whole backlog and the duplicates swamp the genuinely new findings. With it they stay on what the phase actually changed.

   **Send only the entries in scope for this phase.** Where a component is being rebuilt or is otherwise off the table, its entries are noise: the reviewers spend the pass re-deriving bugs in code nobody is going to touch, and the real findings compete with them. Name the excluded area in the preamble — *"`local-models` and `claude-toggle-backend` are being rebuilt; their open issues are out of scope, do not report on those two skills"* — rather than silently dropping the IDs, so a reviewer that finds something there can still say so in one line. Scope exclusions are per-review; nothing leaves the roadmap files.
3. **Focus list** by mode:
   - *plan*: gaps and missing steps, risks and failure modes, sequencing problems, simpler approaches missed, anything underspecified.
   - *phase / repo*: real bugs (report everything, do not self-filter for severity), silent failures, security issues, design choices that will not hold up, code duplication/consolidation opportunities, genuinely missing test coverage; plus doc-vs-code contradictions (README, ARCHITECTURE, CLAUDE.md, ROADMAP + KNOWN_ISSUES/ENHANCEMENTS/OPEN_QUESTIONS, CHANGELOG).
4. **Test-discrimination question** (*phase / repo* only): *"For each test in the material below, say whether it would still pass with the change it covers reverted. Name any test that asserts on a mock, on a constant, or on something true before the change."* This is a backstop — phase-workflow §3 step 3 already runs the check by **mutating** the named behaviour in place and re-running, which a reviewer cannot do. Ask anyway: a reviewer reading the assertion catches a different class than a mutation catches.
5. **Do-not-read instruction (mandatory, both reviewers):**

   > Do not open `.env`, `.env.*`, `*.pem`, `*.key`, `*.p12`, `*.pfx`, `credentials*`, `.netrc`, `.npmrc`, `id_rsa*`, `id_ed25519*`, or anything else shaped like a secret. If a finding depends on one, name the file and say what you would need rather than reading it.

6. **Don't explain the tools:**

   > This is a workflow document, not a git tutorial. Flag any passage that explains standard behaviour of `git`, `gh`, `pytest` or the shell rather than stating this project's policy. Genuine nuances that people get wrong are in scope; plain feature descriptions are not.

7. **Suggested remediation:** for each finding, add one or two sentences on how you would fix it. A sketch, not a patch — enough to show what change you have in mind.

8. **Output contract — always a list, even an empty one:**

   > Return a numbered list of findings, each with file/function references and a severity. Return the list **even when you found nothing**: emit the heading and the single line `No findings.` Never answer with prose instead of the list.

   The empty list is what separates a reviewer that ran and found nothing from one that never ran. **Absent output means the review did not happen — nothing else does.** A reviewer that returns `No findings.` has covered the material; a reviewer that returns nothing at all has not, and the coverage line must say which.

## Modes

**Every mode bundles through the same procedure below.** The exclusions, the symlink test, the binary test and the reconciled count are not phase-mode details — they are what stops source and secrets reaching a third party, and they apply whenever anything is inlined. Only the *selection* differs by mode.

**`plan <plan-file>`** — **name the plan file explicitly.** Fall back to the newest file in `~/.claude/plans/` only when the user gave no path and you have confirmed the newest file is this phase's plan; say which file you selected. Newest-in-directory silently reviews an unrelated plan when a plan was drafted for other work in between. Inline the plan text for BOTH reviewers (Codex may also explore the repo for context; Gemini gets text only). A plan can quote configuration and connection strings, so run it through the same exclusion check before inlining.

**`phase [base-branch]`** — detect base via `git remote show origin` if not given. Codex: repo-rooted with the rubric framed around the phase's changes. Gemini: the change bundle below, written to a scratchpad file and inlined into the prompt.

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
```

It writes `bundle.txt`, a NUL-delimited `withheld.txt`, `manifest.z`, `all.z`, `captured.z` and
`counts.txt` into the scratchpad, prints the reconciled count line, and **exits non-zero when the
bundle is incomplete** — an enumeration failure, or any file it could not read. A non-zero exit
means do not send.

`repo` and `plan` modes take the same first two arguments; `plan` takes the plan file as its
third and adds that file's directory to the allowed roots, because plans live in
`~/.claude/plans` by design.

**Why a script and not a fenced block.** This procedure decides what source leaves the machine,
and while it lived only in prose nothing ever ran it: external review pass 8 found four separate
defects in it at once, including a symlinked parent directory that `cat` would read straight
through. `tests/capture.bats` now exercises it against scratch repositories — a planted secret
outside the repo, a file named `-n`, a filename containing a newline, a tracked file deleted from
the worktree, an unreadable file. Change the procedure by changing the script and its tests, and
keep the rules below, which say why the script does what it does.

**Feed the loop from a file, not from a pipe.** On the right-hand side of a pipe the loop runs in
a subshell, so an `exit` inside it ends the subshell and the script carries on to send a bundle it
already knows is incomplete.

**Write the bundle outside the repo.** The untracked sweep lists whatever is untracked, so a
bundle written inside the working tree is listed, appended to itself, and grows until the disk
fills. The scratchpad is outside the repo; keep it that way.

**The tracked diff bypasses `capture()`, so filter tracked paths before building it.** Only
untracked files go through the function; everything in `git diff` reaches the bundle as a patch.
`--no-textconv --no-ext-diff` stops conversion *filters*, but a `diff` attribute set in
`.gitattributes` can still force a binary blob to be emitted as text, and a tracked path that
became a symlink is patched rather than withheld. Classify the changed paths first — same
symlink, binary and allowed-root tests — and exclude the disallowed ones from the diff pathspec,
naming them in the withheld list like any other.

**Turn conversion off for the tracked diff.** A repo that configures `textconv` or an external
diff driver — for PDFs, notebooks, or an encrypted-file helper — otherwise runs it during capture,
and the converted plaintext lands in the bundle for a file the exclusions were written to keep
out.

**Bundling sends your source to a third party.** Exclude credential-shaped files from **both** lists — a tracked `.env` reaches the reviewer through `git diff` just as easily as an untracked one. **Every pattern needs a leading `*` and `icase`**: without them a pathspec anchors at the repo root and is case-sensitive, so `config/credentials.json` and `Credentials.yaml` both pass.

**The exclusions protect Gemini only. Codex reads the repository itself**, so `--sandbox read-only` stops writes, not reads, and `permissions.filesystem.deny_read` is an enterprise-managed layer that `-c` does not enforce. The control that remains is the prompt, so the rubric carries an explicit instruction not to open credential-shaped files (below). It is a soft instruction and a determined agent, or a broad recursive grep, can defeat it — so a repo whose secrets must never leave the machine needs the secrets moved out of it, not a better prompt. Use `git` pathspecs rather than a `grep` filter: `grep` inside Claude Code is a shadowed ugrep with injected `--ignore-files`, `-I` and `--exclude-dir` defaults, so a filter written with it searches a different file set than you think.

**Skip symlinks explicitly; the pathspecs cannot.** `git ls-files` matches an untracked symlink by *its own name*, so an innocuous `notes.txt` pointing at `~/.ssh/id_rsa`, or at a `.env` outside the repo, passes every exclusion — and `cat` then reads the target. Test `-L` **before** `-f`, because `-f` follows the link and reports the target's type.

**Check each step.** A failed `git diff` leaves a truncated bundle that looks exactly like a small phase, and a failed `cat` inside the loop disappears the moment a later iteration succeeds.

Skip binaries the same way, with no grep involved:

```bash
perl -e 'exit(-B $ARGV[0] ? 0 : 1)' "$f" && continue   # skip binary files
```

Do **not** use `git add -N` to sweep untracked files into the diff. It mutates the index, and phase-workflow's gate checks that the tree is clean.

**Reconcile the bundle, and say the count out loud.** This failure is silent — a short bundle looks exactly like a small phase — so a better command is not the fix; a stated count is:

```bash
# Build ONE NUL-delimited manifest per mode, then count off it. Never mix a
# newline count with a NUL count, and never compare a pre-exclusion total with a
# post-exclusion selection.
#   phase mode:
{ git diff -z --name-only "<base>"...HEAD; git ls-files --others --exclude-standard -z; } \
  > "<scratchpad>/all.z"
#   repo mode:
git ls-files -z > "<scratchpad>/all.z"

# manifest.z is the same enumeration with the exclusion pathspecs applied. It is what
# the capture loop reads, so the counts describe the bundle that was actually built.
#   phase mode:
{ git diff -z --name-only "<base>"...HEAD -- . "${EXCL[@]}"
  git ls-files --others --exclude-standard -z -- . "${EXCL[@]}"; } > "<scratchpad>/manifest.z" \
  || { echo "MANIFEST FAILED — do not send this bundle"; exit 1; }
#   repo mode:
git ls-files -z -- . "${EXCL[@]}" > "<scratchpad>/manifest.z" \
  || { echo "MANIFEST FAILED — do not send this bundle"; exit 1; }

nul() { tr -cd '\0' < "$1" | wc -c | tr -d ' '; }   # every list here is NUL-delimited
TOTAL="$(nul "<scratchpad>/all.z")"                 # everything in scope, before exclusions
SELECTED="$(nul "<scratchpad>/manifest.z")"         # what the exclusions left
WITHHELD_N="$(nul "$WITHHELD")"                     # symlinks, binaries, escapes, absences
CAPTURED=$(( SELECTED - WITHHELD_N ))               # what actually reached the bundle
echo "bundle contains $CAPTURED of $TOTAL files; $WITHHELD_N withheld, $(( TOTAL - SELECTED )) excluded"
[ "$CAPTURED" -ge 0 ] || { echo "COUNTS DO NOT RECONCILE — do not send this bundle"; exit 1; }
```

**All three counts come from the same NUL-delimited manifest.** A filename containing a newline
inflates a `wc -l` count, and counting the total before exclusions against a selection made
after them produces a difference that looks like data loss. `INCLUDED + WITHHELD_N` need not
equal `TOTAL` — the excluded credential-shaped paths are the remainder, and the report names
them.

**Use the count that matches the mode.** `git status --porcelain` counts *changed* files, so on
the clean committed tree a phase review is supposed to run against it returns zero while the
bundle is large — the check can never fire in the mode it was written for.

**Phase capture covers commits plus untracked files, not staged or unstaged edits to tracked
files.** At a proper review point the tree is clean and that is complete. If a review is
requested mid-task, say so and either commit first or state in the report that working-tree
edits to tracked files were not captured — never let the diff silently stand in for them.

Once exclusions are applied the bundle can no longer equal that count, so report both and name what was withheld:

> *This bundle contains 23 of 25 changed files. Withheld: `.env.staging`, `fixtures/sample.db` (credential-shaped or binary).*

A reviewer told what was withheld never reports it as missing. `-z` in the bundle loop protects the *loop*; it does nothing for the count, which is why the count command above is NUL-delimited too. (A rename still emits two paths for one entry — rare, and worth knowing before trusting the number blindly.)

Put that count in the prompt (*"this bundle contains all N changed files"*) and in the report's coverage line. Codex reads the working tree and sees untracked files on its own, but give it the same manifest so it is not inferring the scope of the phase.

**`repo`** — no in-flight branch; review current state (workflow adoption, periodic health check). Codex: repo-rooted as above. Gemini: one bundle of the source, inlined.

**Build the `repo` bundle from `git ls-files`, never from a filesystem walk.** A walk that
follows symlinks goes straight out through `node_modules` and `.venv` into the environment root
and sweeps in every ignored file. `capture.sh repo` does this correctly:

```bash
bash "$CLAUDE_PLUGIN_ROOT/skills/external-review/capture.sh" repo "<scratchpad>"
```

Same outputs, same exclusions, same symlink, binary and read-failure handling as `phase`. One
capture procedure serves every mode; none rolls its own.

**Chunk when the bundle is too large, and measure before sending. The binding limit is wall-clock, not input size.** Measured on 2026-09-08: a 125,000-character prompt answered comfortably, a 198,000-character one hit `Error: timeout waiting for response` at `--print-timeout 15m` and produced nothing. Keep a chunk near **120,000 characters** and raise the timeout to 25m; a bigger single call does not fail with a truncated answer, it fails with no answer at all after burning the whole timeout.

```bash
wc -c "$BUNDLE"    # split by directory or concern if this is over ~120000
```

**Split on a seam, and repeat the shared context in every chunk.** Cross-file contradiction is the main thing a review of prose is for, and chunking is exactly what hides it — so the files every other file must agree with (the repo `CLAUDE.md`, `README.md`, `docs/ARCHITECTURE.md`) go into *each* chunk, and each prompt says which chunk it is and that the others cover the rest, so nothing is reported missing merely because it is elsewhere.

Never silently review a subset. Say in the report exactly what each call covered, and reconcile the chunks against the file count the same way a single bundle is reconciled.

## Failure handling — classify, don't guess

On empty output or non-zero exit, run a tiny probe before reporting:

```bash
codex exec -C "<repo-root>" --sandbox read-only -m <same model as the real run> \
  "Do not open .env, .env.*, *.pem, *.key, credentials*, .netrc, .npmrc, id_rsa*, id_ed25519*, or anything else shaped like a secret. List the three most obvious code-quality issues in this repository. Be brief."   # or the agy equivalent with inline text
```

**Availability is per-model; quota is account-wide.** Probe on the SAME model as the real run,
because that is what diagnoses an *availability* failure. A *quota* failure needs no probe at
all — the error text already says so, and walking the ladder just spends the window on three
identical refusals. Measured 2026-09-08: Gemini returned the same account-wide quota error with
the same countdown on both its top rung and its flash rung, and Codex, Gemini and Claude all
meter usage per account rather than per model. **The probe carries the do-not-read instruction too.** It is a real agentic run over the repo, and a diagnostic is not an exemption.

- Probe succeeds → the real prompt was the problem (too large, malformed) — fix and re-run.
- Probe fails → read the error: quota/usage → **no output from that reviewer, and not a skip** (the CLI is installed and it ran); report "Codex/Gemini out of usage" with the error verbatim, per *A skip and partial coverage are different things* above; `model ... is not supported` → an unavailable model tier, not a quota problem (see the pins above); auth → say re-login is needed (`codex login` / `agy` interactive); tool-permission denial (Gemini) → the prompt asked it to use tools — inline the material instead.
- `command not found` → the CLI is not installed; that is a preflight case, not a runtime failure. Don't probe — report the skip per *Preflight* above.
- Never silently drop a reviewer; the report names which ran, which didn't, and why.

## Triage — verify before presenting

1. **Verify each finding against the repo** (read the cited file/function) before it reaches the user. A confident false finding routed into the roadmap files is worse than no review. Verification decides the **Verdict**, never whether the row appears.
2. **Deduplicate across reviewers.** One row per distinct finding. Two reviewers reporting the same thing is signal, not noise — merge them into one row listing **both model ids**, per the Model column rule below. Never `Both`: a row can outlive this table by being filed as a roadmap entry, and `Both` resolves only against a coverage line that is chat-only.
3. **Give every finding a disposition** and present them in the findings table below. *plan* mode: the table goes in the plan. *phase / repo* mode: the table goes in the hand-off at the gate.

## The findings table (canonical format — both modes)

**One table, both reviewers.** Each reviewer returns its own list; you merge them into the single table below, dedupe across them, and present that. Never hand the user two tables to reconcile.

Every finding the reviewers returned gets a row, **including rejected and duplicate ones** — the user has to see what was thrown away. Never summarize the list down.

**A reviewer that returned `No findings.` is covered and contributes no rows.** Say so in the coverage line (`Gemini gemini-3.1-pro-high 0`). That is a clean result, not partial coverage. A reviewer that returned *nothing* is the partial-coverage case instead — name it and give the error verbatim. When both reviewers return `No findings.`, present the empty table under its coverage line rather than omitting the table: an absent table has to keep meaning "no review ran".

Open with a coverage line so the count is unambiguous:

```text
Codex gpt-5.6-sol 7 · Gemini gemini-3.1-pro-high 4 · 3 overlapping → 8 unique findings
```

Name the **exact model that ran**, not the CLI — the ladder is discovered at run time and downshifts on availability, so "Codex" alone hides whether the findings came from the top tier or a lighter rung. If a downshift happened, say so here too: `Codex gpt-5.6-terra 5 (gpt-5.6-sol unavailable) · …`.

If neither CLI is installed, print the skip line in its place — `External review skipped — neither codex nor agy is installed` — so a missing table is never mistaken for a clean review.

**Format: a compact table, then keyed notes.** Commentary lives below the table, keyed by finding ID.

| # | Finding | Files | Model | Likelihood | Severity | Verdict | Disposition |
| --- | --------- | ------- | ------- | ---------- | ---------- | --------- | ------------- |
| F-01 | No rollback if the migration half-applies | `migrate.py:88-140` | gpt-5.6-sol | Rare | Critical | Confirmed | Incorporated — new step 6 |
| F-02 | Token refresh races on concurrent runs | `auth/token.py`, `worker.py:41` | gpt-5.6-sol, gemini-3.1-pro-high | Likely | Medium | Confirmed | Filed KI-08 |
| F-03 | Add a caching layer for lookups | `lookup.py` | gemini-3.1-pro-high | Almost always | Medium | Rejected | Not incorporated |

*The dispositions above are **plan** mode; phase and repo mode use the five buckets further down. The columns are the same in every mode.*

**F-01** — *When it fires:* `the condition that has to hold` *What happens:* `the observable
consequence, concretely` *Commentary:* `what you found verifying it, and why the disposition
follows`

**Every keyed note carries those first two lines.** They are the same pair that makes a
`KNOWN_ISSUES` entry assessable — *What happens* and *Example scenario* — and a findings row
without them asks the reader to take the severity on trust. They also travel: a row filed as
`KI-nn` inherits both, so the entry starts with the two things a reader needs first.
**F-02** — *Explanation:* … *Commentary:* …

Column rules:

- **#** — `F-01`, `F-02`, … Stable within this review only; they exist so the user can say "also fix F-03" without quoting titles.
- **Finding** — one short line. Not a summary of the explanation.
- **Files** — where the finding lives, as `path` or `path:start-end`, comma-separated when it spans more than one. **Take the reviewer's own reference and verify it against the repo during triage** — a wrong path is itself a signal the finding was not verified. Two or three paths is the cap; a finding touching more than that is really a finding about the design, so name the area (`skills/*/SKILL.md — every skill`) rather than listing every file. Use `—` only where the finding genuinely has no location, such as a missing file or an absent test. This column is what makes a filed `KI-nn`/`ENH-nn` entry actionable from cold, since the roadmap entry inherits it.
- **Model** — the **model id that produced the finding**, not the CLI that ran it: `gpt-5.6-sol`, `gemini-3.1-pro-high`. Which rung of the ladder actually answered changes how much weight a finding deserves, and that is per-run state the CLI name cannot carry. When both reviewers found the same thing, **list both ids** — `gpt-5.6-sol, gemini-3.1-pro-high` — never `Both`: a row can outlive this table by being filed as a `KI-nn`/`ENH-nn`/`UNK-nn` entry, and `Both` resolves only against a coverage line that is chat-only. Two ids in one cell is also the agreement signal, stated so it survives the move. Never write `Codex` or `Gemini` alone in this column.
- **Likelihood** — `Rare` | `Likely` | `Almost always`. **How often a user following the
  documented workflow actually hits the harm**, not how often the code path runs. The two come
  apart: a bad count computed on every run is `Rare` if it only misleads when something else has
  already failed. **A defect that is always present but harmful only in combination is `Rare`.**
  Judge it against the workflow as written — if a step tells the user to do the thing that
  triggers it, that is `Almost always` for everyone who follows the step, however unusual it
  looks. This is the reviewer's estimate where they gave one; where they did not, it is yours,
  and the commentary says so.
- **Severity** — **the consequence if it does fire, and nothing about how often.** Take the
  reviewer's own rating verbatim, attributed by **model id** and never by CLI name:
  `High (gpt-5.6-sol)`. **Two columns, because one number cannot carry both.** A rare defect
  that exfiltrates source is `Rare · Critical`; friction on every run is
  `Almost always · Low`. Both get fixed, for different reasons, and a single rating hides
  which reason. Where a reviewer's rating obviously folded in likelihood, keep their word in
  the cell and say so in the commentary rather than silently re-rating it. Never renormalize it: the same pass decides disposition, so quietly downgrading an inconvenient Critical would hide the decision. **When the two reviewers disagree, record both and order by the higher** — `High (gpt-5.6-sol) / Medium (gemini-3.1-pro-high)`. If you disagree with a rating yourself, say so in the commentary, where the user can see the disagreement.
- **Verdict** — `Confirmed` | `Partly` | `Rejected`, from step 1. Separate from Disposition on purpose: *valid but deferred* and *invalid so dropped* are different states, and one column cannot carry both.
- **Disposition** — what actually happened; vocabulary differs by mode (below).

**Order: descending criticality**, mapping the reviewers' scales onto the KNOWN_ISSUES severity scale (Critical / High / Medium / Low). Tiebreak Confirmed above Rejected, so the actionable rows sit at the top.

### Disposition vocabulary — *plan* mode

`Incorporated — <where>` | `Already covered — <where>` | `Filed KI-nn / ENH-nn / UNK-nn` | `Not incorporated` (Verdict `Rejected`).

A valid finding that is out of scope for this phase is **filed, not dropped** — it gets a `KI-nn`, `ENH-nn` or `UNK-nn` entry with its ROADMAP pointer row, the same as at phase end. **A reviewer reading a plan often finds a real defect in the existing code; that is a `KI-nn`.** Forcing it into `UNK-nn` because plan mode once listed only two buckets files defined wrong behaviour as an open question, which the `OPEN_QUESTIONS` template forbids. Present the whole table in one pass regardless of severity: a confirmed Critical does not block the plan reaching the user, who is in plan mode and can send it back.

### Disposition vocabulary — *phase / repo* mode

`Fixed in phase` | `Filed KI-nn` | `Filed ENH-nn` | `Filed UNK-nn` | `Rejected`.

Exactly five buckets, and **every row lands in one** — that is what guarantees nothing is quietly lost. Regressions this phase introduced are fixed before hand-off; everything else that survives verification becomes a rated entry in `docs/KNOWN_ISSUES.md`, `docs/ENHANCEMENTS.md`, or `docs/OPEN_QUESTIONS.md`, each with its ROADMAP pointer row. `Rejected` is a real disposition, not a gap: a finding that fails verification produces no artifact, and forcing it into the roadmap would pollute it.

The table itself is **chat-only** — do not write a per-phase review file. It presents state that already lives elsewhere: fixes are in the diff, deferrals are roadmap entries. A `docs/reviews/phase-N.md` would be a backward-looking doc outside CHANGELOG, breaking the tense split. Instead give each filed entry a provenance line carrying the same model ids as the Model column — `Source: gpt-5.6-sol, gemini-3.1-pro-high — phase review, phase 4` — so the attribution survives the move into a durable doc without a second store.

## Follow-up passes — *phase* mode only

**This section is canonical for the review loop.** `phase-workflow` §3 step 5 states only what is phase-specific and delegates the rest here.

A first review changes the code, and those changes have been reviewed by no one — so a phase review is a loop, not one shot.

**There is no pass ceiling.** How many passes a phase needs depends on what the findings are and which way the count is moving, and neither is knowable at the start. Pass 1 is full scope; every later pass narrows. `plan` and `repo` modes stay single-pass: a plan already loops through the user's approval, and a `repo` review seeds the backlog rather than gating a hand-off.

### The loop

1. **Pass 1** — full scope, per *Modes* above.
2. **Present the findings table and STOP.** Blocking, every time. The user decides what gets fixed, what gets filed, and what gets rejected before any code is touched. A disposition you assigned yourself is a proposal until they say so.
3. **Fix and file** what they approved.
4. **Pass 2** — narrow (below). Then present and stop again, and repeat on the same terms.

### Ending the loop is the user's call, every pass

Close every pass with a short assessment under the findings table, then stop:

- **The trend** — the finding count for each pass so far, as a series.
- **What the new findings are about** — fresh defects in untouched code, defects in the previous pass's own fixes, or documentation drift. A count that holds steady while the *kind* changes is a different situation from one that holds steady on the same kind.
- **Your recommendation** — another pass, or land what is here and file the rest, with the reason.

Recommend stopping when a pass returns no confirmed finding needing a code change, or when what remains is better filed than fixed. **The decision is the user's.** Never end the loop on your own judgement, and never open another pass without asking.

Whatever is still open when the loop ends is *filed* — `KI-nn`, `ENH-nn` or `UNK-nn` with its ROADMAP pointer row — never fixed-and-unreviewed. Say in the hand-off what remains open.

### What "narrow" means

Scope each follow-up prompt to exactly three things:

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

Finding IDs run in **one sequence for the whole phase** — pass 1 ends at `F-08`, pass 2 opens at `F-09`. A row can outlive the table by being filed as a roadmap entry, and per-pass numbering would make `F-01` ambiguous the moment it moves. Each pass presents its own table, headed with the pass number and its own coverage line.

## Hard rules

- **The reviewers never write.** Codex is held to that by `--sandbox read-only`, not by prompt wording; Gemini gets text and no tools. Neither is restricted from *reading* — see the bundle section — so "read-only" here means it cannot change the repo, never that it cannot see a file.
- **Who acts on a finding differs by mode, and both are review-only in the sense that matters — no fix is applied straight from review output.**
  - *plan*: the agent revises the plan itself, then presents the revision and the findings table together. This is deliberate: phase-workflow §1 says the plan the user sees is the revised one, so waiting for a disposition first would defeat the checkpoint.
  - *phase / repo*: the user dispositions every finding **before any code is touched**. A disposition you assigned yourself is a proposal until they say so.
- **The pause after a findings table is blocking.** Present, stop, wait. Not "present and start fixing while they read".
- **Never widen a follow-up pass back to full scope.** If pass 2 looks thin, that is the loop working, not a reason to re-review the phase.
- **Never report a bundle without its reconciled file count.** An unstated count is how a reviewer ends up reviewing half a phase and nobody notices.
- The Codex stop-time review gate (`/codex:setup`) stays **off** — it reviews every turn and burns quota; these checkpoints are the intended cadence.
- **Triage subagents gather evidence, never verdicts.** A subagent returns the quoted file lines or command output a finding turns on; the judgement stays with the main agent. That is the narrow exception to the global ban on using subagents to verify correctness — it parallelizes the lookup without asking a copy of yourself whether you were right.
