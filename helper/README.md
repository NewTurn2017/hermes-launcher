# launcher-helper.sh

WSL-side helper for Hermes Launcher. Wraps upstream tools (install.sh, codex CLI,
hermes CLI) **without modifying them** and emits one JSON event per line on stdout.

## Contract

The event schema is the single source of truth: [`events.schema.json`](events.schema.json).
Both these bats tests and the Rust backend (Plan 2) validate against it.

## Subcommands

| Subcommand | Emits |
|---|---|
| `detect` | one `detect` event (in-WSL preflight facts) |
| `install-hermes` | `step` (progress) … `done` / `error` |
| `codex-login` | `codex_authed` / `codex_error` / `codex_aborted` / `codex_timeout` |
| `slack-manifest` | `slack_manifest` |
| `slack-verify <xoxb-…>` | `slack_verified` / `slack_error` |
| `write-config [--slack-bot T] [--slack-app T] [--codex]` | `done` / `error` |
| `verify` | `done` / `error` |

Tokens are written to `~/.hermes/.env` (`SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`).
Codex auth lives in `~/.codex/auth.json` (written by `codex login`).

## Dependencies

- **Production:** `bash`, `python3` (stdlib only), `curl`, and the upstream tools it wraps.
- **Tests/CI:** `bats-core`, `python3` + `jsonschema`, `shellcheck`.

## Running the tests

```bash
bats helper/tests/
```

All upstream calls are overridable via env vars (see the helper header) so tests
run fully offline with stubs/fixtures.
