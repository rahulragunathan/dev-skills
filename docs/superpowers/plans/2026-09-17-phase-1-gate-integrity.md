# Phase 1 — Gate integrity: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the verification gate trustworthy before five more phases run through it.

**Architecture:** Two new helpers in `phase-workflow` turn KI-45's "make each assertion false
once" into a repeatable run over the existing `mutation-restore.sh` primitive. KI-46 replaces a
branch-retention test that is wrong on every squash merge. Three gaps found while planning are
fixed in `external-review` because the programme depends on them from task one.

**Tech Stack:** bash, bats-core 1.14.0, python3 (stdlib only), `gh`, `codex`, `agy`

**Spec:** [2026-09-16-plugin-fix-program-design.md](../specs/2026-09-16-plugin-fix-program-design.md)

**Diagrams:** none. The architecture diagram names skills, not their scripts, so adding two
helpers inside `phase-workflow` leaves it factually correct. No generator filenames to record,
and §2 step 4 is skipped.

## Global Constraints

- **Astra writes production diffs; Claude writes the tests.** Each task's "implement" step names
  the constraint and the interface, not the code. This is a deliberate departure from the
  writing-plans template, which assumes one author for both.
- Model and effort are recorded in every commit trailer, per the spec. Top rung is
  `gpt-6-astra` at `max`; `ultra` is not used.
- `[[ ... ]]` is banned in new bats assertions. Use `[ ... ]`, a `grep -q` pipeline, or
  `bats-assert`. Under bats 1.14.0 a false `[[ ]]` does not fail its test unless it is the test's
  last command.
- Python is stdlib only. No new dependency enters this repo in phase 1.
- Every roadmap edit is followed by `roadmap.py check || exit 1`. KI-40 is phase 4's, not this
  phase's, so if the check fails on template placeholders here, stop and report rather than
  working around it.
- Markdown is linted with `markdownlint-cli2 --config ~/.markdownlint.jsonc` before hand-off.

---

## File Structure

Produced by `/localclaude:design-review plan`. Rows are ordered most-stable-first.

| Unit | Responsibility | Interface | Depends on |
| --- | --- | --- | --- |
| `skills/phase-workflow/bats_assertions.py` | Report every `[[ ]]` assertion in a bats file and whether it is its test's final command | `bats_assertions.py <file.bats>...` → tab-separated `file`, `line`, `test_name`, `final` or `mid` on stdout, exit 0; exit 1 on an unparseable file | — |
| `skills/phase-workflow/verify_assertions.sh` | Confirm one converted assertion is load-bearing, by negating it and requiring its own test to name the failure | `verify_assertions.sh <task-sha> <repo-relative-file> <line> <test-name>` → prints `RED`, `GREEN` or `REFUSED <reason>`; exit 0 only on `RED` | `bats_assertions.py`, `mutation-restore.sh` (unchanged) |
| `skills/external-review/SKILL.md` — ladder fence | Rank Codex and Gemini rungs as (slug, effort) pairs, and bar a reviewer that authored the diff under review | `codex_ladder()` → lines of `slug:effort`, strongest first | `~/.codex/models_cache.json`, `agy models` |
| `skills/phase-workflow/SKILL.md` §4 step 7, `skills/phase-workflow/publish-release.sh` | Delete a phase branch whose work is upstream; retain one holding commits that are not | `git cherry <default> <branch>` in both fences | `git` |
| The 12 in-scope `*.bats` suites | Assert so that a false condition fails its test wherever it sits in the body | bats test bodies | `bats`, `bats_assertions.py` |
| `docs/KNOWN_ISSUES.md`, `docs/ROADMAP.md`, `docs/OPEN_QUESTIONS.md`, `CHANGELOG.md`, `CLAUDE.md` | Record KI-47 to KI-51, close UNK-02, correct KI-45's counts and two stale CHANGELOG claims | markdown | `roadmap.py check` |

**Expected change:** a new bats assertion idiom. Adding one should mean editing
`bats_assertions.py` and nothing else.

**Shared state:** the git working tree, across every iteration of `verify_assertions.sh`. A
failed restore in one iteration would otherwise contaminate the rest. See the Lifetime line.

### Checks that fired

- **Responsibility** — the first draft had one script both enumerating assertions and verifying
  them. Enumeration changes when bats syntax changes; verification changes when the audit
  procedure changes. Split into `bats_assertions.py` and `verify_assertions.sh`.
- **Duplication** — the verifier gets no mutation mechanism of its own. `mutation-restore.sh`
  already refuses a dirty tree, requires exit 1 specifically rather than any non-zero, restores
  across index and worktree on every exit path including INT and TERM, and verifies the file
  against the SHA afterwards rather than trusting the restore's status. The driver calls it.
- **Lifetime** — the working tree outlives one call and is shared across all iterations.
  Resolution: the driver halts on the first `REFUSED` instead of continuing, and re-asserts a
  clean tree between iterations rather than trusting the previous restore.
- **Surface** — `codex_ladder()` returns bare slugs, so a caller cannot express Astra-low versus
  Astra-max, and cannot pin a model past the `sol`/`astra` priority tie. Resolution: it returns
  `slug:effort` pairs and callers pass both to `-m` and `-c model_reasoning_effort`.
- **Variation** — `bats_assertions.py` gets no plug-in seam for assertion styles. One shape is
  being converted, so a classifier `Protocol` would be machinery for a single implementation.
  Declined; the conversion table stays as data inside the script.

---

## Task 1: Enumerate bats assertions

**Files:**

- Create: `skills/phase-workflow/bats_assertions.py`
- Create: `skills/phase-workflow/tests/fixtures/brace.bats`, `trailing-helper.bats`, `heredoc.bats`
- Test: `skills/phase-workflow/tests/bats-assertions.bats`

**Interfaces:**

- Consumes: nothing.
- Produces: `bats_assertions.py <file.bats>...` -> tab-separated `file`, `line`, `test_name`,
  `final` or `mid` on stdout, exit 0. Exit 1 with a message on stderr for a file it cannot parse.

**Why this is task 1.** The authoritative count is an *output* of this tool, not an input to this
plan. KI-45 states 325 tests, 145 assertions, 78 mid-test; a hand parser reproduced 320 and 141,
because brace-depth tracking breaks on `${...}` and embedded python. Carry none of those numbers
into an assertion.

**Fixtures are real files under `tests/fixtures/`, never heredocs inside a test.** Bats
preprocesses the file it runs, so a heredoc containing `@test` lines does not survive intact
(F-23), and Task 3 would otherwise inventory this plan's own fixture text as convertible
assertions (F-09).

