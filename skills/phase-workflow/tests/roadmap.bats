#!/usr/bin/env bats
#
# The roadmap writer. Every test names the condition that turns it red.
#
# The canary is SURVIVOR: entries that must still be there afterwards. Both
# real incidents this replaces left a well-formed, lint-clean file that was
# simply missing entries, so counting is not the assertion — surviving content
# is.

setup() {
  export TEST_TMP="$(mktemp -d)"
  export DOCS="$TEST_TMP/docs"
  mkdir -p "$DOCS"
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export RM="$(dirname "$here")/roadmap.py"

  cat > "$DOCS/KNOWN_ISSUES.md" <<'EOF'
# Known Issues

Preamble that must survive.

## Severity

| Level | Means |
| --- | --- |
| **High** | Silently wrong. |

---

<a id="ki-01"></a>

## KI-01 — first issue

**Severity:** High
**Likelihood:** Rare

SURVIVOR-ONE

---

<a id="ki-02"></a>

## KI-02 — doomed issue

**Severity:** Medium
**Likelihood:** Likely

DOOMED-BODY

---

<a id="ki-03"></a>

## KI-03 — third issue

**Severity:** Low
**Likelihood:** Almost always

SURVIVOR-THREE
EOF

  cat > "$DOCS/ENHANCEMENTS.md" <<'EOF'
# Enhancements

---

<a id="enh-01"></a>

## ENH-01 — an enhancement

**Priority:** Low

SURVIVOR-ENH
EOF

  cat > "$DOCS/OPEN_QUESTIONS.md" <<'EOF'
# Open Questions

---

<a id="unk-01"></a>

## UNK-01 — a question

**Kind:** Verification

SURVIVOR-UNK
EOF

  cat > "$DOCS/ROADMAP.md" <<'EOF'
# Roadmap

## Known Issues

| ID | Issue | Likelihood | Severity |
| --- | --- | --- | --- |
| [KI-01](KNOWN_ISSUES.md#ki-01) | first issue | Rare | High |
| [KI-02](KNOWN_ISSUES.md#ki-02) | doomed issue | Likely | Medium |
| [KI-03](KNOWN_ISSUES.md#ki-03) | third issue | Almost always | Low |

## Enhancements

| ID | Enhancement | Priority | Effort |
| --- | --- | --- | --- |
| [ENH-01](ENHANCEMENTS.md#enh-01) | an enhancement | Low | ~1 hour |

## Open Questions

| ID | Question | Kind |
| --- | --- | --- |
| [UNK-01](OPEN_QUESTIONS.md#unk-01) | a question | Verification |
EOF
}

teardown() { rm -rf "$TEST_TMP"; }

entries() { grep -c '^## KI-' "$DOCS/KNOWN_ISSUES.md"; }
anchors() { grep -c '<a id="ki-' "$DOCS/KNOWN_ISSUES.md"; }
pointers() { grep -c 'KNOWN_ISSUES.md#ki-' "$DOCS/ROADMAP.md"; }

@test "check: a consistent roadmap reconciles" {
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

@test "close: removes exactly one entry and one index row" {
  run python3 "$RM" close KI-02 --docs "$DOCS"
  [ "$status" -eq 0 ]
  [ "$(entries)" -eq 2 ]
  [ "$(anchors)" -eq 2 ]
  [ "$(pointers)" -eq 2 ]
  ! grep -q 'DOOMED-BODY' "$DOCS/KNOWN_ISSUES.md"
}

@test "close: entries after the closed one survive" {
  # THE regression. Closing an entry by slicing to end of file took every
  # entry below it, and lint passed on the result.
  run python3 "$RM" close KI-02 --docs "$DOCS"
  [ "$status" -eq 0 ]
  grep -q 'SURVIVOR-ONE' "$DOCS/KNOWN_ISSUES.md"
  grep -q 'SURVIVOR-THREE' "$DOCS/KNOWN_ISSUES.md"
}

@test "close: closing the last entry keeps the ones above it" {
  run python3 "$RM" close KI-03 --docs "$DOCS"
  [ "$status" -eq 0 ]
  grep -q 'SURVIVOR-ONE' "$DOCS/KNOWN_ISSUES.md"
  ! grep -q 'SURVIVOR-THREE' "$DOCS/KNOWN_ISSUES.md"
  [ "$(entries)" -eq 2 ]
}

@test "close: closing the first entry keeps the header and the rest" {
  run python3 "$RM" close KI-01 --docs "$DOCS"
  [ "$status" -eq 0 ]
  grep -q 'Preamble that must survive' "$DOCS/KNOWN_ISSUES.md"
  grep -q '## Severity' "$DOCS/KNOWN_ISSUES.md"
  grep -q 'SURVIVOR-THREE' "$DOCS/KNOWN_ISSUES.md"
  [ "$(entries)" -eq 2 ]
}

@test "close: the other detail files are untouched" {
  run python3 "$RM" close KI-02 --docs "$DOCS"
  [ "$status" -eq 0 ]
  grep -q 'SURVIVOR-ENH' "$DOCS/ENHANCEMENTS.md"
  grep -q 'SURVIVOR-UNK' "$DOCS/OPEN_QUESTIONS.md"
  grep -q 'ENHANCEMENTS.md#enh-01' "$DOCS/ROADMAP.md"
  grep -q 'OPEN_QUESTIONS.md#unk-01' "$DOCS/ROADMAP.md"
}

@test "close: an unknown id is refused and nothing changes" {
  local before; before="$(cat "$DOCS/KNOWN_ISSUES.md")"
  run python3 "$RM" close KI-99 --docs "$DOCS"
  [ "$status" -eq 1 ]
  [ "$(cat "$DOCS/KNOWN_ISSUES.md")" = "$before" ]
}

@test "close: an entry with no index row is refused" {
  # Red if the writer removes the entry and leaves the index consistent by
  # accident. A missing row means the roadmap was already wrong; say so.
  python3 - "$DOCS/ROADMAP.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text("".join(l for l in p.read_text().splitlines(keepends=True) if 'ki-02' not in l))
PY
  local before; before="$(cat "$DOCS/KNOWN_ISSUES.md")"
  run python3 "$RM" close KI-02 --docs "$DOCS"
  [ "$status" -eq 1 ]
  [ "$(cat "$DOCS/KNOWN_ISSUES.md")" = "$before" ]
}

@test "close: works on enhancements too" {
  run python3 "$RM" close ENH-01 --docs "$DOCS"
  [ "$status" -eq 0 ]
  ! grep -q 'SURVIVOR-ENH' "$DOCS/ENHANCEMENTS.md"
  ! grep -q 'ENHANCEMENTS.md#enh-01' "$DOCS/ROADMAP.md"
  grep -q 'SURVIVOR-ONE' "$DOCS/KNOWN_ISSUES.md"
}

@test "check: a dangling index row is reported" {
  python3 - "$DOCS/KNOWN_ISSUES.md" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1]); t = p.read_text()
i = t.index('<a id="ki-03"></a>')
p.write_text(t[:t.rindex('\n---\n', 0, i)] + "\n")
PY
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ki-03"* || "$output" == *"KI-03"* ]]
}

@test "check: an entry with no index row is reported" {
  python3 - "$DOCS/ROADMAP.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text("".join(l for l in p.read_text().splitlines(keepends=True) if 'ki-03' not in l))
PY
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
}

@test "close: a duplicated id is refused rather than guessed at" {
  cat >> "$DOCS/KNOWN_ISSUES.md" <<'EOF'

---

<a id="ki-02"></a>

## KI-02 — a second copy

**Severity:** Low
**Likelihood:** Rare

DUPLICATE-BODY
EOF
  run python3 "$RM" close KI-02 --docs "$DOCS"
  [ "$status" -eq 1 ]
  grep -q 'DOOMED-BODY' "$DOCS/KNOWN_ISSUES.md"
}

@test "close: nothing is written when the result would not reconcile" {
  # THE ordering bug. close wrote both files and then ran the reconcile check,
  # so a refusal happened after the edits, and a failure writing the second
  # file left the first already changed.
  python3 - "$DOCS/ROADMAP.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text("".join(l for l in p.read_text().splitlines(keepends=True) if 'ki-03' not in l))
PY
  local before_detail; before_detail="$(cat "$DOCS/KNOWN_ISSUES.md")"
  local before_index; before_index="$(cat "$DOCS/ROADMAP.md")"
  run python3 "$RM" close KI-02 --docs "$DOCS"
  [ "$status" -eq 1 ]
  [ "$(cat "$DOCS/KNOWN_ISSUES.md")" = "$before_detail" ]
  [ "$(cat "$DOCS/ROADMAP.md")" = "$before_index" ]
}

@test "close: prose between the last rule and the first anchor survives" {
  # Red while the header ends at the last preceding rule unconditionally while
  # entry parsing claims that rule only when the gap is blank. Text in the gap
  # then belongs to neither slice and is dropped on the next write.
  python3 - "$DOCS/KNOWN_ISSUES.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1]); t = p.read_text()
i = t.index('<a id="ki-01"></a>')
p.write_text(t[:i] + "HEADER-PROSE-IN-THE-GAP\n\n" + t[i:])
PY
  run python3 "$RM" close KI-02 --docs "$DOCS"
  [ "$status" -eq 0 ]
  grep -q 'HEADER-PROSE-IN-THE-GAP' "$DOCS/KNOWN_ISSUES.md"
  grep -q 'SURVIVOR-ONE' "$DOCS/KNOWN_ISSUES.md"
  grep -q 'SURVIVOR-THREE' "$DOCS/KNOWN_ISSUES.md"
}

@test "check: an index row pointing at the wrong anchor is reported" {
  # Red while reconciliation compares only the displayed ID. The link target is
  # what a reader follows, so a row can look right and go nowhere.
  python3 - "$DOCS/ROADMAP.md" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text().replace("KNOWN_ISSUES.md#ki-01", "KNOWN_ISSUES.md#wrong-anchor"))
PY
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"KI-01"* ]]
}

@test "close: failure installing the second document restores both originals" {
  run python3 - "$RM" "$DOCS" <<'PY'
import importlib.util, pathlib, sys, os
spec = importlib.util.spec_from_file_location('roadmap', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
d = pathlib.Path(sys.argv[2]); before = {p: p.read_bytes() for p in d.iterdir()}
write, replace = pathlib.Path.write_text, os.replace
failed = False
def bad_write(p, *a, **kw):
    if p.parent == d and p.name == 'ROADMAP.md': raise OSError('injected second installation failure')
    return write(p, *a, **kw)
def bad_replace(src, dst):
    global failed
    if pathlib.Path(dst).name == 'ROADMAP.md' and not failed:
        failed = True
        raise OSError('injected second installation failure')
    return replace(src, dst)
pathlib.Path.write_text, os.replace = bad_write, bad_replace
try: m.cmd_close(d, 'KI-02')
except (OSError, SystemExit): pass
else: raise AssertionError('injection never fired')
assert all(p.read_bytes() == b for p,b in before.items()), 'partial close changed original'
PY
  [ "$status" -eq 0 ]
}

@test "check: wrong-file displayed IDs cannot disappear from reconciliation" {
  sed -i.bak 's/KNOWN_ISSUES.md#ki-01/WRONG.md#ki-01/' "$DOCS/ROADMAP.md"
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"wrong destination"* ]]
}

