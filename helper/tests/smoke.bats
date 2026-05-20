#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "helper script exists and is executable" {
  [ -f "$HELPER" ]
  [ -x "$HELPER" ]
}

@test "common harness creates isolated HERMES_HOME and CODEX_HOME" {
  [ -d "$HERMES_HOME" ]
  [[ "$HERMES_HOME" == "$TMP"/* ]]
  [[ "$CODEX_HOME" == "$TMP"/* ]]
}
