#!/usr/bin/env bash
# Verify that negating one assertion fails its own Bats test at that line.
set -uo pipefail

refuse() { printf 'REFUSED %s\n' "$1"; exit 1; }

[ "$#" -eq 4 ] || refuse 'usage: verify_assertions.sh <task-sha> <file> <line> <test-name>'
sha=$1 file=$2 line=$3 name=$4
[[ "$line" =~ ^[1-9][0-9]*$ ]] || refuse 'line must be a positive integer'
[ -n "$name" ] || refuse 'test name is empty'
script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) \
  || refuse 'cannot locate mutation-restore.sh'

# Inspect only the condition: the trailing `|| false` is outside the brackets.
assertion=$(sed -n "${line}p" "$file") || refuse 'cannot read target line'
if [[ "$assertion" == *'[['*']]'* ]]; then
  condition=${assertion#*'[['}
  condition=${condition%%']]'*}
  [[ "$condition" != *'||'* ]] \
    || refuse 'compound condition cannot be falsified by negating one operator; check it by hand'
fi

# Branch after the first substitution so inverse pairs cannot undo each other.
# The address restricts every substitution to the requested assertion line.
expr="$line{"
for pair in '== !=' '!= ==' '= !=' '-eq -ne' '-ne -eq' \
            '-lt -ge' '-ge -lt' '-le -gt' '-gt -le' '-z -n' '-n -z'; do
  expr="$expr
s/\([[:space:]]\)${pair% *}\([[:space:]]\)/\1${pair#* }\2/
t"
done
expr="$expr
}"

# Bats filters are extended regular expressions, not literal test names.
filter="^$(printf '%s' "$name" | sed 's/[][\\.^$*+?(){}|]/\\&/g')$"
output=$(bash "$script_dir/mutation-restore.sh" "$sha" "$file" "$expr" \
  bats -f "$filter" "$file" 2>&1)
rc=$?
last_message=${output##*$'\n'}

if [ "$rc" -eq 0 ]; then
  failed_test=
  while IFS= read -r entry; do
    case "$entry" in
      'not ok '[0-9]*' '*)
        failed_test=${entry#not ok }
        failed_test=${failed_test#* }
        ;;
      'ok '*|'1..'*) failed_test= ;;
      "# (in test file $file, line $line)")
        if [ "$failed_test" = "$name" ]; then
          printf 'RED\n'
          exit 0
        fi
        ;;
    esac
  done <<< "$output"
  refuse 'output does not show the named test failing at the target file and line'
fi

# Read the final message: a later restoration error must override a green run.
case "$last_message" in
  'TEST PASSED UNDER MUTATION'*)
    case "$output" in
      *$'\n'"ok 1 $name"$'\n'*) printf 'GREEN\n'; exit 1 ;;
    esac
    refuse 'no passing result for the named test (missing or skipped test)'
    ;;
esac
refuse "${last_message:-mutation runner failed (exit $rc)}"
