#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

# Run a representative happy-path flow; concatenate ALL events; validate as one stream.
@test "full happy-path flow emits only schema-valid events" {
  : > "$TMP/all.jsonl"

  export LAUNCHER_NET_CHECK_URL="file://$HELPER"   # any readable file => internet true
  "$HELPER" detect >> "$TMP/all.jsonl"

  export HERMES_INSTALL_URL="file://$FIX/install-success.sh"
  "$HELPER" install-hermes >> "$TMP/all.jsonl"

  export STUB_CODEX_MODE=authok STUB_CODEX_DELAY=0
  "$HELPER" codex-login >> "$TMP/all.jsonl"

  "$HELPER" slack-manifest >> "$TMP/all.jsonl"

  export LAUNCHER_SLACK_API="file://$FIX/slack-auth-ok"
  "$HELPER" slack-verify "xoxb-token" >> "$TMP/all.jsonl"

  "$HELPER" write-config --slack-bot "xoxb-token" --slack-app "xapp-token" --codex >> "$TMP/all.jsonl"
  "$HELPER" verify >> "$TMP/all.jsonl"

  assert_valid_jsonl "$TMP/all.jsonl"
}

@test "shellcheck is clean on helper and stubs" {
  if ! command -v shellcheck >/dev/null 2>&1; then skip "shellcheck not installed"; fi
  run shellcheck -x "$HELPER" "$STUBS/codex" "$STUBS/hermes" "$STUBS/wslview" "$FIX/install-success.sh" "$FIX/install-fail.sh"
  [ "$status" -eq 0 ]
}