- [ ] **Step 1: Write the three fixtures**

`fixtures/brace.bats` — a literal unbalanced brace inside a valid string, which is what defeats
brace counting. `"${UNCLOSED"` is *not* valid bash and must not be used:

```bash
@test "brace in a string" {
  run printf '%s' "{"
  [[ "$output" == "x" ]]
  [ "$status" -eq 0 ]
}
@test "assertion is last" {
  [[ "$output" == "y" ]]
}
```

`fixtures/trailing-helper.bats` — HEAD's real counterexample, a final assertion followed by a
helper function defined outside any test (F-10, mirroring `phase-git.bats:289-310`):

```bash
@test "ends with an assertion" {
  run true
  [[ "$output" != *'nope'* ]]
}

helper_defined_after() {
  echo not a test body
}
```

`fixtures/heredoc.bats` — assertion-shaped text inside a quoted heredoc, which must not be
inventoried:

```bash
@test "writes a fixture" {
  cat > "$BATS_TEST_TMPDIR/inner.bats" <<'INNER'
@test "not a real test" {
  [[ "a" == "b" ]]
}
INNER
  [ -s "$BATS_TEST_TMPDIR/inner.bats" ]
}
```

- [ ] **Step 2: Write the failing test**

Three failure conditions, one per fixture:

- *fails if an assertion followed by a later command is reported `final` when the body contains an
  unbalanced brace in a string*
- *fails if a test's last assertion is reported `mid` because a function definition follows the
  test*
- *fails if assertion text inside a quoted heredoc is reported as an assertion at all*

```bash
setup() {
  FIX="$BATS_TEST_DIRNAME/fixtures"
  SCRIPT="$BATS_TEST_DIRNAME/../bats_assertions.py"
}

@test "an assertion before a later command is mid, even past an unbalanced brace" {
  grep -q 'printf .%s. "{"' "$FIX/brace.bats"          # fixture carries the property
  run python3 "$SCRIPT" "$FIX/brace.bats"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | awk -F'\t' '$3=="brace in a string" && $4=="mid"' | grep -q .
  printf '%s\n' "$output" | awk -F'\t' '$3=="assertion is last" && $4=="final"' | grep -q .
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
}

@test "a trailing function definition does not make the last assertion mid" {
  grep -q '^helper_defined_after()' "$FIX/trailing-helper.bats"
  run python3 "$SCRIPT" "$FIX/trailing-helper.bats"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | awk -F'\t' '$3=="ends with an assertion" && $4=="final"' | grep -q .
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
}

@test "assertion text inside a heredoc is not inventoried" {
  grep -q 'not a real test' "$FIX/heredoc.bats"
  run python3 "$SCRIPT" "$FIX/heredoc.bats"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 0 ]
}
```

- [ ] **Step 3: Run the tests and confirm each fails for its own reason**

```bash
bats skills/phase-workflow/tests/bats-assertions.bats
```

Expected: all three FAIL naming the missing script. A bats parse error in the test file or a
fixture is a harness red and does not count.

- [ ] **Step 4: Astra implements**

Constraint, not code. Determine each test's extent without counting braces. Skip lines inside a
heredoc: track an opening `<<'WORD'`/`<<WORD` and ignore everything to its terminator. A test's
body ends at the next `@test`, at a top-level function definition, or at end of file. An
assertion is a line whose first token is `[[`; it is `final` when no later *command* in that body
follows, where blank lines, `#` comments and heredoc content are not commands. Report a compound
line carrying `[[` after a `;` as mid unless the `[[` is last on it.

- [ ] **Step 5: Run the tests and confirm they pass**

- [ ] **Step 6: Mutation-check the new helper** (F-30)

The reds above were missing-script reds, which do not discharge §3 step 3. Commit first, then
break the heredoc skip in place and confirm the heredoc test fails on its named assertion:

```bash
SHA="$(git rev-parse HEAD)"
bash skills/phase-workflow/mutation-restore.sh "$SHA" \
  skills/phase-workflow/bats_assertions.py 's/in_heredoc/False and in_heredoc/' \
  bats skills/phase-workflow/tests/bats-assertions.bats
```

Inspect the output for the heredoc test's assertion. Exit 1 alone is not sufficient.

- [ ] **Step 7: `/simplify`, re-run, commit**

```bash
git add skills/phase-workflow/bats_assertions.py skills/phase-workflow/tests/
git commit -m "$(cat <<'MSG'
feat(phase-workflow): enumerate bats [[ ]] assertions and their position

KI-45 needs to know which assertions sit mid-test before any can be
converted. Brace-depth parsing breaks on embedded python and ${...}, and
heredoc content must not be inventoried as test code.

Implemented by gpt-6-astra at effort=max.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
MSG
)"
```

---

## Task 2: Verify one converted assertion is load-bearing

**Files:**

- Create: `skills/phase-workflow/verify_assertions.sh`
- Test: `skills/phase-workflow/tests/verify-assertions.bats`

**Interfaces:**

- Consumes: `bats_assertions.py` from Task 1.
- Produces: `verify_assertions.sh <task-sha> <repo-relative-file> <line> <test-name>` -> one line,
  `RED`, `GREEN`, or `REFUSED <reason>`. Exit 0 only for `RED`.

**What this establishes, and what it does not.** Negating an assertion and watching its test fail
proves the assertion is **load-bearing** — that a false result stops the test. It does **not**
prove the conversion preserved the original meaning: `[ 1 -eq 1 ]` substituted for
`[[ "$output" == "x" ]]` leaves the suite green and still earns `RED` when negated (F-07). No
mechanical check catches that; only diff review does. So this harness does not by itself
discharge §3 step 3, whose requirement is to break "the specific behaviour the test names".
Meaning preservation is established by review of the conversion diff, and the phase record says so.

**Exit 0 from `mutation-restore.sh` is not `RED`.** That script's own final message is
`EXIT 1 — verify the named failure in the output before certifying`, and bats returns 1 for
fixture failures too (F-08). The wrapper must additionally confirm the bats output names the
target test and reports a failure at the target line.

- [ ] **Step 1: Write the failing tests**

Fixtures live in a committed scratch repository, because `mutation-restore.sh` requires the target
present at the SHA and addressed repo-relative (F-24), and `$SHA` must be set (F-25).
`bats -f` takes an unanchored regex, so the name is anchored and quoted (F-26).

