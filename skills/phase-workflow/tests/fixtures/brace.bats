@test "brace in a string" {
  run printf '%s' "{"
  [[ "$output" == "x" ]]
  [ "$status" -eq 0 ]
}
@test "assertion is last" {
  [[ "$output" == "y" ]]
}
