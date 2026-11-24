#!/usr/bin/env bats
#
# dependency-scan.py: known vulnerabilities in the committed dependency files.
# Every test names the condition that turns it red. The fake osv-scanner replays
# answers recorded from osv-scanner 2.7.1 (fixtures/osv/README.md).

setup() {
  export TEST_TMP="$(mktemp -d)"
  export REPO="$TEST_TMP/my repo"
  export BIN="$TEST_TMP/bin"
  export SCAN="$BATS_TEST_DIRNAME/../dependency-scan.py"
  export OSV="$BATS_TEST_DIRNAME/fixtures/osv"
  mkdir -p "$REPO" "$BIN"
  git -C "$REPO" init -q -b main .
  git -C "$REPO" config user.email t@example.invalid
  git -C "$REPO" config user.name Test
  # The fake answers by the scanned file's content: VULN, EMPTY, FAIL, or clean.
  cat > "$BIN/osv-scanner" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_TMP/calls"
[ "$1 $2" = "scan source" ] || { echo "unknown command: $1" >&2; exit 127; }
file=""; prev=""
for a in "$@"; do [ "$prev" = -L ] && file="${a#*:}"; prev="$a"; done
case " $* " in *" --offline "*) [ -n "${FAKE_NO_DB:-}" ] && { echo "no local database" >&2; exit 127; } ;; esac
[ -f "$file" ] || { echo "failed to resolve path: $file" >&2; exit 127; }
if grep -qE "VULN|==2\.19\.0" "$file"; then sed "s|<FILE>|$file|" "$OSV/vuln.json"; exit 1; fi
if grep -q EMPTY "$file"; then echo "found 0 packages" >&2; exit 128; fi
if grep -q FAIL "$file"; then echo "boom: the database is unreachable" >&2; exit 127; fi
sed "s|<FILE>|$file|" "$OSV/clean.json"; exit 0
SH
  chmod +x "$BIN/osv-scanner"
  export PATH="$BIN:/usr/bin:/bin"   # not the real osv-scanner
}

teardown() { rm -rf "$TEST_TMP"; }

# put <path> <content>: write a file into the fixture repository and commit it.
put() {
  mkdir -p "$(dirname "$REPO/$1")"
  printf '%s\n' "$2" > "$REPO/$1"
  git -C "$REPO" add -- "$1" && git -C "$REPO" commit -qm "add $1"
}

scan() { run python3 "$SCAN" --root "$REPO" "$@"; }

@test "no dependency files: says so, exit 0, scanner not called" {
  # Control: a repository with nothing to scan says so and runs nothing.
  put README.md 'hello'
  scan
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"no supported dependency files" ]] || false
  [ ! -e "$TEST_TMP/calls" ]
}

@test "a clean lockfile is scanned and counted" {
  # Fails if a supported lockfile is never passed to the scanner.
  put uv.lock 'clean'
  scan
  [ "$status" -eq 0 ] || false
  [ "$(wc -l < "$TEST_TMP/calls" | tr -d ' ')" = 1 ] || false
  [[ "$output" == *"1 file scanned: no known vulnerabilities"* ]]
}

@test "only committed files are scanned, and a tracked symlink is not followed" {
  # Fails if untracked or ignored files, an untracked config, or a symlink's target reach the scan.
  put requirements.txt 'six==1.17.0'
  put uv.lock 'clean'
  put package-lock.json 'clean'
  printf 'VULN\n' > "$REPO/poetry.lock"
  mkdir -p "$REPO/node_modules/x" && printf 'VULN\n' > "$REPO/node_modules/x/package-lock.json"
  printf 'VULN\n' > "$TEST_TMP/outside.lock"
  mkdir -p "$REPO/sub" && ln -s "$TEST_TMP/outside.lock" "$REPO/sub/Cargo.lock"
  git -C "$REPO" add sub/Cargo.lock && git -C "$REPO" commit -qm link
  scan
  [ "$status" -eq 3 ] || false              # the symlinked lockfile is a gap, not read
  [ "$(wc -l < "$TEST_TMP/calls" | tr -d ' ')" = 3 ] || false
  [[ "$(cat "$TEST_TMP/calls")" != *poetry.lock* ]] || false
  [[ "$(cat "$TEST_TMP/calls")" != *node_modules* ]] || false
  [[ "$(cat "$TEST_TMP/calls")" != *Cargo.lock* ]]
}