@test "check: mismatched detail and pointer ratings are refused" {
  sed -i.bak 's/first issue | Rare | High/first issue | Rare | Low/' "$DOCS/ROADMAP.md"
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"rating"* ]]
}

@test "check: rating order is validated independently of agreement" {
  python3 - "$DOCS/ROADMAP.md" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); s=p.read_text().splitlines(True)
a=next(i for i,l in enumerate(s) if '[KI-01]' in l); b=a+2
s[a],s[b]=s[b],s[a];p.write_text(''.join(s))
PY
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"order"* ]]
}

@test "QC T3-10: interrupted close restores originals and removes staging outside docs" {
  run python3 - "$RM" "$DOCS" <<'PY'
import importlib.util, pathlib, sys, os, tempfile
spec=importlib.util.spec_from_file_location('roadmap',sys.argv[1]); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
d=pathlib.Path(sys.argv[2]); before={p:p.read_bytes() for p in d.iterdir()}
replace, mkdtemp=os.replace, tempfile.mkdtemp
stages=[]
def stage(*a,**kw):
    p=pathlib.Path(mkdtemp(*a,**kw)); stages.append(p); return str(p)
def interrupt(src,dst):
    if pathlib.Path(dst).name=='ROADMAP.md': raise KeyboardInterrupt('injected interruption')
    return replace(src,dst)
tempfile.mkdtemp=stage; os.replace=interrupt
try: m.cmd_close(d,'KI-02')
except (KeyboardInterrupt,SystemExit): pass
else: raise AssertionError('interruption never fired')
assert all(p.read_bytes()==b for p,b in before.items()), 'interruption left a partial close'
assert stages and all(not p.is_relative_to(d) for p in stages), 'staging was inside docs'
assert all(not p.exists() for p in stages), 'staging leaked'
assert set(d.iterdir())==set(before), 'temporary file leaked'
PY
  [ "$status" -eq 0 ]
}

