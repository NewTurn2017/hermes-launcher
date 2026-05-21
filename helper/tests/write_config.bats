#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "write-config configures seb profile through hpk" {
  run "$HELPER" write-config --slack-bot "xoxb-new" --slack-signing "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" --slack-app "xapp-new"
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'{"event":"done","step":"write-config","ok":true}'* ]]
  grep -qx 'SLACK_BOT_TOKEN=xoxb-new' "$HERMES_HOME/profiles/seb/.env"
  grep -qx 'SLACK_SIGNING_SECRET=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$HERMES_HOME/profiles/seb/.env"
  grep -qx 'SLACK_APP_TOKEN=xapp-new' "$HERMES_HOME/profiles/seb/.env"
}

@test "write-config is idempotent across repeated runs" {
  run "$HELPER" write-config --slack-bot "xoxb-a" --slack-signing "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" --slack-app "xapp-a"
  run "$HELPER" write-config --slack-bot "xoxb-a" --slack-signing "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" --slack-app "xapp-a"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^SLACK_BOT_TOKEN=' "$HERMES_HOME/profiles/seb/.env")" -eq 1 ]
  grep -qx 'SLACK_BOT_TOKEN=xoxb-a' "$HERMES_HOME/profiles/seb/.env"
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

@test "write-config rejects partial Slack tokens before hpk setup" {
  run "$HELPER" write-config --slack-bot "xoxb-only"
  [ "$status" -ne 0 ]
  [[ "$output" == *'requires bot, signing, and app tokens'* ]]
}
