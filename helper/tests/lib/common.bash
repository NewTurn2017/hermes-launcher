# Shared bats setup/teardown/assertions for the launcher helper.

setup_common() {
  HELPER="$BATS_TEST_DIRNAME/../launcher-helper.sh"
  SCHEMA="$BATS_TEST_DIRNAME/../events.schema.json"
  VALIDATE="$BATS_TEST_DIRNAME/lib/validate_events.py"
  STUBS="$BATS_TEST_DIRNAME/stubs"
  FIX="$BATS_TEST_DIRNAME/fixtures"

  TMP="$(mktemp -d)"
  export HERMES_HOME="$TMP/.hermes"
  export CODEX_HOME="$TMP/.codex"
  mkdir -p "$HERMES_HOME"

  # Fast, deterministic polling for codex-login tests.
  export LAUNCHER_CODEX_TIMEOUT=3
  export LAUNCHER_POLL_INTERVAL=1

  # Stubs (codex/hermes/wslview) take precedence over real tools.
  export PATH="$STUBS:$PATH"
}

teardown_common() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# assert_valid_jsonl <file> — every line must validate against events.schema.json
assert_valid_jsonl() {
  python3 "$VALIDATE" "$SCHEMA" < "$1"
}
