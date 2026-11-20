#!/usr/bin/env bats
#
# The name check: names in Markdown that should exist in the repository.
# Every test names the condition that turns it red. Each builds its own git
# repository, because the check reads only tracked files.

setup() {
  export TEST_TMP="$(mktemp -d)"
  export REPO="$TEST_TMP/repo"
  mkdir -p "$REPO"
  local here; here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  export NC="$(dirname "$here")/name_check.py"
  export PLUGIN="$(cd "$here/../../.." && pwd)"
  git -C "$REPO" init -q -b main .
  git -C "$REPO" config user.email t@example.invalid
  git -C "$REPO" config user.name Test
}

teardown() { rm -rf "$TEST_TMP"; }

# put <path> <content>: write a file into the fixture repository and track it.
put() {
  mkdir -p "$(dirname "$REPO/$1")"
  printf '%s\n' "$2" > "$REPO/$1"
  git -C "$REPO" add -- "$1"
}

check() { run python3 "$NC" --root "$REPO" "$@"; }

@test "reports a missing repo path" {
  # Fails if a backticked path under a real top-level folder is not checked.
  put skills/real.py 'x = 1'
  put doc.md 'See `skills/gone.py`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"doc.md:1: missing path skills/gone.py"* ]]
}

@test "accepts root-relative and doc-relative paths" {
  # Fails if an existing path is reported because it was resolved from the wrong folder.
  put skills/a/x.py 'x = 1'
  put skills/a/README.md 'Root: `skills/a/x.py`. Relative: `./x.py` and `../a/x.py`.'
  check
  [ "$status" -eq 0 ]
}

@test "strips line and symbol suffixes" {
  # Fails if `path:12` or `path::test` is read as a file name of its own.
  put a/x.py 'def test_y(): pass'
  put doc.md 'At `a/x.py:12`, `a/x.py:3-9` and `a/x.py::test_y`.'
  check
  [ "$status" -eq 0 ]
}

@test "reports a link to a missing file and a missing anchor" {
  # Fails if a link target or its anchor is not checked.
  put ok.md '# Title'
  put doc.md '[a](nope.md) and [b](ok.md#nope)'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing link nope.md"* ]] || false
  [[ "$output" == *"missing anchor ok.md#nope"* ]]
}

@test "accepts a heading slug, a repeated heading and an a-id" {
  # Fails if anchors are not slugged the way GitHub slugs them.
  put ok.md "$(printf '## Two words\n\n## Two words\n\n<a id="ki-01"></a>\n\n## It'"'"'s `code`, here!')"
  put doc.md '[a](ok.md#two-words) [b](ok.md#two-words-1) [c](ok.md#ki-01) [d](ok.md#its-code-here)'
  check
  [ "$status" -eq 0 ]
}

@test "checks reference-style links" {
  # Fails if a reference-style link definition is skipped.
  put doc.md "$(printf 'See [x][g].\n\n[g]: gone.md')"
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing link gone.md"* ]]
}

@test "refuses a link outside the root without reading it" {
  # Fails if a link that leaves the repository is followed.
  put doc.md '[x](../../outside.md)'
  printf '# Outside\n' > "$TEST_TMP/outside.md"
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing link ../../outside.md — outside the repository"* ]]
}

@test "checks a flag against the repo script its command names" {
  # Fails if a flag on a repo script's command line is not looked up in that script.
  put tools/s.py "p.add_argument('--real')"
  put doc.md 'Run `python3 tools/s.py --real 1`, `python3 tools/s.py --fake` and `python3 tools/s.py --fake2=1`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" != *"missing flag --real"* ]] || false
  printf '%s\n' "$output" | grep -qE 'missing flag --fake$' || false
  [[ "$output" == *"missing flag --fake2"* ]]
}

@test "checks a lone flag only beside a repo command" {
  # Fails if a lone flag is checked with no command to own it, or not checked when one is named.
  put tools/s.py "p.add_argument('--real')"
  put alone.md 'Pass `--fake` to git.'
  put beside.md 'Run `tools/s.py run` with `--fake`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" != *"alone.md"* ]] || false
  [[ "$output" == *"beside.md:1: missing flag --fake"* ]]
}

@test "reports a missing command" {
  # Fails if a command whose program does not exist is accepted.
  put scripts/real.sh 'echo hi'
  put doc.md 'Run `scripts/none.sh run` or `nosuchtool-xyz --version`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing command scripts/none.sh"* ]] || false
  [[ "$output" == *"missing command nosuchtool-xyz"* ]]
}

@test "reports an ID found in no roadmap file or CHANGELOG" {
  # Fails if an ID is accepted without appearing in the roadmap files or CHANGELOG.
  put CHANGELOG.md '- Fixed KI-01.'
  put doc.md 'See `KI-99` and `KI-01`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing id KI-99"* ]] || false
  [[ "$output" != *"KI-01"* ]]
}

@test "an ignore comment covers its names on the next line only" {
  # Fails if the ignore comment is not honoured, or leaks past the next line.
  put skills/real.py 'x = 1'
  put doc.md "$(printf '<!-- name-check: ignore skills/gone.py skills/also.py -->\n`skills/gone.py` `skills/also.py`\n\n`skills/gone.py`')"
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" != *"doc.md:2:"* ]] || false
  [[ "$output" == *"doc.md:4: missing path skills/gone.py"* ]]
}

