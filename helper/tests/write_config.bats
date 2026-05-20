#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "write-config upserts slack tokens into ~/.hermes/.env, preserving others" {
  printf 'OTHER=keepme\nSLACK_BOT_TOKEN=xoxb-old\n' > "$HERMES_HOME/.env"
  run "$HELPER" write-config --slack-bot "xoxb-new" --slack-app "xapp-new"
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'{"event":"done","step":"write-config","ok":true}'* ]]
  grep -qx 'OTHER=keepme' "$HERMES_HOME/.env"
  grep -qx 'SLACK_BOT_TOKEN=xoxb-new' "$HERMES_HOME/.env"
  grep -qx 'SLACK_APP_TOKEN=xapp-new' "$HERMES_HOME/.env"
  # exactly one SLACK_BOT_TOKEN line (idempotent upsert)
  [ "$(grep -c '^SLACK_BOT_TOKEN=' "$HERMES_HOME/.env")" -eq 1 ]
}

@test "write-config is idempotent across repeated runs" {
  run "$HELPER" write-config --slack-bot "xoxb-a"
  run "$HELPER" write-config --slack-bot "xoxb-a"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^SLACK_BOT_TOKEN=' "$HERMES_HOME/.env")" -eq 1 ]
  grep -qx 'SLACK_BOT_TOKEN=xoxb-a' "$HERMES_HOME/.env"
}

@test "write-config --codex calls hermes config set model.provider" {
  run "$HELPER" write-config --codex
  [ "$status" -eq 0 ]
  [[ "$output" == *'{"event":"done","step":"write-config","ok":true}'* ]]
}

@test "write-config rejects unknown args" {
  run "$HELPER" write-config --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *'"level":"recoverable"'* ]]
}
