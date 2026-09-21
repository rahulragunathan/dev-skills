@test "wrapped" {
  run printf 'alpha beta'
  [[ "$output" == *"alpha"* \
     || "$output" == *"beta"* ]] || false
  [ 1 -eq 1 ]
}