```bash
setup() {
  export TEST_TMP="$(mktemp -d)"
  export REPO="$TEST_TMP/repo"; mkdir -p "$REPO/t"
  SCRIPT_SRC="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/verify_assertions.sh"
  cd "$REPO"; git init -q -b main .
  git config user.email t@example.invalid; git config user.name Test
  cp "$SCRIPT_SRC" ./verify_assertions.sh 2>/dev/null || touch ./verify_assertions.sh
  cat > t/vac.bats <<'FIXTURE'
@test "vacuous" {
  [[ "a" == "b" ]]
  [ 1 -eq 1 ]
}
FIXTURE
  cat > t/real.bats <<'FIXTURE'
@test "loadbearing" {
  [ "a" = "a" ]
  [ 1 -eq 1 ]
}
FIXTURE
  git add -A && git commit -qm base
  export SHA="$(git rev-parse HEAD)"
}
teardown() { cd /; rm -rf "$TEST_TMP"; }

@test "a mid-test [[ ]] assertion is GREEN because negating it cannot fail its test" {
  run bats t/vac.bats
  [ "$status" -eq 0 ]                       # the fixture really is vacuous before we verify it
  run bash ./verify_assertions.sh "$SHA" t/vac.bats 2 vacuous
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^GREEN'
}

@test "a converted assertion is RED because negating it fails its test" {
  run bash ./verify_assertions.sh "$SHA" t/real.bats 2 loadbearing
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^RED'
}

@test "a fixture error under mutation is REFUSED, not RED" {
  cat > t/broken.bats <<'FIXTURE'
@test "needs a missing helper" {
  load nonexistent_helper
  [ "a" = "a" ]
}
FIXTURE
  git add -A && git commit -qm broken
  SHA2="$(git rev-parse HEAD)"
  run bash ./verify_assertions.sh "$SHA2" t/broken.bats 3 'needs a missing helper'
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^REFUSED'
}
```

- [ ] **Step 2: Run all three and confirm each fails for its own reason**

The first test's `run bats t/vac.bats` must pass before the verifier is called — that is what
establishes the fixture is genuinely vacuous. The third is the F-08 arm: bats exits 1 for the
missing `load`, and a wrapper that reads exit status alone would call it `RED`.

- [ ] **Step 3: Astra implements**

Constraint: call `mutation-restore.sh` for the mutation, the run and the restore; add no mutation
logic. Negate only the operator at `<line>`. Pass `bats -f "^<test-name>$" <file>` as the test
command, with the name regex-escaped. Treat `mutation-restore.sh` exit 0 as `RED` **only** when
the captured bats output names the target test and reports a failure at `<line>`; otherwise
`REFUSED` with the reason. Distinguish `GREEN` (test passed under mutation) from `REFUSED` by that
script's message rather than collapsing both into exit 1.

- [ ] **Step 4: Run all three and confirm they pass**

- [ ] **Step 5: Mutation-check the new helper** (F-30)

Commit, then remove the output check in place and confirm the third test fails on its `REFUSED`
assertion.

- [ ] **Step 6: `/simplify`, re-run, commit**

---

## Task 3: Baseline inventory, and correct KI-45's figures

**Files:**

