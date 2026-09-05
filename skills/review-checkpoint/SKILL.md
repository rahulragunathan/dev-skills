---
name: review-checkpoint
description: Run external-model reviews (OpenAI Codex + Google Gemini via the Antigravity `agy` CLI) at the critical junctures of the user's phase workflow — `/localclaude:review-checkpoint plan` on a drafted plan before it goes to the user for approval, `/localclaude:review-checkpoint phase` after a phase's implementation is complete, `/localclaude:review-checkpoint repo` for the current state of a repo with no in-flight branch (e.g. adopting the workflow on an existing project). Review-only, never applies fixes; verifies findings against the repo, then presents every finding — confirmed and rejected alike — in a standard table with a disposition for each, so nothing is lost; classifies CLI failures (missing vs quota vs auth vs sandbox) plainly and continues with whichever reviewer is available, skipping the review outright when neither CLI is installed. In phase mode it runs as a short loop — up to three review→fix passes, each follow-up narrowed to the fixes just made, with a blocking pause on the findings table after every pass. Use when the user asks for an external review, a second-model opinion on a plan, diff, or codebase, or when the phase-workflow skill reaches a review checkpoint.
---

# review-checkpoint

Independent reviews from non-Claude models at three junctures: **plan** (before implementation), **phase** (branch diff before hand-off), **repo** (current state, no in-flight branch). Both reviewers run each time; findings are verified, then presented in the standard findings table with a disposition for every row.

## Preflight — check the CLIs first

```bash
command -v codex; command -v agy
```

Neither CLI is a hard requirement of this plugin. Check both **before** composing any prompt, so a missing tool surfaces as one clear line instead of a confusing failure halfway through:

