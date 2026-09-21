@test "ends with an assertion" {
  run true
  [[ "$output" != *'nope'* ]]
}

helper_defined_after() {
  echo not a test body
}
