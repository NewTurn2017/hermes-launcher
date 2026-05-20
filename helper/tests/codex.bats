#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "codex-login succeeds and emits codex_authed with email" {
  export STUB_CODEX_MODE=authok STUB_CODEX_DELAY=1
  run "$HELPER" codex-login
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"codex_authed"'* ]]
  [[ "$output" == *'"email":"user@example.com"'* ]]
  [ -f "$CODEX_HOME/auth.json" ]
}

@test "codex-login is idempotent when auth.json already exists" {
  mkdir -p "$CODEX_HOME"; echo '{}' > "$CODEX_HOME/auth.json"
  export STUB_CODEX_MODE=hang   # would hang if we actually spawned login
  run "$HELPER" codex-login
  [ "$status" -eq 0 ]
  [[ "$output" == *'"event":"codex_authed"'* ]]
}