- Modify: `docs/KNOWN_ISSUES.md` (the KI-45 entry's three counts)
- Create: `docs/superpowers/plans/phase-1-assertion-inventory.tsv` — a **pre-conversion**
  snapshot. After the conversion the same command reports 0 `mid` rows, which is the standing
  regression check; the file is kept as the record of what was measured, not as current state.

**Interfaces:**

- Consumes: `bats_assertions.py`.
- Produces: the authoritative per-suite mid-test count that Tasks 4 and 5 divide.

- [ ] **Step 1: Run the enumerator over the four in-scope skills**

```bash
python3 skills/phase-workflow/bats_assertions.py \
  skills/{claude-setup,design-review,external-review,phase-workflow}/tests/*.bats \
  | tee docs/superpowers/plans/phase-1-assertion-inventory.tsv | awk -F'\t' '$4=="mid"' | wc -l
```

The new `tests/fixtures/*.bats` files are deliberately **not** globbed: they are fixture data, not
suites, and inventorying them would convert this phase's own negative controls (F-09).

- [ ] **Step 2: (deleted — out of scope)**

`claude-toggle-backend` is held and being rebuilt, so its tests are replaced rather than
repaired and a baseline count of them has no consumer. KI-45 records that exclusion in words
instead of a number. The two enumerator defects this step originally surfaced were repaired on
their own merits and are listed under Task 1.

- [ ] **Step 3: Correct the KI-45 entry**

Replace its three counts with the measured ones, name this tool as how the count is obtained, and
state that the entry stays open at reduced scope for `claude-toggle-backend` only. Do not call the
old numbers wrong without saying what produced the new ones.

- [ ] **Step 4: Verify and commit**

```bash
python3 skills/phase-workflow/roadmap.py check || exit 1
markdownlint-cli2 --config ~/.markdownlint.jsonc docs/KNOWN_ISSUES.md
```

---

## Tasks 4 and 5: Convert the assertions — calibration dropped

**What was planned:** two tranches, `medium` and `max`, to compare Astra's defect rate.

**What happened, and why it changed.** The conversion turned out to be a single-line append —
`[[ ... ]] || false` — chosen because it leaves the expression untouched and so cannot change an
assertion's meaning. Rewriting each into `grep -q` was the alternative and would have narrowed
every pattern spanning newlines. Two consequences followed:

1. A `medium`-versus-`max` comparison on a per-line append would measure nothing. F-16 had
   already reduced the calibration to descriptive-only; this removed what was left.
2. Tasks 4 and 5 edit test files exclusively, and the authorship split makes tests Claude's.
   Having Astra write them contradicted it.

The user dropped the calibration. Claude converted all 68 in one pass, per suite, and verified
each one.

**Result.** 68 of 68 load-bearing: 66 proven by `verify_assertions.sh`, 2 by hand after
falsifying every branch of a disjunction the single-operator mutation could not falsify — which
exposed the tool reporting `GREEN` for a verdict it had not earned, fixed under Task 2.

One suite went red once its assertions were evaluated. `preflight.bats:127` could never have
passed: its glob matched `codex` on one line and `gemini ... READY` on the next. `preflight.sh`
was correct.

---

## Task 6: KI-46 — delete a branch whose commits are on the remote, retain everything else

**Files:**

- Modify: `skills/phase-workflow/SKILL.md` §4 step 7
- Modify: `skills/phase-workflow/publish-release.sh`
- Modify: `docs/KNOWN_ISSUES.md` — KI-46's "Notes for a fix" recommends `git cherry`, which is wrong
- Test: `skills/phase-workflow/tests/phase-git.bats`

**Interfaces:**

- Consumes: `APPROVED_SHA`, already confirmed equal to `MERGED_HEAD` and `REMOTE_HEAD` earlier in §4.
- Produces: the retain rule, unchanged in meaning, resting on branch identity rather than ancestry.

**`git cherry` is wrong in both directions, and was measured.** A two-commit branch squash-merged
gives `+` for both commits with an empty tree diff, so it would be retained forever. A branch whose
unique work is a merge commit with both parents upstream gives *empty* `cherry` output with a
non-empty tree diff, so it would be **deleted although it holds work nothing else has** (F-01).
KI-46's note claims `git cherry` "discriminates correctly" and was "Verified both ways"; that
verification used a one-commit branch. The note is corrected in this task.

**Changing the test alone cannot work.** The action is `xargs git branch -d`, which refuses a
squash-merged branch whatever the guard concluded (F-02). The chosen resolution:

```bash
if [ "$(git rev-parse "$b")" = "$APPROVED_SHA" ]; then
    git branch -D "$b"                      # commits proven present on the remote
elif git branch -d "$b"; then
    :                                       # ordinary merge or rebase
else
    echo "RETAINED — holds commits absent from $DEFAULT_BRANCH"; exit 1
fi
```

`-D` is reached only where §4 has already confirmed `MERGED_HEAD = APPROVED_SHA` **and**
`REMOTE_HEAD = APPROVED_SHA`, so a branch still at that tip can discard nothing. The block's bolded
**Never -D here** becomes **never `-D` except at a tip already confirmed on the remote**, and the
reason moves into the comment.

- [ ] **Step 1: Write the four failing tests**

The suite supplies `$REPO`, `$FORK`, `$PUBLISH` and `$TASK_SHA`; there is no `$R` or `$CLEANUP`
(F-06). The fence takes no arguments and reads `git for-each-ref` from the working directory, and
it only inspects branches whose `%(upstream:track)` is `[gone]` — so the fixture must set an
upstream and then delete it from the fork (F-15). Files are written with `git -C` or from inside
`$REPO` (F-05), and `$output` is read before any later `run` overwrites it (F-20).

```bash
extract_cleanup() {
  python3 - "$(dirname "$PUBLISH")/SKILL.md" "$TEST_TMP/cleanup.sh" <<'PY'
import pathlib,re,sys
blocks=re.findall(r'```bash\n(.*?)```',pathlib.Path(sys.argv[1]).read_text(),re.S)
pathlib.Path(sys.argv[2]).write_text(next(b for b in blocks if 'GONE=' in b))
PY
}

land_and_orphan() {            # $1 = branch, $2... = commit subjects
  local b="$1"; shift
  git checkout -q -b "$b"
  local n=0
  for m in "$@"; do n=$((n+1)); printf '%s\n' "$m" > "file$n"; git add -A; git commit -qm "$m"; done
  git push -q -u origin "$b"
  git checkout -q main
  git merge -q --squash "$b" && git commit -qm "squashed $b"
  git push -q origin main
  git push -q origin --delete "$b"
  git fetch -q --prune origin
}

@test "KI-46: a multi-commit squash-merged branch at the approved tip is deleted" {
  extract_cleanup
  land_and_orphan feature/multi one two
  export APPROVED_SHA="$(git rev-parse feature/multi)"
  export DEFAULT_BRANCH=main
  # fixture properties: upstream gone, more than one commit, tree already equal
  [ "$(git for-each-ref --format='%(upstream:track)' refs/heads/feature/multi)" = '[gone]' ]
  [ "$(git rev-list --count main..feature/multi)" -eq 2 ]
  [ -z "$(git diff feature/multi main)" ]
  run git branch -d feature/multi
  [ "$status" -ne 0 ]                        # confirms -d alone cannot do this
  run bash "$TEST_TMP/cleanup.sh"
  [ "$status" -eq 0 ]
  run git rev-parse --verify feature/multi
  [ "$status" -ne 0 ]
}

@test "KI-46: a branch holding an unmerged commit is retained with the reason" {
  extract_cleanup
  git checkout -q -b feature/un
  printf 'x\n' > u; git add -A; git commit -qm unique
  git push -q -u origin feature/un
  git push -q origin --delete feature/un
  git fetch -q --prune origin
  export APPROVED_SHA="$TASK_SHA" DEFAULT_BRANCH=main
  git checkout -q main
  [ -n "$(git diff feature/un main)" ]
  run bash "$TEST_TMP/cleanup.sh"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'RETAINED'
  run git rev-parse --verify feature/un
  [ "$status" -eq 0 ]
}

@test "KI-46: a branch whose unique work is a merge commit is retained" {
  extract_cleanup
  git checkout -q -b side; printf 's\n' > s; git add -A; git commit -qm side
  git checkout -q main;   printf 'm\n' > m; git add -A; git commit -qm mainward
  git push -q origin main
  git checkout -q -b feature/mc side
  git merge -q --no-ff main -m "merge with resolution"
  printf 'resolved\n' > s; git add -A; git commit -q --amend --no-edit
  git push -q -u origin feature/mc; git push -q origin --delete feature/mc
  git fetch -q --prune origin
  export APPROVED_SHA="$TASK_SHA" DEFAULT_BRANCH=main
  git checkout -q main
  # the arm git cherry gets wrong: it reports nothing unique for a merge commit
  [ -z "$(git cherry main feature/mc)" ]
  [ -n "$(git diff feature/mc main)" ]
  run bash "$TEST_TMP/cleanup.sh"
  [ "$status" -ne 0 ]
  run git rev-parse --verify feature/mc
  [ "$status" -eq 0 ]
}

@test "KI-46: an ordinary merged branch is still deleted by -d" {
  extract_cleanup
  git checkout -q -b feature/ff; printf 'f\n' > f2; git add -A; git commit -qm ff
  git push -q -u origin feature/ff
  git checkout -q main; git merge -q --no-ff feature/ff -m "merge ff"
  git push -q origin main; git push -q origin --delete feature/ff
  git fetch -q --prune origin
  export APPROVED_SHA="$TASK_SHA" DEFAULT_BRANCH=main
  run bash "$TEST_TMP/cleanup.sh"
  [ "$status" -eq 0 ]
  run git rev-parse --verify feature/ff
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run all four and confirm each fails for its own reason**

Arm 1 must fail because the branch was **retained**, and its `run git branch -d` precondition must
have failed first — that is what proves `-d` cannot do the job. Arms 2, 3 and 4 pass on HEAD once
the harness is right; they are regression arms guarding against the fix over-deleting, and the
phase record says so rather than claiming four initial reds (F-19).

- [ ] **Step 3: Astra implements**

Constraint: the block above, in both `SKILL.md` §4 step 7 and `publish-release.sh`, which carries
the same false message. Keep the retain rule. Give the refusal the reason it retained. Reword
**Never -D here** to name the one confirmed-upstream condition that permits it, and say in the
comment why that condition makes it safe.

- [ ] **Step 4: Run the whole suite**

```bash
bats skills/phase-workflow/tests/phase-git.bats
```

- [ ] **Step 5: Correct KI-46's "Notes for a fix"**

State that `git cherry` was measured wrong in both directions, give both counterexamples, and
record the adopted test. The entry is closed in Task 9, but a closed entry whose notes recommend a
broken fix would mislead anyone reading the CHANGELOG back to it.

- [ ] **Step 6: `/simplify`, re-run, commit**

---

## Task 7: The Codex ladder returns (slug, effort) pairs

**Files:**

- Modify: `skills/external-review/SKILL.md` — the ladder fence and every `codex_ladder` consumer
- Modify: `skills/external-review/preflight.sh` — it receives the ladder and hardcodes its own effort
- Test: `skills/external-review/tests/codex-root.bats`, `skills/external-review/tests/preflight.bats`

**Interfaces:**

- Consumes: nothing.
- Produces: `codex_ladder()` -> lines of `slug:effort`, strongest first.
  `preflight.sh --codex-model <slug>:<effort>` probes at that effort.

**Why this is untested today.** `codex-root.bats:164` stubs `codex_ladder() { echo fixture-model; }`,
so the real function has never run under test. That is why both defects survived.

**`preflight.sh` is in scope.** The SKILL.md fence forwards rungs as `--codex-model "$m"`, and
`preflight.sh:112-113` then runs `-m "$model" -c model_reasoning_effort="high"`. Passing a pair
unchanged yields an invalid model id; stripping the effort makes the probe check a different effort
from the review it is clearing (F-13).

- [ ] **Step 1: Write the failing tests**

Three failure conditions:

- *fails if two models tied on `priority` resolve by their order in the cache file*
- *fails if a rung omits its effort*
- *fails if `preflight.sh` probes at an effort other than the one in the rung*

The fixture goes at `$TEST_TMP/.codex/models_cache.json`, because the function reads
`$HOME/.codex/models_cache.json` (F-04). The extraction helper is defined, not assumed (F-22), and
order is asserted rather than mere presence — `grep -q 'model-a:max'` also passes when `model-b`
comes first, which is the property under test (F-21).

```bash
extract_ladder() {
  python3 - "$SKILL" <<'PY'
import pathlib,re,sys
blocks=re.findall(r'```bash\n(.*?)```',pathlib.Path(sys.argv[1]).read_text(),re.S)
print(next(b for b in blocks if 'codex_ladder()' in b))
PY
}

@test "a priority tie does not resolve by file order, and each rung carries its effort" {
  mkdir -p "$TEST_TMP/.codex"
  cat > "$TEST_TMP/.codex/models_cache.json" <<'JSON'
{"models":[
 {"slug":"model-b","visibility":"list","priority":1,"default_reasoning_level":"low",
  "supported_reasoning_levels":[{"effort":"low"},{"effort":"max"}]},
 {"slug":"model-a","visibility":"list","priority":1,"default_reasoning_level":"low",
  "supported_reasoning_levels":[{"effort":"low"},{"effort":"max"}]}]}
JSON
  # fixture property: the tie exists and file order puts model-b first
  [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["models"][0]["slug"])' \
        "$TEST_TMP/.codex/models_cache.json")" = "model-b" ]
  run bash -c "$(extract_ladder); HOME='$TEST_TMP' codex_ladder"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n 1p)" = "model-a:max" ]   # order, not presence
  [ "$(printf '%s\n' "$output" | sed -n 2p)" = "model-b:max" ]
}

