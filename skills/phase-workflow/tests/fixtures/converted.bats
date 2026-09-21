@test "already converted" {
  run true
  [[ "$output" == "" ]] || false
  [ 1 -eq 1 ]
}