- **Both present** → normal run.
- **One missing** → say which reviewer is unavailable and its install hint (`codex` → the OpenAI Codex CLI, then `codex login`; `agy` → the Antigravity CLI), then review with the other. A single-reviewer report says so at the top — there is no agree/disagree axis, so the findings carry less weight.
- **Both missing** → **skip the review entirely.** Report: *"External review skipped — neither `codex` nor `agy` is installed"*, with both install hints. Do not fall back to a Claude-run review: a second opinion from the same model is not a second opinion, and presenting one as this checkpoint's output would be misleading. This is a skip, not a failure — never block the user's workflow on it (see phase-workflow's note on the same rule).

Offer the install commands; never install a CLI or change the user's login state yourself.

## The two reviewers are NOT interchangeable — different invocation contracts

**Review models — always try the strongest tier first, downshift only on rejection.** Model entitlements differ per machine and per signed-in account (a work account may have tiers a personal one doesn't), so never hard-code the fallback as the default. Ladders, strongest first:

| Reviewer | Try in this order |
| --- | --- |
| Codex (`-m`) | `gpt-5.6-sol` → `gpt-5.6-terra` (CLI default) → unflagged default |
| Gemini (`--model`) | `gemini-3.1-pro-high` → `gemini-3.6-flash-high` → unflagged default |

Downshift rule: run with the top model; **only** if it fails with an availability error (`model ... is not supported`, unknown/retired model, entitlement error) drop to the next rung and retry. Quota, auth, and timeout errors are NOT downshift triggers — handle them per *Failure handling* below. **Record which model actually ran** — it goes in the findings table's coverage line and its Model column (below), which is the one place that attribution is carried. Note a downshift plainly there (`gpt-5.6-sol unavailable on this account — reviewed with gpt-5.6-terra`), since a lighter model changes how much weight the findings deserve.

- **Sol availability is a PLAN-TIER issue, not an auth-method one.** Sol is available to paid ChatGPT subscriptions (Plus/Pro/Business/Enterprise) through the Codex CLI as well as via API key; the **free** tier does not include it. The CLI's error is misleading — it says *"not supported when using Codex with a ChatGPT account"* when the real cause is the account's plan. Diagnose with `codex login status` plus the `chatgpt_plan_type` claim in `~/.codex/auth.json` (read that key only — the file holds tokens). If it reads `free`, tell the user Sol needs a paid account and that `codex logout && codex login` switches accounts — noting that Codex auth is global per machine, so a work account would then cover personal projects too. `gpt-5.6-luna` is the lightest sibling — never use it for reviews.
- **Never pick `agy`'s `claude-*` models** (it offers Sonnet/Opus) — the entire point of this checkpoint is a non-Claude second opinion.
- If every rung is rejected, the IDs likely retired: run `agy models` / check the [Codex models list](https://developers.openai.com/codex/models), use the current equivalent, and tell the user the ladder needs updating.

**Codex is agentic** — it explores the repo itself. Point it at the repo root and pin it read-only at the tool level (never rely on prompt wording alone):

```bash
codex exec -C "<repo-root>" --sandbox read-only -m gpt-5.6-sol -o "<scratchpad>/codex_<mode>.txt" "<prompt>"   # downshift per the ladder if unavailable
```

- `-C` replaces `cd "…" &&` (which the global shell rules prohibit); `--sandbox read-only` makes review-only enforced, not requested; `-o` writes only the final message (no event noise).

**Gemini (`agy -p`) is one-shot print mode — it cannot prompt for tool permissions.** Any prompt asking it to "review this repository" gets its tool calls auto-denied and fails. **Always inline the material in the prompt** and state: *"REVIEW ONLY: do not attempt to use any tools; answer purely from the text below."*

```bash
agy -p "$(cat "<scratchpad>/gemini_prompt.txt")" --model gemini-3.1-pro-high --effort high --print-timeout 15m > "<scratchpad>/gemini_<mode>.txt" 2>&1
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
git diff "<base>" -- .                     # tracked: committed + staged + unstaged, all at once
git ls-files --others --exclude-standard   # untracked — append each file IN FULL, with a path header
```

Do **not** use `git add -N` to sweep untracked files into the diff. It mutates the index, and phase-workflow's gate checks `git status` to prove the work is uncommitted.

**Reconcile the bundle, and say the count out loud.** This failure is silent — a short bundle looks exactly like a small phase — so a better command is not the fix; a stated count is:

```bash
git status --porcelain | wc -l    # must equal the file count in the bundle
```

Put that count in the prompt (*"this bundle contains all N changed files"*) and in the report's coverage line. Codex reads the working tree and sees untracked files on its own, but give it the same manifest so it is not inferring the scope of the phase.

**`repo`** — no in-flight branch; review current state (workflow adoption, periodic health check). Codex: repo-rooted as above. Gemini: concatenate the source into one bundle (`allsrc.txt`-style) and inline it. **If the bundle exceeds the model's input limit, chunk by package/directory and run one call per chunk — never silently review a subset; say in the report exactly what each call covered.**

## Failure handling — classify, don't guess

On empty output or non-zero exit, run a tiny probe before reporting:

```bash
codex exec -C "<repo-root>" --sandbox read-only -m <same model as the real run> "List the three most obvious code-quality issues in this repository. Be brief."   # or the agy equivalent with inline text
```

Use the SAME model as the real run — quota and availability limits are per-model, so a probe on a different rung misdiagnoses the failure.

- Probe succeeds → the real prompt was the problem (too large, malformed) — fix and re-run.
- Probe fails → read the error: quota/usage → report "Codex/Gemini out of usage — skipped"; `model ... is not supported` → an unavailable model tier, not a quota problem (see the pins above); auth → say re-login is needed (`codex login` / `agy` interactive); tool-permission denial (Gemini) → the prompt asked it to use tools — inline the material instead.
- `command not found` → the CLI is not installed; that is a preflight case, not a runtime failure. Don't probe — report the skip per *Preflight* above.
- Never silently drop a reviewer; the report names which ran, which didn't, and why.

## Triage — verify before presenting

1. **Verify each finding against the repo** (read the cited file/function) before it reaches the user. A confident false finding routed into the roadmap files is worse than no review. Verification decides the **Verdict**, never whether the row appears.
2. **Deduplicate across reviewers.** One row per distinct finding. Two reviewers reporting the same thing is signal, not noise — merge them into one row whose Model reads **Both**.
3. **Give every finding a disposition** and present them in the findings table below. *plan* mode: the table goes in the plan. *phase / repo* mode: the table goes in the hand-off at the gate.

## The findings table (canonical format — both modes)

Every finding the reviewers returned gets a row, **including rejected and duplicate ones**. A table that shows only survivors cannot be audited: the user has to be able to see what was thrown away and push back on it. Never summarize the list down.

Open with a coverage line so the count is unambiguous:

```text
Codex gpt-5.6-sol 7 · Gemini gemini-3.1-pro-high 4 · 3 overlapping → 8 unique findings
```

Name the **exact model that ran**, not the CLI — the ladder in *Review models* downshifts on availability, so "Codex" alone hides whether the findings came from the top tier or a lighter rung. If a downshift happened, say so here too: `Codex gpt-5.6-terra 5 (gpt-5.6-sol unavailable) · …`.

If neither CLI is installed, print the skip line in its place — `External review skipped — neither codex nor agy is installed` — so a missing table is never mistaken for a clean review.

**Format: a compact table, then keyed notes.** Explanation and commentary are prose and wrap badly inside table cells, so they live in the notes below the table, keyed by finding ID.

| # | Finding | Model | Severity | Verdict | Disposition |
| --- | --------- | ------- | ---------- | --------- | ------------- |
| F-01 | No rollback if the migration half-applies | gpt-5.6-sol | High | Confirmed | Incorporated — new step 6 |
| F-02 | Token refresh races on concurrent runs | gpt-5.6-sol, gemini-3.1-pro-high | Medium | Confirmed | Filed UNK-08 |
| F-03 | Add a caching layer for lookups | gemini-3.1-pro-high | Medium | Rejected | Not incorporated |

**F-01** — *Explanation:* <what the reviewer claims, in a sentence or two> *Commentary:* <what you found verifying it, and why the disposition follows>
**F-02** — *Explanation:* … *Commentary:* …

Column rules:

- **#** — `F-01`, `F-02`, … Stable within this review only; they exist so the user can say "also fix F-03" without quoting titles.
- **Finding** — one short line. Not a summary of the explanation.
- **Model** — the **model id that produced the finding**, not the CLI that ran it: `gpt-5.6-sol`, `gemini-3.1-pro-high`. Which rung of the ladder actually answered changes how much weight a finding deserves, and that is per-run state the CLI name cannot carry. When both reviewers found the same thing, **list both ids** — `gpt-5.6-sol, gemini-3.1-pro-high` — never `Both`: a row can outlive this table by being filed as a `KI-nn`/`ENH-nn`/`UNK-nn` entry, and `Both` resolves only against a coverage line that is chat-only. Two ids in one cell is also the agreement signal, stated so it survives the move. Never write `Codex` or `Gemini` alone in this column.
- **Severity** — **the reviewer's own rating, verbatim** (`High (Codex)`). Never renormalize it: the same pass decides disposition, so quietly downgrading an inconvenient Critical would hide the decision. If you disagree with the rating, say so in the commentary, where the user can see the disagreement.
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

A first review changes the code. Those changes have never been reviewed by anyone, and the fixes for high-severity findings are exactly where a hurried repair introduces the next bug. So a phase review is a short loop, not one shot.

**Three review runs per phase, maximum — a ceiling, not a target.** Pass 1 full scope; passes 2 and 3 narrow. `plan` and `repo` modes stay single-pass: a plan already loops through the user's approval, and a `repo` review seeds the backlog rather than gating a hand-off.

### The loop

1. **Pass 1** — full scope, per *Modes* above.
2. **Present the findings table and STOP.** Blocking, every time. The user decides what gets fixed, what gets filed, and what gets rejected before any code is touched. A disposition you assigned yourself is a proposal until they say so.
3. **Fix and file** what they approved.
4. **Pass 2** — narrow (below). Then present and stop again. Then pass 3, on the same terms.

**Early exit.** A pass that returns no confirmed finding needing a code change ends the loop. Do not spend the remaining passes to use them up.

**At the cap.** Anything still open after pass 3 is *filed* — `KI-nn`, `ENH-nn` or `UNK-nn` with its ROADMAP pointer row — never fixed-and-unreviewed. Say in the hand-off that the cap was reached and what is still open, so the user can call another round if they want one.

### What "narrow" means

The churn risk in a follow-up is a reviewer re-reading the whole phase and returning pass 1's list with the numbers shuffled. Scope each follow-up prompt to exactly three things:

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

- Review-only: never apply fixes, patches, or "quick corrections" from review output.
- **The pause after a findings table is blocking.** Present, stop, wait. Not "present and start fixing while they read".
- **Never widen a follow-up pass back to full scope.** If pass 2 looks thin, that is the loop working, not a reason to re-review the phase.
- **Never report a bundle without its reconciled file count.** An unstated count is how a reviewer ends up reviewing half a phase and nobody notices.
- The Codex stop-time review gate (`/codex:setup`) stays **off** — it reviews every turn and burns quota; these checkpoints are the intended cadence.
- Subagents dispatched for triage (if any) never commit — global policy.
