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
  # Fails if a link that leaves the repository is followed: the file exists and
  # has the anchor, so following it would pass, and it is unreadable, so
  # reading it would crash.
  put doc.md '[x](../outside.md#outside)'
  printf '# Outside\n' > "$TEST_TMP/outside.md"
  chmod 000 "$TEST_TMP/outside.md"
  check
  chmod 644 "$TEST_TMP/outside.md"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing link ../outside.md#outside — outside the repository"* ]]
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
  put gone/keep.md 'k'
  put doc.md 'Run `./trap.sh --x`, `bash ./trap.sh --x` and see `gone/x.md`.'
  check
  # The check ran to the end: it reported the name after the commands.
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing path gone/x.md"* ]] || false
  [ ! -e "$TEST_TMP/RAN" ]
}

@test "never runs a git hook while listing files" {
  # Fails if git ls-files runs a filesystem monitor the repository configures.
  printf '#!/bin/sh\ntouch "%s/HOOK"\n' "$TEST_TMP" > "$TEST_TMP/monitor.sh"
  chmod +x "$TEST_TMP/monitor.sh"
  put doc.md 'Plain text.'
  # Set last: the fixture's own git add would run the monitor too.
  git -C "$REPO" config core.fsmonitor "$TEST_TMP/monitor.sh"
  check
  [ "$status" -eq 0 ] || false
  [ ! -e "$TEST_TMP/HOOK" ]
}

@test "real skill prose gives no false positives" {
  # Fails if ordinary prose in the shipped skills is reported as a missing name.
  # The one line expected is a target-project example in design-review, which
  # cannot take an ignore comment: its pressure-test evidence records its hash.
  run python3 "$NC" --root "$PLUGIN" skills/design-review/SKILL.md skills/external-review/SKILL.md \
    skills/phase-workflow/SKILL.md skills/project-docs/SKILL.md
  [ "$status" -eq 1 ] || false
  [ "$output" = "skills/design-review/SKILL.md:215: missing path docs/build_system.py" ]
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
  put tools/keys.env/s.sh 'echo --hidden'
  put doc.md 'Run `tools/keys.env/s.sh --hidden`.'
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
src = open(sys.argv[2]).read()
capture = set(re.findall(r"':\(top,exclude,icase\)([^']+)'", src))
# capture.sh's plan mode has its own case list; it must agree too.
body = src[src.index("credential_shaped() {"):]
body = body[:body.index("\n}")]
cases = {p for line in re.findall(r"^\s+(\*[^)]*)\) return 0", body, re.M) for p in line.split("|")}
print(sorted(capture ^ set(m.SECRET_NAMES)), sorted(cases ^ set(m.SECRET_NAMES)))
PY
  [ "$status" -eq 0 ] || false
  [ "$output" = "[] []" ]
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

@test "a comment opener inside a code span does not hide the rest of the doc" {
  # Fails if a backticked `<!--` starts comment mode and blanks every later line.
  put skills/real.py 'x = 1'
  put doc.md "$(printf 'Open a comment with `<!--`.\n\nSee `skills/gone.py`.')"
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"doc.md:3: missing path skills/gone.py"* ]]
}

@test "a named doc that is not a tracked Markdown file is a usage error" {
  # Fails if a mistyped FILE argument is checked as an empty doc and passes.
  put README.md '# Readme'
  check READMEE.md
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"READMEE.md"* ]]
}

@test "a ./ prefix on a named doc does not defeat the history exclusions" {
  # Fails if FILE arguments are matched against the scope rules without normalising.
  put skills/real.py 'x = 1'
  put docs/superpowers/plans/2026-01-01-p.md '`skills/gone.py`'
  check ./docs/superpowers/plans/2026-01-01-p.md
  [ "$status" -eq 0 ]
}

@test "a query string or a repo-root link is resolved, not reported" {
  # Fails if `x.md?plain=1` or `/docs/x.md` is reported though GitHub resolves both.
  put docs/x.md '# X'
  put sub/doc.md '[a](../docs/x.md?plain=1) and [b](/docs/x.md)'
  check
  [ "$status" -eq 0 ]
}

