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
blocks = [b for b in re.findall(r'```bash\n(.*?)```', text, re.S) if 'roadmap.py" close' in b]
assert len(blocks) == 1, 'SOP must invoke the tested roadmap close and check commands in one block'
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
# Tests marked CONTROL assert status 0 and so pass before the feature exists.
# They are here because the other half of getting this right is not flagging
# correct references: a checker that refused everything would satisfy the rest.
# ---------------------------------------------------------------------------

# Put reference text into KI-01's body. Multi-line input is supported, because
# a real **Where:** field wraps and three entries in this repo do.
#
# Refuses unless the marker occurs exactly once, and checks it was consumed.
# Without both, a missing marker left the fixture unchanged and reported
# success, so a CONTROL test then passed against an entry that never received
# the reference under test.
put_ref() {
  local tmp="$TEST_TMP/ki.md" n
  n="$(grep -cx 'SURVIVOR-ONE' "$DOCS/KNOWN_ISSUES.md" || true)"
  if [ "$n" != 1 ]; then
    echo "put_ref: expected one SURVIVOR-ONE marker, found $n" >&2
    return 1
  fi
  printf '%s\n' "$1" > "$TEST_TMP/ref.txt"
  awk -v f="$TEST_TMP/ref.txt" '
    $0 == "SURVIVOR-ONE" { while ((getline l < f) > 0) print l; next }
    { print }
  ' "$DOCS/KNOWN_ISSUES.md" > "$tmp" && mv "$tmp" "$DOCS/KNOWN_ISSUES.md"
  if grep -qx 'SURVIVOR-ONE' "$DOCS/KNOWN_ISSUES.md"; then
    echo "put_ref: marker survived the substitution" >&2
    return 1
  fi
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

# Fails if a reference on the field's second line goes unchecked.
#
# The control above asserts a wrapped field stays clean, which cannot detect
# the field being truncated: dropping a valid reference produces no finding
# either way. Measured -- truncating the field left that control green. This
# puts a fragment that is absent from the cited file on line 2, so the second
# line must actually be read for the check to fail.
@test "refs: a bad reference on the field's second line is still checked" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`,
[y.sh](../skills/y.sh) — `no_such_symbol`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fragment absent"* ]] || false
  [[ "$output" == *"y.sh"* ]] || false
}

# Fails if fence tracking toggles on the inner three-backtick line: `inside`
# stays true past the real close and every later reference disappears, which is
# a false green rather than a false alarm.
#
# EXACTLY ONE inner three-backtick line, and that is load-bearing. With two,
# the toggles land evenly and the Where line ends up unfenced either way -- the
# first version of this test passed under mutation and proved nothing. With
# one, breaking the length rule leaves the fence open across the Where line and
# the anchor goes unseen.
@test "refs: a four-backtick fence does not swallow the rest of the entry" {
  seed_source
  put_ref '````markdown
```
inner fence
````

**Where:** [x.sh:2](../skills/x.sh#L2) — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"line anchor"* ]] || false
}

# Fails if a link carrying a title is not parsed. The fragment is absent from
# x.sh, so a parsed link reports "fragment absent" while an unparsed one is
# refused as not in the accepted reference form. The input carries no line
# anchor, so no other check can produce the asserted finding.
@test "refs: a link carrying a title is parsed, not skipped" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh "the guard") — `no_such_function`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fragment absent from ../skills/x.sh"* ]] || false
  [[ "$output" != *"accepted reference form"* ]] || false
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

# Fails if a link shape the parser cannot read is treated as absence of a
# reference rather than as a finding.
#
# A target containing a space matches no accepted form, so LINK does not match
# it while the `](` is still there. That is the one case where "I did not
# understand this" must not become "there was nothing here" — every other
# check in this pass is downstream of a link the parser recognised.
#
# Written after the code, so its discrimination is established by mutation
# rather than by having watched it go red first: removing the raise leaves the
# entry reported clean.
@test "refs: an unparseable link shape is a finding, not an absence" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/my file.sh) — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in the accepted reference form"* ]] || false
}