@test "skips CHANGELOG, templates, dated plans, fences and quoted fences" {
  # Fails if history files, templates or examples inside fences are checked.
  put skills/real.py 'x = 1'
  put CHANGELOG.md '`skills/gone.py`'
  put skills/X-template.md '`skills/gone.py`'
  put docs/superpowers/plans/2026-01-01-p.md '`skills/gone.py`'
  put doc.md "$(printf '```text\n`skills/gone.py`\n```\n\n> ```bash\n> `skills/gone.py`\n> ```')"
  check
  [ "$status" -eq 0 ]
}

@test "skips binary, symlinked and credential-shaped files" {
  # Fails if the check opens a binary, a symlink or a credential-shaped file to look for a flag.
  mkdir -p "$REPO/tools"
  printf 'x\0--hidden\n' > "$REPO/tools/blob.bin"
  git -C "$REPO" add tools/blob.bin
  put tools/credentials.json '"--hidden"'
  printf -- '--hidden\n' > "$REPO/tools/target.txt"
  ln -s target.txt "$REPO/tools/link.txt"; git -C "$REPO" add tools/link.txt
  put doc.md 'Run `tools/blob.bin --hidden`, `tools/credentials.json --hidden` and `tools/link.txt --hidden`.'
  check
  [ "$status" -eq 1 ] || false
  [ "$(printf '%s\n' "$output" | grep -c 'missing flag --hidden')" -eq 3 ]
}

@test "never runs a program named in a doc" {
  # Fails if the check executes a command it finds in Markdown.
  put trap.sh "$(printf '#!/bin/sh\ntouch "%s/RAN"' "$TEST_TMP")"
  chmod +x "$REPO/trap.sh"
  put doc.md 'Run `./trap.sh --x` and `bash trap.sh --x`.'
  check
  [ ! -e "$TEST_TMP/RAN" ]
}

@test "real skill prose gives no false positives" {
  # Fails if ordinary prose in the shipped skills is reported as a missing name.
  run python3 "$NC" --root "$PLUGIN" skills/design-review/SKILL.md skills/external-review/SKILL.md
  for name in billing.py mailer.py N/A auth/token.py bundle.txt origin/main; do
    [[ "$output" != *" $name"* ]] || false
  done
}

@test "accepts a path relative to the doc folder without a ./ prefix" {
  # Fails if `tests/x.bats` in a skill's doc is resolved only from the repository root.
  put tests/root.py 'x = 1'
  put skills/a/tests/x.bats 'true'
  put skills/a/SKILL.md 'Run `tests/x.bats`.'
  check
  [ "$status" -eq 0 ]
}

@test "accepts a bare command the repository defines" {
  # Fails if a subcommand defined in a repo script is reported as a missing program.
  put tools/s.py "sub.add_parser('log-dispatch')"
  put doc.md 'Then `log-dispatch --replace`.'
  check
  [ "$status" -eq 0 ]
}

@test "skips scenario files under tests/ but not a README there" {
  # Fails if test inputs are checked as docs, or if a tests/README.md is skipped.
  put skills/real.py 'x = 1'
  put skills/a/tests/s01-case.md '`skills/gone.py`'
  put skills/a/tests/README.md '`skills/gone.py`'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" != *"s01-case.md"* ]] || false
  [[ "$output" == *"skills/a/tests/README.md:1: missing path"* ]]
}

@test "skips a file under a credential-shaped folder" {
  # Fails if only the file's own name is tested against the credential names.
  put tools/credentials/s.sh 'echo --hidden'
  put doc.md 'Run `tools/credentials/s.sh --hidden`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing flag --hidden"* ]]
}

@test "the credential names match external-review's capture list" {
  # Fails if a pattern is added to capture.sh and not here, so the check could open a secret.
  run python3 - "$NC" "$PLUGIN/skills/external-review/capture.sh" <<'PY'
import importlib.util, re, sys
spec = importlib.util.spec_from_file_location('name_check', sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
capture = set(re.findall(r"':\(top,exclude,icase\)([^']+)'", open(sys.argv[2]).read()))
print(sorted(capture ^ set(m.SECRET_NAMES)))
PY
  [ "$status" -eq 0 ] || false
  [ "$output" = "[]" ]
}

@test "checks a path in a folder beside the doc" {
  # Fails if a skill-local folder that is not top-level is never checked.
  put skills/a/references/new.md '# New'
  put skills/a/SKILL.md 'See `references/old.md`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"skills/a/SKILL.md:1: missing path references/old.md"* ]]
}

@test "an XPath or a doubled slash is not a path" {
  # Fails if `.//mxCell` or `a//b` is read as a file path.
  put doc.md 'Query `.//mxCell` and `docs//x`.'
  put docs/real.md '# Real'
  check
  [ "$status" -eq 0 ]
}

@test "a path outside the repository says so" {
  # Fails if a ../ path that leaves the root is reported as an ordinary missing path.
  put doc.md 'See `../sibling.skill`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing path ../sibling.skill — outside the repository"* ]]
}

@test "never reads through a tracked symlink to a folder outside the root" {
  # Fails if a file under a symlinked folder is opened, leaking whether a string occurs outside.
  mkdir -p "$TEST_TMP/outside"
  printf -- '--secretflag\n' > "$TEST_TMP/outside/tool.sh"
  ln -s "$TEST_TMP/outside" "$REPO/ext"; git -C "$REPO" add ext
  put doc.md 'Run `ext/tool.sh --secretflag`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing command ext/tool.sh"* ]]
}
