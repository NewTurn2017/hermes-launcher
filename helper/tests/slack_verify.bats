#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "slack-verify rejects a token without xoxb- prefix" {
  run "$HELPER" slack-verify "xapp-wrong"
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"slack_error"'* ]]
  [[ "$output" == *'xoxb-'* ]]
}

@test "slack-verify emits slack_verified with workspace and bot on ok" {
  export LAUNCHER_SLACK_API="file://$FIX/slack-auth-ok"
  run "$HELPER" slack-verify "xoxb-valid-token"
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"slack_verified"'* ]]
  [[ "$output" == *'"workspace":"Acme"'* ]]
  [[ "$output" == *'"bot":"hermes"'* ]]
}

@test "slack-verify emits slack_error with Slack error code" {
  export LAUNCHER_SLACK_API="file://$FIX/slack-auth-bad"
  run "$HELPER" slack-verify "xoxb-bad-token"
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"slack_error"'* ]]
  [[ "$output" == *'invalid_auth'* ]]
}

@test "slack-verify errors when token argument missing" {
  run "$HELPER" slack-verify
  [ "$status" -ne 0 ]
  [[ "$output" == *'"level":"recoverable"'* ]]
}
