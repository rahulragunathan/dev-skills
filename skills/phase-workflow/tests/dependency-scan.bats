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
if grep -q VULN "$file"; then sed "s|<FILE>|$file|" "$OSV/vuln.json"; exit 1; fi
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

@test "no dependency files: one line, exit 0, scanner not called" {
  # Control: a repository with nothing to scan says so and runs nothing.
  put README.md 'hello'
  scan
  [ "$status" -eq 0 ] || false
  [ "$output" = "no supported dependency files" ] || false
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
  put requirements.txt 'requests==2.19.0  # VULN'
  scan
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"FINDING PYSEC-2018-28 (CVE-2018-18074, GHSA-x84v-xcm2-53pg) requests 2.19.0 requirements.txt"* ]]
}

@test "findings and gaps are both printed" {
  # Fails if a coverage gap hides a finding, or the reverse.
  put requirements.txt 'requests==2.19.0  # VULN'
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
  [ "$output" = "no supported dependency files" ]
}

@test "a file yielding no packages is NOT SCANNED" {
  # Fails if exit 128, no packages found, counts as clean.
  put requirements.txt '# EMPTY'
  scan
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"NOT SCANNED requirements.txt: no packages found"* ]]
}

@test "unpinned requirements lines are listed as not scanned" {
  # Fails if a range the scanner skips silently goes unreported.
  put requirements.txt "$(printf 'six==1.17.0\nrequests>=2.0\n# a comment\n')"
  scan
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"NOT SCANNED requirements.txt: requests>=2.0 is not pinned"* ]] || false
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
  [[ "$output" == *"osv-scanner failed on uv.lock"*"boom"* ]] || false
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
  [[ "$output" == *"osv-scanner.toml ignores PYSEC-2018-28"* ]]
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
echo '{"results": [{"source": {"path": "x"}, "advisories": []}]}'; exit 1
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
