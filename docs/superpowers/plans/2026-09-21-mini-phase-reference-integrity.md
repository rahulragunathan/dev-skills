# Mini phase — reference integrity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** make a roadmap reference verifiable by machine, and settle whether the mid-test `[[ ]]`
evidence phase 1 gathered is host-dependent.

**Architecture:** `roadmap.py check` gains a second pass, separate from `reconcile`, that parses
each entry's `**Where:**` field, resolves every `../` link in it, and confirms the greppable
fragment beside each one still appears in the file it cites. The 59 `#Lnn` anchors are then
replaced by file link plus fragment. Separately, bash 5 is installed alongside the system bash and
the in-scope suites are run under each with the interpreter pinned explicitly, so KI-52's open
question is answered by measurement rather than by either model's assertion.

**Tech Stack:** Python 3 (`roadmap.py`, no dependencies), bats 1.14.0, bash 3.2.57 and bash 5.x
from Homebrew, `markdownlint-cli2`.

**Spec:** `docs/superpowers/specs/2026-09-16-plugin-fix-program-design.md`. That spec plans six
phases and does not cover this one — ENH-30 and KI-52 were both filed *during* phase 1. Task 1
adds the section, on the branch, because the spec is now a tracked file and editing it before the
branch exists would violate §2 step 1's clean-tree guard.

**Diagrams:** none. The architecture diagram names skills, not their scripts, so new functions
inside `roadmap.py` leave it factually correct. §2 step 4 is skipped, as in phase 1.

## Global Constraints

- **Five skills in scope for code changes:** `claude-setup`, `design-review`, `external-review`,
  `phase-workflow`, `project-env`. `claude-toggle-backend`, `drive-backup` and `local-models` are
  out of scope. **`project-env` has no test suite** — it is `SKILL.md` alone, which is why every
  suite command in this plan names four skills and not five.
- **46 of the 59 anchors point at those out-of-scope skills.** Converting them edits
  `docs/KNOWN_ISSUES.md` only — their files are *read* to choose a fragment and never modified.
  That is what makes ENH-30's "land all of them in one phase" satisfiable without breaking scope.
- Astra (`gpt-6-astra`) writes the production diff; Claude writes the red test first. Model slug
  and effort in every commit trailer.
- No `git reset --hard`. One commit per task, on the phase branch, pushed by the main agent.
- Markdown linted with `markdownlint-cli2 --config ~/.markdownlint.jsonc` over **every** changed
  markdown file, `skills/phase-workflow/SKILL.md` and the bundled templates included.

---

## Why this phase runs now, before phases 2 to 6

Both items are instruments the remaining four phases would otherwise be measured with.

- **ENH-30** — the documented drift check verifies "every identifier, file path, command, flag and
  config key a doc names". A line number is none of those, so it is the one reference type no gate
  can catch. Phase 1 proved the cost on itself: its own edits left KI-40 citing `SKILL.md:454-455`
  for a line then at 520-521, and KI-43 citing `preflight.sh:119` for a check at 136. Both were
  **in range**, so only reading found them.
- **KI-52** — phase 1 converted 68 assertions on measured behaviour: under bash 3.2.57 a false
  mid-test `[[ ]]` passes and a false mid-test `[ ]` fails. Astra asserts modern bash stops the
  test. If that is right, then §3 step 3's own rule — never predict a red whose outcome depends on
  the machine — applies to the evidence phase 1 collected.

**Neither is a code fix, and that is the point.** They are the two instruments phase 1 left
uncalibrated.

## The decision this plan needs

**How much must a fragment cover?** Three readings, with their measured cost:

| Rule | Fragments to write | What stays unverified |
| --- | --- | --- |
| Convert the existing anchors only | 59 | 12 entries that cite a file with nothing checked |
| One fragment per entry | 71 | 18 file links inside multi-link `**Where:**` fields |
| **One per file link (recommended)** | **89** | nothing |

**Recommended: one per file link**, because both reviewers independently attacked the weaker
readings as false greens, and they are right — one verified fragment in an entry that cites three
files reports "verified" while two references rot silently. Of the 89, 38 point inside the five
in-scope skills or the repo root and 51 do not.

Two exemptions, both forced by real entries rather than invented:

- **A link whose target is a directory is an existence-only reference and takes no fragment.**
  `ENH-04` cites `tests/fakes/` and `ENH-07` cites `claude-toggle-backend`. Without this the rule
  is unsatisfiable for them: demanding a fragment fails, and attaching one trips the
  directory rejection.
