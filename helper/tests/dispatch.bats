#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "no args prints usage and exits 2" {
  run "$HELPER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "unknown subcommand prints usage and exits 2" {
  run "$HELPER" frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "emit.py builds a valid string-field event" {
  run python3 "$BATS_TEST_DIRNAME/../lib/emit.py" event=slack_error detail="invalid \"auth\""
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == '{"event":"slack_error","detail":"invalid \"auth\""}' ]]
}

@test "emit.py builds raw (number/bool) fields" {
  run python3 "$BATS_TEST_DIRNAME/../lib/emit.py" event=step step=verify progress:=42 msg="x"
  [ "$status" -eq 0 ]
  [[ "$output" == '{"event":"step","step":"verify","progress":42,"msg":"x"}' ]]
}

@test "emit.py keeps a string value that contains := intact" {
  run python3 "$BATS_TEST_DIRNAME/../lib/emit.py" event=codex_error detail="x:=y"
  [ "$status" -eq 0 ]
  [[ "$output" == '{"event":"codex_error","detail":"x:=y"}' ]]
}