@test "F-07: the documented roadmap commands close one entry and detect drift" {
  # Fails if the SOP has no executable close/check path, or if that path ignores failure.
  python3 - "$BATS_TEST_DIRNAME/../SKILL.md" "$TEST_TMP/commands.sh" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
blocks = [b for b in re.findall(r'```bash\n(.*?)```', text, re.S) if 'roadmap.py' in b]
assert len(blocks) == 1, 'SOP must invoke the tested roadmap close and check commands'
pathlib.Path(sys.argv[2]).write_text(blocks[0].replace('<entry-id>', 'KI-02'))
PY
  cd "$TEST_TMP"
  CLAUDE_PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)" run bash "$TEST_TMP/commands.sh"
  [ "$status" -eq 0 ]
  ! grep -q 'DOOMED-BODY' "$DOCS/KNOWN_ISSUES.md"
  grep -q 'SURVIVOR-ONE' "$DOCS/KNOWN_ISSUES.md"
  grep -q 'SURVIVOR-THREE' "$DOCS/KNOWN_ISSUES.md"
  sed -i.bak 's/ki-01/wrong-anchor/' "$DOCS/ROADMAP.md"
  python3 - "$TEST_TMP/commands.sh" <<'PYCODE'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); p.write_text('\n'.join(l for l in p.read_text().splitlines() if ' check ' in l) + '\n')