@test "never reads through a symlinked folder to a credential-shaped one" {
  # Fails if only the spelled path is tested: lib looks harmless, but it is
  # tools/keys.env inside the repository.
  put tools/keys.env/s.sh 'echo --hidden'
  ln -s tools/keys.env "$REPO/lib"; git -C "$REPO" add lib
  put doc.md 'Run `lib/s.sh --hidden`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing flag --hidden"* ]]
}

@test "an ECDSA key and a .pypirc are credential-shaped" {
  # Fails if the name list misses id_ecdsa or .pypirc, so the check would open them.
  run python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("name_check", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print([n for n in ("home/id_ecdsa", "home/id_ecdsa.pub", ".pypirc") if not m.credential_shaped(n)])
' "$NC"
  [ "$output" = "[]" ]
}

@test "a flag is matched whole, not as part of a longer one" {
  # Fails if --format passes because the script defines --format-long.
  put tools/s.py "p.add_argument('--format-long')"
  put doc.md 'Run `python3 tools/s.py --format`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing flag --format"* ]]
}

@test "an ID mentioned only in ROADMAP prose does not vouch for itself" {
  # Fails if every ID-shaped string in the roadmap files counts as declared.
  put docs/ROADMAP.md 'See `KI-07` for the history.'
  put docs/KNOWN_ISSUES.md '<a id="ki-01"></a>'
  put doc.md 'Fixed in `KI-07`; still open: `KI-01`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"doc.md:1: missing id KI-07"* ]] || false
  [[ "$output" != *"missing id KI-01"* ]]
}

@test "a backticked ignore directive is an example, not a directive" {
  # Fails if a directive shown in a code span suppresses the next line.
  put skills/real.py 'x = 1'
  put doc.md "$(printf 'Write `<!-- name-check: ignore skills/gone.py -->` above it.\nSee `skills/gone.py`.')"
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"doc.md:2: missing path skills/gone.py"* ]]
}

@test "an id shown in a code span is not an anchor" {
  # Fails if a backticked <a id> example counts as a real anchor.
  put a.md 'Write `<a id="ki-09"></a>` before the heading.'
  put doc.md '[x](a.md#ki-09)'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing anchor a.md#ki-09"* ]]
}

@test "a named doc deleted from the work tree is a usage error" {
  # Fails if a tracked doc that cannot be read is checked as empty and passes.
  put doc.md 'See `gone.md`.'
  git -C "$REPO" commit -qm doc
  rm "$REPO/doc.md"
  check doc.md
  [ "$status" -eq 2 ]
}

@test "a line anchor suffix and a dated spec are handled" {
  # Fails if #L12 is kept on the path, or a dated spec is checked as a current doc.
  put skills/x.py 'x = 1'
  put doc.md 'See `skills/x.py#L12`.'
  put docs/superpowers/specs/2026-01-01-x.md '`skills/gone.py`'
  check
  [ "$status" -eq 0 ]
}

@test "a missing command outside the repository says so" {
  # Fails if a command path that leaves the root is reported without the reason.
  put doc.md 'Run `../outside/tool.sh --flag`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing command ../outside/tool.sh — outside the repository"* ]]
}

@test "an entry anchor shown as an example declares nothing" {
  # Fails if an <a id> in a code span or fence, or in the wrong detail file, declares an ID.
  put docs/KNOWN_ISSUES.md "$(printf 'Write `<a id="ki-08"></a>` above it.\n\n```\n<a id="ki-09"></a>\n```\n\n<a id="enh-03"></a>')"
  put doc.md 'See `KI-08`, `KI-09` and `ENH-03`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing id KI-08"* ]] || false
  [[ "$output" == *"missing id KI-09"* ]] || false
  [[ "$output" == *"missing id ENH-03"* ]]
}

@test "an ignore directive may name its target in backticks" {
  # Fails if backticks inside a real directive blank out the name it ignores.
  put skills/real.py 'x = 1'
  put doc.md "$(printf '<!-- name-check: ignore `skills/gone.py` -->\nSee `skills/gone.py`.')"
  check
  [ "$status" -eq 0 ]
}

@test "a tracked doc that cannot be read is said, not passed as empty" {
  # Fails if a full run checks a deleted tracked doc as an empty one, in silence.
  put doc.md 'See `gone.md`.'
  put other.md 'Fine.'
  git -C "$REPO" commit -qm docs
  rm "$REPO/doc.md"
  check
  [[ "$output" == *"cannot read: doc.md"* ]]
}