@test "a finding prints its advisory group, aliases, package, version and file" {
  # Fails if a vulnerable lockfile reads as clean or loses what identifies the advisory.
  put requirements.txt 'requests==2.19.0'
  scan
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"FINDING PYSEC-2018-28 (CVE-2018-18074, GHSA-x84v-xcm2-53pg) requests 2.19.0 requirements.txt"* ]]
}

@test "findings and gaps are both printed" {
  # Fails if a coverage gap hides a finding, or the reverse.
  put requirements.txt 'requests==2.19.0'
  put web/package.json '{"dependencies": {"left-pad": "1.3.0"}}'
  scan
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"FINDING PYSEC-2018-28"* ]] || false
  [[ "$output" == *"NOT SCANNED web/package.json"* ]]
}

@test "a manifest with dependencies and no lockfile is NOT SCANNED, exit 3" {
  # Fails if a project whose dependencies were never resolved reads as clean.
  put pyproject.toml "$(printf '[project]\nname = "x"\ndependencies = ["requests>=2"]\n')"
  scan
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"NOT SCANNED pyproject.toml: declares dependencies and has no lockfile"* ]]
}

@test "a workspace package covered by the root lockfile is not a gap" {
  # Fails if a manifest below a folder holding its ecosystem's lockfile is reported.
  put package-lock.json 'clean'
  put packages/a/package.json '{"dependencies": {"x": "1.0.0"}}'
  scan
  [ "$status" -eq 0 ] || false
  [[ "$output" != *"NOT SCANNED"* ]]
}

@test "a tooling-only pyproject.toml is not a gap" {
  # Fails if a pyproject.toml holding only tool settings is taken for a project with dependencies.
  put pyproject.toml "$(printf '[tool.ruff]\nline-length = 100\n')"
  scan
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"no supported dependency files" ]]
}

@test "a file yielding no packages is NOT SCANNED" {
  # Fails if exit 128, no packages found, counts as clean.
  put uv.lock 'EMPTY'
  scan
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"NOT SCANNED uv.lock: no packages found"* ]]
}

@test "unpinned requirements lines are listed as not scanned" {
  # Fails if a range the scanner skips silently goes unreported.
  put requirements.txt "$(printf 'six==1.17.0\nrequests>=2.0\n# a comment\n')"
  scan
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"NOT SCANNED requirements.txt: line 2 is not pinned"* ]] || false
  [[ "$output" != *"comment"* ]]
}

@test "a missing scanner exits 2 with the install hint" {
  # Fails if a scan that could not run reads as clean.
  put uv.lock 'clean'
  rm "$BIN/osv-scanner"
  scan
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"osv-scanner is not installed"*"brew install osv-scanner"* ]]
}

@test "a v1 scanner and a scanner failure each exit 2" {
  # Fails if an error from the scanner is read as no findings.
  put uv.lock 'FAIL'
  scan
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"osv-scanner failed on uv.lock (exit 127)"* ]] || false
  printf '#!/bin/bash\necho "unknown command: scan" >&2; exit 127\n' > "$BIN/osv-scanner"
  put requirements.txt 'six==1.17.0'
  scan
  [ "$status" -eq 2 ]
}

@test "--offline without a database exits 2" {
  # Fails if an offline run with nothing to compare against reads as clean.
  put uv.lock 'clean'
  FAKE_NO_DB=1 scan --offline
  [ "$status" -eq 2 ] || false
  grep -q -- '--offline' "$TEST_TMP/calls"
}

