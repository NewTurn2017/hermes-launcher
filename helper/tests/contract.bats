#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "validator accepts a valid step event" {
  echo '{"event":"step","step":"install-hermes","progress":42,"msg":"cloning repo"}' > "$TMP/ev.jsonl"
  run assert_valid_jsonl "$TMP/ev.jsonl"
  [ "$status" -eq 0 ]
}

@test "validator accepts all confirmed event types" {
  cat > "$TMP/ev.jsonl" <<'EOF'
{"event":"detect","internet":true,"python3":true,"wslview":false,"cmd_exe":true,"hermes_installed":false,"codex_installed":true,"codex_authed":false}
{"event":"step","step":"verify","progress":0,"msg":"verifying"}
{"event":"codex_authed","email":"user@example.com"}
{"event":"codex_authed","email":null}
{"event":"codex_error","detail":"no subscription"}
{"event":"codex_aborted"}
{"event":"codex_timeout"}
{"event":"slack_manifest","json":"{\"display_information\":{}}"}
{"event":"slack_verified","workspace":"Acme","bot":"hermes"}
{"event":"slack_error","detail":"invalid_auth"}
{"event":"done","step":"write-config","ok":true}
{"event":"error","step":"install-hermes","level":"fatal","detail":"boom"}
EOF
  run assert_valid_jsonl "$TMP/ev.jsonl"
  [ "$status" -eq 0 ]
}

@test "validator rejects unknown event type" {
  echo '{"event":"explode","detail":"x"}' > "$TMP/ev.jsonl"
  run assert_valid_jsonl "$TMP/ev.jsonl"
  [ "$status" -ne 0 ]
}

@test "validator rejects step with out-of-range progress" {
  echo '{"event":"step","step":"verify","progress":150,"msg":"x"}' > "$TMP/ev.jsonl"
  run assert_valid_jsonl "$TMP/ev.jsonl"
  [ "$status" -ne 0 ]
}

@test "validator rejects step with unknown step enum" {
  echo '{"event":"step","step":"nope","progress":1,"msg":"x"}' > "$TMP/ev.jsonl"
  run assert_valid_jsonl "$TMP/ev.jsonl"
  [ "$status" -ne 0 ]
}

@test "validator rejects extra/unknown property" {
  echo '{"event":"codex_aborted","surprise":1}' > "$TMP/ev.jsonl"
  run assert_valid_jsonl "$TMP/ev.jsonl"
  [ "$status" -ne 0 ]
}

@test "validator rejects malformed JSON line" {
  echo '{not json' > "$TMP/ev.jsonl"
  run assert_valid_jsonl "$TMP/ev.jsonl"
  [ "$status" -ne 0 ]
}