@test "an interpreter command outside the root names its script" {
  # Fails if the diagnostic names the interpreter instead of the script path.
  put doc.md 'Run `python3 ../outside/tool.py --flag`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing command ../outside/tool.py — outside the repository"* ]]
}

@test "a full run with an unreadable tracked doc exits 2 after checking the rest" {
  # Fails if the run reports success although a doc it should check was never read.
  put doc.md 'Fine.'
  put other.md 'See `skills/gone.py`.'
  put skills/real.py 'x = 1'
  git -C "$REPO" commit -qm docs
  rm "$REPO/doc.md"
  check
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"cannot read: doc.md"* ]] || false
  [[ "$output" == *"missing path skills/gone.py"* ]]
}

@test "an example directive before a real one on the same line does not lend its names" {
  # Fails if the names come from the first directive-shaped text, a backticked example.
  put skills/real.py 'x = 1'
  put doc.md "$(printf 'Write `<!-- name-check: ignore skills/other.py -->` <!-- name-check: ignore skills/gone.py -->\nSee `skills/gone.py` and `skills/other.py`.')"
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" != *"missing path skills/gone.py"* ]] || false
  [[ "$output" == *"missing path skills/other.py"* ]]
}

@test "an anchor in an indented code block declares nothing" {
  # Fails if an <a id> shown as indented example code is read as an entry declaration.
  put docs/KNOWN_ISSUES.md "$(printf 'Example:\n\n    <a id="ki-77"></a>\n')"
  put doc.md 'See `KI-77`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing id KI-77"* ]]
}

@test "an interpreter followed by a flag keeps the bare-program check" {
  # Fails if `node --version` loses its program check because node is an interpreter name.
  mkdir -p "$TEST_TMP/emptybin"
  put doc.md 'Run `node --version`.'
  PATH="$TEST_TMP/emptybin:/usr/bin:/bin" run python3 "$NC" --root "$REPO"
  if command -v node >/dev/null 2>&1 && PATH="$TEST_TMP/emptybin:/usr/bin:/bin" command -v node >/dev/null; then skip "node is on the system PATH"; fi
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing command node"* ]]
}

@test "an interpreter with a missing repo script reports the script" {
  # Control for F-147: `locate` names a path under a known root whether or not it exists, so a
  # missing script after an interpreter is still reported.
  put skills/real.py 'x = 1'
  put doc.md 'Run `python3 skills/gone.py --flag`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing command skills/gone.py"* ]]
}

# --- KI-68: an unreadable folder -----------------------------------------------

@test "a doc under a folder without search permission is reported, and the rest still checked" {
  # Fails if a denied folder stops the run before the other docs are checked (KI-68).
  [ "$(id -u)" -ne 0 ] || skip "root reads every folder"
  put locked/doc.md 'fine'
  put other.md 'See `skills/gone.py`.'
  put skills/real.py 'x = 1'
  chmod 000 "$REPO/locked"
  check
  chmod 755 "$REPO/locked"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"other.md:1: missing path skills/gone.py"* ]] || false
  [[ "$output" == *"cannot read: locked/doc.md"* ]] || false
  [[ "$output" != *"Traceback"* ]]
}

@test "a PermissionError from the metadata lookup is a doc that cannot be read" {
  # Fails if the lookup raises past the handler on a Python where it does not return False.
  put doc.md 'fine'
  put other.md 'See `skills/gone.py`.'
  put skills/real.py 'x = 1'
  run python3 - "$NC" "$REPO" <<'PY'
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('name_check', sys.argv[1])
m = importlib.util.module_from_spec(spec); sys.path.insert(0, str(pathlib.Path(sys.argv[1]).parent)); spec.loader.exec_module(m)
real = pathlib.Path.is_file
def is_file(self):
    if self.name == "doc.md": raise PermissionError(13, "Permission denied")
    return real(self)
pathlib.Path.is_file = is_file
sys.argv = ["name_check.py", "--root", sys.argv[2]]
print("exit", m.main())
PY
  [[ "$output" == *"other.md:1: missing path skills/gone.py"* ]] || false
  [[ "$output" == *"cannot read: doc.md"* ]] || false
  [[ "$output" == *"exit 2"* ]]
}

# --- ENH-33: more command spellings ------------------------------------------------

