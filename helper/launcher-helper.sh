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

cmd_detect() {
  local internet=false wslview=false cmd_exe=false
  local hermes_installed=false codex_installed=false codex_authed=false
  if curl -fsS --max-time 5 "$LAUNCHER_NET_CHECK_URL" >/dev/null 2>&1; then internet=true; fi
  if command -v wslview >/dev/null 2>&1; then wslview=true; fi
  if command -v cmd.exe >/dev/null 2>&1; then cmd_exe=true; fi
  if command -v hermes >/dev/null 2>&1 || [ -d "$HERMES_HOME/hermes-agent" ]; then hermes_installed=true; fi
  if command -v codex >/dev/null 2>&1; then codex_installed=true; fi
  if [ -f "$CODEX_HOME/auth.json" ]; then codex_authed=true; fi
  emit event=detect \
    internet:="$internet" python3:=true wslview:="$wslview" cmd_exe:="$cmd_exe" \
    hermes_installed:="$hermes_installed" codex_installed:="$codex_installed" codex_authed:="$codex_authed"
}

# Map one line of install.sh stdout to a progress event (unknown lines ignored).
map_install_line() {
  case "$1" in
    *"Installing uv"*)              emit event=step step=install-hermes progress:=15 msg="installing uv" ;;
    *"Cloning"*|*"git clone"*)      emit event=step step=install-hermes progress:=35 msg="cloning hermes-agent" ;;
    *"virtual environment"*)        emit event=step step=install-hermes progress:=55 msg="creating venv" ;;
    *"Installing package"*)         emit event=step step=install-hermes progress:=70 msg="installing package" ;;
    *"config.yaml from template"*)  emit event=step step=install-hermes progress:=85 msg="writing config" ;;
    *"Installation Complete"*)      emit event=step step=install-hermes progress:=100 msg="installation complete" ;;
  esac
}

cmd_install_hermes() {
  emit event=step step=install-hermes progress:=0 msg="starting installer"
  local tmp
  tmp="$(mktemp)"
  if ! curl -fsSL "$HERMES_INSTALL_URL" -o "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    die install-hermes environment "failed to download install.sh from $HERMES_INSTALL_URL"
  fi
  local rc=0
  set +e
  bash "$tmp" 2>&1 | while IFS= read -r line; do map_install_line "$line"; done
  rc=${PIPESTATUS[0]}
  set -e
  rm -f "$tmp"
  if [ "$rc" -ne 0 ]; then
    die install-hermes fatal "install.sh exited with code $rc"
  fi
  emit event=done step=install-hermes ok:=true
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    detect)         cmd_detect "$@" ;;
    install-hermes) cmd_install_hermes "$@" ;;
    ""|-h|--help)   usage; exit 2 ;;
    *)              usage; exit 2 ;;
  esac
}

main "$@"