# CONTROL. Fails if the fragment requirement leaks out of the **Where:** field.
#
# The two rules have deliberately different scopes: no line anchor anywhere, but
# a fragment only where the bug lives. KI-07 and KI-17 both link a file in prose
# after their Where field, and requiring a fragment there would make those
# entries unwritable. Nothing else asserts this, so a change that tightened the
# scope would pass every other test.
@test "refs: a file link in prose needs no fragment" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`

The same guard is reached from [y.sh](../skills/y.sh) during startup.'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

# CONTROL. Fails if a tilde fence is not treated as a fence.
#
# CommonMark allows ~~~ as well as ```, and an entry may show a banned reference
# inside one. Untested until now: no roadmap file uses tilde fences, so this
# guards a path that has never run on real content.
@test "refs: a tilde-fenced example is not a finding" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`

~~~markdown
before:  [x.sh:2](../skills/x.sh#L2)
~~~'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

# Fails if a fragment that occurs more than once in the cited file is accepted.
#
# "Greppable" promises one hit, and the conversion verified all 89 fragments as
# occurring exactly once -- CHANGELOG says so. The gate only tested presence,
# so the enforced guarantee was weaker than the documented one: a fragment
# chosen as unique can become ambiguous later, when the guarded code is copied
# elsewhere in the same file, with nothing failing.
@test "refs: a fragment occurring twice in the cited file fails the check" {
  seed_source
  printf 'guard() {\n  timed_out "$ERR" || return 1\n}\n\nguard_again() {\n  timed_out "$ERR" || return 1\n}\n' \
    > "$TEST_TMP/skills/x.sh"
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"occurs more than once"* ]] || false
}

# Fails if an unbalanced backtick makes the links after it disappear.
#
# The masking pass blanks code spans before finding links, so a lone backtick
# swallows the rest of the field -- including the `](` that LOOSE watches for.
# _references then returns [] and the entry reports clean. That is precisely
# the "unrecognised links must be findings, never silently missing references"
# contract the function's own docstring states, and the guard cannot catch it
# because the evidence was erased in the same pass.
@test "refs: an unbalanced backtick in the field is a finding, not silence" {
  seed_source
  put_ref '**Where:** the `guard helper in [x.sh](../skills/x.sh) — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
}

# Fails if a KI or ENH entry with no parseable **Where:** field is skipped
# silently. A list item, a `**Where**:` typo or a dropped field all yield "",
# and verify_references answers that with a bare continue -- so the entry is
# never checked and the gate still says verified. Open questions legitimately
# have no Where field; known issues and enhancements do not.
@test "refs: an entry whose Where field does not parse is a finding" {
  seed_source
  put_ref '- **Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
}

