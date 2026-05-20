#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "detect emits exactly one schema-valid detect event" {
  export LAUNCHER_NET_CHECK_URL="file://$HELPER"  # any readable file => internet true
  run "$HELPER" detect
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"detect"'* ]]
}

@test "detect reports codex_authed true when auth.json exists" {
  export LAUNCHER_NET_CHECK_URL="file:///nonexistent-$$"
  mkdir -p "$CODEX_HOME"; echo '{}' > "$CODEX_HOME/auth.json"
  run "$HELPER" detect
  [ "$status" -eq 0 ]
  [[ "$output" == *'"codex_authed":true'* ]]
  [[ "$output" == *'"internet":false'* ]]
}

@test "detect reports hermes_installed true when install dir exists" {
  export LAUNCHER_NET_CHECK_URL="file:///nonexistent-$$"
  mkdir -p "$HERMES_HOME/hermes-agent"
  run "$HELPER" detect
  [[ "$output" == *'"hermes_installed":true'* ]]
}

@test "detect reports wslview true when wslview on PATH" {
  export LAUNCHER_NET_CHECK_URL="file:///nonexistent-$$"
  run "$HELPER" detect
  [[ "$output" == *'"wslview":true'* ]]   # stubs dir provides wslview
}
