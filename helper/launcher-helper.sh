#!/usr/bin/env bash
# launcher-helper.sh — Hermes Launcher WSL-side helper.
# Emits exactly one JSON event per line on stdout. Contract: events.schema.json.
set -euo pipefail

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
