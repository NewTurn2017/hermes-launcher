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

# Print a JSON value for the codex account email, or `null`.
codex_email() {
  local out email
  out="$(codex login status 2>/dev/null || true)"
  email="$(printf '%s' "$out" | grep -oE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]+' | head -n1 || true)"
  if [ -n "$email" ]; then printf '"%s"' "$email"; else printf 'null'; fi
}

cmd_codex_login() {
  emit event=step step=codex-login progress:=0 msg="starting codex login"
  if [ -f "$CODEX_HOME/auth.json" ]; then
    emit event=codex_authed email:="$(codex_email)"
    return 0
  fi
  codex login >/dev/null 2>"$HERMES_HOME/codex-login.err" &
  local pid=$! waited=0 crc=0
  while [ "$waited" -lt "$LAUNCHER_CODEX_TIMEOUT" ]; do
    if [ -f "$CODEX_HOME/auth.json" ]; then
      kill "$pid" 2>/dev/null || true
      emit event=codex_authed email:="$(codex_email)"
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      crc=0
      wait "$pid" 2>/dev/null || crc=$?
      if [ -f "$CODEX_HOME/auth.json" ]; then
        emit event=codex_authed email:="$(codex_email)"; return 0
      fi
      if [ "$crc" -eq 130 ]; then emit event=codex_aborted; return 0; fi
      local detail
      detail="$(tr -d '\r\n' < "$HERMES_HOME/codex-login.err" 2>/dev/null || true)"
      emit event=codex_error detail="${detail:-codex login exited with code $crc}"
      return 0
    fi
    sleep "$LAUNCHER_POLL_INTERVAL"
    waited=$((waited + LAUNCHER_POLL_INTERVAL))
  done
  kill "$pid" 2>/dev/null || true
  emit event=codex_timeout
  return 0
}

cmd_slack_manifest() {
  emit event=step step=slack-manifest progress:=0 msg="generating slack manifest"
  local json
  if ! json="$(hermes slack manifest 2>/dev/null)"; then
    die slack-manifest recoverable "hermes slack manifest failed"
  fi
  emit event=slack_manifest json="$json"
}

# Parse a Slack auth.test JSON body from stdin into a TSV line: status\tteam\tuser
# Uses `python3 -c` (not a heredoc) so piped stdin reaches sys.stdin.
parse_slack_auth() {
  python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("parse_error\t\t"); sys.exit(0)
if d.get("ok"):
    print("ok\t%s\t%s" % (d.get("team", ""), d.get("user", "")))
else:
    print("%s\t\t" % d.get("error", "unknown"))
'
}

cmd_slack_verify() {
  local bot="${1:-}"
  if [ -z "$bot" ]; then die slack-verify recoverable "missing bot token argument"; fi
  case "$bot" in
    xoxb-*) : ;;
    *) emit event=slack_error detail="bot token must start with xoxb-"; return 0 ;;
  esac
  local resp status team user line
  resp="$(curl -fsS -H "Authorization: Bearer $bot" "$LAUNCHER_SLACK_API/auth.test" 2>/dev/null || true)"
  line="$(printf '%s' "$resp" | parse_slack_auth)"
  IFS=$'\t' read -r status team user <<<"$line"
  if [ "$status" = "ok" ]; then
    emit event=slack_verified workspace="$team" bot="$user"
  else
    emit event=slack_error detail="$status"
  fi
}

upsert_env() { python3 "$HELPER_DIR/lib/upsert_env.py" "$1" "$2" "$3"; }

cmd_write_config() {
  local bot="" app="" set_codex=false
  while [ $# -gt 0 ]; do
    case "$1" in
      --slack-bot) bot="${2:-}"; shift 2 ;;
      --slack-app) app="${2:-}"; shift 2 ;;
      --codex)     set_codex=true; shift ;;
      *)           die write-config recoverable "unknown arg: $1" ;;
    esac
  done
  mkdir -p "$HERMES_HOME"
  local envf="$HERMES_HOME/.env"
  [ -f "$envf" ] || : > "$envf"
  [ -n "$bot" ] && upsert_env "$envf" SLACK_BOT_TOKEN "$bot"
  [ -n "$app" ] && upsert_env "$envf" SLACK_APP_TOKEN "$app"
  if [ "$set_codex" = true ]; then
    if ! hermes config set model.provider "$LAUNCHER_CODEX_PROVIDER" >/dev/null 2>&1; then
      die write-config recoverable "hermes config set model.provider failed"
    fi
  fi
  emit event=done step=write-config ok:=true
}

cmd_verify() {
  emit event=step step=verify progress:=0 msg="verifying installation"
  if ! command -v codex >/dev/null 2>&1; then
    die verify environment "codex not found on PATH"
  fi
  if ! codex --version >/dev/null 2>&1; then
    die verify recoverable "codex --version failed"
  fi
  if ! codex login status >/dev/null 2>&1; then
    die verify recoverable "codex is not logged in"
  fi
  if ! command -v hermes >/dev/null 2>&1 && [ ! -d "$HERMES_HOME/hermes-agent" ]; then
    die verify environment "hermes not installed"
  fi
  emit event=done step=verify ok:=true
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    detect)         cmd_detect "$@" ;;
    install-hermes) cmd_install_hermes "$@" ;;
    codex-login)    cmd_codex_login "$@" ;;
    slack-manifest) cmd_slack_manifest "$@" ;;
    slack-verify)   cmd_slack_verify "$@" ;;
    write-config)   cmd_write_config "$@" ;;
    verify)         cmd_verify "$@" ;;
    ""|-h|--help)   usage; exit 2 ;;
    *)              usage; exit 2 ;;
  esac
}

main "$@"
