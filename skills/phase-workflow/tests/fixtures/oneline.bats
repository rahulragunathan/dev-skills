@test "one line mid" { run true; [[ "$output" == "x" ]]; [ 1 -eq 1 ]; }
@test "one line final" { run true; [[ "$output" == "y" ]]; }