- **A fragment cannot contain a backtick.** `ENH-27`'s natural fragment is the
  ```` ```markdown ```` fence marker, quoted in the source with a four-backtick span. That entry
  picks a different distinctive string from the same file; the limit is stated in the skill rather
  than worked around in the parser.

## File Structure

Produced by `design-review plan`, then revised after external review — the reviewers' attacks on
the parser changed the unit boundaries, so the table below is the second version, not the first.
Rows are ordered most-stable-first.

| Unit | Responsibility | Interface | Depends on |
| --- | --- | --- | --- |
| `roadmap.py` · `_fenced_lines` | Mark which lines sit inside a fenced block, by delimiter char and run length | `_fenced_lines(text: str) -> list[bool]` | — |
| `roadmap.py` · `_where_field` | Return an entry's whole `**Where:**` field, continuation lines included | `_where_field(lines: list[str]) -> str` | — |
| `roadmap.py` · `_references` | Parse one field into `(target, anchor, fragment)` triples, refusing a shape it cannot parse | `_references(field: str) -> list[Ref]` | — |
| `roadmap.py` · `verify_references` | Resolve each reference and confirm its fragment still appears in the cited file | `verify_references(docs: Path) -> tuple[bool, list[str]]` | the three above, filesystem |
| `roadmap.py` · `cmd_check` | Run reconciliation and reference verification, report both | `cmd_check(docs: Path) -> int` | `reconcile`, `verify_references` |
| `phase-workflow/SKILL.md` §3 step 3 | State what the mid-test measurement showed on each interpreter | — | — |
| `docs/KNOWN_ISSUES.md`, `docs/ENHANCEMENTS.md` | Carry entry detail, anchored by fragment rather than by position | — | the source files they cite |

**Expected change:** a referenced source file gets edited. That should mean `roadmap.py check`
either stays green, because the fragment moved with its code, or fails naming the entry and the
reference — and should mean editing no roadmap file unless the cited code genuinely changed.

**Shared state:** none. Every function above takes its input and returns; nothing is held across
calls.

### Checks that fired

- **Responsibility → `reconcile` is not where this goes.** `reconcile` answers one question: does
  the index agree with the detail files. Fragment checking answers a different one — do the detail
  files agree with the source tree — and needs a reach outside `docs/` that `reconcile` has never
  had. Resolved by a separate pass, with `cmd_check` composing the two.
- **Responsibility → the parser is three jobs, not one.** The first draft put fence handling,
  field extraction, link parsing and verification in a single function. Each has its own reason to
  change: markdown fence rules, the entry format, the reference syntax, and what counts as
  verified. Resolved by the three helpers above, which is also what makes each one testable on its
  own — the reviewers' four parser findings all land on a specific helper rather than on a
  hundred-line function.
- **Surface → no new parameter.** The obvious signature is `verify_references(docs, repo_root)`,
  and it is wrong: a link in `docs/KNOWN_ISSUES.md` is written relative to the file that contains
  it, so `docs / "../skills/x"` already resolves correctly. Resolved by resolving each link
  against the doc that holds it, exactly as a markdown renderer does.
- **Variation → refuse, do not extend.** The first draft said "one regex, no registry". That was
  the wrong shape of answer: the risk is not too few syntaxes, it is a syntax the parser does not
  recognise being read as *no reference*, which is a silent false green. Resolved by making
  `_references` refuse a reference field it cannot parse, so an unrecognised shape fails loudly
  instead of passing quietly. Adding a syntax then means adding a rule and a test, which is the
  cost that should be paid.
- **Duplication → two copies, deliberately.** `verify_references` returns the same
  `(ok, problems)` shape as `reconcile`, so the accumulate-and-report idiom now appears twice.
  Three occurrences justify creating a shared home; two do not, and there is no existing home to
  move them into. Recorded so the next phase does not re-litigate it.

---

## Task 1: Land the plan, the spec section and the phase record

**Files:**

- Create: `docs/superpowers/plans/2026-09-21-mini-phase-reference-integrity.md` (this file)
- Modify: `docs/superpowers/specs/2026-09-16-plugin-fix-program-design.md`
- Modify: `docs/PHASE_RECORD.md` (overwrite — phase 1's record is closed)
- Modify: `docs/ROADMAP.md` (clear phase 1's "awaiting merge" note)

**Interfaces:**

- Consumes: nothing.
- Produces: the recorded `ORIGIN_URL`, `ORIGIN_PUSH_URL`, `REPO`, `DEFAULT_BRANCH`,
  `PHASE_BRANCH`, `MERGE_METHOD` and `PR` that §4 reads back at merge.

Phase 1's hand-off left two notes that §3 step 4 says the *next* phase clears, so that no
unreviewed commit lands on the default branch after sign-off: ROADMAP naming phase 1 as awaiting
merge, and `PHASE_RECORD.md` still describing it. Both are cleared here.

**This plan lives outside the repo until this task.** `codex-root.sh` refuses any untracked file,
and a plan drafted before the branch exists is necessarily untracked, so §1's external review
cannot run while the plan sits in `docs/superpowers/plans/`. It is drafted in `~/.claude/plans/`,
reviewed there, and moved in here.

- [ ] **Step 1: Create the branch and record the phase**

Run `phase-workflow` §2 step 1's discovery and creation blocks with `PHASE_BRANCH`
`feature/reference-integrity`, then overwrite `docs/PHASE_RECORD.md` with this phase's table
before publishing.

- [ ] **Step 2: Add the spec section**

Append a section to the programme spec, after the six-phase table, stating that ENH-30 and KI-52
were filed during phase 1, that they are instruments rather than fixes, and that they run before
phase 2 for the reason given above. Keep it short; the argument lives in this plan.

- [ ] **Step 3: Confirm ROADMAP needs no in-flight edit**

Phase 1 already made ROADMAP's Status section delegate — *"The phase in flight, and how it will
merge, is in PHASE_RECORD.md. It is not restated here."* So overwriting `PHASE_RECORD.md` is the
whole edit and ROADMAP needs none. Confirm that rather than assume it; the rest of its Status
prose is about the held rebuild work and is still true.

- [ ] **Step 4: Verify and commit**

```bash
python3 skills/phase-workflow/roadmap.py check || exit 1
markdownlint-cli2 --config ~/.markdownlint.jsonc docs/ROADMAP.md docs/PHASE_RECORD.md \
  docs/superpowers/plans/2026-09-21-mini-phase-reference-integrity.md \
  docs/superpowers/specs/2026-09-16-plugin-fix-program-design.md
git add docs/
git commit -F - <<'MSG'
docs: open the reference-integrity mini phase

<body>

Co-Authored-By: ...
MSG
```

**`git commit -F -` reads the message from stdin, so it needs the heredoc.** Without it the
command waits for input and appears to hang. A quoted `<<'MSG'` delimiter is what keeps backticks
in the body from being run as command substitution, which cost a commit in phase 1.

Then open the draft PR per §2 step 2.

---

## Task 2: Measure mid-test `[[ ]]` under bash 5 (KI-52)

**Files:**

- Create: `skills/phase-workflow/tests/fixtures/vacuity.bats`
- Modify: `skills/phase-workflow/SKILL.md` (§3 step 3, and the assertion reference section)

**Interfaces:**

- Consumes: nothing.
- Produces: the measured behaviour of a false mid-test `[[ ]]` and `[ ]` on each interpreter, and
  the `$BASH_VERSION` each measurement actually ran under.

**This task is a measurement, not a fix.** Its deliverable is two recorded results and whatever
wording they force. It **does not close KI-52** — Task 5 owns every roadmap close, because
`roadmap.py close` refuses an entry that is already gone and two owners would abort it.

`brew install bash` installs to `$(brew --prefix)/bin/bash` and does not replace `/bin/bash`, so
the system shell is untouched. **Ask before installing** — it changes the user's machine, and this
plan does not pre-authorise it.

- [ ] **Step 1: Write the fixture that carries the property under test**

A real file, never a heredoc: bats rewrites `@test` lines inside heredocs into
`bats_test_function --description ...`, which phase 1 hit twice. The fixture also records the
interpreter from *inside* the run, which is the only place that answer is trustworthy.

```bash
cat > skills/phase-workflow/tests/fixtures/vacuity.bats <<'EOF'
#!/usr/bin/env bats
#
# Fixture only, never part of the suite. Both tests assert something false in
# mid-test position; whether either fails is the measurement. The third test
# records which interpreter actually ran, because PATH order decides that and
# a version printed outside the run cannot establish it.