@test "an interpreter with a bare script name resolves it against tracked basenames" {
  # Fails if `python3 roadmap.py` is never checked because the script has no folder in it.
  put tools/roadmap.py 'import argparse; p.add_argument("--docs")'
  put doc.md 'Run `python3 roadmap.py --docs x` and `python3 roadmap.py --nope`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"doc.md:1: missing flag --nope"* ]] || false
  [[ "$output" != *"--docs"* ]]
}

@test "a bare script name that matches two files is not checked, and one that matches none is" {
  # Fails if an ambiguous name is guessed at, or a missing script passes.
  put a/x.py 'pass'
  put b/x.py 'pass'
  put doc.md 'Run `python3 x.py --any` and `python3 gone.py --any`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing command gone.py"* ]] || false
  [[ "$output" != *"--any"* ]]
}

@test "a lone flag beside a bare script in its own span is checked" {
  # Fails if `roadmap.py` in one span and `--fake` in another are never paired.
  put tools/roadmap.py 'p.add_argument("--docs")'
  put doc.md 'Give `roadmap.py` the flag `--fake`, or `--docs`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing flag --fake"* ]] || false
  [[ "$output" != *"--docs"* ]]
}

@test "a plugin-root path is checked from the repository root" {
  # Fails if "$CLAUDE_PLUGIN_ROOT/..." is skipped because it holds a $.
  put skills/a/run.sh 'echo --real'
  put doc.md 'Run `bash "$CLAUDE_PLUGIN_ROOT/skills/a/run.sh" --real` or `bash "$CLAUDE_PLUGIN_ROOT/skills/a/gone.sh" x`; helpers live under `$CLAUDE_PLUGIN_ROOT/skills/...`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing command skills/a/gone.sh"* ]] || false
  [[ "$output" != *"--real"* ]] || false
  [[ "$output" != *"skills/..."* ]]
}

@test "a missing repo script followed by a subcommand is reported" {
  # Fails if only a following --flag makes a bare script name count as a command.
  put tools/real.py 'pass'
  put doc.md 'Use `real.py run` or `gone.py run`, and `git status` as usual.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing command gone.py"* ]] || false
  [[ "$output" != *"real.py"* ]] || false
  [[ "$output" != *"git"* ]]
}

@test "a reference use whose definition was deleted is reported" {
  # Fails if [text][label] with no [label]: definition in the doc passes.
  put ok.md '# Ok'
  put doc.md "$(printf 'See [the guide][guide] and [this][kept].\n\n[kept]: ok.md')"
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing link [guide]"* ]] || false
  [[ "$output" != *"[kept]"* ]]
}

@test "an index expression is not a reference link" {
  # Fails if grid[row][col] in prose is reported as a link with no definition.
  put doc.md 'The cell is read as grid[row][col], or as m[0][1].'
  check
  [ "$status" -eq 0 ]
}

@test "a plugin-root path is read from the root only, a file directly under it included" {
  # Fails if a same-named folder beside the doc answers for it, or a root-level file is skipped (pass 1, Codex 25).
  put docs/skills/a/run.sh 'echo'
  put skills/b/real.sh 'echo'
  put docs/x.md 'Run `bash "$CLAUDE_PLUGIN_ROOT/skills/a/run.sh" x` and `bash "$CLAUDE_PLUGIN_ROOT/gone.sh" y`.'
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing command skills/a/run.sh"* ]] || false
  [[ "$output" == *"missing command gone.sh"* ]]
}

@test "a reference definition with no destination does not define its label" {
  # Fails if a bare `[label]:` counts as a definition.
  put doc.md "$(printf 'See [the guide][guide].\n\n[guide]:\n')"
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"missing link [guide]"* ]]
}

@test "a backticked reference label is read from the text, and an empty <> defines nothing" {
  # Fails if code spans blank a label to "", so any backticked definition covers every backticked use (pass 2, Gemini c3 1, 2).
  put ok.md '# Ok'
  put doc.md "$(printf 'See [the tool][`roadmap.py`] and [x][empty].\n\n[`other.py`]: ok.md\n[empty]: <>\n')"
  check
  [ "$status" -eq 1 ] || false
  [[ "$output" == *'missing link [`roadmap.py`]'* ]] || false
  [[ "$output" == *"missing link [empty]"* ]]
}