# Fails if a link with an empty target is treated as an existence-only
# reference. `docs / ""` resolves to docs itself, which is a directory that
# exists, so a doc-internal anchor link passes the directory exemption and is
# never checked against anything.
@test "refs: a link with an empty target is not an existence-only reference" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`, [KI-42](#ki-42)'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
}

# CONTROL. Fails if a non-filesystem URL is stat-ed. The escape tests for
# "://", so an authority-less scheme such as mailto: falls through and is
# reported as a missing path that no author can satisfy.
@test "refs: a mailto link is left alone, not reported missing" {
  seed_source
  put_ref '**Where:** [x.sh](../skills/x.sh) — `timed_out "$ERR"`, [owner](mailto:someone@example.com)'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

# Fails if a reference outside the repository is read rather than refused.
#
# The repository here is $TEST_TMP/repo, so the outside file still sits inside
# the test's own temp tree and teardown removes it. The file is unreadable: a
# check that refuses on containment reports "outside repository", while one
# that reads first reports "cannot read cited path" instead.
@test "refs: a relative target outside the repository is refused, not read" {
  mkdir -p "$TEST_TMP/repo"
  mv "$DOCS" "$TEST_TMP/repo/docs"
  DOCS="$TEST_TMP/repo/docs"
  printf 'sentinel-value-for-this-test\n' > "$TEST_TMP/outside.txt"
  chmod 000 "$TEST_TMP/outside.txt"
  put_ref '**Where:** [outside](../../outside.txt) — `sentinel-value-for-this-test`'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cited path outside repository: ../../outside.txt"* ]] || false
  [[ "$output" != *"cannot read"* ]] || false
}

# Same property for an absolute target, which pathlib lets win outright over
# the docs directory it is joined to. Kept inside the test's temp tree.
@test "refs: an absolute target outside the repository is refused, not read" {
  mkdir -p "$TEST_TMP/repo"
  mv "$DOCS" "$TEST_TMP/repo/docs"
  DOCS="$TEST_TMP/repo/docs"
  printf 'sentinel-value-for-this-test\n' > "$TEST_TMP/outside.txt"
  chmod 000 "$TEST_TMP/outside.txt"
  put_ref "**Where:** [outside]($TEST_TMP/outside.txt) — \`sentinel-value-for-this-test\`"
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cited path outside repository: $TEST_TMP/outside.txt"* ]] || false
  [[ "$output" != *"cannot read"* ]] || false
}

# Fails if a reference-style link is verified without being checked. The
# parser recognises inline links only, and a reference-style link contains no
# inline `](` for the refusal guard to see, so the entry reported verified with
# no fragment at all.
@test "refs: a reference-style link is refused, not silently verified" {
  seed_source
  put_ref '**Where:** [x.sh][src] holds the guard

[src]: ../skills/x.sh'
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"KI-01: a link in this Where field is not in the accepted reference form"* ]] || false
}

# The rating scales come from the templates bundled beside roadmap.py. These
# tests run a copy of the skill so they can edit its templates.
skill_copy() {
  export SKILL="$TEST_TMP/skill"
  mkdir -p "$SKILL"
  cp "$RM" "$(dirname "$RM")"/*-template.md "$SKILL/"
  export RMC="$SKILL/roadmap.py"
}

@test "scales: a level added to a template is accepted in rank order" {
  # Fails while the ranks are hard-coded: an unknown level breaks the order check.
  skill_copy
  python3 - "$SKILL/KNOWN_ISSUES-template.md" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text()
row = next(l for l in t.splitlines(True) if l.startswith('| **Medium** |'))
p.write_text(t.replace(row, '| **Severe** | Between high and medium. |\n' + row, 1))
PY
  grep -q '^| \*\*Severe\*\*' "$SKILL/KNOWN_ISSUES-template.md" || false
  sed -i.bak 's/^\*\*Severity:\*\* Medium/**Severity:** Severe/' "$DOCS/KNOWN_ISSUES.md"
  sed -i.bak 's/doomed issue | Likely | Medium/doomed issue | Likely | Severe/' "$DOCS/ROADMAP.md"
  run python3 "$RMC" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

@test "scales: a reordered template changes the accepted order" {
  # Fails while the ranks are hard-coded: Low before Medium is refused.
  skill_copy
  python3 - "$SKILL/KNOWN_ISSUES-template.md" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]); s = p.read_text().splitlines(True)
m = next(i for i, l in enumerate(s) if l.startswith('| **Medium** |'))
l = next(i for i, l in enumerate(s) if l.startswith('| **Low** |'))
s[m], s[l] = s[l], s[m]; p.write_text(''.join(s))
PY
  sed -i.bak 's/^\*\*Severity:\*\* Medium/**Severity:** LOWTMP/; s/^\*\*Severity:\*\* Low/**Severity:** Medium/; s/LOWTMP/Low/' "$DOCS/KNOWN_ISSUES.md"
  sed -i.bak 's/doomed issue | Likely | Medium/doomed issue | Likely | Low/; s/third issue | Almost always | Low/third issue | Almost always | Medium/' "$DOCS/ROADMAP.md"
  run python3 "$RMC" check --docs "$DOCS"
  [ "$status" -eq 0 ]
}

@test "scales: a missing, empty or repeated scale is refused by name" {
  # Fails if a broken scale table is silently ignored instead of refused.
  skill_copy
  cp "$SKILL/KNOWN_ISSUES-template.md" "$TEST_TMP/ki.orig"
  for broken in missing tableless empty repeated; do
    cp "$TEST_TMP/ki.orig" "$SKILL/KNOWN_ISSUES-template.md"
    python3 - "$SKILL/KNOWN_ISSUES-template.md" "$broken" <<'PY'
import pathlib, re, sys
p = pathlib.Path(sys.argv[1]); t = p.read_text(); how = sys.argv[2]
rows = re.compile(r'^\| \*\*(Critical|High|Medium|Low)\*\* \|.*\n', re.M)
if how == 'missing':
    t = t.replace('## Severity', '## Seriousness', 1)
elif how == 'tableless':
    # The heading stays; its table goes, so the next section's table is nearest.
    t = re.sub(r'(## Severity\n)(?:.*\n)*?(?=## )', r'\1\nNo table.\n\n', t, count=1)
elif how == 'empty':
    t = rows.sub('', t)
else:
    first = rows.search(t)[0]
    t = t.replace(first, first + first, 1)
p.write_text(t)
PY
    run python3 "$RMC" check --docs "$DOCS"
    [ "$status" -eq 1 ] || false
    [[ "$output" == *"KNOWN_ISSUES-template.md"* ]] || false
    [[ "$output" == *"Severity"* ]] || false
  done
}

@test "scales: an unknown Kind is refused" {
  # Fails while Kind is only compared between the entry and its row, never against the scale.
  sed -i.bak 's/^\*\*Kind:\*\* Verification/**Kind:** Maybe/' "$DOCS/OPEN_QUESTIONS.md"
  sed -i.bak 's/a question | Verification/a question | Maybe/' "$DOCS/ROADMAP.md"
  run python3 "$RM" check --docs "$DOCS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown Kind: UNK-01"* ]]
}

@test "init: a fresh set-up passes the check" {
  # Fails if init leaves the templates' example rows in place (KI-40).
  NEW="$TEST_TMP/fresh/docs"
  run python3 "$RM" init --docs "$NEW"
  [ "$status" -eq 0 ] || false
  run python3 "$RM" check --docs "$NEW"
  [ "$status" -eq 0 ]
}

@test "init never touches an existing file, including a dangling symlink" {
  # Fails if init overwrites a file the project already has, or writes through a symlink.
  NEW="$TEST_TMP/partial/docs"; mkdir -p "$NEW"
  printf 'KEEP\n' > "$NEW/ENHANCEMENTS.md"
  ln -s "$TEST_TMP/nowhere.md" "$NEW/OPEN_QUESTIONS.md"
  run python3 "$RM" init --docs "$NEW"
  [ "$status" -eq 0 ] || false
  [ "$(cat "$NEW/ENHANCEMENTS.md")" = "KEEP" ] || false
  [ -L "$NEW/OPEN_QUESTIONS.md" ] || false
  [ ! -e "$TEST_TMP/nowhere.md" ] || false
  [ -f "$NEW/ROADMAP.md" ] || false
  [ -f "$NEW/KNOWN_ISSUES.md" ]
}

@test "init: a failure after the first file is created removes only what init created" {
  # Fails if a failed init leaves a partial set or a new docs/ behind, or removes a file it did not create.
  NEW="$TEST_TMP/broken/docs"; mkdir -p "$NEW"
  printf 'KEEP\n' > "$NEW/ENHANCEMENTS.md"
  FRESH="$TEST_TMP/fresh-broken/docs"
  run python3 - "$RM" "$NEW" "$FRESH" <<'PY'
import builtins, importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('roadmap', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
for target in sys.argv[2:]:
    created = []
    def flaky(path, mode='r', *a, **kw):
        if 'x' in mode:
            created.append(path)
            if len(created) == 2:
                raise OSError('injected failure on the second file')
        return builtins.open(path, mode, *a, **kw)
    m.open = flaky
    try:
        m.cmd_init(pathlib.Path(target))
    except SystemExit as e:
        print('exit', e.code)
PY
  [[ "$output" == *"exit 1"*"exit 1"* ]] || false
  [ "$(cat "$NEW/ENHANCEMENTS.md")" = "KEEP" ] || false
  [ "$(ls -A "$NEW")" = "ENHANCEMENTS.md" ] || false
  [ ! -e "$FRESH" ] || false
  # The parent init made for docs/ goes too.
  [ ! -e "$TEST_TMP/fresh-broken" ]
}

@test "init: a file replaced by someone else during set-up survives the rollback" {
  # Fails if rollback unlinks by name, deleting a file another writer put in place.
  NEW="$TEST_TMP/race/docs"
  run python3 - "$RM" "$NEW" <<'PY'
import builtins, importlib.util, os, pathlib, sys
spec = importlib.util.spec_from_file_location('roadmap', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
docs = pathlib.Path(sys.argv[2]); opened = []
def flaky(path, mode='r', *a, **kw):
    if 'x' in mode:
        opened.append(pathlib.Path(path))
        if len(opened) == 2:
            # Another writer replaces the first file, then this init fails.
            os.unlink(opened[0]); opened[0].write_text('THEIRS\n')
            raise OSError('injected failure on the second file')
    return builtins.open(path, mode, *a, **kw)
m.open = flaky
try:
    m.cmd_init(docs)
except SystemExit as e:
    print('exit', e.code)
print('first:', opened[0].read_text().strip() if opened[0].exists() else 'GONE')
PY
  [[ "$output" == *"exit 1"* ]] || false
  [[ "$output" == *"first: THEIRS"* ]]
}

@test "init: a file another init created meanwhile is left in place, not a failure" {
  # Fails if a concurrent init's file makes this one roll back, leaving the set incomplete.
  NEW="$TEST_TMP/twin/docs"
  run python3 - "$RM" "$NEW" <<'PY'
import builtins, importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('roadmap', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
docs = pathlib.Path(sys.argv[2]); seen = []
def racing(path, mode='r', *a, **kw):
    if 'x' in mode:
        seen.append(path)
        if len(seen) == 2:
            builtins.open(path, 'w').write('OTHER INIT\n')
    return builtins.open(path, mode, *a, **kw)
m.open = racing
try:
    print('rc', m.cmd_init(docs))
except SystemExit as e:
    print('exit', e.code)
print(sorted(p.name for p in docs.iterdir()))
PY
  [[ "$output" == *"rc 0"* ]] || false
  [[ "$output" == *"['ENHANCEMENTS.md', 'KNOWN_ISSUES.md', 'OPEN_QUESTIONS.md', 'ROADMAP.md']"* ]]
}

@test "init: a termination signal mid-set-up rolls back" {
  # Fails if SIGTERM kills init with a partial set on disk.
  NEW="$TEST_TMP/term/docs"
  run python3 - "$RM" "$NEW" <<'PY'
import builtins, importlib.util, os, pathlib, signal, sys
spec = importlib.util.spec_from_file_location('roadmap', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
count = []
def killed(path, mode='r', *a, **kw):
    if 'x' in mode:
        count.append(path)
        if len(count) == 3:
            os.kill(os.getpid(), signal.SIGTERM)
    return builtins.open(path, mode, *a, **kw)
m.open = killed
try:
    m.cmd_init(pathlib.Path(sys.argv[2]))
except SystemExit as e:
    print('exit', e.code)
PY
  [[ "$output" == *"exit 1"* ]] || false
  [ ! -e "$TEST_TMP/term" ]
}

@test "init: a docs path that is a file is refused cleanly" {
  # Fails if init crashes with a traceback when --docs names a file.
  printf 'x\n' > "$TEST_TMP/afile"
  run python3 "$RM" init --docs "$TEST_TMP/afile"
  [ "$status" -eq 1 ] || false
  [[ "$output" != *Traceback* ]] || false
  [ "$(cat "$TEST_TMP/afile")" = "x" ]
}

@test "init and check refuse a stray entry id" {
  # Fails if `init KI-01` is read as `init`, setting up files the user did not mean to create.
  run python3 "$RM" init KI-01 --docs "$TEST_TMP/stray/docs"
  [ "$status" -ne 0 ] || false
  [ ! -e "$TEST_TMP/stray" ] || false
  run python3 "$RM" check KI-01 --docs "$DOCS"
  [ "$status" -ne 0 ]
}

@test "init: keeps each template's header and scales" {
  # Fails if stripping the example entries also strips the scale tables or the index tables.
  NEW="$TEST_TMP/hdr/docs"
  run python3 "$RM" init --docs "$NEW"
  [ "$status" -eq 0 ] || false
  grep -q '^## Severity' "$NEW/KNOWN_ISSUES.md" || false
  grep -q '^## Likelihood' "$NEW/KNOWN_ISSUES.md" || false
  grep -q '^| ID | Issue |' "$NEW/ROADMAP.md"
}

@test "--docs may come before the subcommand" {
  # Fails if the option is accepted only after the subcommand, breaking the old spelling.
  run python3 "$RM" --docs "$DOCS" check
  [ "$status" -eq 0 ]
}

@test "init: a folder another init made meanwhile is used, not a failure" {
  # Fails if mkdir losing a race to a concurrent init rolls this one back.
  NEW="$TEST_TMP/mk/docs"
  run python3 - "$RM" "$NEW" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('roadmap', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
real = pathlib.Path.mkdir
def racing(self, *a, **kw):
    real(self, *a, **kw)        # someone else made it first
    return real(self, *a, **kw)
pathlib.Path.mkdir = racing
try:
    print('rc', m.cmd_init(pathlib.Path(sys.argv[2])))
except SystemExit as e:
    print('exit', e.code)
PY
  [[ "$output" == *"rc 0"* ]] || false
  [ -f "$NEW/ROADMAP.md" ]
}

@test "init: a signal between creating a file and recording it still rolls it back" {
  # Fails if a file made just before SIGTERM is left behind because it was never recorded.
  NEW="$TEST_TMP/gap/docs"
  run python3 - "$RM" "$NEW" <<'PY'
import importlib.util, os, pathlib, signal, sys
spec = importlib.util.spec_from_file_location('roadmap', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
real, calls = os.fstat, []
def fstat(fd):
    calls.append(fd)
    if len(calls) == 2:
        os.kill(os.getpid(), signal.SIGTERM)   # the file exists; it is not yet recorded
    return real(fd)
m.os.fstat = fstat
try:
    m.cmd_init(pathlib.Path(sys.argv[2]))
except SystemExit as e:
    print('exit', e.code)
PY
  [[ "$output" == *"exit 1"* ]] || false
  [ ! -e "$TEST_TMP/gap" ]
}