@test "record the interpreter" {
  echo "BASH_VERSION=$BASH_VERSION" >&3
  echo "BASH=$BASH" >&3
}

@test "a false mid-test [[ ]] is the measurement" {
  [[ 1 -eq 2 ]]
  true
}

@test "a false mid-test [ ] is the control" {
  [ 1 -eq 2 ]
  true
}
EOF
```

- [ ] **Step 2: Pin each interpreter explicitly and measure both**

**An unqualified `bats` is not the system bash.** `/opt/homebrew/bin` precedes `/bin` on this
machine — position 2 against position 11 — so once bash 5 is installed, plain `bats` runs under
it. Both arms would be bash 5 while reading as a comparison.

**And invoking the wanted bash on the bats script does not pin it either.** That was this plan's
first fix and it was wrong: `bats` re-execs `bats-exec-file` and `bats-exec-test`, each
`#!/usr/bin/env bash`, so the interpreter is resolved from `PATH` however the outer script was
started. Measured — `/bin/bash "$(command -v bats)" …` reported `BASH_VERSION=5.3.20` from inside
the run.

**Pin it by putting the wanted bash's directory first on `PATH`, then read `BASH_VERSION` from
inside the run to confirm it took.** The confirmation is not ceremony: it is what caught the
failed pinning above.

```bash
for dir in /bin "$(brew --prefix)/bin"; do
  echo "=== PATH front: $dir ==="
  PATH="$dir:$PATH" bats skills/phase-workflow/tests/fixtures/vacuity.bats
done
```

Expected under bash 3.2.57, from phase 1: the `[[ ]]` test passes, the `[ ]` test fails. The bash
5 result is the measurement. **Read `BASH_VERSION` out of each run's own output** and check it
matches the interpreter you meant to use; a mismatch invalidates that arm.

- [ ] **Step 3: Record both results and settle the wording**

Two outcomes. The plan commits to both now so the result is not argued after the fact, and both
statements are **scoped to the exact versions measured** rather than to "modern bash":

- **Same behaviour on both** — the vacuity does not differ between bash 3.2.57 and the bash 5.x
  measured here. KI-52 is answered. §3 step 3 gains one sentence naming both versions.
- **Bash 5 fails the test** — the vacuity differs by interpreter version. `SKILL.md` then states
  three separate things, because collapsing them is what overstates the result:
  1. The `|| false` conversion is **correct** under both — the assertion fails its test either way.
  2. It is **load-bearing** only where the bare form would not have failed. Under a bash that
     already stops the test, removing the suffix changes nothing, so phase 1's evidence that the
     suffix supplies the discrimination holds for bash 3.2.57 and not for that bash 5.
  3. The suites pin no interpreter, and a mutation whose predicted red comes *from* mid-test
     position is already forbidden by §3 step 3.

  Phase 1's 68 conversions stand under either outcome; what changes is the claim made for them.

- [ ] **Step 4: Re-run the in-scope suite under both interpreters**

```bash
for dir in /bin "$(brew --prefix)/bin"; do
  echo "=== PATH front: $dir ==="
  PATH="$dir:$PATH" bats \
    skills/{claude-setup,design-review,external-review,phase-workflow}/tests/*.bats | tail -3
done
```

A suite that passes under 3.2 and fails under 5 is a finding, not a blocker for this task —
record it and file it.

- [ ] **Step 5: Commit**

Stage `skills/phase-workflow` only. `docs/KNOWN_ISSUES.md` is Task 5's.

---

## Task 3: `roadmap.py check` verifies a cited fragment (ENH-30, the check)

**Files:**

- Modify: `skills/phase-workflow/roadmap.py`
- Test: `skills/phase-workflow/tests/roadmap.bats`

**Interfaces:**

- Consumes: `split_entries(text) -> (preamble, {eid: body})` and `FILES` — both already in
  `roadmap.py`.
- Produces: `verify_references(docs: Path) -> tuple[bool, list[str]]`, called by `cmd_check`
  alongside `reconcile`. Exit status stays 0 clean / 1 dirty; no new CLI argument.

**The check comes before the conversion.** Converting 89 references by hand and then writing the
gate would mean the conversion was verified by reading — the failure ENH-30 exists to end.

- [ ] **Step 1: Write the failing tests**

Twelve tests. Each names what turns it red, and **four are controls that pass before the change**
— they exist to catch a checker that is too eager, which is the other half of getting this right.
They append to `roadmap.bats`, which already builds a scratch `$DOCS` and exports `$RM`.

