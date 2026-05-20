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

@test "codex-login emits codex_error with detail on subscription failure" {
  export STUB_CODEX_MODE=fail
  run "$HELPER" codex-login
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"codex_error"'* ]]
  [[ "$output" == *'no subscription'* ]]
}

@test "codex-login emits codex_aborted when login exits 130" {
  export STUB_CODEX_MODE=abort
  run "$HELPER" codex-login
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'{"event":"codex_aborted"}'* ]]
}

@test "codex-login emits codex_timeout when auth never completes" {
  export STUB_CODEX_MODE=hang LAUNCHER_CODEX_TIMEOUT=2 LAUNCHER_POLL_INTERVAL=1
  # Events are stdout-only; killing the hung child prints a job-control
  # "Terminated" notice on stderr, so capture stdout in isolation here.
  "$HELPER" codex-login > "$TMP/ev.jsonl" 2>/dev/null
  assert_valid_jsonl "$TMP/ev.jsonl"
  grep -q '{"event":"codex_timeout"}' "$TMP/ev.jsonl"
}
