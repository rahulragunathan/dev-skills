#!/usr/bin/env bats
setup() {
  T="$(mktemp -d)"
  SCRIPT="$BATS_TEST_DIRNAME/../install-link.sh"
  mkdir "$T/source" "$T/link"
  echo original > "$T/link/keep"
}
teardown() { rm -rf "$T"; }
@test "missing source leaves the existing setup directory enabled" {
  run bash "$SCRIPT" "$T/missing" "$T/link"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SOURCE"* ]]
  [ -f "$T/link/keep" ]
  [ ! -e "$T/link.local.bak" ]
}
@test "link failure restores the original setup directory" {
  mkdir "$T/bin"
  printf '#!/bin/sh\nexit 1\n' > "$T/bin/ln"
  chmod +x "$T/bin/ln"
  PATH="$T/bin:$PATH" run bash "$SCRIPT" "$T/source" "$T/link"
  [ "$status" -eq 1 ]
  [[ "$output" == *"LINK FAILED"* ]]
  [ -f "$T/link/keep" ]
}
@test "successful link keeps original backup and resolves to physical source" {
  run bash "$SCRIPT" "$T/source" "$T/link"
  [ "$status" -eq 0 ]
  [ -L "$T/link" ]
  [ -f "$T/link.local.bak/keep" ]
  [ "$(cd "$T/link" && pwd -P)" = "$(cd "$T/source" && pwd -P)" ]
}
@test "rerunning a correct link succeeds and retains the original backup" {
  bash "$SCRIPT" "$T/source" "$T/link"
  run bash "$SCRIPT" "$T/source" "$T/link"
  [ "$status" -eq 0 ]
  [ -f "$T/link.local.bak/keep" ]
}

@test "adversarial: README installation replaces a real directory with a verified link" {
  local plugin; plugin="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  mkdir -p "$T/home/.claude/localclaude-plugins"
  echo KEEP > "$T/home/.claude/localclaude-plugins/keep"
  python3 - "$plugin/README.md" "$T/source" "$T/readme.sh" <<'PY'
import pathlib,re,sys
block=re.search(r'```bash\n(.*?)```',pathlib.Path(sys.argv[1]).read_text(),re.S)[1]
pathlib.Path(sys.argv[3]).write_text(block.replace('<abs path to Code/Plugins>',sys.argv[2]).replace('$HOME', '$SETUP_TEST_HOME'))
PY
  SETUP_TEST_HOME="$T/home" CLAUDE_PLUGIN_ROOT="$plugin" run bash "$T/readme.sh"
  [ "$status" -eq 0 ]
  [ -L "$T/home/.claude/localclaude-plugins" ]
  [ -f "$T/home/.claude/localclaude-plugins.local.bak/keep" ]
}

@test "QC T2-1: moved sources repoint repeatedly without consuming the directory backup" {
  bash "$SCRIPT" "$T/source" "$T/link"
  mkdir "$T/second" "$T/third"
  for source in second third; do
    run bash "$SCRIPT" "$T/$source" "$T/link"
    [ "$status" -eq 0 ]
    [ "$(readlink "$T/link")" = "$(cd "$T/$source" && pwd -P)" ]
    [ "$(cat "$T/link.local.bak/keep")" = original ]
  done
}

@test "QC T2-1: candidate link failure never moves the destination" {
  mkdir "$T/bin"
  printf '#!/bin/sh\nexit 1\n' > "$T/bin/ln"
  printf '#!/bin/sh\necho moved >> "%s"\nexec /bin/mv "$@"\n' "$T/moves" > "$T/bin/mv"
  chmod +x "$T/bin/ln" "$T/bin/mv"
  PATH="$T/bin:$PATH" run bash "$SCRIPT" "$T/source" "$T/link"
  [ "$status" -eq 1 ]
  [ -f "$T/link/keep" ]
  [ ! -e "$T/moves" ]
}

@test "QC T2-7: setup link examples run with no installed plugin root" {
  local plugin; plugin="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  mkdir -p "$T/code/Plugins/localclaude/skills/claude-setup" "$T/code/Skills" "$T/home"
  cp "$SCRIPT" "$T/code/Plugins/localclaude/skills/claude-setup/"
  python3 - "$plugin/skills/claude-setup/SKILL.md" "$T/examples" <<'PY'
import pathlib,re,sys
blocks=re.findall(r'```bash\n(.*?)```',pathlib.Path(sys.argv[1]).read_text(),re.S)
blocks=[b for b in blocks if 'install-link.sh' in b]
assert len(blocks)==2
pathlib.Path(sys.argv[2]).write_text('\n'.join(blocks).replace('$HOME', '$SETUP_TEST_HOME'))
PY
  env -u CLAUDE_PLUGIN_ROOT CODE_ROOT="$T/code" SETUP_TEST_HOME="$T/home" bash "$T/examples"
  [ -L "$T/home/.claude/skills" ]
  [ -L "$T/home/.claude/localclaude-plugins" ]
}
