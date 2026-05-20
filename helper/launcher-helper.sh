#!/usr/bin/env bash
# launcher-helper.sh — Hermes Launcher WSL-side helper.
# Emits exactly one JSON event per line on stdout. Contract: events.schema.json.
set -euo pipefail

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- bootstrap: python3 is required for safe JSON emission ---
if ! command -v python3 >/dev/null 2>&1; then
  # The only hand-written JSON in this file (emit.py is unavailable here).
  printf '%s\n' '{"event":"error","step":"detect","level":"environment","detail":"python3 not found in WSL distro"}'
  exit 1
fi

# --- config (overridable for tests) ---
: "${HERMES_HOME:=$HOME/.hermes}"
: "${CODEX_HOME:=$HOME/.codex}"
: "${HERMES_INSTALL_URL:=https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh}"
: "${LAUNCHER_NET_CHECK_URL:=https://raw.githubusercontent.com}"
: "${LAUNCHER_CODEX_TIMEOUT:=300}"
: "${LAUNCHER_POLL_INTERVAL:=1}"
: "${LAUNCHER_SLACK_API:=https://slack.com/api}"
: "${LAUNCHER_CODEX_PROVIDER:=openai-codex}"

emit() { python3 "$HELPER_DIR/lib/emit.py" "$@"; }

# die <step> <level> <detail> — emit an error event and exit non-zero.
die() {
  emit event=error step="$1" level="$2" detail="$3"
  exit 1
}

usage() {
  cat >&2 <<'EOF'
usage: launcher-helper.sh <subcommand> [args]

subcommands:
  detect                          Report in-WSL preflight facts (one detect event)
  install-hermes                  Run upstream install.sh, emit step/progress events
  codex-login                     Run `codex login`, poll auth.json, emit codex_* event
  slack-manifest                  Run `hermes slack manifest`, emit slack_manifest
  slack-verify <xoxb-token>       Verify bot token via Slack auth.test
  write-config [--slack-bot T] [--slack-app T] [--codex]
                                  Upsert ~/.hermes/.env tokens; optionally set codex provider
  verify                          Verify codex + hermes are usable
EOF
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    ""|-h|--help) usage; exit 2 ;;
    *)            usage; exit 2 ;;
  esac
}

main "$@"