@test "a tracked osv-scanner.toml is named with what it ignores" {
  # Fails if a committed suppression changes the verdict without the output saying so.
  put uv.lock 'clean'
  put osv-scanner.toml "$(printf '[[IgnoredVulns]]\nid = "PYSEC-2018-28"\nreason = "not reachable"\n')"
  scan
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"osv-scanner.toml can suppress findings: PYSEC-2018-28"* ]]
}

@test "paths with a space or a colon reach the scanner intact" {
  # Fails if a path is split or its colon read as the parser separator.
  put "a:b/c d/uv.lock" 'clean'
  scan
  [ "$status" -eq 0 ] || false
  grep -qF -- "-L uv.lock:" "$TEST_TMP/calls" || false
  grep -qF "a:b/c d/uv.lock" "$TEST_TMP/calls"
}

# fence_in <shell...>: the documented dependency-scan fence, run from the repository.
fence_in() {
  put uv.lock 'clean'
  python3 "$BATS_TEST_DIRNAME/../../../tests/fence.py" "$BATS_TEST_DIRNAME/../SKILL.md" dependency-scan > "$TEST_TMP/fence.sh"
  cd "$REPO"
  CLAUDE_PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)" run "$@" "$TEST_TMP/fence.sh"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"1 file scanned: no known vulnerabilities"* ]]
}

@test "bash: the documented fence scans the repository" {
  # Fails if the fence names the helper wrongly or runs it outside the repository.
  fence_in bash
}

@test "zsh: the documented fence scans the repository" {
  # Fails if the fence reads differently under zsh.
  command -v zsh >/dev/null || skip "zsh is not installed"
  fence_in zsh -f
}

# --- /code-review high fixes ---------------------------------------------------

@test "exit 1 with no readable finding is a scanner failure, not clean" {
  # Fails if osv-scanner says it found something and the run still reports clean.
  put uv.lock 'VULNSHAPE'
  cat > "$BIN/osv-scanner" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_TMP/calls"
echo '{"results": [{"source": {"path": "x"}, "packages": [{"package": {"name": "x", "version": "1"}, "advisories": []}]}]}'; exit 1
SH
  chmod +x "$BIN/osv-scanner"
  scan
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"reported vulnerabilities but none could be read"* ]]
}

@test "a lockfile marked export-ignore is still scanned" {
  # Fails if git archive's export-ignore drops a committed lockfile from the scan.
  put composer.lock 'clean'
  put .gitattributes 'composer.lock export-ignore'
  scan
  [ "$status" -eq 0 ] || false
  grep -q 'composer.lock' "$TEST_TMP/calls"
}

@test "a tracked symlink named like a lockfile is a coverage gap" {
  # Fails if a lockfile that is a symlink is skipped without a word.
  printf 'VULN\n' > "$TEST_TMP/outside.lock"
  ln -s "$TEST_TMP/outside.lock" "$REPO/Cargo.lock"
  git -C "$REPO" add Cargo.lock && git -C "$REPO" commit -qm link
  scan
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"NOT SCANNED Cargo.lock: a symlink, not read"* ]]
}

@test "hash-pinned requirements are pinned" {
  # Fails if pip-compile's hash lines are each reported as unpinned.
  put requirements.txt "$(printf 'six==1.17.0 \\\n    --hash=sha256:abc\nidna==3.7 --hash=sha256:def\n')"
  scan
  [ "$status" -eq 0 ] || false
  [[ "$output" != *"NOT SCANNED"* ]]
}

@test "dependency groups and optional dependencies count as declared" {
  # Fails if a pyproject.toml whose dependencies sit in a group is read as tooling-only.
  local body
  for body in '[dependency-groups]\ndev = ["requests==2.0"]\n' '[project.optional-dependencies]\nweb = ["flask"]\n' \
              '[tool.poetry.group.dev-tools.dependencies]\npytest = "^8"\n'; do
    printf "$body" > "$REPO/pyproject.toml"; git -C "$REPO" add pyproject.toml; git -C "$REPO" commit -qm "$body"
    scan
    [ "$status" -eq 3 ] || { echo "$body: $output"; false; }
  done
}

# --- external review pass 1 fixes ----------------------------------------------