@test "ultra is never selected as a rung" {
  mkdir -p "$TEST_TMP/.codex"
  cat > "$TEST_TMP/.codex/models_cache.json" <<'JSON'
{"models":[{"slug":"model-u","visibility":"list","priority":1,"default_reasoning_level":"low",
 "supported_reasoning_levels":[{"effort":"max"},{"effort":"ultra"}]}]}
JSON
  grep -q ultra "$TEST_TMP/.codex/models_cache.json"
  run bash -c "$(extract_ladder); HOME='$TEST_TMP' codex_ladder"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'model-u:max'
  printf '%s\n' "$output" | grep -qv ultra
}

@test "preflight probes at the effort named in the rung" {
  mkdir -p "$TEST_TMP/bin"
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" > "%s/args"\necho ready\n' "$TEST_TMP" \
    > "$TEST_TMP/bin/codex"
  chmod +x "$TEST_TMP/bin/codex"
  PATH="$TEST_TMP/bin:$PATH" run bash "$PREFLIGHT" --codex-model model-a:medium --timeout 30
  grep -q 'model_reasoning_effort=medium' "$TEST_TMP/args"
  grep -qv 'model_reasoning_effort=high' "$TEST_TMP/args"
  grep -q '^model-a$' "$TEST_TMP/args"
}
```

- [ ] **Step 2: Run all three and confirm each fails for its own reason**

Test 1 must fail on the order assertion, not on a missing cache. Test 3 must fail because
`preflight.sh` sends `high`, not because `codex` was absent.

- [ ] **Step 3: Astra implements**

Constraint: emit `slug:effort`, strongest first, choosing the highest supported effort that is not
`ultra` — `ultra` delegates tasks automatically, so the diff may not come from the model recorded
against it. Break a `priority` tie deterministically and not by file order. Split the pair in every
consumer, including `preflight.sh`, and pass both `-m "$slug"` and
`-c model_reasoning_effort="$effort"`. Accept a bare slug in `preflight.sh` for compatibility only
if a test pins the default it then uses. Hardcode no model name anywhere.

- [ ] **Step 4: Run both suites; mutation-check; `/simplify`; re-run; commit**

---

## Task 8: A reviewer that authored the diff is not a reviewer

**Files:**

- Modify: `skills/external-review/SKILL.md` — preflight and coverage classification
- Test: `skills/external-review/tests/preflight.bats`

**Interfaces:**

- Consumes: nothing.
- Produces: `--authored-by <reviewer>` excludes that reviewer and downgrades the coverage line.

**The rule today runs one way only.** It says a second opinion from the same model is not a second
opinion, and it names Claude. It must hold for any author: when Astra writes the diff, Codex is the
author and not a reviewer of it.

**The fixture needs both reviewers answering.** Under the current matrix one successful reviewer
already reports *partial*, so an assertion that coverage is "not full" passes on HEAD and is no red
at all (F-14). And excluding the sole author should yield **no coverage**, not partial.

- [ ] **Step 1: Write the failing tests**

Failure conditions:

- *fails if a pass reports full coverage when one of the two answering reviewers authored the diff*
- *fails if excluding the only answering reviewer reports partial rather than no coverage*
- *fails if an excluded reviewer is reported as unavailable rather than disqualified*

```bash
@test "an authoring reviewer does not count toward coverage" {
  stub_reviewer codex ready; stub_reviewer agy ready       # BOTH answer
  run bash "$PREFLIGHT" --codex-model m:max --gemini-model g-high --timeout 30 --authored-by codex
  printf '%s\n' "$output" | grep -q 'Partial coverage'
  printf '%s\n' "$output" | grep -qv 'Full coverage'
}

