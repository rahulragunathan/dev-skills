@test "quoted operator" {
  run printf 'alpha'
  [[ "$output" != *"a == b"* ]] || false
  [ 1 -eq 1 ]
}
