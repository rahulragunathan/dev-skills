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