@test "excluding the only answering reviewer is no coverage, not partial" {
  stub_reviewer codex ready; stub_reviewer agy missing
  run bash "$PREFLIGHT" --codex-model m:max --gemini-model g-high --timeout 30 --authored-by codex
  printf '%s\n' "$output" | grep -q 'No coverage'
}

@test "an excluded reviewer is reported as the author, not as unavailable" {
  stub_reviewer codex ready; stub_reviewer agy ready
  run bash "$PREFLIGHT" --codex-model m:max --gemini-model g-high --timeout 30 --authored-by codex
  printf '%s\n' "$output" | grep -qi 'author'
  printf '%s\n' "$output" | grep -qvi 'codex.*unavailable'
}
```

`stub_reviewer` is the suite's existing helper pattern; where it does not exist, add it in this task
rather than inlining three copies.

- [ ] **Step 2: Run all three and confirm each fails for its own reason**

Test 1 must fail because HEAD reports full coverage with both reviewers ready — `--authored-by` does
not exist yet, so confirm the red is an unrecognised-flag error only if the flag is rejected loudly;
if `preflight.sh` ignores unknown flags silently, the red is the coverage assertion, which is the
one that counts.

- [ ] **Step 3: Astra implements**

Constraint: state the rule symmetrically, as a property of the diff's author rather than of Claude.
An excluded reviewer is neither unavailable nor failed: record it as disqualified with the reason,
so the coverage line distinguishes a reviewer that could not run from one that was barred.

- [ ] **Step 4: Run the suite; mutation-check; `/simplify`; re-run; commit**

---

## Task 9: Roadmap and changelog

**Files:**

- Modify: `docs/KNOWN_ISSUES.md`, `docs/ROADMAP.md`, `docs/OPEN_QUESTIONS.md`,
  `docs/superpowers/specs/2026-09-16-plugin-fix-program-design.md`, `CHANGELOG.md`, `CLAUDE.md`

- [ ] **Step 1: File KI-47 to KI-51 from the spec, and KI-52 from this review**

Each gets a full entry and a ROADMAP pointer row together. Ratings: KI-47 High/Almost always,
KI-48 High/Almost always, KI-49 Medium/Almost always, KI-50 Medium/Likely, KI-51 Medium/Likely.
Source line names `gpt-6-astra` and the archived report path.

**KI-52 — mid-test `[[ ]]` vacuity may depend on the bash version.** Medium/Likely. On this machine
(bash 3.2.57, bats 1.14.0) a false mid-test `[[ ]]` passes and a false mid-test `[ ]` fails, exactly
as KI-45 describes. Codex asserts modern bash stops the test, which would make the vacuity — and any
verification predicting a red — host-dependent, which §3 step 3 forbids. Record the measurement,
both bash versions, and the open decision on pinning the interpreter (F-32).

- [ ] **Step 2: Close KI-45 and KI-46** (F-18)

Both are fixed in this phase. Delete each entry and its ROADMAP pointer row, and write the record
into CHANGELOG `[Unreleased]`. KI-45 closes at reduced scope: note that `claude-toggle-backend`'s
mid-test assertions remain unconverted and are held, and carry that residue into KI-52's entry
rather than leaving KI-45 open for it.

- [ ] **Step 3: Close UNK-02**

Delete its entry and its ROADMAP row. Add one line to "Decisions taken and not taken" in
`CLAUDE.md` recording that the mutation check replaces the need for historical red-state evidence.

- [ ] **Step 4: Correct the spec** (F-16, F-17)

Two errors found in review. Its Open items 1 names `local-models` and `drive-backup` as held bats
suites; neither has any bats file, so only `claude-toggle-backend` holds the residue and the
"22 remaining" figure is replaced by Task 3's measurement. Its calibration section claims the
tranche comparison "sets the rung rule for phases 2 to 6 on evidence" — withdraw that and keep the
comparison as descriptive.

- [ ] **Step 5: Correct the two stale CHANGELOG claims**

The ladder does not "top out at `gpt-6-astra`" — nothing in the cache ranks it above `sol`, and both
sit at `priority: 1`. "Every listed model supports low through max" is wrong for `gpt-5.6-luna` and
`gpt-5.5`. A released section is never edited, so correct these as new `[Unreleased]` entries that
state what the earlier claim got wrong.

- [ ] **Step 6: Write the `[Unreleased]` entries for this phase**

- [ ] **Step 7: Verify and commit**

```bash
python3 skills/phase-workflow/roadmap.py check || exit 1
markdownlint-cli2 --config ~/.markdownlint.jsonc docs/*.md docs/superpowers/**/*.md CHANGELOG.md CLAUDE.md
```

**A bulk edit to a structured file is verified against that structure.** After the ROADMAP rows
land, re-read the severity and likelihood columns and confirm rows are still ordered
most-severe-first within each severity, and that every deleted ID is gone from both files. Lint
checks formatting, not ordering.

---

## External review findings

```text
Codex gpt-6-astra (max) 8 · Gemini gemini-3.8-flash-high 16 · 11 overlapping → 32 unique findings
```

Full coverage: both reviewers returned non-empty findings. No Gemini Pro tier exists on this
account, so the Gemini rung is `gemini-3.8-flash-high` rather than a pro model.

All 32 are incorporated. Three changed the plan's *approach* rather than its detail: F-01 and
F-02 replaced the KI-46 fix method and its deletion command (the user chose `-D` only at a tip
already confirmed on the remote), F-07 narrowed what the KI-45 harness claims to establish, and
F-16 withdrew the spec's claim that the calibration sets later phases' rung rule.

| # | Finding | Files | Model | Likelihood | Severity | Verdict | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F-01 | `git cherry` both retains landed work and deletes unique work | `docs/KNOWN_ISSUES.md` KI-46, plan Task 6 | gpt-6-astra, gemini-3.8-flash-high | Almost always | Critical | Confirmed | Incorporated — Task 6 rewritten |
| F-02 | Changing only the test leaves the action as `git branch -d`, which refuses a squash merge regardless | `skills/phase-workflow/SKILL.md:425-427` | gpt-6-astra | Almost always | Critical | Confirmed | Incorporated — Task 6, `-D` at confirmed tip |
| F-03 | Task 8 supplies no test, only prose | plan Task 8 | gpt-6-astra, gemini-3.8-flash-high | Almost always | Critical | Confirmed | Incorporated — test written |
| F-04 | Task 7 fixture written to `$TEST_TMP/cache.json`; the function reads `$HOME/.codex/models_cache.json` | plan Task 7 | gpt-6-astra, gemini-3.8-flash-high | Almost always | Critical | Confirmed | Incorporated — fixture path corrected |
| F-05 | Task 6 fixtures write outside `$R`, so no commit is made and the test dies early | plan Task 6 | gemini-3.8-flash-high | Almost always | Critical | Confirmed | Incorporated — rewritten |
| F-06 | Task 6 uses `$R`/`$CLEANUP`; the suite supplies `$REPO`/`$PUBLISH`, and the fence takes no positional arguments | plan Task 6, `skills/phase-workflow/tests/phase-git.bats` | gpt-6-astra, gemini-3.8-flash-high | Almost always | Critical | Confirmed | Incorporated — rewritten |
| F-07 | Negating an assertion proves it can fail, not that it preserves meaning; `[ 1 -eq 1 ]` earns `RED` | plan Task 2, Testing Strategy | gpt-6-astra | Almost always | High | Confirmed | Incorporated — Task 2 claim narrowed |
| F-08 | Mapping `mutation-restore.sh` exit 0 to `RED` ignores its own instruction to verify the named failure | plan Task 2, `skills/phase-workflow/mutation-restore.sh:115` | gpt-6-astra, gemini-3.8-flash-high | Almost always | High | Confirmed | Incorporated — output check added |
| F-09 | The enumerator's boundary rule reads heredoc fixture text as real tests, including this plan's own new fixtures | plan Task 1, Task 3 | gpt-6-astra | Almost always | High | Confirmed | Incorporated — heredoc condition added |
| F-10 | HEAD counterexample: a final assertion followed by a helper function outside its test is classified mid | `skills/phase-workflow/tests/phase-git.bats:289-310` | gpt-6-astra | Almost always | High | Confirmed | Incorporated — second fixture arm |
| F-11 | Inventory line numbers are recorded pre-conversion; conversions shift lines, so mutations hit the wrong line | plan Tasks 4-5 | gpt-6-astra, gemini-3.8-flash-high | Almost always | High | Confirmed | Incorporated — re-enumerate after commit |
| F-12 | The conversion loop's `break` exits 0, so a failed verification skips the rest without failing | plan Tasks 4-5 | gpt-6-astra | Almost always | High | Confirmed | Incorporated — explicit failure status |
| F-13 | `preflight.sh` consumes the ladder and hardcodes `model_reasoning_effort="high"`; absent from Task 7 | `skills/external-review/preflight.sh:112-113` | gpt-6-astra, gemini-3.8-flash-high | Almost always | High | Confirmed | Incorporated — added to Task 7 |
| F-14 | Task 8's stated assertion passes on HEAD; one successful reviewer already reports partial | `skills/external-review/SKILL.md:29-33` | gpt-6-astra | Almost always | High | Confirmed | Incorporated — both reviewers answer in fixture |
| F-15 | Task 6 fixtures set no `[gone]` upstream, so the prune fence never inspects them | plan Task 6 | gpt-6-astra, gemini-3.8-flash-high | Almost always | High | Confirmed | Incorporated — upstream set and deleted |
| F-16 | The calibration cannot set the rung rule for phases 2-6; mechanical substitution does not predict semantic work | `docs/superpowers/specs/2026-09-16-plugin-fix-program-design.md:120-123` | gpt-6-astra, gemini-3.8-flash-high | Almost always | High | Confirmed | Incorporated — Task 9 step 4 |
| F-17 | The spec names `local-models` and `drive-backup` as held bats suites; neither has any bats file | spec Open items 1 | gemini-3.8-flash-high | Almost always | High | Confirmed | Incorporated — spec corrected |
| F-18 | Task 9 never schedules closing KI-45 and KI-46 or removing their ROADMAP pointers | plan Task 9 | gpt-6-astra | Almost always | Medium | Confirmed | Incorporated — steps added |
| F-19 | Task 6's `branch --contains` on an empty listing exits 0, failing the assertion before cleanup runs | plan Task 6 | gpt-6-astra | Almost always | Medium | Confirmed | Incorporated — rewritten |
| F-20 | Task 6's retention arm: a second `run` overwrites `$output`, so `grep RETAINED` fails even on correct retention | plan Task 6 | gpt-6-astra | Almost always | Medium | Confirmed | Incorporated — order corrected |
| F-21 | Task 7's assertions accept the wrong order; the test never checks the property it names | plan Task 7 | gpt-6-astra | Almost always | Medium | Confirmed | Incorporated — order asserted |
| F-22 | Task 7 calls an undefined `extract_ladder_fence` helper | plan Task 7 | gpt-6-astra | Almost always | Medium | Confirmed | Incorporated — helper defined |
| F-23 | Task 1's `"${UNCLOSED"` is an unterminated expansion, not a literal brace, and bats preprocesses nested `@test` in a heredoc | plan Task 1 | gpt-6-astra | Almost always | Medium | Confirmed | Incorporated — fixture rewritten |
| F-24 | Task 2's fixture is outside git; `mutation-restore.sh` requires the file present at the SHA and repo-relative | plan Task 2 | gpt-6-astra, gemini-3.8-flash-high | Almost always | Medium | Confirmed | Incorporated — scratch repo committed |
| F-25 | Task 2's `$SHA` is never defined | plan Task 2 | gemini-3.8-flash-high | Almost always | Medium | Confirmed | Incorporated — set in setup |
| F-26 | `bats -f` treats the name as an unanchored regex; repo test names contain metacharacters | plan Task 2 | gemini-3.8-flash-high | Likely | Medium | Confirmed | Incorporated — name anchored and quoted |
| F-27 | The loop does not re-assert a clean tree between iterations, though the Lifetime line claims it does | plan Tasks 4-5, File Structure | gemini-3.8-flash-high | Likely | Medium | Confirmed | Incorporated — check added |
| F-28 | Calibration metric contradiction: "GREEN on first verification" against "fix it and re-verify rather than recording the GREEN" | plan Tasks 4-5 | gpt-6-astra | Almost always | Medium | Confirmed | Incorporated — first-attempt outcome recorded |
| F-29 | Running Task 5 after Task 4 permits learning from the first tranche; alternation does not equalise complexity | plan Tasks 4-5 | gpt-6-astra, gemini-3.8-flash-high | Almost always | Medium | Confirmed | Incorporated — stated as a limit |
| F-30 | Missing-script reds do not discharge the per-task mutation-check obligation for the new helpers | spec, plan Tasks 1-2 | gpt-6-astra | Almost always | Medium | Confirmed | Incorporated — mutation step added |
| F-31 | The three review gaps are said to be needed "from task one" but scheduled as Tasks 7-8 | plan line 11 | gpt-6-astra, gemini-3.8-flash-high | Almost always | Medium | Confirmed | Incorporated — wording corrected |
| F-32 | Mid-test `[[ ]]` vacuity may be bash-version dependent, making the verification's prediction host-dependent | `skills/phase-workflow/SKILL.md` §3 step 3 | claude-opus-5 (verification) | Likely | Medium | Confirmed | Filed — see below |

**F-01** — *When it fires:* any phase branch with more than one commit is squash-merged, or a
branch's unique work sits in a merge commit whose parents are both upstream. *What happens:* the
first is retained forever, the second is deleted although it holds work nothing else has.
*Reviewer's fix:* Gemini — "every squash-merged branch with >1 commit is retained and never
deleted"; Codex — compare "resulting trees" rather than per-commit patches.
*Commentary:* verified both directions in a scratch repo. A two-commit squash merge gives
`+` for both commits with an empty tree diff; a merge commit holding unique resolution gives
empty `cherry` output with a non-empty tree diff. KI-46's own note says `git cherry`
"discriminates correctly" and was "Verified both ways" — that verification used a one-commit
branch, so the entry is wrong and needs correcting alongside the fix.

**F-02** — *When it fires:* every squash-merged phase. *What happens:* the guard is fixed and
the branch still is not deleted, because `git branch -d` refuses it whatever the guard concluded.
*Reviewer's fix:* Codex — the plan "does not explain how a squash-merged branch gets removed when
the existing action remains `xargs git branch -d`". *Commentary:* correct, and it is the reason
F-01 alone is not a fix. KI-46's own strongest suggestion resolves it: the block has already
confirmed `MERGED_HEAD = APPROVED_SHA` and `REMOTE_HEAD = APPROVED_SHA`, so a branch still at
`APPROVED_SHA` holds nothing absent from the remote. That makes `-D` safe *under that specific
condition* — but the block bolds **Never -D here**, so this is the user's call, not mine.

**F-07** — *When it fires:* any conversion that changes what the assertion means while leaving it
able to fail. *What happens:* the verification certifies it, because negation still produces a
red. *Reviewer's fix:* Codex — §3 step 3 requires breaking "the specific behaviour the test
names", and negation does not establish that. *Commentary:* confirmed by construction: replacing
`[[ "$output" == "x" ]]` with `[ 1 -eq 1 ]` leaves the suite green and earns `RED` on negation.
No mechanical check catches this; only diff review does. The plan must stop claiming the harness
discharges §3 step 3 and say what it actually establishes — that the assertion is now
load-bearing.

**F-16** — *When it fires:* whenever the tranche result is used to choose a rung for phases 2-6.
*What happens:* a rung rule is set from a task type with no bearing on the work it governs.
*Reviewer's fix:* Gemini — "mechanical syntax replacement in bats scripts has zero predictive
validity for complex semantic tasks"; Codex — "It cannot isolate an effort effect or establish a
general defect rate for later phases." *Commentary:* both are right, and the plan already
contradicts the spec on this point in Task 5 step 5. Keep the calibration as a descriptive
comparison of two tranches and delete the spec's claim that it sets the rule for later phases.

**F-32** — *When it fires:* the suite runs under a bash where a false mid-test `[[ ]]` does stop
the test. *What happens:* the vacuity KI-45 describes is absent, and any verification predicting
a red gets a different answer on that host. *Commentary:* found while checking Codex's claim that
"Modern Bash fails the fixture's false `[[ ]]`". On this machine — bash 3.2.57, bats 1.14.0 — a
false mid-test `[[ ]]` passes, a false mid-test `[ ]` fails, and KI-45's diagnosis holds exactly.
Codex's claim is therefore wrong here but may hold under bash 5. That matters because §3 step 3
forbids a mutation "whose predicted outcome depends on the machine the suite runs on". Needs a
`KI-nn` recording the host dependence and a decision on whether to pin the interpreter.

## Testing Strategy

- **Per task:** the red test precedes the fix, and the red is confirmed to be the named failure
  and not an import, collection or fixture error.
- **Per assertion in Tasks 4 and 5:** `verify_assertions.sh` establishes that each converted
  assertion is **load-bearing** — that a false result stops its test. It does not establish that
  the conversion preserved the assertion's meaning, which only review of the conversion diff can
  (F-07). §3 step 3 is discharged by the two together, and the phase record says which part came
  from which.
- **Full suite before hand-off:** `bats skills/*/tests/*.bats` across all four in-scope skills,
  reported with counts rather than asserted green.
- **Not covered:** `claude-toggle-backend`'s mid-test assertions, which move to KI-52 rather than
  keeping KI-45 open. `ultra` as a rung is deliberately unexercised. Whether the vacuity holds
  under bash 5 is unmeasured on this machine and is KI-52's open question.
