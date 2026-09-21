@test "shift" {
  x=$(( 1 << 2 ))
  [[ "$x" == 4 ]] || false
  [ 1 -eq 1 ]
}