`````bash
# Put reference text into KI-01's body, so reconcile stays satisfied and only
# the new pass can fail. Multi-line text is supported: the Where field wraps.
put_ref() {
  local tmp="$TEST_TMP/ki.md"
  printf '%s\n' "$1" > "$TEST_TMP/ref.txt"
  awk -v f="$TEST_TMP/ref.txt" '
    $0 == "SURVIVOR-ONE" { while ((getline l < f) > 0) print l; next } { print }
  ' "$DOCS/KNOWN_ISSUES.md" > "$tmp" && mv "$tmp" "$DOCS/KNOWN_ISSUES.md"
}

# The scratch source tree the links resolve into: ../skills/x.sh from $DOCS.
seed_source() {
  mkdir -p "$TEST_TMP/skills/subdir"
  printf 'guard() {\n  timed_out "$ERR" || return 1\n}\n' > "$TEST_TMP/skills/x.sh"
  printf 'other_guard() {\n  :\n}\n' > "$TEST_TMP/skills/y.sh"
}

@test "a #Lnn line anchor fails the check" {
  # Red if check exits 0 while an entry still carries a line anchor.
  seed_source
  put_ref '**Where:** [x.sh:2](../skills/x.sh#L2) — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line anchor"* ]] || false
}

@test "a fragment absent from the cited file fails the check" {
  # Red if a quoted fragment that is nowhere in the cited file is accepted.
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `no_such_function`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fragment absent"* ]] || false
}

@test "a fragment present in the cited file passes" {
  # CONTROL, passes before the change. Red if a correct reference is reported.
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

@test "a cited path missing from the tree fails the check" {
  # Red if a link to a deleted or renamed file is accepted.
  seed_source
  put_ref '**Where:** [gone.sh](../skills/gone.sh) — `guard`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cited path missing"* ]] || false
}

@test "a #Lnn shown inside a fenced block is not a finding" {
  # CONTROL, passes before the change. Red if the checker reads an entry's own
  # example as a real reference.
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `guard`

```markdown
before:  [x.sh:2](../skills/x.sh#L2)
```'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

@test "a file link with no fragment fails the check" {
  # Red if an entry can name where a bug lives with nothing greppable.
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) and the guard it holds'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no fragment"* ]] || false
}

@test "a second file link without a fragment fails, even when the first has one" {
  # Red if one verified fragment is allowed to certify a whole entry. This is
  # the false green both reviewers attacked: "verified" while y.sh rots.
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`, [y.sh](../skills/y.sh)'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no fragment"* ]] || false
  [[ "$output" == *"y.sh"* ]] || false
}

@test "a Where field wrapped onto a second line is read whole" {
  # CONTROL, passes before the change. Red if the checker reads only the first
  # line: the fragment for y.sh is on line 2, and three real entries wrap.
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`,
[y.sh](../skills/y.sh) — `other_guard`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

@test "a four-backtick fence does not swallow the rest of the entry" {
  # Red if fence tracking toggles on the inner three-backtick line: `inside`
  # stays true after the real close and every later reference vanishes, which
  # is a false green rather than a false alarm.
  seed_source
  put_ref '````markdown
```
inner fence
```
````

**Where:** [x.sh:2](../skills/x.sh#L2) — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line anchor"* ]] || false
}

@test "a link carrying a title is parsed, not skipped" {
  # Red if an unrecognised link shape reads as no reference at all: adding a
  # title would otherwise bypass both anchor rejection and the fragment rule.
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh#L2 "the guard") — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line anchor"* ]] || false
}

@test "a directory link needs no fragment" {
  # CONTROL, passes before the change. Red if an existence-only reference is
  # forced to carry a fragment; ENH-04 and ENH-07 cite directories.
  seed_source
  put_ref '**Where:** [subdir](../skills/subdir)'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

@test "a whitespace-only fragment fails the check" {
  # Red if a degenerate fragment certifies a reference. A four-backtick span
  # yields a single space, which is present in every file.
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — ` `'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fragment too weak"* ]] || false
}
`````

- [ ] **Step 2: Run the tests to verify they fail for the named reason**

```bash
bats skills/phase-workflow/tests/roadmap.bats
```

**Expected: eight fail, four pass.** The four that pass are the controls — `a fragment present`,
`a #Lnn shown inside a fenced block`, `a Where field wrapped onto a second line`, and
`a directory link needs no fragment` — because nothing is checked yet and all four assert
`status -eq 0`. Any other distribution means a fixture is wrong, not that the feature is present.

Each of the eight must fail on its **named** assertion — a `status` of 0 where 1 was required, or
the missing message — never on a fixture or collection error. Phase 1 produced two false reds
whose exit status looked right and whose failing line was the wrong one.

- [ ] **Step 3: Write the minimal implementation**

Four functions, because the four things here change for four different reasons: markdown fence
rules, the entry format, the reference syntax, and what counts as verified.

**`roadmap.py` does not import `collections` today** — add it to the import block beside
`argparse` and `pathlib`, in the same alphabetical-ish order the file already uses.

```python
FENCE = re.compile(r'^\s*(`{3,}|~{3,})')
LINK = re.compile(r'\[[^\]]*\]\(\s*([^()\s#]+)(#[^()\s]*)?(?:\s+"[^"]*")?\s*\)')
LOOSE = re.compile(r'\]\(')
FRAGMENT = re.compile(r'`([^`]+)`')
FIELD = re.compile(r'\*\*[A-Z][^*]*:\*\*')
WHERE = "**Where:**"
Ref = collections.namedtuple("Ref", "target anchor fragment")


def _fenced_lines(text: str) -> list[bool]:
    """True for each line inside a fenced block. Tracks the opening delimiter's
    character and length, because a four-backtick fence may legally contain a
    three-backtick line — and toggling on that line leaves `inside` true after
    the real close, hiding every later reference instead of surfacing it."""
    flags, opened = [], None
    for line in text.splitlines():
        m = FENCE.match(line)
        if opened is None:
            flags.append(bool(m))
            if m:
                opened = m.group(1)
        else:
            flags.append(True)
            if m and m.group(1)[0] == opened[0] and len(m.group(1)) >= len(opened):
                opened = None
    return flags


def _where_field(lines: list[str]) -> str:
    """The whole `**Where:**` field, continuation lines included. Real entries
    wrap it, and reading only the first line is wrong in both directions: a
    fragment on line 2 reads as missing, and a link on line 2 is never
    required to have one."""
    for i, line in enumerate(lines):
        if not line.startswith(WHERE):
            continue
        out = [line]
        for nxt in lines[i + 1:]:
            if not nxt.strip() or nxt.startswith(("**", "#", "|")):
                break
            out.append(nxt)
        return " ".join(out)
    return ""