PYCODE
  CLAUDE_PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)" run bash "$TEST_TMP/commands.sh"
  [ "$status" -eq 1 ]
}

@test "QC T3-10: missing trailing pipe refuses with a diagnostic instead of IndexError" {
  python3 - "$DOCS/ROADMAP.md" <<'PY'
import pathlib,sys
p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace('| [KI-01](KNOWN_ISSUES.md#ki-01) | first issue | Rare | High |','| [KI-01](KNOWN_ISSUES.md#ki-01)'))
PY
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing:"* ]] || false
  [[ "$output" != *"Traceback"* ]]
}

# ---------------------------------------------------------------------------
# ENH-30 — a roadmap reference carries a greppable fragment, and check verifies
# it still appears in the file cited beside it.
#
# Five of the fifteen tests below are CONTROLS: they assert status 0 and so pass
# before the feature exists. They are here because the other half of getting
# this right is not flagging correct references, and a checker that refuses
# everything would satisfy the other ten without them.
# ---------------------------------------------------------------------------

# Put reference text into KI-01's body. Multi-line input is supported, because
# a real **Where:** field wraps and three entries in this repo do.
put_ref() {
  local tmp="$TEST_TMP/ki.md"
  printf '%s\n' "$1" > "$TEST_TMP/ref.txt"
  awk -v f="$TEST_TMP/ref.txt" '
    $0 == "SURVIVOR-ONE" { while ((getline l < f) > 0) print l; next }
    { print }
  ' "$DOCS/KNOWN_ISSUES.md" > "$tmp" && mv "$tmp" "$DOCS/KNOWN_ISSUES.md"
}

# The scratch source tree the links resolve into: ../skills/x.sh from $DOCS.
seed_source() {
  mkdir -p "$TEST_TMP/skills/subdir"
  printf 'guard() {\n  timed_out "$ERR" || return 1\n}\n' > "$TEST_TMP/skills/x.sh"
  printf 'other_guard() {\n  :\n}\n' > "$TEST_TMP/skills/y.sh"
}

# Fails if check exits 0 while an entry still carries a line anchor.
@test "refs: a #Lnn line anchor fails the check" {
  seed_source
  put_ref '**Where:** [x.sh:2](../skills/x.sh#L2) — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line anchor"* ]] || false
}

# Fails if a quoted fragment that is nowhere in the cited file is accepted.
@test "refs: a fragment absent from the cited file fails the check" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `no_such_function`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fragment absent"* ]] || false
}