@test "a requirements file that includes another file is NOT SCANNED and never reaches the scanner" {
  # Fails if osv-scanner follows a committed -r include, which can reach files outside HEAD.
  put requirements.txt "$(printf 'six==1.17.0\n-r ../../outside.txt\n')"
  scan
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"NOT SCANNED requirements.txt: line 2 includes another file"* ]] || false
  [[ "$(cat "$TEST_TMP/calls")" != *"requirements.txt:$REPO"* ]]   # the committed file never reaches it
}

@test "an unpinned line is named by its number, never its text" {
  # Fails if a URL requirement carrying credentials is copied into the report.
  put requirements.txt "$(printf 'six==1.17.0\npkg @ https://user:s3cret@example.invalid/pkg.tar.gz\n')"
  scan
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"NOT SCANNED requirements.txt: line 2 is not pinned"* ]] || false
  [[ "$output" != *"s3cret"* ]]
}

@test "scanner errors are printed with credentials masked" {
  # Fails if a URL with userinfo in osv-scanner's stderr reaches the report.
  put uv.lock 'clean'
  printf '#!/bin/bash\necho "fetch https://user:s3cret@db.example.invalid/x failed" >&2; exit 127\n' > "$BIN/osv-scanner"
  scan
  [ "$status" -eq 2 ] || false
  [[ "$output" != *"s3cret"* ]]
}

@test "a tracked osv-scanner.toml names single-quoted ids and package overrides" {
  # Fails if a valid suppression is reported as ignoring nothing.
  put uv.lock 'clean'
  put osv-scanner.toml "$(printf "[[IgnoredVulns]]\nid = 'PYSEC-1'\n\n[[PackageOverrides]]\nname = \"left-pad\"\nignore = true\n")"
  scan
  [[ "$output" == *"osv-scanner.toml can suppress findings: PYSEC-1, a package override"* ]]
}

@test "only dependency files are read from HEAD" {
  # Fails if every committed blob is copied out, credential-shaped files included.
  put uv.lock 'clean'
  put src/app.py 'print(1)'
  put .env 'NOT-A-REAL-SECRET'
  local real_git; real_git="$(command -v git)"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/git-calls"\nexec "%s" "$@"\n' "$TEST_TMP" "$real_git" > "$BIN/git"
  chmod +x "$BIN/git"
  scan
  [ "$status" -eq 0 ] || false
  [ "$(grep -c 'cat-file' "$TEST_TMP/git-calls")" -eq 1 ]
}

@test "exit 0 with no readable results is a scanner failure" {
  # Fails if an empty or malformed answer with exit 0 is counted as clean.
  local body
  put uv.lock 'clean'
  for body in '' '{}' '{"results": null}'; do
    printf '#!/bin/bash\nprintf "%%s" %q; exit 0\n' "$body" > "$BIN/osv-scanner"
    scan
    [ "$status" -eq 2 ] || { echo "[$body]: $status $output"; false; }
  done
}

@test "wildcard and editable requirements are NOT SCANNED" {
  # Fails if ==2.* or -e lines pass as pinned.
  put requirements.txt "$(printf 'six==1.17.0\nrequests==2.*\n-e .\n')"
  scan
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"line 2 is not pinned"* ]] || false
  [[ "$output" == *"line 3 is not pinned"* ]]
}

@test "require-dev, peer dependencies, python-dateutil and an indented key count as declared" {
  # Fails if a manifest whose only dependencies sit in these places is read as tooling-only.
  local f body
  for f in composer.json package.json pyproject.toml pyproject.toml; do :; done
  put composer.json '{"require-dev": {"phpunit/phpunit": "^10"}}'
  scan; [[ "$output" == *"NOT SCANNED composer.json"* ]] || false
  git -C "$REPO" rm -q composer.json && git -C "$REPO" commit -qm rm
  put package.json '{"peerDependencies": {"react": "^18"}}'
  scan; [[ "$output" == *"NOT SCANNED package.json"* ]] || false
  git -C "$REPO" rm -q package.json && git -C "$REPO" commit -qm rm
  put pyproject.toml "$(printf '[tool.poetry.dependencies]\npython-dateutil = "^2"\n')"
  scan; [[ "$output" == *"NOT SCANNED pyproject.toml"* ]] || false
  put pyproject.toml "$(printf '[project]\n  dependencies = ["x"]\n')"
  scan; [[ "$output" == *"NOT SCANNED pyproject.toml"* ]]
}

