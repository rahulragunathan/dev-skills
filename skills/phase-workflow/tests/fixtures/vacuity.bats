#!/usr/bin/env bats
#
# Fixture only, never part of the suite. Both assertions below are false and sit
# in mid-test position; whether either fails is the measurement KI-52 needs.
#
# The first test records the interpreter from inside the run. That is the only
# place the answer is trustworthy: PATH order decides which bash runs bats, and
# a version printed outside the run cannot establish what ran inside it.

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