# CONTROL. Fails if a correct reference is reported as a problem.
@test "refs: a fragment present in the cited file passes" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

# Fails if a link to a deleted or renamed file is accepted.
@test "refs: a cited path missing from the tree fails the check" {
  seed_source
  put_ref '**Where:** [gone.sh](../skills/gone.sh) — `guard`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cited path missing"* ]] || false
}

# CONTROL. Fails if the checker reads an entry's own example as a real
# reference. ENH-30 demonstrates the banned form in a fence; successors will.
@test "refs: a #Lnn shown inside a fenced block is not a finding" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `guard`

```markdown
before:  [x.sh:2](../skills/x.sh#L2)
```'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

# Fails if an entry can name where a bug lives with nothing greppable.
@test "refs: a file link with no fragment fails the check" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) and the guard it holds'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no fragment"* ]] || false
}

# Fails if one verified fragment is allowed to certify a whole entry. This is
# the false green both external reviewers attacked: the entry reports verified
# while y.sh rots unwatched.
@test "refs: a second file link without a fragment fails, even when the first has one" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`, [y.sh](../skills/y.sh)'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no fragment"* ]] || false
  [[ "$output" == *"y.sh"* ]] || false
}

# CONTROL. Fails if the checker reads only the first line of the field: the
# fragment for y.sh is on line 2, and KI-47, KI-48 and KI-49 all wrap.
@test "refs: a Where field wrapped onto a second line is read whole" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`,
[y.sh](../skills/y.sh) — `other_guard`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

# Fails if fence tracking toggles on the inner three-backtick line: `inside`
# stays true past the real close and every later reference disappears, which is
# a false green rather than a false alarm.
@test "refs: a four-backtick fence does not swallow the rest of the entry" {
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

# Fails if an unrecognised link shape reads as no reference at all. A title
# would otherwise bypass both anchor rejection and the fragment rule.
@test "refs: a link carrying a title is parsed, not skipped" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh#L2 "the guard") — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line anchor"* ]] || false
}

# CONTROL. Fails if an existence-only reference is forced to carry a fragment.
# ENH-04 cites a directory and ENH-07 cites a skill folder.
@test "refs: a directory link needs no fragment" {
  seed_source
  put_ref '**Where:** [subdir](../skills/subdir)'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

# Fails if a degenerate fragment certifies a reference. A four-backtick inline
# span parses down to a single space, which is present in every file.
@test "refs: a whitespace-only fragment fails the check" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — ` `'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fragment too weak"* ]] || false
}

# Fails if a line anchor outside the **Where:** field escapes the check.
#
# The two rules have different scopes and conflating them leaves a false green:
# a fragment is required where the bug lives, so that requirement is scoped to
# **Where:**, but no entry may carry a line anchor ANYWHERE. KI-07 and KI-17
# both cite one in prose, and a gate that reports the roadmap clean while two
# anchors remain is the failure ENH-30 exists to remove.
@test "refs: a #Lnn line anchor in prose fails the check" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`

The behaviour is set by [x.sh:2](../skills/x.sh#L2) and nothing else.'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line anchor"* ]] || false
}

# Fails if a link whose target is a near-miss typo escapes verification.
#
# `[x.sh](skills/x.sh)` is missing the `../`, so it resolves to `docs/skills/x.sh`
# and nothing is there. Measured before this test existed: exit 0 with no
# finding at all — a recognised link, silently skipped, which is the very thing
# `_references` refuses to do for an unrecognised one. Once the conversion
# removes every line anchor, no other check would catch it.
@test "refs: a near-miss target with no ../ prefix is a finding, not a skip" {
  seed_source
  put_ref '**Where:** [x.sh](skills/x.sh) — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cited path missing"* ]] || false
}

# CONTROL. Fails if a legitimate doc-relative link is forced to carry a
# fragment. ENH-05 cites two plan documents exactly this way, and they resolve
# inside docs/ rather than into the source tree, so there is no code for a
# fragment to anchor to. This test is what stops the fix above over-reaching.
@test "refs: a doc-relative link inside docs needs no fragment" {
  seed_source
  mkdir -p "$DOCS/superpowers/plans"
  printf '# a plan\n' > "$DOCS/superpowers/plans/p.md"
  put_ref '**Where:** [p.md](superpowers/plans/p.md)'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}