@test "a symlinked manifest is a coverage gap" {
  # Fails if a manifest that is a symlink disappears from the report.
  printf '{"dependencies": {"x": "1"}}' > "$TEST_TMP/outside.json"
  ln -s "$TEST_TMP/outside.json" "$REPO/package.json"
  git -C "$REPO" add package.json && git -C "$REPO" commit -qm link
  scan
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"NOT SCANNED package.json: a symlink, not read"* ]]
}

@test "other formats osv-scanner reads are scanned" {
  # Fails if a pubspec.lock or mix.lock reads as nothing to scan.
  put pubspec.lock 'clean'
  put mix.lock 'clean'
  scan
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"2 files scanned"* ]]
}

# --- external review pass 2 fixes ----------------------------------------------

@test "the scanner gets only the validated pins, never the committed requirements file" {
  # Fails if a continuation-joined or attached include, or an env-var version, reaches the scanner (pass 2, Codex 1, 11).
  put requirements.txt "$(printf 'six==1.17.0\n-r\\\n  ../../x.txt\n-rother.txt\nreq==${VER}\n')"
  cat > "$BIN/osv-scanner" <<'SH'
#!/bin/bash
prev=""; for a in "$@"; do [ "$prev" = -L ] && cp "${a#*:}" "$TEST_TMP/scanned"; prev="$a"; done
cat "$OSV/clean.json"; exit 0
SH
  chmod +x "$BIN/osv-scanner"
  scan
  [ "$status" -eq 3 ] || false
  [ "$(cat "$TEST_TMP/scanned")" = "six==1.17.0" ] || false
  [[ "$output" == *"line 2"* ]] || false
  [[ "$output" == *"line 4"* ]] || false
  [[ "$output" == *"line 5 is not pinned"* ]]
}

@test "scanner stderr never reaches the report" {
  # Fails if any of osv-scanner's own error text, a signed URL or token included, is copied out (Codex 7).
  put uv.lock 'clean'
  printf '#!/bin/bash\necho "GET https://db.example.invalid/x?sig=TOPSECRET failed" >&2; exit 127\n' > "$BIN/osv-scanner"
  scan
  [ "$status" -eq 2 ] || false
  [[ "$output" != *"TOPSECRET"* ]] || false
  [[ "$output" == *"osv-scanner failed on uv.lock (exit 127)"* ]]
}

@test "a results entry without packages is unreadable output, not clean" {
  # Fails if {"results":[{}]} counts as a scanned, clean file (Codex 10).
  put uv.lock 'clean'
  printf '#!/bin/bash\necho %s; exit 0\n' "'{\"results\": [{}]}'" > "$BIN/osv-scanner"
  scan
  [ "$status" -eq 2 ] || false
}

@test "a later Poetry group and a Dart manifest count as declared" {
  # Fails if only the first Poetry table is read, or pubspec.yaml is not a manifest (Codex 11).
  put pyproject.toml "$(printf '[tool.poetry.dependencies]\npython = "^3.11"\n\n[tool.poetry.group.dev.dependencies]\npytest = "^8"\n')"
  scan; [[ "$output" == *"NOT SCANNED pyproject.toml"* ]] || false
  git -C "$REPO" rm -q pyproject.toml && git -C "$REPO" commit -qm rm
  put pubspec.yaml "$(printf 'name: app\ndependencies:\n  http: ^1.0.0\n')"
  scan; [[ "$output" == *"NOT SCANNED pubspec.yaml"* ]]
}

@test "the report names the commit it scanned" {
  # Fails if the scanned commit has to be found separately and may describe another state (Codex 20).
  put uv.lock 'clean'
  scan
  [[ "$output" == *"scanned commit $(git -C "$REPO" rev-parse HEAD)"* ]]
}