def _references(field: str) -> list[Ref]:
    """Parse a Where field into references. Refuses a field holding a link it
    cannot parse: an unrecognised shape must fail loudly, because reading it as
    *no reference* is a silent false green."""
    matches = list(LINK.finditer(field))
    if len(matches) != len(LOOSE.findall(field)):
        raise ValueError("a link in this Where field is not in the accepted reference form")
    refs = []
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(field)
        between = field[m.end():end]
        stop = FIELD.search(between)        # a new bold field ends this reference
        if stop:
            between = between[:stop.start()]
        frag = FRAGMENT.search(between)
        refs.append(Ref(m.group(1), m.group(2) or "", frag.group(1) if frag else None))
    return refs


def verify_references(docs: pathlib.Path) -> tuple[bool, list[str]]:
    """Confirm every reference in every entry's Where field resolves, carries no
    line anchor, and matches a fragment still present in the cited file.
    Separate from reconcile: that compares the index with the detail files, this
    compares the detail files with the source tree."""
    ok, problems = True, []
    for name in FILES.values():
        _, entries = split_entries((docs / name).read_text())
        for eid, body in entries.items():
            lines = [l for l, fenced in zip(body.splitlines(), _fenced_lines(body))
                     if not fenced]
            field = _where_field(lines)
            if not field:
                continue
            try:
                refs = _references(field)
            except ValueError as exc:
                problems.append(f"  {eid}: {exc}")
                ok = False
                continue
            for r in refs:
                path = docs / r.target
                if r.anchor.startswith("#L"):
                    problems.append(f"  {eid}: line anchor {r.anchor} on {r.target}")
                    ok = False
                if not path.exists():
                    problems.append(f"  {eid}: cited path missing: {r.target}")
                    ok = False
                elif path.is_dir():
                    if r.fragment:
                        problems.append(f"  {eid}: fragment on a directory link: {r.target}")
                        ok = False
                elif r.fragment is None:
                    problems.append(f"  {eid}: file link with no fragment: {r.target}")
                    ok = False
                elif len(r.fragment.strip()) < 4:
                    problems.append(f"  {eid}: fragment too weak to verify: {r.target}")
                    ok = False
                elif r.fragment not in path.read_text():
                    problems.append(f"  {eid}: fragment absent from {r.target}: {r.fragment}")
                    ok = False
        problems.append(f"{name:22} references verified")
    return ok, problems
