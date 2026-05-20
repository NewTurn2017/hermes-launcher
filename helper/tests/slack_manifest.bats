#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "slack-manifest emits a slack_manifest event carrying the JSON string" {
  run "$HELPER" slack-manifest
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"slack_manifest"'* ]]
  [[ "$output" == *'socket_mode_enabled'* ]]
}

@test "slack-manifest emits recoverable error when hermes fails" {
  export STUB_HERMES_MANIFEST_FAIL=1
  run "$HELPER" slack-manifest
  [ "$status" -ne 0 ]
  [[ "$output" == *'"level":"recoverable"'* ]]
}