# spy: a fake scanner that copies what it was given, notes whether a config sat beside it,
# and answers clean.
spy() {
  cat > "$BIN/osv-scanner" <<'SH'
#!/bin/bash
prev=""; for a in "$@"; do
  if [ "$prev" = -L ]; then f="${a#*:}"; cp "$f" "$TEST_TMP/scanned"
    [ -f "$(dirname "$f")/osv-scanner.toml" ] && echo beside > "$TEST_TMP/config"; fi
  prev="$a"; done
cat "$OSV/clean.json"; exit 0
SH
  chmod +x "$BIN/osv-scanner"
}

@test "an indented include or editable line is a gap, and a comment never swallows the next pin" {
  # Fails if leading whitespace lets option stripping erase a directive, or a comment ending in a
  # backslash joins the next requirement into the comment (pass 3, Codex 1, Gemini 2).
  put requirements.txt "$(printf 'six==1.17.0\n  --requirement other.txt\n  --editable ./local\n# note \\\nreq==1.0\n')"
  spy
  scan
  [ "$status" -eq 3 ] || false
  [ "$(cat "$TEST_TMP/scanned")" = "$(printf 'six==1.17.0\nreq==1.0')" ] || false
  [[ "$output" == *"line 2 includes another file"* ]] || false
  [[ "$output" == *"NOT SCANNED requirements.txt: line 3"* ]]
}

@test "the scanner gets only a name and a checked version, never a URL or a variable" {
  # Fails if a URL-shaped version, a marker, or a \${...} variable reaches the scanner (pass 3, Codex 2).
  put requirements.txt "$(printf 'six==1.17.0 ; python_version >= "3"\na===https://x.example/p?tok=SECRET\nb==1.0 ; extra == "${X}"\n')"
  spy
  scan
  [ "$status" -eq 3 ] || false
  [ "$(cat "$TEST_TMP/scanned")" = "six==1.17.0" ] || false
  [[ "$output" == *"line 2"* ]] || false
  [[ "$output" == *"line 3"* ]] || false
  [[ "$output" != *SECRET* ]]
}

@test "a requirements file is scanned beside its tracked osv-scanner.toml" {
  # Fails if the checked copy is scanned from a folder the file's own config does not reach (pass 3, Codex 3).
  put sub/requirements.txt 'six==1.17.0'
  put sub/osv-scanner.toml "$(printf '[[IgnoredVulns]]\nid = "GHSA-1"\n')"
  spy
  scan
  [ "$status" -eq 0 ] || false
  [ "$(cat "$TEST_TMP/config")" = beside ]
}

# answer <json>: a fake scanner that prints <json> and exits 1, as when it found something.
answer() {
  printf '#!/bin/bash\ncat <<"JSON"\n%s\nJSON\nexit 1\n' "$1" > "$BIN/osv-scanner"
  chmod +x "$BIN/osv-scanner"
}

@test "an advisory the scan cannot name is a scanner failure, even beside a readable one" {
  # Fails if a vulnerable package with no groups, a string ids, or an empty group is dropped or
  # misread while another package's finding passes the exit-1 check (pass 3, Codex 4, Gemini 10).
  put uv.lock 'clean'
  ok='{"package": {"name": "a", "version": "1"}, "groups": [{"ids": ["GHSA-ok"]}], "vulnerabilities": [{"id": "GHSA-ok"}]}'
  for bad in '{"package": {"name": "b", "version": "1"}, "vulnerabilities": [{"id": "GHSA-lost"}]}' \
             '{"package": {"name": "b", "version": "1"}, "groups": [{"ids": "GHSA-str"}]}' \
             '{"package": {"name": "b", "version": "1"}, "groups": [{}]}'; do
    answer "{\"results\": [{\"packages\": [$ok, $bad]}]}"
    scan
    [ "$status" -eq 2 ] || false
    [[ "$output" == *"unreadable output for uv.lock"* ]] || false
  done
}
