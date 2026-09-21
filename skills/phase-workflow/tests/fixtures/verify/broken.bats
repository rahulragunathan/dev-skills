@test "needs a missing helper" {
  load nonexistent_helper
  [ "a" = "a" ]
}
