@test "fails at another line" {
  run bash -c '[ 1 -eq 2 ]'
  [ "$status" -eq 1 ]
}
