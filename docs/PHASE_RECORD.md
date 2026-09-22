# Phase record

**The phase in flight, and nothing else.** Written at `phase-workflow` §2 step 3, preserved across
sessions, and read back at §4 for `MERGE_METHOD`. Later checks do not replace it: it pins what was
decided at phase start so a repository setting changed mid-phase cannot silently alter the merge.

This file is **overwritten** at each phase start, never appended. Accumulated records would be the
phase ledger the roadmap rules forbid — the release history is the phase history. When no phase is
in flight the body is the single line `No phase in flight.`

---

## Mini phase — reference integrity

| Key | Value |
| --- | --- |
| `ORIGIN_URL` | `git@github.com:rahulragunathan/localclaude.git` |
| `ORIGIN_PUSH_URL` | `git@github.com:rahulragunathan/localclaude.git` |
| `REPO` | `rahulragunathan/localclaude` |
| `DEFAULT_BRANCH` | `main` |
| `PHASE_BRANCH` | `feature/reference-integrity` |
| `MERGE_METHOD` | `squash` |
| Branched from | `origin/main` at `bcf5473` |
| Started | 2026-09-21 |
| `PR` | [#6](https://github.com/rahulragunathan/localclaude/pull/6) |
| Release | v1.12.0 |
| `APPROVED_SHA` | the PR head at sign-off — see **Gate** below |

All three merge methods are enabled on the repository; `squash` is selected because the preflight
takes the first allowed method in the order squash, rebase, merge.

## Scope

Two items filed *during* phase 1, both instruments rather than fixes, both taken before phase 2
because the remaining phases would otherwise be measured with them.

| Item | What it is |
| --- | --- |
| ENH-30 | Anchor roadmap references to a greppable fragment, and make `roadmap.py check` verify it |
| KI-52 | Measure whether mid-test `[[ ]]` vacuity differs between bash 3.2.57 and bash 5 |

**Plan:** `docs/superpowers/plans/2026-09-21-mini-phase-reference-integrity.md`.

## Diagram generators

None. The architecture diagram names skills rather than their scripts, so new functions inside
`roadmap.py` leave it factually correct. §2 step 4 is skipped, as in phase 1.

## Decisions taken at phase start

1. **A fragment is required per file link, not per entry.** 89 fragments across 71 entries; 38
   point inside the five in-scope skills or the repo root and 51 outside them. Both external
   reviewers attacked the per-entry reading independently as a false green: one verified fragment
   would certify an entry citing three files. Chosen by the user over the 71-fragment and
   59-fragment readings, with those costs measured and presented.
2. **Two exemptions, both forced by real entries.** A link whose target is a directory is an
   existence-only reference and takes no fragment (`ENH-04`, `ENH-07`). A fragment cannot contain a
   backtick, so `ENH-27` picks a different distinctive string from the file it cites.
3. **bash 5 is installed on the host** with `brew install bash`, authorised by the user at phase
   start. It lands at `$(brew --prefix)/bin/bash` and leaves `/bin/bash` untouched.

## Model and effort, per task

Recorded in each commit trailer. Astra (`gpt-6-astra`) writes the production diff; Claude writes
the red test first.

## Deviations from the documented workflow, recorded rather than silent

1. **The plan was drafted outside the repository.** `codex-root.sh` refuses any untracked file, so
   §1's external review cannot run while the plan sits in `docs/superpowers/plans/`. It was
   drafted and reviewed in `~/.claude/plans/` and moved in as this phase's first commit. Filed as
   a finding — the two documents are consistent and neither says this.

## KI-52 — measured

**The vacuity is host-dependent. Astra's claim was right and phase 1's evidence was narrower than
phase 1 thought.** bats 1.14.0 in both arms, interpreter confirmed from inside each run:

| Interpreter | false mid-test `[[ ]]` | false mid-test `[ ]` |
| --- | --- | --- |
| bash 3.2.57 (`/bin/bash`, stock macOS) | **passes** — vacuous | fails |
| bash 5.3.20 (Homebrew) | **fails** | fails |

Consequences, all recorded in `SKILL.md`:

1. `|| false` is correct under both, and **load-bearing only under bash 3.2**. Phase 1's claim
   that the suffix supplies the discrimination holds for 3.2.57 and not for 5.3.20.
2. The 68 conversions stand. What narrows is the claim made for them.
3. The 0-`mid` gate is about **the interpreter macOS ships**, not about the machine running it.

**One phase-1 test encoded the 3.2 behaviour and failed under bash 5.** `verify-assertions.bats`
asserted `verify_assertions.sh` reports `GREEN` for a mid-test `[[ ]]`; under bash 5 its fixture
no longer passes, so the property under test does not exist there. The test now decides its own
scope by **running the fixture** rather than reading `$BASH_VERSION` — two measured points say
nothing about bash 4 — and skips with the interpreter named. `verify_assertions.sh` itself needed
no change: reporting `RED` for every assertion under bash 5 is correct there.

**Two pinning methods failed silently before one worked.** Selecting the interpreter with an
unqualified `bats` runs whatever is first on `PATH`. Invoking the wanted bash *on the bats script*
also fails, because `bats` re-execs `bats-exec-file` and `bats-exec-test`, each
`#!/usr/bin/env bash`, so the shebang resolves from `PATH` regardless: `/bin/bash "$(command -v
bats)"` reported `BASH_VERSION=5.3.20`. Only putting the wanted directory first on `PATH` works,
and **only reading `BASH_VERSION` from inside the run caught the two failures**. The external
review had insisted on that reading; it then caught the review's own fix.

## This phase changed how the project is verified

`brew install bash` put bash 5.3.20 at `/opt/homebrew/bin/bash`, and `/opt/homebrew/bin` precedes
`/bin` on this machine — position 2 against position 11. **Every unpinned `bats` run on this
machine is now bash 5.3.20.** `/bin/bash` is untouched at 3.2.57.

The suite passes under both, so the gate is not weakened; but a result gathered without pinning no
longer means what it meant before this phase, and the hand-off says which interpreter each number
came from.

## Task 3 mutation audit — ten behaviours, and two tests that proved nothing

One mutation per behaviour, checking **which** test went red rather than the exit status. Eight
of ten were red at their named test first time. Two left all 38 tests passing:

| Behaviour mutated | Outcome |
| --- | --- |
| Fence delimiter length (`len(match[1]) >= len(opened)` → `True`) | **green** — fixture had two inner three-backtick lines, so the toggles landed evenly and the Where line was unfenced either way |
| Where-field continuation (`lines[i + 1:]` → `[]`) | **green** — the control asserted a wrapped field stays clean, and dropping a *valid* reference produces no finding either way |

Both were test defects of mine, both fixed, both now red at the named test. The fence fixture
needs **exactly one** inner three-backtick line and the comment says so; the wrapped field gained
a sibling test whose second line carries an absent fragment, so the line must be read for the
check to fail. The control stayed, because it is what stops the fix over-reaching.

The audit is the only thing that separated these two from the eight that worked. Reading them did
not, and neither did their passing.

## Findings from executing the workflow

Filed properly in Task 5; recorded here as they are found.

| ID | Finding |
| --- | --- |
| — | The documented 0-`mid` gate in `phase-workflow/SKILL.md` cannot fail: a scanner failure prints nothing, which reads as clean. Confirmed by running it against a missing file. |
| — | The same gate's `skills/*/tests/*.bats` glob sweeps in `claude-toggle-backend`, so the documented command reported **5** `mid` rows while the text beside it claimed **0**. Fixed here by naming the four in-scope skills. |
| — | §1's plan review cannot run with the plan inside the repo (deviation 1 above). |
| — | `bats` cannot be pinned by invoking a bash on its script; its helpers re-exec through `env bash`. Worth a line in the skill for anyone measuring interpreter behaviour again. |

## External review, plan pass

**Full coverage** — `Codex gpt-6-astra (max) 11 · Gemini gemini-3.1-pro-high 8 · 4 overlapping →
15 unique findings`. Single chunk of 60,399 characters; `bundle contains 1 of 1 files; 0 withheld,
0 excluded`. Both reviewers answered at their top rung, and neither authored the plan, so the
author-disqualification rule phase 1 added did not apply.

All 17 rows incorporated. The two that changed the phase:

- **The interpreter comparison was not one.** Task 2 selected bash with `PATH`, and
  `/opt/homebrew/bin` precedes `/bin` on this machine, so after the install both arms would have
  run bash 5, agreed, and produced "not host-dependent" from a single interpreter. Each arm now
  invokes its bash on the bats script directly and reads `BASH_VERSION` from inside the run.
- **One verified fragment concealed every other reference in its entry.** Found independently by
  both reviewers, and the reason decision 1 above went to the strict reading.

## What the phase did

| Closed | ENH-30, KI-52 |
| --- | --- |
| Filed | KI-55 |

59 line anchors became 89 verified fragments across 71 entries; `roadmap.py check` gained the
pass that verifies them; and KI-52 was answered by measurement rather than by assertion.

Three references turned out to be drift already, found by reading and not by any gate: KI-17's
fourth link pointed at a blank line in an alias block, and KI-07 and KI-17 each carried a line
anchor in prose rather than in the Where field.

**Astra wrote every production diff; Claude wrote every test.** Astra raised no dispute this
round. Its two defects were both found by my review of its diff rather than by a test: the
line-anchor scan read only the `**Where:**` field, missing two real prose anchors, and a
recognised link with a near-miss target was skipped silently by both the existence and fragment
checks. Each got a red test before the fix.

**My defects were again test-side**, and the mutation audit is what found them: two of the
fifteen tests passed for the wrong reason. The four-backtick fixture had an even number of inner
fences, so the toggles landed evenly and the Where line was unfenced whether or not the rule
worked; and the wrapped-field control could not detect the field being truncated, because
dropping a valid reference produces no finding either way.

## Test-validity audit — every test this phase added or changed

**20 `refs:` tests, all with a proven red.** Thirteen went red under a mutation of the behaviour
they name. The seven controls assert the *absence* of a finding, so their discriminating mutation
is the opposite one — something that makes the checker over-report — and each was found:

| Control | Mutation that reds it |
| --- | --- |
| a fragment present in the cited file passes | force the absent branch |
| a #Lnn inside a fenced block is not a finding | never open a fence |
| a Where field wrapped onto a second line is read whole | force the absent branch |
| a directory link needs no fragment | remove the directory exemption |
| a doc-relative link inside docs needs no fragment | remove the docs-relative skip |
| a file link in prose needs no fragment | extend the field past its blank line |
| a tilde-fenced example is not a finding | never open a fence |

I expected the wrapped-field control to have no discriminating mutation, because truncating the
field removes a *valid* reference and produces no finding either way. That was too pessimistic:
an over-reporting mutation reds it. The sibling test asserting a bad reference on line 2 is still
the one that proves the line is read.

**`verify-assertions.bats`** had one test changed rather than added: it now decides its own scope
by running its fixture. Under bash 3.2.57 it runs and passes, under 5.3.20 it skips with the
interpreter named. Its GREEN assertion was proven by mutation in phase 1 and is unchanged.

**`tests/fixtures/vacuity.bats`** is a fixture, not part of any suite, and asserts nothing.

## design-review, phase mode

| Unit | Responsibility | Interface | Depends on |
| --- | --- | --- | --- |
| `roadmap.py` · `_fenced_lines` | Mark which lines sit inside a fenced block, by delimiter char and run length | `_fenced_lines(text) -> list[bool]` | — |
| `roadmap.py` · `_where_field` | Return an entry's whole `**Where:**` field, continuation lines included | `_where_field(lines) -> str` | — |
| `roadmap.py` · `_references` | Parse one field into `(target, fragment)` pairs, refusing a shape it cannot read | `_references(field) -> list[Ref]` | — |
| `roadmap.py` · `verify_references` | Resolve each reference and confirm its fragment is still in the cited file | `verify_references(docs) -> (bool, list[str])` | the three above, filesystem |
| `roadmap.py` · `cmd_check` | Run reconciliation and reference verification, report both | `cmd_check(docs) -> int` | `reconcile`, `verify_references` |
| `phase-workflow/SKILL.md` | State the reference rule and what the interpreter measurement showed | — | — |
| `KNOWN_ISSUES-template.md` | Show the reference shape a new entry copies | — | — |
| `docs/KNOWN_ISSUES.md`, `docs/ENHANCEMENTS.md` | Carry entry detail, anchored by fragment rather than by position | — | the source files they cite |

**Expected change:** a referenced source file gets edited. That should mean `roadmap.py check` stays
green because the fragment moved with its code, or fails naming the entry and the reference.

**Shared state:** none. Every function takes its input and returns; the content cache lives for one
call.

### Checks that fired

- **Responsibility — `roadmap.py` now holds two passes with different reasons to change.**
  `reconcile` asks whether the index agrees with the detail files; `verify_references` asks whether
  the detail files agree with the source tree, and it reaches outside `docs/` to do it. Resolved by
  keeping them separate functions composed in `cmd_check` rather than one pass. Recorded for the
  next phase: a **third** pass over these files is the point at which the file becomes a module
  with its own directory, not a fourth function.
- **Duplication — `_fenced_lines` is the second fence tracker in this repo**, after the one inline
  in `design-review/tests/write_results.py`. Deliberately not consolidated. The two differ in a
  load-bearing way — only this one implements the rule that a backtick fence whose info string
  contains a backtick is not a fence — they sit in different skills with no shared module between
  them, and two occurrences do not justify creating one. The third occurrence creates the home.
- **Surface — `verify_references` takes one argument, not two.** The obvious signature threads a
  repository root through it, and it is unnecessary: a link inside `docs/KNOWN_ISSUES.md` is
  written relative to that file, so `docs / "../skills/x"` already resolves. The CLI surface did
  not change.
- **Variation — `_references` refuses rather than extends.** The first draft planned "one regex, no
  registry". That was the wrong shape of answer: the risk is not too few syntaxes but an
  unrecognised one being read as *no reference*, which is silent. It now raises, and the caller
  turns that into a finding, so adding a syntax costs a rule and a test — which is the cost that
  should be paid.

## External review, phase pass 1

**Partial coverage** — `Gemini gemini-3.1-pro-high · chunk 1: 3 · chunk 2: 6 → 9 findings ·
Codex AUTHOR — disqualified (probe: READY)`. Two chunks of 52,000 and 67,000 characters;
`bundle contains 17 of 17 files; 0 withheld, 0 excluded`, reconciling as 7 code files + 7 document
files + 3 phase artifacts named as deliberately not sent.

**Codex authored every production diff, so it cannot review it.** `preflight.sh --authored-by
codex` reported `AUTHOR — disqualified` and warned partial coverage before the pass started —
the rule phase 1 added, on its second real use. Gemini was the only independent reviewer, and the
prompt said so, because Claude wrote every test and neither author is independent of this work.

**Split by concern, not alphabetically.** Phase 1 chunked an alphabetically-ordered diff and the
reviewer saw only `docs/`, producing twelve findings about code it never read. Chunk 1 was the
code and its tests, chunk 2 the documents the conversion rewrote, each naming what the other
covered.

| # | Finding | Model | Likelihood | Severity | Verdict | Disposition |
| --- | --- | --- | --- | --- | --- | --- |
| F-01 | The gate's reach follows `../` and absolute paths outside the repository | gemini-3.1-pro-high | Rare | Low (gemini) | Confirmed | Fixed in phase |
| F-02 | `awk \| wc -l` reports 0 when `awk` fails, so the 0-`mid` gate passes | gemini-3.1-pro-high | Likely | Medium (gemini) | Confirmed | Fixed in phase |
| F-03 | `ENH-07`'s fragment is the file's description header, unrelated to its subject | gemini-3.1-pro-high | Almost always | High (gemini) | Confirmed | Fixed in phase |
| F-04 | `KI-32`'s second fragment describes bash syntax, not approval state | gemini-3.1-pro-high | Almost always | High (gemini) | Confirmed | Fixed in phase |
| F-05 | An entry omitting its `**Where:**` field entirely is skipped in silence | gemini-3.1-pro-high | Rare | Medium (gemini) | Confirmed | Filed ENH-31 |
| F-06 | CHANGELOG claims `KI-07`/`KI-17` prose-anchor fixes the diff does not show | gemini-3.1-pro-high | — | High (gemini) | Rejected | Rejected |
| F-07 | `KI-44`'s link and fragment are unrelated to its subject | gemini-3.1-pro-high | — | High (gemini) | Rejected | Rejected |
| F-08 | `KI-14`'s fragment points at a success test, contradicting its subject | gemini-3.1-pro-high | — | Low (gemini) | Rejected | Rejected |
| F-09 | `KI-26` silently dropped a fourth link | gemini-3.1-pro-high | — | Low (gemini) | Rejected | Rejected |

**F-02** — *When it fires:* `awk` fails while counting the scanner's output. *What happens:*
`wc -l` receives nothing, prints `0`, and `[ "$MID" -eq 0 ]` passes, so the gate proves nothing.
*Reviewer's fix:* "Set `set -o pipefail` before executing the pipeline, or check `${PIPESTATUS[0]}`
to ensure an `awk` failure explicitly fails the gate." *Commentary:* This is the same defect one
level below a fix made earlier in this phase. I made the *scanner* failure loud and left the
identical hole in the command that reads its output. Worth recording as a pattern: fixing a silent
failure at one level invites checking the next.

**F-03, F-04** — *When they fire:* a reader opens the entry to find the code it describes. *What
happens:* the fragment is unique, so the gate says verified, and it points at something unrelated.
*Reviewer's fix:* "Change the fragment to point to the specific line where the config path is
hardcoded." *Commentary:* Both confirmed, and the review found a pattern rather than two
instances. Auditing all 34 title-chosen fragments turned up a third (`ENH-25`, anchored to repeat
grading rather than the blinding it is about) and two weak ones. **`KI-32` is the more important
case:** its original line anchor pointed at item 5 of the cited file, about `cd` in compound
commands, while the entry is about item 6, the `~/.claude.json` approval state. The reference was
drift before the conversion and the conversion anchored it faithfully. **Anchoring a wrong
reference makes it verifiable and still wrong** — a limit of this mechanism the phase should state
rather than discover later.

**F-06 to F-09 — rejected, and the reason is one cause, not four.** All four assert something
about an entry the reviewer mis-identified, reading a diff without enough surrounding context.
F-06 claims the CHANGELOG invented the `KI-07`/`KI-17` prose-anchor fixes: `grep -c '#L[0-9]'` on
`docs/KNOWN_ISSUES.md` returns **0**, both prose links are converted, and `KI-17` carries three
links where it carried four. F-07 attributes `KI-27`'s fragment to `KI-44`, whose Where field
cites `evidence.py` at the dispatch-log filter — correct for its subject. F-08 attributes
`KI-11`'s fragment to `KI-14`. F-09 attributes `KI-17`'s dropped link to `KI-26`; that removal is
disclosed in its commit message and in the CHANGELOG.

Each was checked against the file rather than acted on. A reviewer confidently wrong about four
entries is worth recording as a property of reviewing a diff in chunks, not as a slight: F-03 and
F-04, which it got right, were worth the pass on their own.

**Test-discrimination answer.** The reviewer observed that the eight controls would pass with the
change reverted, since they assert exit 0 and the old script exited 0 always. That is true as
stated and is the reason the audit above mutates each control with an *over-reporting* mutation
rather than reverting the feature. It identified the exact class this phase had already measured.

## Gate

Recorded at §3 step 7.

## Evidence state

S01 to S07 design-review evidence is untouched so far. `design-review/SKILL.md` is not in this
phase's scope; `phase-workflow/SKILL.md` is, so **S07's with-skill rows expire again** when Task 2
or Task 5 edits it. S07's round-9 row is already marked **Expired** from phase 1 and re-gathering
stays blocked on KI-48, so the mark does not change — but the hash does, and Task 5 records it.