```

**Why the four-character floor.** A four-backtick span parses down to a single space, which is
present in every file, so the reference would certify itself. The floor also rejects `fi`, `do`
and `{`, which match anywhere. It is a crude instrument against a real failure: a fragment that
proves nothing still reads as verified.

And `cmd_check` composes the two passes:

```python
def cmd_check(docs: pathlib.Path) -> int:
    load(docs)          # refuses early if a file is missing or malformed
    ok, problems = reconcile(docs)
    refs_ok, refs_problems = verify_references(docs)
    for line in problems + refs_problems:
        print(line)
    return 0 if (ok and refs_ok) else 1
```

**Both passes always run.** Short-circuiting on `reconcile` would hide every reference finding
behind an unrelated rating mismatch.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bats skills/phase-workflow/tests/roadmap.bats
python3 skills/phase-workflow/bats_assertions.py skills/phase-workflow/tests/roadmap.bats \
  > "$TMPDIR/scan.tsv" || { echo "SCAN FAILED — the gate proves nothing"; exit 1; }
MID="$(set -o pipefail; awk -F'\t' '$4=="mid"' "$TMPDIR/scan.tsv" | tee /dev/stderr | wc -l | tr -d ' ')" \
  || { echo "COUNTING FAILED — the gate proves nothing"; exit 1; }
[ "$MID" -eq 0 ] || { echo "MID ASSERTIONS PRESENT: $MID"; exit 1; }
```

**The scan is checked for success before its output is counted.** Piping the scanner straight into
`wc -l` reports `0` when the scanner fails outright, which reads as "no vacuous assertions" — the
same false green this phase exists to remove. The twelve tests above add several `[[ ]]`
assertions, so this gate matters here.

- [ ] **Step 5: `/simplify`, then re-run**

Once per red-green-refactor cycle, at the refactor step, on this change. Re-run the suite after
it, because it edits the working tree. **Reject any simplification that folds the four functions
back into one** — they were split because the reviewers' parser findings each land on a different
one.

- [ ] **Step 6: Mutation-check each new test**

`roadmap.py` is the target and HEAD is the task commit, so commit first, then one mutation per
behaviour — the line-anchor branch, the fragment comparison, the existence check, the directory
exemption, the four-character floor, the fence delimiter length, the field continuation, and the
`_references` refusal:

```bash
bash skills/phase-workflow/mutation-restore.sh "$(git rev-parse HEAD)" \
  skills/phase-workflow/roadmap.py \
  's/len(m.group(1)) >= len(opened)/True/' \
  bats skills/phase-workflow/tests/roadmap.bats
```

**Check which test failed and on which assertion.** A mutation that makes the script raise is a
red in the wrong place, which phase 1 mistook for success twice.

- [ ] **Step 7: Commit**

---

## Task 4: Convert every reference (ENH-30, the conversion)

**Files:**

- Modify: `docs/KNOWN_ISSUES.md` (48 entries, 57 anchors)
- Modify: `docs/ENHANCEMENTS.md` (24 entries with a file link, 2 anchors)
- Read only: `docs/OPEN_QUESTIONS.md` (2 entries, no `**Where:**` field, nothing to convert —
  confirm rather than assume)

**Interfaces:**

- Consumes: `roadmap.py check` from Task 3 — it is the gate, and the reason this task is
  verifiable at all.
- Produces: a roadmap set with no `#Lnn` anchor and a verified fragment against every file link in
  every `**Where:**` field. 89 fragments: 38 inside the five in-scope skills or the repo root, 51
  outside them.

**The conversion is wider than the anchors.** 59 anchors sit in 44 entries, but the gate binds
every `**Where:**` file link, which is 89 references across 71 entries. The 30 references with no
anchor today need a fragment too. Inventory them; do not work from the anchor list.

```markdown
before:  [preflight.sh:136](../skills/external-review/preflight.sh#L136)
after:   [preflight.sh](../skills/external-review/preflight.sh) — `timed_out "$ERR"`
```

- [ ] **Step 1: Inventory every reference the gate will bind, fence-aware**

Counting `grep -c` lines is wrong twice over: a line holding two references counts once, and a
fenced example counts as a reference. Use the parser that will judge the result:

```bash
python3 - <<'EOF'
import pathlib, sys
sys.path.insert(0, "skills/phase-workflow")
import roadmap
docs = pathlib.Path("docs")
for name in roadmap.FILES.values():
    _, entries = roadmap.split_entries((docs / name).read_text())
    for eid, body in entries.items():
        lines = [l for l, f in zip(body.splitlines(), roadmap._fenced_lines(body)) if not f]
        field = roadmap._where_field(lines)
        if not field:
            continue
        for r in roadmap._references(field):
            kind = "DIR" if (docs / r.target).is_dir() else "FILE"
            print(f"{eid}\t{kind}\t{r.target}\t{r.anchor}\t{r.fragment}")
EOF
```

That list is the work. Each `FILE` row with an empty fragment or a `#L` anchor needs one.

- [ ] **Step 2: Convert entry by entry, reading the cited code**

**Choosing the fragment is judgement, not substitution.** Open the cited file at the cited lines
and pick something distinctive enough to grep and stable enough to survive a refactor — a function
name, a guard's condition, a distinctive string literal. Prefer those to a whole line, which
carries incidental whitespace and formatting that the next edit changes.

Five rules, each learned from the real inventory rather than imagined:

- **Never a bare common token.** `continue`, `fi`, `return 1` appear many times; a fragment that
  matches anywhere proves nothing. The four-character floor catches the worst of these and not the
  merely weak ones.
- **A directory link takes no fragment.** `ENH-04` cites `tests/fakes/` and `ENH-07` cites the
  `claude-toggle-backend` directory and then names four scripts in backticks. Those backticks are
  filenames, not code: put the anchor on a file link, or leave the directory as an existence-only
  reference.
- **`ENH-27` cannot use its natural fragment.** Its `**Where:**` quotes the ```` ```markdown ````
  fence marker with a four-backtick span, and a fragment cannot contain a backtick. Pick a
  different distinctive string from the same file.
- **Mind the `**Regression net:**` field.** Several entries follow the link with that field and a
  backticked *path*. The parser stops at the field marker, so the path is not read as a fragment —
  do not move it, and do not add a fragment after it.
- **46 of the 59 anchors point at out-of-scope skills.** Read them; never edit them. Their code is
  scheduled to be rewritten, and a fragment that breaks then fails loudly, which is the whole
  improvement over a line number that rots silently.

- [ ] **Step 3: Verify mechanically, not by reading**

```bash
python3 skills/phase-workflow/roadmap.py check || exit 1
markdownlint-cli2 --config ~/.markdownlint.jsonc docs/KNOWN_ISSUES.md docs/ENHANCEMENTS.md \
  docs/OPEN_QUESTIONS.md
```

`roadmap.py check` is now the completeness test: a remaining `#Lnn` anchor, a missing fragment and
a stale fragment each fail it. A separate grep would only re-check what the gate already covers.

**Then re-read what the bulk edit touched.** A regex written for one reference shape matches every
line of that shape, and this edit runs across 71 entries. Check the `**Where:**` lines kept their
leading bold marker, that no entry lost a blank line, that no wrapped field lost its continuation,
and that no link text still names a line number the link no longer carries.

- [ ] **Step 4: Commit**

---

## Task 5: Documentation, roadmap and release

**Files:**

- Modify: `CHANGELOG.md`, `docs/ROADMAP.md`, `docs/KNOWN_ISSUES.md`, `docs/ENHANCEMENTS.md`,
  `docs/PHASE_RECORD.md`, `skills/phase-workflow/SKILL.md`, the bundled roadmap templates
- Modify: the container folder's `README.md` and `CLAUDE.md` if either names a count this phase
  changed

**Interfaces:**

- Consumes: everything above.
- Produces: release v1.12.0 prepared, and the entries closed.

**Task 5 is the only task that closes a roadmap entry.** `roadmap.py close` refuses an entry that
is already gone, so two owners would abort the run.

- [ ] **Step 1: Close the entries with the helper**

```bash
python3 skills/phase-workflow/roadmap.py close ENH-30 || exit 1
python3 skills/phase-workflow/roadmap.py close KI-52 || exit 1
python3 skills/phase-workflow/roadmap.py check || exit 1
```

- [ ] **Step 2: File what this phase found and is not fixing**

Two defects in phase 1's landed work, both found by external review of this plan:

- **The documented 0-`mid` gate cannot fail.** `SKILL.md` gives it as
  `bats_assertions.py … | awk -F'\t' '$4=="mid"'`, which prints nothing when the scanner itself
  fails — indistinguishable from a clean result. Confirmed: running it against a missing file
  prints nothing and exits 0. File as `KI-nn`, with the checked form from Task 3 step 4 as the
  fix. In scope to fix here if it lands cheaply; file it either way so it is not lost.
- **§1's plan review cannot run with the plan inside the repo.** `codex-root.sh` refuses any
  untracked file, and a pre-branch plan is necessarily untracked. Consistent with both documents,
  stated in neither, and it cost a failed export this phase. File against `phase-workflow` §1/§2
  and `external-review`'s plan mode.

- [ ] **Step 3: Document the new check where the rule lives**

`phase-workflow`'s roadmap-file rules describe the drift check. Add what changed: a reference to a
repo file carries a greppable fragment, `roadmap.py check` verifies it, a line anchor is rejected,
a directory link is existence-only, and a fragment cannot contain a backtick. Update the bundled
templates so a new entry is written in the new shape from the start. **One fact, one place** —
state the rule in the skill, and let the templates show the shape without restating the rule.

- [ ] **Step 4: CHANGELOG, version v1.12.0**

Minor: `roadmap.py check` gains a verification it did not have. Prepare the release before
external review — rename the populated `[Unreleased]` to
`## [1.12.0] - <date> — Mini phase, reference integrity`, add a fresh empty `[Unreleased]`, and
add the compare link under `## Reference`.

- [ ] **Step 5: Update `docs/PHASE_RECORD.md`**

It went stale twice in phase 1. §3 step 4 names it in the sweep and §3 step 7 checks it
mechanically; run that check rather than remembering.

- [ ] **Step 6: Drift check**

Every identifier, path, command, flag and config key the touched docs name — and now, every
fragment, which `roadmap.py check` covers for the first time.

- [ ] **Step 7: Commit and push**

---

## External review findings

**Pass 1 coverage:** `Codex gpt-6-astra (max) 11 · Gemini gemini-3.1-pro-high 8 · 4 overlapping →
15 unique findings`. **Full coverage** — single chunk of 60,399 characters, one bundled file,
`bundle contains 1 of 1 files; 0 withheld, 0 excluded`; both reviewers answered at their top rung
and neither authored the plan.

| # | Finding | Files | Model | Likelihood | Severity | Verdict | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F-01 | Both "interpreter" suite runs can use bash 5, so the comparison is not one | Task 2 | gpt-6-astra | Almost always | High (gpt-6-astra) | Confirmed | Incorporated — Task 2 step 2 pins each interpreter and records `BASH_VERSION` from inside the run |
| F-02 | One verified fragment conceals every other reference in the entry | Task 3 `verify_references` | gpt-6-astra, gemini-3.1-pro-high | Almost always | High (both) | Confirmed | Incorporated — per-file coverage; new test 7 |
| F-03 | An unrecognised link shape reads as no reference, bypassing every check | Task 3 `_references` | gpt-6-astra, gemini-3.1-pro-high | Likely | High (both) | Confirmed | Incorporated — `_references` refuses what it cannot parse; titles parsed; new test 10 |
| F-04 | Fence tracking desyncs on a nested fence and swallows later references | Task 3 `_fenced_lines` | gpt-6-astra, gemini-3.1-pro-high | Rare | High (gpt-6-astra) / Medium (gemini-3.1-pro-high) | Confirmed | Incorporated — delimiter char and length tracked; tilde fences; new test 9 |
| F-05 | A fragment separated from its link by prose is silently ignored | Task 3 `FRAGMENT` | gemini-3.1-pro-high | Likely | High (gemini-3.1-pro-high) | Confirmed | Incorporated — bounded `search`, and a missing fragment now fails |
| F-06 | The Where field wraps, and reading one line is wrong in both directions | Task 3 `_where_field` | gpt-6-astra | Almost always | High (gpt-6-astra) | Confirmed | Incorporated — `_where_field`; new test 8. Three real entries wrap |
| F-07 | A directory link makes the entry-level rule unsatisfiable | Task 3, Task 4 | gpt-6-astra, gemini-3.1-pro-high | Almost always | Medium (both) | Confirmed | Incorporated — directory links are existence-only; new test 11 |
| F-08 | The vacuity scan reports 0 after the scanner fails | Task 2, Task 3, verification | gpt-6-astra | Likely | Medium (gpt-6-astra) | Confirmed | Incorporated in the plan; the same flaw in shipped `SKILL.md` is filed in Task 5 step 2 |
| F-09 | The migration inventory is narrower than the checker it must satisfy | Task 4 | gpt-6-astra, gemini-3.1-pro-high | Almost always | Medium (both) | Confirmed | Incorporated — Task 4 inventories with the parser, across all three files |
| F-10 | The measurement's conclusions overstate what one machine proves | Task 2 step 3 | gpt-6-astra | Almost always | Medium (gpt-6-astra) | Confirmed | Incorporated — scoped to the measured versions; compatibility split from load-bearing |
| F-11 | The expected red count is five; it is four | Task 3 step 2 | gpt-6-astra | Almost always | Medium (gpt-6-astra) | Confirmed | Incorporated — now twelve tests, eight red and four controls named |
| F-12 | KI-52 is closed by two tasks and the second would abort | Task 2, Task 5 | gpt-6-astra | Almost always | Medium (gpt-6-astra) | Confirmed | Incorporated — Task 5 owns every close |
| F-13 | Final verification omits changed markdown, and 5 skills versus 4 suites is unexplained | Verification | gpt-6-astra | Almost always | Medium (gpt-6-astra) | Confirmed | Incorporated — lint covers every changed file; `project-env` has no suite, now stated |
| F-14 | `git commit -F -` with no piped input waits for input | Tasks 1, 2, 4, 5 | gemini-3.1-pro-high | Almost always | High (gemini-3.1-pro-high) | Confirmed | Incorporated — the heredoc form is shown, with why the delimiter is quoted |
| F-15 | A fragment cannot contain a backtick, and `ENH-27`'s natural one does | Task 4 | gemini-3.1-pro-high | Rare | Low (gemini-3.1-pro-high) | Confirmed | Incorporated — stated as an exemption; `ENH-27` named in Task 4 step 2 |
| F-16 | The hardcoded Homebrew prefix is Apple-Silicon-specific | Task 2 step 3 | gemini-3.1-pro-high | Rare | High (gemini-3.1-pro-high) | Partly | Incorporated — `$(brew --prefix)`; the path was correct on this machine, so the severity is the reviewer's, not mine |
| F-17 | `OPEN_QUESTIONS.md` is checked by the gate but absent from the conversion | Task 4 | gemini-3.1-pro-high | Rare | Low (gemini-3.1-pro-high) | Partly | Incorporated — named in Task 4's files; it has no `**Where:**` field, so there is nothing to convert |

**F-01** — *When it fires:* `brew install bash` has run and `$(brew --prefix)/bin` precedes `/bin`
in `PATH`, which it does on this machine — position 2 against position 11. *What happens:* the
"system bash" arm of the comparison runs under bash 5, so both arms measure the same interpreter
and agree, and the conclusion "not host-dependent" is drawn from one interpreter.
*Reviewer's fix:* "Run the same Bats 1.14.0 executable with controlled Bash selection for each
run, keeping other tool selection unchanged. Record `$BASH_VERSION` from inside each Bats run."
*Commentary:* Confirmed by reading `PATH` directly. This is the finding that mattered: the task
would have produced a false measurement and recorded it as evidence, which is the exact failure
§3 step 3 forbids — and my plan reintroduced it two days after phase 1 wrote that rule. Both
halves of the fix are adopted, including reading the interpreter from inside the run rather than
printing a version outside it.

**F-02** — *When it fires:* an entry's `**Where:**` cites more than one file and any one of them
carries a fragment. *What happens:* `checked > 0` satisfies the entry, so the other files are
never verified, and `roadmap.py check` reports the entry as verified while those references rot.
*Reviewer's fix:* Codex — "Track coverage per cited file… If one fragment per entry remains
intentional, explicitly identify the other references as unverified and narrow the claimed
guarantee." Gemini — "require `checked` to equal the total number of file links on that line".
*Commentary:* Both reviewers found this independently, which is the strongest signal in the pass.
Measured cost of the strict rule: 89 fragments rather than 71, over 15 entries with two or more
file links. Adopted, because a gate that reports "verified" for an unverified reference is worse
than no gate.

**F-04** — *When it fires:* an entry contains a four-backtick fenced example holding a literal
three-backtick line. *What happens:* the three toggles leave `inside` true after the real closing
fence, so every reference later in that entry is treated as fenced and skipped — a false green,
not a false alarm. *Reviewer's fix:* "Track the opening fence's character and length, and
recognize only valid closing fences. Test this case and tilde fences." *Commentary:* No such
fence exists in the docs today, so this is latent — but `ENH-27` already uses a four-backtick
*inline* span, so the construct is in use and one fenced example away from firing. The failure
direction is what raises it above its likelihood.

**F-08** — *When it fires:* `bats_assertions.py` fails — a syntax error, a missing file, a bad
glob. *What happens:* `awk` receives nothing, `wc -l` prints `0`, and the pipeline exits 0, so a
scanner that never ran is indistinguishable from a clean scan. *Reviewer's fix:* "Require
successful scanner execution before inspecting its output, then explicitly fail when any `mid` row
exists. Apply this to all three copies of the gate." *Commentary:* Confirmed by running it against
a nonexistent file: it prints `0`. The shipped `SKILL.md` form prints rows rather than counting,
so a scanner failure there prints nothing, which a reader takes as clean. That is a defect in
phase 1's landed work, not in this plan, and Task 5 files it.

**F-16** — *When it fires:* the plan is followed on an Intel Mac or on Linux. *What happens:*
`/opt/homebrew/bin` does not exist, so the bash 5 arm silently uses the system bash.
*Reviewer's fix:* "Dynamically resolve the Homebrew prefix using `PATH="$(brew --prefix)/bin:$PATH"`."
*Commentary:* Partly. `brew --prefix` is `/opt/homebrew` here, so the literal path was correct and
the `High` rating is the reviewer's rather than mine — on this machine it could not fire. Adopted
anyway: `$(brew --prefix)` costs nothing and the plan is a document that outlives the machine. The
deeper problem in the same step was F-01, which the reviewer did not see.

**F-17** — *Explanation:* Task 4 named two files while the gate reads three. *Reviewer's fix:*
"Add `docs/OPEN_QUESTIONS.md` to the grep command." *Commentary:* Partly — the asymmetry is real
and the consequence is not. Measured: `OPEN_QUESTIONS.md` has two entries, neither with a
`**Where:**` field, so the gate binds nothing there. Named in Task 4's file list as a confirm-not-
assume step rather than as conversion work.

---

## Verification

**Per task.** The red test precedes the fix and the red is confirmed to be the *named* failure,
not a fixture or collection error. Task 3's tests are mutation-checked, one mutation per
behaviour, and its red baseline is eight failures and four named controls.

**Task 2 is a measurement and is verified differently:** its claim is "this is what this
interpreter did", and what makes it checkable is that the fixture, the commands and the
`BASH_VERSION` each run reported are recorded together. The interpreter is pinned by `PATH` order
and **confirmed from inside the run**, because the first two pinning methods tried both failed
silently and only the inside reading caught them.

**Before hand-off.**

```bash
for dir in /bin "$(brew --prefix)/bin"; do
  echo "=== PATH front: $dir ==="
  PATH="$dir:$PATH" bats \
    skills/{claude-setup,design-review,external-review,phase-workflow}/tests/*.bats | tail -3
done
python3 skills/phase-workflow/roadmap.py check || exit 1
python3 skills/phase-workflow/bats_assertions.py \
  skills/{claude-setup,design-review,external-review,phase-workflow}/tests/*.bats \
  > "$TMPDIR/scan.tsv" || { echo "SCAN FAILED — the gate proves nothing"; exit 1; }
MID="$(set -o pipefail; awk -F'\t' '$4=="mid"' "$TMPDIR/scan.tsv" | tee /dev/stderr | wc -l | tr -d ' ')" \
  || { echo "COUNTING FAILED — the gate proves nothing"; exit 1; }
[ "$MID" -eq 0 ] || { echo "MID ASSERTIONS PRESENT: $MID"; exit 1; }
markdownlint-cli2 --config ~/.markdownlint.jsonc docs/*.md CHANGELOG.md CLAUDE.md \
  skills/phase-workflow/SKILL.md skills/phase-workflow/*-template.md
```

**`project-env` names no suite because it has none** — it is `SKILL.md` alone. Four suites for five
in-scope skills is correct, and stated here so the gap is not read as an omission.

**Manual sign-off is the user's**, on the draft PR marked ready, per the phase gate.

## Not covered, stated rather than assumed

- **`claude-toggle-backend`, `drive-backup` and `local-models` are not edited.** Their files are
  read to choose fragments. The five single-line mid-test assertions in `claude-toggle-backend`
  stay unconverted and stay filed.
- **Whether a fragment survives a refactor is unmeasured.** The claim is that it degrades more
  loudly than a line number, not that it never breaks. The first phase to edit a cited file is the
  test, and this plan does not pretend to be it.
- **51 of the 89 fragments point into skills scheduled for a rewrite.** They will break when that
  lands. That is the intended behaviour — loudly, at a gate — but it is real work deferred onto
  that phase, and it is better said now than discovered then.
- **No diagram.** Recorded in the front matter above.
- **`ultra` as a Codex rung stays unexercised**, for the reason phase 1 gave: it delegates tasks,
  so the diff may not come from the model recorded against it.
