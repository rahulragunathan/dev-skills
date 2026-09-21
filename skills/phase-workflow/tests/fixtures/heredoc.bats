@test "writes a fixture" {
  cat > "$BATS_TEST_TMPDIR/inner.bats" <<'INNER'
@test "not a real test" {
  [[ "a" == "b" ]]
}
INNER
  [ -s "$BATS_TEST_TMPDIR/inner.bats" ]
}
