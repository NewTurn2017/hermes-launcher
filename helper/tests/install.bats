#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "install-hermes maps stdout markers to progress and finishes ok" {
  export HERMES_INSTALL_URL="file://$FIX/install-success.sh"
  run "$HELPER" install-hermes
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"step":"install-hermes","progress":15'* ]]
  [[ "$output" == *'"progress":35'* ]]
  [[ "$output" == *'"progress":85'* ]]
  [[ "$output" == *'"progress":100'* ]]
  [[ "$output" == *'{"event":"done","step":"install-hermes","ok":true}'* ]]
}

@test "install-hermes emits fatal error on non-zero install" {
  export HERMES_INSTALL_URL="file://$FIX/install-fail.sh"
  run "$HELPER" install-hermes
  [ "$status" -ne 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *'"level":"fatal"'* ]]
  [[ "$output" != *'"ok":true'* ]]
}

@test "install-hermes emits environment error when download fails" {
  export HERMES_INSTALL_URL="file:///nonexistent-$$-install.sh"
  run "$HELPER" install-hermes
  [ "$status" -ne 0 ]
  [[ "$output" == *'"level":"environment"'* ]]
}
