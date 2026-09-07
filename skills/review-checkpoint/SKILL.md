---
name: review-checkpoint
description: External review from non-Claude models (OpenAI Codex, Google Gemini) at the phase workflow's checkpoints — `plan` on a drafted plan, `phase` on a branch before hand-off, `repo` on current state. Reviewers never apply fixes; every finding is verified and given a disposition in one table. Use when an outside opinion on a plan, diff or codebase is wanted.
---

# review-checkpoint

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

Everything else is **partial coverage**: the step ran, and one reviewer produced nothing. A CLI that is installed and then fails on **quota**, **auth**, **timeout** or **sandbox denial** did not cause a skip — it ran and came back empty. Say so in the coverage line, name the reviewer, and give the reason verbatim:

> *Coverage: Codex `gpt-5.6-sol` 9 findings. Gemini installed but returned `Individual quota reached` (resets 23h26m) — no findings this pass. Single-reviewer coverage, not a clean review.*

Never record partial coverage as "both reviewers clean". A single-reviewer report has no agree/disagree axis, so its findings carry less weight, and the hand-off must say which reviewer is missing and why.

Offer the install commands; never install a CLI or change the user's login state yourself.

## The two reviewers are NOT interchangeable — different invocation contracts

**Review models — always try the strongest tier first, downshift only on rejection.** Model entitlements differ per machine and per signed-in account (a work account may have tiers a personal one doesn't), so never hard-code the fallback as the default. Ladders, strongest first:

| Reviewer | Try in this order |
| --- | --- |
| Codex (`-m`) | `gpt-6-astra` → `gpt-5.6-sol` → `gpt-5.6-terra` → unflagged default |
| Gemini (`--model`) | `gemini-3.1-pro-high` → `gemini-3.6-flash-high` → unflagged default |

**Set the reasoning effort explicitly; `-m` alone does not.** Every model on both ladders supports low/medium/high/xhigh/max, and `gpt-6-astra` defaults to **low** — so naming only the slug gets the weakest setting of the strongest model, and the run reads as stronger than it was. Pass `-c model_reasoning_effort="high"` for a review, and record the effort beside the slug: a `low` run and a `high` run from one slug deserve different weight and the slug alone cannot tell them apart.

Downshift rule: run with the top model; **only** if it fails with an availability error (`model ... is not supported`, unknown/retired model, entitlement error) drop to the next rung and retry. Quota, auth, and timeout errors are NOT downshift triggers — handle them per *Failure handling* below. **Record which model actually ran** — it goes in the findings table's coverage line and its Model column (below), which is the one place that attribution is carried. Note a downshift plainly there (`gpt-5.6-sol unavailable on this account — reviewed with gpt-5.6-terra`), since a lighter model changes how much weight the findings deserve.

- **Sol availability is a PLAN-TIER issue, not an auth-method one.** Sol is available to paid ChatGPT subscriptions (Plus/Pro/Business/Enterprise) through the Codex CLI as well as via API key; the **free** tier does not include it. The CLI's error is misleading — it says *"not supported when using Codex with a ChatGPT account"* when the real cause is the account's plan. Diagnose with `codex login status` plus the `chatgpt_plan_type` claim in `~/.codex/auth.json` (read that key only — the file holds tokens). If it reads `free`, tell the user Sol needs a paid account and that `codex logout && codex login` switches accounts — noting that Codex auth is global per machine, so a work account would then cover personal projects too. `gpt-5.6-luna` is the lightest sibling — never use it for reviews.
- **Never pick `agy`'s `claude-*` models** (it offers Sonnet/Opus) — the entire point of this checkpoint is a non-Claude second opinion.
- If every rung is rejected, the IDs likely retired: run `agy models` / check the [Codex models list](https://developers.openai.com/codex/models), use the current equivalent, and tell the user the ladder needs updating.

**Codex is agentic** — it explores the repo itself. Point it at the repo root and pin it read-only at the tool level (never rely on prompt wording alone):

```bash
codex exec -C "<repo-root>" --sandbox read-only \
  -m gpt-6-astra -c model_reasoning_effort="high" \
  -o "<scratchpad>/codex_<mode>_p<n>.txt" "<prompt>" \
  > "<scratchpad>/codex_<mode>_p<n>.log" 2>&1        # downshift per the ladder if unavailable
```

- `-C` replaces `cd "…" &&` (which the global shell rules prohibit); `--sandbox read-only` makes review-only enforced, not requested; `-o` writes only the final message (no event noise).
- **`-o` captures the final message and nothing else.** A quota, auth or availability failure never reaches it, so the file is absent or empty and says nothing about why. The `.log` beside it holds stderr, and it is what the coverage line quotes verbatim.
- **Number the output files by pass.** `phase-workflow` §3 step 7 cites these paths and byte counts as the evidence step 5 ran. One reused filename lets pass 1's output stand in for a pass 2 that never happened.

**Gemini (`agy -p`) is one-shot print mode — it cannot prompt for tool permissions.** Any prompt asking it to "review this repository" gets its tool calls auto-denied and fails. **Always inline the material in the prompt** and state: *"REVIEW ONLY: do not attempt to use any tools; answer purely from the text below."*

```bash
agy -p "$(cat "<scratchpad>/gemini_prompt_p<n>.txt")" --model gemini-3.1-pro-high --effort high --print-timeout 15m > "<scratchpad>/gemini_<mode>_p<n>.txt" 2>&1
```

- Build the prompt in a file (rubric + inlined material); the default 5m print-timeout is too short for big inputs — set ~15m.

**Both:** run as background tasks; **capture to scratchpad files and Read them — never pipe through `tail`/`head`**, which truncates the top of the findings list (the highest-severity items).

## Shared rubric — both reviewers get this text VERBATIM

Prompt drift between the two reviewers corrupts the agree/disagree triage. Compose once, per mode:

1. **Repo-facts preamble (mandatory, ~5 lines):** what the project is, where tests live and how they run (e.g. "a pytest suite exists under `tests/` — read it before commenting on coverage"), which doc files exist, anything a cold reviewer predictably gets wrong. This prevents false findings (a reviewer confidently reporting "no tests" costs a wasted round trip).
2. **Already-tracked list (mandatory where the roadmap files exist):** every current entry in `docs/KNOWN_ISSUES.md`, `docs/ENHANCEMENTS.md` and `docs/OPEN_QUESTIONS.md` as **ID + title + rating + the entry's first sentence** — IDs, not full bodies, so the prompt stays small. Head it:

   > *Already tracked — do not re-report these. Do say so if you think one is mis-rated, filed in the wrong place, or has a cause different from the one recorded.*

   Without this the reviewers re-derive the whole backlog and the duplicates swamp the genuinely new findings. With it they stay on what the phase actually changed.
3. **Focus list** by mode:
   - *plan*: gaps and missing steps, risks and failure modes, sequencing problems, simpler approaches missed, anything underspecified.
   - *phase / repo*: real bugs (report everything, do not self-filter for severity), silent failures, security issues, design choices that will not hold up, code duplication/consolidation opportunities, genuinely missing test coverage; plus doc-vs-code contradictions (README, ARCHITECTURE, CLAUDE.md, ROADMAP + KNOWN_ISSUES/ENHANCEMENTS/OPEN_QUESTIONS, CHANGELOG).
4. **Test-discrimination question** (*phase / repo* only): *"For each test in the material below, say whether it would still pass with the change it covers reverted. Name any test that asserts on a mock, on a constant, or on something true before the change."* This is a backstop — phase-workflow §3 step 3 already runs the check by actually reverting and re-running, which a reviewer cannot do. Ask anyway: a reviewer reading the assertion catches a different class than a revert catches.
5. **Output contract:** "Return a numbered list of findings with file/function references and a severity for each."

## Modes

**`plan <plan-file>`** — default: newest file in `~/.claude/plans/`. Inline the plan text for BOTH reviewers (Codex may also explore the repo for context; Gemini gets text only).

**`phase [base-branch]`** — detect base via `git remote show origin` if not given. Codex: repo-rooted with the rubric framed around the phase's changes. Gemini: the change bundle below, written to a scratchpad file and inlined into the prompt.

### Capturing the phase's changes — `git diff <base>...HEAD` is WRONG here

Two separate defects, and each one silently hands a reviewer an incomplete picture:

- **`base...HEAD` shows only committed work.** At the phase gate the work is *uncommitted* by design (phase-workflow §3 step 7), so that command can legitimately return nothing at all.
- **No `git diff` ever contains untracked files.** A phase that adds a new module gives the reviewer a diff full of calls into a file it cannot see. It then reports the file as missing — a real review round wasted on an artifact of the capture.

Build the bundle like this instead:

```bash
BUNDLE="<scratchpad>/bundle.txt";   : > "$BUNDLE"
WITHHELD="<scratchpad>/withheld.txt"; : > "$WITHHELD"

EXCL=(':(exclude,icase)*.env' ':(exclude,icase)*.env.*' ':(exclude,icase)*.pem'
      ':(exclude,icase)*.key' ':(exclude,icase)*.p12' ':(exclude,icase)*.pfx'
      ':(exclude,icase)*.crt' ':(exclude,icase)*id_rsa*' ':(exclude,icase)*id_ed25519*'
      ':(exclude,icase)*credentials*' ':(exclude,icase)*.netrc' ':(exclude,icase)*.npmrc'
      ':(exclude,icase)*.sqlite' ':(exclude,icase)*.sqlite3')

# tracked: committed + staged + unstaged
git diff "<base>" -- . "${EXCL[@]}" > "$BUNDLE" || { echo "DIFF FAILED — bundle incomplete"; exit 1; }

# untracked: each one appended IN FULL, behind a path header
git ls-files --others --exclude-standard -z -- . "${EXCL[@]}" |
while IFS= read -r -d '' f; do
  [ -L "$f" ] && { printf '%s\t(symlink)\n' "$f" >> "$WITHHELD"; continue; }
  [ -f "$f" ] || continue
  perl -e 'exit(-B $ARGV[0] ? 0 : 1)' "$f" && { printf '%s\t(binary)\n' "$f" >> "$WITHHELD"; continue; }
  printf '\n===== UNTRACKED FILE: %s =====\n' "$f" >> "$BUNDLE"
  cat "$f" >> "$BUNDLE" || { echo "READ FAILED: $f"; exit 1; }
done
```

**`git ls-files` prints paths, so something has to do the appending.** Show the loop, not the
command plus a comment describing what the comment wishes happened — an agent that runs exactly
what is written otherwise sends a bundle of filenames and reports that it sent the files.

**Bundling sends your source to a third party.** Exclude credential-shaped files from **both** lists — a tracked `.env` reaches the reviewer through `git diff` just as easily as an untracked one. **Every pattern needs a leading `*` and `icase`**: without them a pathspec anchors at the repo root and is case-sensitive, so `config/credentials.json` and `Credentials.yaml` both pass.

**The exclusions protect Gemini only. Codex reads the repository itself.** `--sandbox read-only` stops writes, not reads: an excluded `.env` is still readable, and reading it into a tool response has already sent it. There is no user-level way to prevent this — `permissions.filesystem.deny_read` is an enterprise-managed layer and is not enforced from `-c`. Treat pointing Codex at a repo as granting it read access to everything in that repo, and do not point it at one holding secrets you would not paste into a chat. Use `git` pathspecs rather than a `grep` filter: `grep` inside Claude Code is a shadowed ugrep with injected `--ignore-files`, `-I` and `--exclude-dir` defaults, so a filter written with it searches a different file set than you think.

**Skip symlinks explicitly; the pathspecs cannot.** `git ls-files` matches an untracked symlink by *its own name*, so an innocuous `notes.txt` pointing at `~/.ssh/id_rsa`, or at a `.env` outside the repo, passes every exclusion — and `cat` then reads the target. Test `-L` **before** `-f`, because `-f` follows the link and reports the target's type.

**Check each step.** A failed `git diff` leaves a truncated bundle that looks exactly like a small phase, and a failed `cat` inside the loop disappears the moment a later iteration succeeds.

Skip binaries the same way, with no grep involved:

```bash
perl -e 'exit(-B $ARGV[0] ? 0 : 1)' "$f" && continue   # skip binary files
```

Do **not** use `git add -N` to sweep untracked files into the diff. It mutates the index, and phase-workflow's gate checks `git status` to prove the work is uncommitted.

**Reconcile the bundle, and say the count out loud.** This failure is silent — a short bundle looks exactly like a small phase — so a better command is not the fix; a stated count is:

```bash
git status --porcelain -uall -z | tr -cd '\0' | wc -c   # -uall expands untracked directories; -z survives newlines in paths
```

Once exclusions are applied the bundle can no longer equal that count, so report both and name what was withheld:

> *This bundle contains 23 of 25 changed files. Withheld: `.env.staging`, `fixtures/sample.db` (credential-shaped or binary).*

A reviewer told what was withheld never reports it as missing. `-z` in the bundle loop protects the *loop*; it does nothing for the count, which is why the count command above is NUL-delimited too. (A rename still emits two paths for one entry — rare, and worth knowing before trusting the number blindly.)

Put that count in the prompt (*"this bundle contains all N changed files"*) and in the report's coverage line. Codex reads the working tree and sees untracked files on its own, but give it the same manifest so it is not inferring the scope of the phase.

**`repo`** — no in-flight branch; review current state (workflow adoption, periodic health check). Codex: repo-rooted as above. Gemini: concatenate the source into one bundle (`allsrc.txt`-style) and inline it. **If the bundle exceeds the model's input limit, chunk by package/directory and run one call per chunk — never silently review a subset; say in the report exactly what each call covered.**

## Failure handling — classify, don't guess

On empty output or non-zero exit, run a tiny probe before reporting:

```bash
codex exec -C "<repo-root>" --sandbox read-only -m <same model as the real run> "List the three most obvious code-quality issues in this repository. Be brief."   # or the agy equivalent with inline text
```

Use the SAME model as the real run — quota and availability limits are per-model, so a probe on a different rung misdiagnoses the failure.

- Probe succeeds → the real prompt was the problem (too large, malformed) — fix and re-run.
- Probe fails → read the error: quota/usage → **partial coverage, not a skip** (the CLI is installed and it ran); report "Codex/Gemini out of usage" with the error verbatim, per *A skip and partial coverage are different things* above; `model ... is not supported` → an unavailable model tier, not a quota problem (see the pins above); auth → say re-login is needed (`codex login` / `agy` interactive); tool-permission denial (Gemini) → the prompt asked it to use tools — inline the material instead.
- `command not found` → the CLI is not installed; that is a preflight case, not a runtime failure. Don't probe — report the skip per *Preflight* above.
- Never silently drop a reviewer; the report names which ran, which didn't, and why.

## Triage — verify before presenting

1. **Verify each finding against the repo** (read the cited file/function) before it reaches the user. A confident false finding routed into the roadmap files is worse than no review. Verification decides the **Verdict**, never whether the row appears.
2. **Deduplicate across reviewers.** One row per distinct finding. Two reviewers reporting the same thing is signal, not noise — merge them into one row listing **both model ids**, per the Model column rule below. Never `Both`: a row can outlive this table by being filed as a roadmap entry, and `Both` resolves only against a coverage line that is chat-only.
3. **Give every finding a disposition** and present them in the findings table below. *plan* mode: the table goes in the plan. *phase / repo* mode: the table goes in the hand-off at the gate.

## The findings table (canonical format — both modes)

Every finding the reviewers returned gets a row, **including rejected and duplicate ones** — the user has to see what was thrown away. Never summarize the list down.

Open with a coverage line so the count is unambiguous:

```text
Codex gpt-5.6-sol 7 · Gemini gemini-3.1-pro-high 4 · 3 overlapping → 8 unique findings
```

Name the **exact model that ran**, not the CLI — the ladder in *Review models* downshifts on availability, so "Codex" alone hides whether the findings came from the top tier or a lighter rung. If a downshift happened, say so here too: `Codex gpt-5.6-terra 5 (gpt-5.6-sol unavailable) · …`.

If neither CLI is installed, print the skip line in its place — `External review skipped — neither codex nor agy is installed` — so a missing table is never mistaken for a clean review.

**Format: a compact table, then keyed notes.** Commentary lives below the table, keyed by finding ID.

| # | Finding | Files | Model | Severity | Verdict | Disposition |
| --- | --------- | ------- | ------- | ---------- | --------- | ------------- |
| F-01 | No rollback if the migration half-applies | `migrate.py:88-140` | gpt-5.6-sol | High | Confirmed | Incorporated — new step 6 |
| F-02 | Token refresh races on concurrent runs | `auth/token.py`, `worker.py:41` | gpt-5.6-sol, gemini-3.1-pro-high | Medium | Confirmed | Filed UNK-08 |
| F-03 | Add a caching layer for lookups | `lookup.py` | gemini-3.1-pro-high | Medium | Rejected | Not incorporated |

*The dispositions above are **plan** mode; phase and repo mode use the five buckets further down. The columns are the same in every mode.*

**F-01** — *Explanation:* <what the reviewer claims, in a sentence or two> *Commentary:* <what you found verifying it, and why the disposition follows>
**F-02** — *Explanation:* … *Commentary:* …

Column rules:

- **#** — `F-01`, `F-02`, … Stable within this review only; they exist so the user can say "also fix F-03" without quoting titles.
- **Finding** — one short line. Not a summary of the explanation.
- **Files** — where the finding lives, as `path` or `path:start-end`, comma-separated when it spans more than one. **Take the reviewer's own reference and verify it against the repo during triage** — a wrong path is itself a signal the finding was not verified. Two or three paths is the cap; a finding touching more than that is really a finding about the design, so name the area (`skills/*/SKILL.md — all six`) rather than listing every file. Use `—` only where the finding genuinely has no location, such as a missing file or an absent test. This column is what makes a filed `KI-nn`/`ENH-nn` entry actionable from cold, since the roadmap entry inherits it.
- **Model** — the **model id that produced the finding**, not the CLI that ran it: `gpt-5.6-sol`, `gemini-3.1-pro-high`. Which rung of the ladder actually answered changes how much weight a finding deserves, and that is per-run state the CLI name cannot carry. When both reviewers found the same thing, **list both ids** — `gpt-5.6-sol, gemini-3.1-pro-high` — never `Both`: a row can outlive this table by being filed as a `KI-nn`/`ENH-nn`/`UNK-nn` entry, and `Both` resolves only against a coverage line that is chat-only. Two ids in one cell is also the agreement signal, stated so it survives the move. Never write `Codex` or `Gemini` alone in this column.
- **Severity** — **the reviewer's own rating, verbatim**, attributed by **model id** and never by CLI name: `High (gpt-5.6-sol)`. Never renormalize it: the same pass decides disposition, so quietly downgrading an inconvenient Critical would hide the decision. **When the two reviewers disagree, record both and order by the higher** — `High (gpt-5.6-sol) / Medium (gemini-3.1-pro-high)`. If you disagree with a rating yourself, say so in the commentary, where the user can see the disagreement.
- **Verdict** — `Confirmed` | `Partly` | `Rejected`, from step 1. Separate from Disposition on purpose: *valid but deferred* and *invalid so dropped* are different states, and one column cannot carry both.
- **Disposition** — what actually happened; vocabulary differs by mode (below).

**Order: descending criticality**, mapping the reviewers' scales onto the KNOWN_ISSUES severity scale (Critical / High / Medium / Low). Tiebreak Confirmed above Rejected, so the actionable rows sit at the top.

### Disposition vocabulary — *plan* mode

`Incorporated — <where>` | `Already covered — <where>` | `Filed ENH-nn / UNK-nn` | `Not incorporated` (Verdict `Rejected`).

A valid finding that is out of scope for this phase is **filed, not dropped** — it gets an `ENH-nn` or `UNK-nn` entry with its ROADMAP pointer row, the same as at phase end. Present the whole table in one pass regardless of severity: a confirmed Critical does not block the plan reaching the user, who is in plan mode and can send it back.

### Disposition vocabulary — *phase / repo* mode

`Fixed in phase` | `Filed KI-nn` | `Filed ENH-nn` | `Filed UNK-nn` | `Rejected`.

Exactly five buckets, and **every row lands in one** — that is what guarantees nothing is quietly lost. Regressions this phase introduced are fixed before hand-off; everything else that survives verification becomes a rated entry in `docs/KNOWN_ISSUES.md`, `docs/ENHANCEMENTS.md`, or `docs/OPEN_QUESTIONS.md`, each with its ROADMAP pointer row. `Rejected` is a real disposition, not a gap: a finding that fails verification produces no artifact, and forcing it into the roadmap would pollute it.

The table itself is **chat-only** — do not write a per-phase review file. It presents state that already lives elsewhere: fixes are in the diff, deferrals are roadmap entries. A `docs/reviews/phase-N.md` would be a backward-looking doc outside CHANGELOG, breaking the tense split. Instead give each filed entry a provenance line carrying the same model ids as the Model column — `Source: gpt-5.6-sol, gemini-3.1-pro-high — phase review, phase 4` — so the attribution survives the move into a durable doc without a second store.

## Follow-up passes — *phase* mode only

**This section is canonical for the review loop.** `phase-workflow` §3 step 5 states only what is phase-specific and delegates the rest here.

A first review changes the code, and those changes have been reviewed by no one — so a phase review is a loop, not one shot.

**Five review runs per phase by default — a soft ceiling, not a target.** Go past it when the findings justify it; say why. Pass 1 full scope; passes 2 and 3 narrow. `plan` and `repo` modes stay single-pass: a plan already loops through the user's approval, and a `repo` review seeds the backlog rather than gating a hand-off.

### The loop

1. **Pass 1** — full scope, per *Modes* above.
2. **Present the findings table and STOP.** Blocking, every time. The user decides what gets fixed, what gets filed, and what gets rejected before any code is touched. A disposition you assigned yourself is a proposal until they say so.
3. **Fix and file** what they approved.
4. **Pass 2** — narrow (below). Then present and stop again. Then pass 3, on the same terms.

**Early exit.** A pass that returns no confirmed finding needing a code change ends the loop. Do not spend the remaining passes to use them up.

**At the cap.** Anything still open after pass 3 is *filed* — `KI-nn`, `ENH-nn` or `UNK-nn` with its ROADMAP pointer row — never fixed-and-unreviewed. Say in the hand-off that the cap was reached and what is still open, so the user can call another round if they want one.

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

- **The reviewers never apply anything.** They are read-only by sandbox, not by request.
- **Who acts on a finding differs by mode, and both are review-only in the sense that matters — no fix is applied straight from review output.**
  - *plan*: the agent revises the plan itself, then presents the revision and the findings table together. This is deliberate: phase-workflow §1 says the plan the user sees is the revised one, so waiting for a disposition first would defeat the checkpoint.
  - *phase / repo*: the user dispositions every finding **before any code is touched**. A disposition you assigned yourself is a proposal until they say so.
- **The pause after a findings table is blocking.** Present, stop, wait. Not "present and start fixing while they read".
- **Never widen a follow-up pass back to full scope.** If pass 2 looks thin, that is the loop working, not a reason to re-review the phase.
- **Never report a bundle without its reconciled file count.** An unstated count is how a reviewer ends up reviewing half a phase and nobody notices.
- The Codex stop-time review gate (`/codex:setup`) stays **off** — it reviews every turn and burns quota; these checkpoints are the intended cadence.
- Subagents dispatched for triage (if any) never commit — global policy.
