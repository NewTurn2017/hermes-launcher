#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "verify passes when codex authed and hermes present" {
  mkdir -p "$CODEX_HOME"; echo '{}' > "$CODEX_HOME/auth.json"  # so `codex login status` succeeds
  run "$HELPER" verify
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'{"event":"done","step":"verify","ok":true}'* ]]
}

@test "verify fails (recoverable) when codex not logged in" {
  # no auth.json -> stub `codex login status` exits 1
  run "$HELPER" verify
  [ "$status" -ne 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *'"step":"verify"'* ]]
}

@test "verify fails (environment) when codex missing from PATH" {
  # Remove stubs from PATH so codex is not found.
  export PATH="/usr/bin:/bin"
  run "$HELPER" verify
  [ "$status" -ne 0 ]
  [[ "$output" == *'"level":"environment"'* ]]
}
