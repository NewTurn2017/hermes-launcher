# Hermes Launcher — Plan 1: helper.sh + JSONL 이벤트 계약 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** WSL 안에서 hermes/codex/slack 업스트림 도구를 감싸 한 줄 = 1 JSON 이벤트(JSONL)로 진행 상황을 emit하는 `launcher-helper.sh`와, Rust·bats가 공유하는 단일 이벤트 스키마(`events.schema.json`)를 TDD로 구현한다.

**Architecture:** 하이브리드(브레인스토밍 옵션 C). 헬퍼는 업스트림 도구(install.sh, codex CLI, hermes CLI)를 **수정 없이** 호출하고, 그 결과를 표준 JSONL 이벤트로 변환한다. 헬퍼 자체는 `python3`(stdlib만)에 의존해 JSON을 안전하게 생성/파싱하고, 업스트림 호출은 모두 환경변수로 override 가능해 bats에서 스텁/픽스처로 격리 테스트한다. 이벤트 스키마는 단일 JSON Schema 파일을 계약으로 삼아 bats(`validate_events.py`)와 Rust(Plan 2의 serde)가 함께 참조한다.

**Tech Stack:** bash 5 (`set -euo pipefail`), python3 stdlib (production emit/merge), JSON Schema draft 2020-12, bats-core(테스트), python `jsonschema`(테스트/CI 전용), shellcheck, GitHub Actions(ubuntu-latest).

---

## 이 문서의 위치 (foundation-first 로드맵)

설계는 4개의 독립 서브시스템으로 나뉘며, 의존 순서대로 별도 플랜으로 작성한다. **이 문서는 Plan 1**이다.

1. **Plan 1 (이 문서) — helper.sh + JSONL 이벤트 계약.** 모든 상위 레이어가 의존하는 기반. WSL/Linux에서 bats로 독립 실행·검증 가능.
2. Plan 2 — Tauri/Rust 백엔드 (`wsl.rs`, `events.rs`(이 스키마 소비), `state.rs`, `secrets.rs`). `cargo test`로 검증.
3. Plan 3 — React 프론트엔드 (5단계 위저드 상태머신·토큰 형식 검증). Vitest로 검증.
4. Plan 4 — 통합 + 패키징/CI(`tauri-action`) + 튜토리얼 문서 + 수동 E2E 체크리스트.

Plan 2~4는 Plan 1 승인·구현 후 순차 작성한다.

## 설계 문서 대비 수정 사항 (조사로 확정)

실제 업스트림(`NousResearch/hermes-agent`, `openai/codex`) 소스를 확인한 결과, 설계 문서 8절의 "구현 시 확정할 사항"이 다음과 같이 정리됐다. 이 플랜은 **수정된 사실**을 따른다.

| 설계 문서의 가정 | 실제 (이 플랜이 따르는 것) |
|---|---|
| Slack 토큰을 `config.yaml`의 `platforms.slack.{bot_token,app_token}`에 주입 | **틀림.** 토큰은 `~/.hermes/.env`의 `SLACK_BOT_TOKEN`(xoxb-)/`SLACK_APP_TOKEN`(xapp-)에 들어감. config.yaml의 `platforms:`는 동작 옵션만 |
| 검증에 `codex models` 사용 | **없음.** `codex --version` + `codex login status`(+선택 `codex debug models`) 사용 |
| config에 `openai_runtime: codex_app_server` 한 줄 추가 | **그런 키 없음.** hermes는 `model.provider`(`openai-codex` 또는 `codex`)로 코덱스 연결. `hermes config set model.provider …`로 설정 |
| codex auth 경로 `~/.codex/auth.json` | **맞음** (기본값; keyring 모드는 대안) |
| hermes config 경로 `~/.hermes/config.yaml` | **맞음** |
| install.sh = `curl -fsSL …/main/scripts/install.sh \| bash` | **맞음** |
| `hermes slack manifest` 존재 | **맞음** (`--write`는 `~/.hermes/slack-manifest.json`에 기록) |

> 구현 후, 위 표를 반영해 설계 문서(spec)도 갱신할지 사용자에게 확인한다. `LAUNCHER_CODEX_PROVIDER`(기본 `openai-codex`)는 hermes의 codex OAuth 연결 키이며, 실제 hermes에서 `openai-codex` vs `codex` 중 어떤 값이 필요한지는 Plan 4 통합 E2E에서 최종 확정한다(헬퍼는 환경변수로 override 가능하게 둔다).

---

## File Structure

설계 문서 70~85줄의 `helper/` 구조를 확장한다. 각 파일은 단일 책임을 가진다.

- `helper/launcher-helper.sh` — 서브커맨드 디스패처 + 7개 서브커맨드 구현. 헬퍼의 유일한 엔트리포인트.
- `helper/events.schema.json` — JSONL 이벤트 계약(JSON Schema draft 2020-12). **단일 진실의 출처.** bats와 Rust(Plan 2)가 공유.
- `helper/lib/emit.py` — production용 JSON 한 줄 생성기(stdlib만). 헬퍼가 모든 이벤트 출력에 사용.
- `helper/lib/upsert_env.py` — production용 `.env` KEY=VALUE upsert(보존 머지, stdlib만).
- `helper/tests/lib/validate_events.py` — 테스트/CI 전용 스키마 검증기(python `jsonschema` 필요). 헬퍼 production 코드는 이걸 의존하지 않음.
- `helper/tests/lib/common.bash` — bats 공통 setup/teardown/assert 헬퍼.
- `helper/tests/stubs/{codex,hermes,wslview}` — 업스트림 도구 스텁(PATH 앞에 끼움).
- `helper/tests/fixtures/` — `install-success.sh`, `install-fail.sh`, `slack-auth-ok/auth.test`, `slack-auth-bad/auth.test`.
- `helper/tests/*.bats` — 관심사별 테스트 파일(계약/디스패처/서브커맨드별).
- `helper/README.md` — 헬퍼 실행법·계약 요약.
- `.github/workflows/helper.yml` — 헬퍼 단독 CI(bats + 스키마 검증 + shellcheck).

### 헬퍼의 override 가능한 환경변수 (테스트 격리의 핵심)

| 변수 | 기본값 | 용도 |
|---|---|---|
| `HERMES_HOME` | `$HOME/.hermes` | hermes 데이터·config·.env 위치 |
| `CODEX_HOME` | `$HOME/.codex` | codex auth.json 위치 |
| `HERMES_INSTALL_URL` | `https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh` | install.sh 다운로드 URL (테스트는 `file://` 픽스처) |
| `LAUNCHER_NET_CHECK_URL` | `https://raw.githubusercontent.com` | detect 인터넷 점검 대상 (테스트는 `file://`) |
| `LAUNCHER_CODEX_TIMEOUT` | `300` | codex-login auth.json 폴링 최대 초(정수) |
| `LAUNCHER_POLL_INTERVAL` | `1` | 폴링 간격 초(정수) |
| `LAUNCHER_SLACK_API` | `https://slack.com/api` | Slack API 베이스 (테스트는 `file://` 픽스처 디렉터리) |
| `LAUNCHER_CODEX_PROVIDER` | `openai-codex` | `hermes config set model.provider` 값 |

---

## 사전 준비 (모든 Task 공통)

로컬 개발 머신(darwin)과 CI(ubuntu)에서 필요한 도구:

- **bats-core**: macOS `brew install bats-core`, Ubuntu `sudo apt-get install -y bats`(또는 `npm install -g bats`).
- **python3**: macOS/Ubuntu 기본 포함. 헬퍼 production은 stdlib만 사용.
- **python `jsonschema`**(테스트 전용): `python3 -m pip install --user jsonschema` (CI는 워크플로에서 설치).
- **shellcheck**: macOS `brew install shellcheck`, Ubuntu `sudo apt-get install -y shellcheck`.

테스트 실행 표준 명령: `bats helper/tests/<file>.bats` (단일 파일) 또는 `bats helper/tests/` (전체).

---

## Task 1: 테스트 하니스 스캐폴드

WSL 없이도 bats가 헬퍼를 실행할 수 있도록 디렉터리·공통 라이브러리·스텁을 만들고, "헬퍼 파일이 존재하고 실행 가능하다"는 최소 스모크 테스트를 통과시킨다.

**Files:**
- Create: `helper/tests/lib/common.bash`
- Create: `helper/tests/smoke.bats`
- Create: `helper/launcher-helper.sh` (셸뱅+헤더만; 이후 Task에서 채움)

- [ ] **Step 1: Write the failing test**

Create `helper/tests/smoke.bats`:

```bash
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
```

Create `helper/tests/lib/common.bash`:

```bash
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

# emit_to <file> — run helper, capture stdout to a file, keep status in $status via `run`
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats helper/tests/smoke.bats`
Expected: FAIL — `$HELPER` 파일이 없어 첫 테스트의 `[ -f "$HELPER" ]`가 실패.

- [ ] **Step 3: Write minimal implementation**

Create `helper/launcher-helper.sh`:

```bash
#!/usr/bin/env bash
# launcher-helper.sh — Hermes Launcher WSL-side helper.
# Emits exactly one JSON event per line on stdout. Contract: events.schema.json.
set -euo pipefail

HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

Make it executable:

```bash
chmod +x helper/launcher-helper.sh
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats helper/tests/smoke.bats`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add helper/launcher-helper.sh helper/tests/lib/common.bash helper/tests/smoke.bats
git commit -m "test: scaffold helper bats harness + executable stub

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: 이벤트 스키마 계약 + 검증기

JSONL 이벤트의 단일 진실의 출처인 `events.schema.json`과, 그것을 소비하는 검증기 `validate_events.py`를 만든다. 유효/무효 픽스처로 검증기 동작을 TDD한다.

**Files:**
- Create: `helper/events.schema.json`
- Create: `helper/tests/lib/validate_events.py`
- Create: `helper/tests/contract.bats`

- [ ] **Step 1: Write the failing test**

Create `helper/tests/contract.bats`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats helper/tests/contract.bats`
Expected: FAIL — `events.schema.json`와 `validate_events.py`가 없어 검증기 호출이 실패.

- [ ] **Step 3: Write minimal implementation**

Create `helper/events.schema.json`:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "hermes-launcher/helper/events.schema.json",
  "title": "Hermes Launcher helper event",
  "description": "One JSON object per line emitted by launcher-helper.sh on stdout.",
  "type": "object",
  "required": ["event"],
  "oneOf": [
    {
      "properties": {
        "event": { "const": "step" },
        "step": { "$ref": "#/$defs/step" },
        "progress": { "type": "integer", "minimum": 0, "maximum": 100 },
        "msg": { "type": "string" }
      },
      "required": ["event", "step", "progress", "msg"],
      "additionalProperties": false
    },
    {
      "properties": {
        "event": { "const": "detect" },
        "internet": { "type": "boolean" },
        "python3": { "type": "boolean" },
        "wslview": { "type": "boolean" },
        "cmd_exe": { "type": "boolean" },
        "hermes_installed": { "type": "boolean" },
        "codex_installed": { "type": "boolean" },
        "codex_authed": { "type": "boolean" }
      },
      "required": ["event", "internet", "python3", "wslview", "cmd_exe", "hermes_installed", "codex_installed", "codex_authed"],
      "additionalProperties": false
    },
    {
      "properties": {
        "event": { "const": "codex_authed" },
        "email": { "type": ["string", "null"] }
      },
      "required": ["event"],
      "additionalProperties": false
    },
    {
      "properties": {
        "event": { "const": "codex_error" },
        "detail": { "type": "string" }
      },
      "required": ["event", "detail"],
      "additionalProperties": false
    },
    {
      "properties": { "event": { "const": "codex_aborted" } },
      "required": ["event"],
      "additionalProperties": false
    },
    {
      "properties": { "event": { "const": "codex_timeout" } },
      "required": ["event"],
      "additionalProperties": false
    },
    {
      "properties": {
        "event": { "const": "slack_manifest" },
        "json": { "type": "string" }
      },
      "required": ["event", "json"],
      "additionalProperties": false
    },
    {
      "properties": {
        "event": { "const": "slack_verified" },
        "workspace": { "type": "string" },
        "bot": { "type": "string" }
      },
      "required": ["event", "workspace", "bot"],
      "additionalProperties": false
    },
    {
      "properties": {
        "event": { "const": "slack_error" },
        "detail": { "type": "string" }
      },
      "required": ["event", "detail"],
      "additionalProperties": false
    },
    {
      "properties": {
        "event": { "const": "done" },
        "step": { "$ref": "#/$defs/step" },
        "ok": { "type": "boolean" }
      },
      "required": ["event", "step", "ok"],
      "additionalProperties": false
    },
    {
      "properties": {
        "event": { "const": "error" },
        "step": { "$ref": "#/$defs/step" },
        "level": { "enum": ["recoverable", "environment", "fatal"] },
        "detail": { "type": "string" }
      },
      "required": ["event", "step", "level", "detail"],
      "additionalProperties": false
    }
  ],
  "$defs": {
    "step": {
      "enum": ["detect", "install-hermes", "codex-login", "slack-manifest", "slack-verify", "write-config", "verify"]
    }
  }
}
```

Create `helper/tests/lib/validate_events.py`:

```python
#!/usr/bin/env python3
"""Validate JSONL events (one object per stdin line) against a JSON Schema.

Usage: validate_events.py <schema.json>   # instances read from stdin
Exit 0 if all lines valid, 1 otherwise (errors printed to stderr).
"""
import json
import pathlib
import sys

import jsonschema

def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_events.py <schema.json>", file=sys.stderr)
        return 2
    schema = json.loads(pathlib.Path(sys.argv[1]).read_text())
    validator = jsonschema.Draft202012Validator(schema)
    errors = 0
    for i, raw in enumerate(sys.stdin, 1):
        line = raw.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"line {i}: invalid JSON: {exc}", file=sys.stderr)
            errors += 1
            continue
        for err in validator.iter_errors(obj):
            print(f"line {i}: {err.message}", file=sys.stderr)
            errors += 1
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats helper/tests/contract.bats`
Expected: PASS (7 tests). 만약 `ModuleNotFoundError: jsonschema`가 나오면 `python3 -m pip install --user jsonschema` 후 재실행.

- [ ] **Step 5: Commit**

```bash
git add helper/events.schema.json helper/tests/lib/validate_events.py helper/tests/contract.bats
git commit -m "feat: define JSONL event schema contract + validator

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: 부트스트랩 + emit.py + 디스패처/usage

헬퍼의 공통 골격을 만든다: python3 부트스트랩 점검, 안전한 JSON 한 줄 생성기(`emit.py`), `emit`/`die` 셸 함수, 서브커맨드 디스패처와 usage.

**Files:**
- Create: `helper/lib/emit.py`
- Modify: `helper/launcher-helper.sh`
- Create: `helper/tests/dispatch.bats`

- [ ] **Step 1: Write the failing test**

Create `helper/tests/dispatch.bats`:

```bash
#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "no args prints usage and exits 2" {
  run "$HELPER"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "unknown subcommand prints usage and exits 2" {
  run "$HELPER" frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "emit.py builds a valid string-field event" {
  run python3 "$BATS_TEST_DIRNAME/../lib/emit.py" event=slack_error detail="invalid \"auth\""
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == '{"event":"slack_error","detail":"invalid \"auth\""}' ]]
}

@test "emit.py builds raw (number/bool) fields" {
  run python3 "$BATS_TEST_DIRNAME/../lib/emit.py" event=step step=verify progress:=42 msg="x"
  [ "$status" -eq 0 ]
  [[ "$output" == '{"event":"step","step":"verify","progress":42,"msg":"x"}' ]]
}

@test "emit.py keeps a string value that contains := intact" {
  run python3 "$BATS_TEST_DIRNAME/../lib/emit.py" event=codex_error detail="x:=y"
  [ "$status" -eq 0 ]
  [[ "$output" == '{"event":"codex_error","detail":"x:=y"}' ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats helper/tests/dispatch.bats`
Expected: FAIL — `emit.py`가 없고 디스패처/usage 미구현.

- [ ] **Step 3: Write minimal implementation**

Create `helper/lib/emit.py`:

```python
#!/usr/bin/env python3
"""Build one compact JSON object from key=value / key:=rawjson args.

  key=value     -> string field
  key:=value    -> raw JSON field (number, bool, null, object, array)

Robust to string values that themselves contain ':=' (the raw form only
matches when an identifier is immediately followed by ':=').
"""
import json
import re
import sys

_RAW = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):=(.*)$", re.S)
_STR = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)

def main() -> int:
    ev = {}
    for arg in sys.argv[1:]:
        m = _RAW.match(arg)
        if m:
            ev[m.group(1)] = json.loads(m.group(2))
            continue
        m = _STR.match(arg)
        if not m:
            print(f"emit: bad arg: {arg}", file=sys.stderr)
            return 2
        ev[m.group(1)] = m.group(2)
    sys.stdout.write(json.dumps(ev, separators=(",", ":")) + "\n")
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

Append to `helper/launcher-helper.sh` (after the `HELPER_DIR=` line):

```bash
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
```

> 이후 Task들은 `main`의 `case`에 한 줄씩 추가하고 해당 `cmd_*` 함수를 `main` 정의 **위**에 추가한다.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats helper/tests/dispatch.bats`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add helper/lib/emit.py helper/launcher-helper.sh helper/tests/dispatch.bats
git commit -m "feat: helper bootstrap, emit.py, dispatcher + usage

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `detect` 서브커맨드

WSL 안 사전 점검 사실(인터넷·python3·wslview·cmd.exe·hermes/codex 설치 여부·codex 인증 여부)을 한 줄 `detect` 이벤트로 emit한다. (Windows 쪽 `wsl -l -v`·distro 선택은 Plan 2 Rust 담당.)

**Files:**
- Modify: `helper/launcher-helper.sh`
- Create: `helper/tests/stubs/wslview`
- Create: `helper/tests/detect.bats`

- [ ] **Step 1: Write the failing test**

Create `helper/tests/stubs/wslview`:

```bash
#!/usr/bin/env bash
# Stub WSL browser opener: accept a URL, do nothing, succeed.
exit 0
```

Make it executable:

```bash
chmod +x helper/tests/stubs/wslview
```

Create `helper/tests/detect.bats`:

```bash
#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "detect emits exactly one schema-valid detect event" {
  export LAUNCHER_NET_CHECK_URL="file://$FIX/install-success.sh"  # any readable file => internet true
  mkdir -p "$FIX"; echo "ok" > "$FIX/install-success.sh"
  run "$HELPER" detect
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"detect"'* ]]
}

@test "detect reports codex_authed true when auth.json exists" {
  export LAUNCHER_NET_CHECK_URL="file:///nonexistent-$$"
  mkdir -p "$CODEX_HOME"; echo '{}' > "$CODEX_HOME/auth.json"
  run "$HELPER" detect
  [ "$status" -eq 0 ]
  [[ "$output" == *'"codex_authed":true'* ]]
  [[ "$output" == *'"internet":false'* ]]
}

@test "detect reports hermes_installed true when install dir exists" {
  export LAUNCHER_NET_CHECK_URL="file:///nonexistent-$$"
  mkdir -p "$HERMES_HOME/hermes-agent"
  run "$HELPER" detect
  [[ "$output" == *'"hermes_installed":true'* ]]
}

@test "detect reports wslview true when wslview on PATH" {
  export LAUNCHER_NET_CHECK_URL="file:///nonexistent-$$"
  run "$HELPER" detect
  [[ "$output" == *'"wslview":true'* ]]   # stubs dir provides wslview
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats helper/tests/detect.bats`
Expected: FAIL — `detect` 미구현이라 usage(exit 2) 반환.

- [ ] **Step 3: Write minimal implementation**

Add `cmd_detect` to `helper/launcher-helper.sh` (above `main`):

```bash
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
```

Add the dispatcher case in `main` (replace the `""|-h|--help` block region so `detect` is matched before the fallthrough):

```bash
  case "$cmd" in
    detect)       cmd_detect "$@" ;;
    ""|-h|--help) usage; exit 2 ;;
    *)            usage; exit 2 ;;
  esac
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats helper/tests/detect.bats`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add helper/launcher-helper.sh helper/tests/stubs/wslview helper/tests/detect.bats
git commit -m "feat: detect subcommand (in-WSL preflight facts)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `install-hermes` 서브커맨드

업스트림 install.sh를 다운로드해 실행하고, 그 stdout의 알려진 마커를 progress 이벤트로 매핑한다. 성공 시 `done(ok:true)`, 실패 시 `error(fatal)`.

**Files:**
- Modify: `helper/launcher-helper.sh`
- Create: `helper/tests/fixtures/install-success.sh`
- Create: `helper/tests/fixtures/install-fail.sh`
- Create: `helper/tests/install.bats`

- [ ] **Step 1: Write the failing test**

Create `helper/tests/fixtures/install-success.sh`:

```bash
#!/usr/bin/env bash
# Fixture mimicking upstream install.sh stdout markers (confirmed from real script).
echo "Installing uv..."
echo "Cloning hermes-agent..."
echo "Creating virtual environment..."
echo "Installing package..."
echo "Created $HOME/.hermes/config.yaml from template"
echo "✓ Installation Complete!"
exit 0
```

Create `helper/tests/fixtures/install-fail.sh`:

```bash
#!/usr/bin/env bash
echo "Installing uv..."
echo "ERROR: network unreachable" >&2
exit 1
```

Create `helper/tests/install.bats`:

```bash
#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "install-hermes maps stdout markers to progress and finishes ok" {
  export HERMES_INSTALL_URL="file://$FIX/install-success.sh"
  run "$HELPER" install-hermes
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"step":"install-hermes","progress":15'* ]]
  [[ "$output" == *'"progress":35'* ]]
  [[ "$output" == *'"progress":85'* ]]
  [[ "$output" == *'"progress":100'* ]]
  [[ "$output" == *'{"event":"done","step":"install-hermes","ok":true}'* ]]
}

@test "install-hermes emits fatal error on non-zero install" {
  export HERMES_INSTALL_URL="file://$FIX/install-fail.sh"
  run "$HELPER" install-hermes
  [ "$status" -ne 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"error"'* ]]
  [[ "$output" == *'"level":"fatal"'* ]]
  [[ "$output" != *'"ok":true'* ]]
}

@test "install-hermes emits environment error when download fails" {
  export HERMES_INSTALL_URL="file:///nonexistent-$$-install.sh"
  run "$HELPER" install-hermes
  [ "$status" -ne 0 ]
  [[ "$output" == *'"level":"environment"'* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats helper/tests/install.bats`
Expected: FAIL — `install-hermes` 미구현(exit 2).

- [ ] **Step 3: Write minimal implementation**

Add to `helper/launcher-helper.sh` (above `main`):

```bash
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
```

Add dispatcher case in `main`:

```bash
    install-hermes) cmd_install_hermes "$@" ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats helper/tests/install.bats`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add helper/launcher-helper.sh helper/tests/fixtures/install-success.sh helper/tests/fixtures/install-fail.sh helper/tests/install.bats
git commit -m "feat: install-hermes subcommand (stdout -> progress events)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `codex-login` 서브커맨드 — 성공 + 멱등

`codex login`을 백그라운드로 띄우고 `~/.codex/auth.json` 생성을 폴링한다. 이미 인증돼 있으면 즉시 통과(멱등). 인증 성공 시 `codex_authed`(가능하면 email).

**Files:**
- Modify: `helper/launcher-helper.sh`
- Create: `helper/tests/stubs/codex`
- Create: `helper/tests/codex.bats`

- [ ] **Step 1: Write the failing test**

Create `helper/tests/stubs/codex`:

```bash
#!/usr/bin/env bash
# Stub codex CLI. Behavior controlled by env:
#   STUB_CODEX_MODE  : authok|fail|abort|hang   (default authok)
#   STUB_CODEX_DELAY : seconds before writing auth.json (default 0)
# Writes auth.json under $CODEX_HOME on `login` in authok mode.
set -u
sub="${1:-}"
shift || true
case "$sub" in
  --version) echo "codex 0.0.0-stub"; exit 0 ;;
  login)
    if [ "${1:-}" = "status" ]; then
      if [ -f "$CODEX_HOME/auth.json" ]; then echo "Logged in as user@example.com"; exit 0
      else echo "Not logged in"; exit 1; fi
    fi
    case "${STUB_CODEX_MODE:-authok}" in
      authok)
        sleep "${STUB_CODEX_DELAY:-0}"
        mkdir -p "$CODEX_HOME"
        printf '%s' '{"OPENAI_API_KEY":null,"tokens":{},"last_refresh":null}' > "$CODEX_HOME/auth.json"
        exit 0 ;;
      fail)  echo "no subscription" >&2; exit 1 ;;
      abort) exit 130 ;;
      hang)  sleep 60; exit 0 ;;
    esac ;;
  debug) echo '{"models":[]}'; exit 0 ;;
  *) exit 0 ;;
esac
```

Make it executable:

```bash
chmod +x helper/tests/stubs/codex
```

Create `helper/tests/codex.bats`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats helper/tests/codex.bats`
Expected: FAIL — `codex-login` 미구현(exit 2).

- [ ] **Step 3: Write minimal implementation**

Add to `helper/launcher-helper.sh` (above `main`):

```bash
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
```

Add dispatcher case in `main`:

```bash
    codex-login)  cmd_codex_login "$@" ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats helper/tests/codex.bats`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add helper/launcher-helper.sh helper/tests/stubs/codex helper/tests/codex.bats
git commit -m "feat: codex-login subcommand (poll auth.json, idempotent)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: `codex-login` 실패 모드 — fail / abort / timeout

설계 문서 121~128줄의 실패 처리표를 검증한다. 구독 없음→`codex_error`, 브라우저 닫음/중단→`codex_aborted`, 미완료→`codex_timeout`.

**Files:**
- Modify: `helper/tests/codex.bats` (테스트 추가; 구현은 Task 6에서 이미 완료)

- [ ] **Step 1: Write the failing test**

Append to `helper/tests/codex.bats`:

```bash
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
  run "$HELPER" codex-login
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'{"event":"codex_timeout"}'* ]]
}
```

- [ ] **Step 2: Run test to verify it fails or passes**

Run: `bats helper/tests/codex.bats`
Expected: 새 3개 테스트 PASS (구현이 Task 6에서 이미 모든 분기를 다룸). 만약 `codex_error` 테스트가 detail 비어서 실패하면, 스텁이 stderr에 "no subscription"을 쓰고 `$HERMES_HOME/codex-login.err` 경로가 올바른지 확인. timeout 테스트는 ~2초 소요.

> 이 Task는 "이미 구현된 분기의 회귀 테스트"다. 만약 어떤 분기가 실패하면 Task 6 `cmd_codex_login`을 수정해 통과시킨 뒤 진행한다(TDD: 빨강→초록).

- [ ] **Step 3: (필요 시) 구현 보정**

테스트가 모두 통과하면 생략. 실패 시 `cmd_codex_login`의 해당 분기를 수정.

- [ ] **Step 4: Run test to verify it passes**

Run: `bats helper/tests/codex.bats`
Expected: PASS (5 tests 총합).

- [ ] **Step 5: Commit**

```bash
git add helper/tests/codex.bats helper/launcher-helper.sh
git commit -m "test: codex-login failure modes (error/abort/timeout)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: `slack-manifest` 서브커맨드

`hermes slack manifest` stdout(JSON)을 캡처해 `slack_manifest{json:"…"}` 이벤트로 emit한다.

**Files:**
- Modify: `helper/launcher-helper.sh`
- Create: `helper/tests/stubs/hermes`
- Create: `helper/tests/slack_manifest.bats`

- [ ] **Step 1: Write the failing test**

Create `helper/tests/stubs/hermes`:

```bash
#!/usr/bin/env bash
# Stub hermes CLI.
#   hermes --version
#   hermes slack manifest        -> prints a manifest JSON
#   hermes config set KEY VALUE  -> echoes, exit 0
#   STUB_HERMES_MANIFEST_FAIL=1  -> `slack manifest` exits 1
set -u
sub="${1:-}"
shift || true
case "$sub" in
  --version) echo "hermes 1.2.3-stub"; exit 0 ;;
  slack)
    if [ "${1:-}" = "manifest" ]; then
      if [ "${STUB_HERMES_MANIFEST_FAIL:-0}" = "1" ]; then echo "manifest error" >&2; exit 1; fi
      printf '%s' '{"display_information":{"name":"hermes"},"settings":{"socket_mode_enabled":true}}'
      exit 0
    fi ;;
  config)
    if [ "${1:-}" = "set" ]; then echo "set ${2:-} = ${3:-}"; exit 0; fi ;;
esac
exit 0
```

Make it executable:

```bash
chmod +x helper/tests/stubs/hermes
```

Create `helper/tests/slack_manifest.bats`:

```bash
#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "slack-manifest emits a slack_manifest event carrying the JSON string" {
  run "$HELPER" slack-manifest
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"slack_manifest"'* ]]
  [[ "$output" == *'socket_mode_enabled'* ]]
}

@test "slack-manifest emits recoverable error when hermes fails" {
  export STUB_HERMES_MANIFEST_FAIL=1
  run "$HELPER" slack-manifest
  [ "$status" -ne 0 ]
  [[ "$output" == *'"level":"recoverable"'* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats helper/tests/slack_manifest.bats`
Expected: FAIL — `slack-manifest` 미구현(exit 2).

- [ ] **Step 3: Write minimal implementation**

Add to `helper/launcher-helper.sh` (above `main`):

```bash
cmd_slack_manifest() {
  emit event=step step=slack-manifest progress:=0 msg="generating slack manifest"
  local json
  if ! json="$(hermes slack manifest 2>/dev/null)"; then
    die slack-manifest recoverable "hermes slack manifest failed"
  fi
  emit event=slack_manifest json="$json"
}
```

Add dispatcher case in `main`:

```bash
    slack-manifest) cmd_slack_manifest "$@" ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats helper/tests/slack_manifest.bats`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add helper/launcher-helper.sh helper/tests/stubs/hermes helper/tests/slack_manifest.bats
git commit -m "feat: slack-manifest subcommand

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: `slack-verify` 서브커맨드

bot 토큰(xoxb-) 형식을 1차 검증하고, Slack `auth.test`로 워크스페이스/봇 이름을 확인해 `slack_verified` 또는 `slack_error`를 emit한다.

**Files:**
- Modify: `helper/launcher-helper.sh`
- Create: `helper/tests/fixtures/slack-auth-ok/auth.test`
- Create: `helper/tests/fixtures/slack-auth-bad/auth.test`
- Create: `helper/tests/slack_verify.bats`

- [ ] **Step 1: Write the failing test**

Create `helper/tests/fixtures/slack-auth-ok/auth.test`:

```json
{"ok":true,"team":"Acme","user":"hermes"}
```

Create `helper/tests/fixtures/slack-auth-bad/auth.test`:

```json
{"ok":false,"error":"invalid_auth"}
```

Create `helper/tests/slack_verify.bats`:

```bash
#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "slack-verify rejects a token without xoxb- prefix" {
  run "$HELPER" slack-verify "xapp-wrong"
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"slack_error"'* ]]
  [[ "$output" == *'xoxb-'* ]]
}

@test "slack-verify emits slack_verified with workspace and bot on ok" {
  export LAUNCHER_SLACK_API="file://$FIX/slack-auth-ok"
  run "$HELPER" slack-verify "xoxb-valid-token"
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"slack_verified"'* ]]
  [[ "$output" == *'"workspace":"Acme"'* ]]
  [[ "$output" == *'"bot":"hermes"'* ]]
}

@test "slack-verify emits slack_error with Slack error code" {
  export LAUNCHER_SLACK_API="file://$FIX/slack-auth-bad"
  run "$HELPER" slack-verify "xoxb-bad-token"
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'"event":"slack_error"'* ]]
  [[ "$output" == *'invalid_auth'* ]]
}

@test "slack-verify errors when token argument missing" {
  run "$HELPER" slack-verify
  [ "$status" -ne 0 ]
  [[ "$output" == *'"level":"recoverable"'* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats helper/tests/slack_verify.bats`
Expected: FAIL — `slack-verify` 미구현(exit 2).

- [ ] **Step 3: Write minimal implementation**

Add to `helper/launcher-helper.sh` (above `main`):

```bash
# Parse a Slack auth.test JSON body from stdin into a TSV line: status\tteam\tuser
parse_slack_auth() {
  python3 - <<'PY'
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print("parse_error\t\t"); sys.exit(0)
if d.get("ok"):
    print("ok\t%s\t%s" % (d.get("team", ""), d.get("user", "")))
else:
    print("%s\t\t" % d.get("error", "unknown"))
PY
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
```

Add dispatcher case in `main`:

```bash
    slack-verify) cmd_slack_verify "$@" ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats helper/tests/slack_verify.bats`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add helper/launcher-helper.sh helper/tests/fixtures/slack-auth-ok helper/tests/fixtures/slack-auth-bad helper/tests/slack_verify.bats
git commit -m "feat: slack-verify subcommand (auth.test)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: `write-config` 서브커맨드

Slack 토큰을 `~/.hermes/.env`에 보존 머지(upsert)하고, `--codex` 시 `hermes config set model.provider`로 코덱스 공급자를 설정한다. 멱등.

**Files:**
- Modify: `helper/launcher-helper.sh`
- Create: `helper/lib/upsert_env.py`
- Create: `helper/tests/write_config.bats`

- [ ] **Step 1: Write the failing test**

Create `helper/tests/write_config.bats`:

```bash
#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

@test "write-config upserts slack tokens into ~/.hermes/.env, preserving others" {
  printf 'OTHER=keepme\nSLACK_BOT_TOKEN=xoxb-old\n' > "$HERMES_HOME/.env"
  run "$HELPER" write-config --slack-bot "xoxb-new" --slack-app "xapp-new"
  [ "$status" -eq 0 ]
  echo "$output" > "$TMP/ev.jsonl"
  assert_valid_jsonl "$TMP/ev.jsonl"
  [[ "$output" == *'{"event":"done","step":"write-config","ok":true}'* ]]
  grep -qx 'OTHER=keepme' "$HERMES_HOME/.env"
  grep -qx 'SLACK_BOT_TOKEN=xoxb-new' "$HERMES_HOME/.env"
  grep -qx 'SLACK_APP_TOKEN=xapp-new' "$HERMES_HOME/.env"
  # exactly one SLACK_BOT_TOKEN line (idempotent upsert)
  [ "$(grep -c '^SLACK_BOT_TOKEN=' "$HERMES_HOME/.env")" -eq 1 ]
}

@test "write-config is idempotent across repeated runs" {
  run "$HELPER" write-config --slack-bot "xoxb-a"
  run "$HELPER" write-config --slack-bot "xoxb-a"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^SLACK_BOT_TOKEN=' "$HERMES_HOME/.env")" -eq 1 ]
  grep -qx 'SLACK_BOT_TOKEN=xoxb-a' "$HERMES_HOME/.env"
}

@test "write-config --codex calls hermes config set model.provider" {
  run "$HELPER" write-config --codex
  [ "$status" -eq 0 ]
  [[ "$output" == *'{"event":"done","step":"write-config","ok":true}'* ]]
}

@test "write-config rejects unknown args" {
  run "$HELPER" write-config --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *'"level":"recoverable"'* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats helper/tests/write_config.bats`
Expected: FAIL — `write-config` 미구현(exit 2).

- [ ] **Step 3: Write minimal implementation**

Create `helper/lib/upsert_env.py`:

```python
#!/usr/bin/env python3
"""Idempotently upsert KEY=VALUE into a .env-style file, preserving other lines.

Usage: upsert_env.py <path> <KEY> <VALUE>
"""
import pathlib
import sys

def main() -> int:
    if len(sys.argv) != 4:
        print("usage: upsert_env.py <path> <KEY> <VALUE>", file=sys.stderr)
        return 2
    path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
    p = pathlib.Path(path)
    lines = p.read_text().splitlines() if p.exists() else []
    out, found = [], False
    for line in lines:
        if line.startswith(key + "="):
            if not found:
                out.append(f"{key}={value}")
                found = True
            # drop duplicate KEY= lines
        else:
            out.append(line)
    if not found:
        out.append(f"{key}={value}")
    p.write_text("\n".join(out) + "\n")
    return 0

if __name__ == "__main__":
    sys.exit(main())
```

Add to `helper/launcher-helper.sh` (above `main`):

```bash
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
```

Add dispatcher case in `main`:

```bash
    write-config) cmd_write_config "$@" ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats helper/tests/write_config.bats`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add helper/launcher-helper.sh helper/lib/upsert_env.py helper/tests/write_config.bats
git commit -m "feat: write-config subcommand (.env upsert + codex provider)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: `verify` 서브커맨드

설치 종료 검증: `codex --version`, `codex login status`, hermes 존재 확인. 성공 시 `done(ok:true)`, 실패 시 단계별 `error`.

**Files:**
- Modify: `helper/launcher-helper.sh`
- Create: `helper/tests/verify.bats`

- [ ] **Step 1: Write the failing test**

Create `helper/tests/verify.bats`:

```bash
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats helper/tests/verify.bats`
Expected: FAIL — `verify` 미구현(exit 2).

> 주의: 세 번째 테스트는 `PATH=/usr/bin:/bin`로 바꾸므로 `python3`도 그 경로에 있어야 부트스트랩을 통과한다(대개 `/usr/bin/python3` 존재). 없으면 부트스트랩이 environment 에러를 내는데, 이 역시 `"level":"environment"`를 만족하므로 테스트는 통과한다.

- [ ] **Step 3: Write minimal implementation**

Add to `helper/launcher-helper.sh` (above `main`):

```bash
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
```

Add dispatcher case in `main`:

```bash
    verify)       cmd_verify "$@" ;;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats helper/tests/verify.bats`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add helper/launcher-helper.sh helper/tests/verify.bats
git commit -m "feat: verify subcommand (codex + hermes usable)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: 전체 계약 적합성 + shellcheck + 헬퍼 CI

전체 흐름을 한 번에 돌려 **모든** emit이 스키마를 만족함을 회귀 테스트하고, shellcheck 린트를 추가하고, 헬퍼 단독 GitHub Actions CI를 만든다. `helper/README.md`도 작성.

**Files:**
- Create: `helper/tests/conformance.bats`
- Create: `.github/workflows/helper.yml`
- Create: `helper/README.md`

- [ ] **Step 1: Write the failing test**

Create `helper/tests/conformance.bats`:

```bash
#!/usr/bin/env bats

load lib/common

setup() { setup_common; }
teardown() { teardown_common; }

# Run a representative happy-path flow; concatenate ALL events; validate as one stream.
@test "full happy-path flow emits only schema-valid events" {
  mkdir -p "$FIX"; echo "ok" > "$FIX/install-success.sh" 2>/dev/null || true
  : > "$TMP/all.jsonl"

  export LAUNCHER_NET_CHECK_URL="file://$FIX/install-success.sh"
  "$HELPER" detect >> "$TMP/all.jsonl"

  export HERMES_INSTALL_URL="file://$FIX/install-success.sh"
  "$HELPER" install-hermes >> "$TMP/all.jsonl"

  export STUB_CODEX_MODE=authok STUB_CODEX_DELAY=0
  "$HELPER" codex-login >> "$TMP/all.jsonl"

  "$HELPER" slack-manifest >> "$TMP/all.jsonl"

  export LAUNCHER_SLACK_API="file://$FIX/slack-auth-ok"
  "$HELPER" slack-verify "xoxb-token" >> "$TMP/all.jsonl"

  "$HELPER" write-config --slack-bot "xoxb-token" --slack-app "xapp-token" --codex >> "$TMP/all.jsonl"
  "$HELPER" verify >> "$TMP/all.jsonl"

  assert_valid_jsonl "$TMP/all.jsonl"
}

@test "shellcheck is clean on helper and stubs" {
  if ! command -v shellcheck >/dev/null 2>&1; then skip "shellcheck not installed"; fi
  run shellcheck -x "$HELPER" "$STUBS/codex" "$STUBS/hermes" "$STUBS/wslview" "$FIX/install-success.sh" "$FIX/install-fail.sh"
  [ "$status" -eq 0 ]
}
```

> 위 conformance 테스트의 install-success 픽스처는 Task 5에서 만든 실제 마커 버전을 쓴다(여기서 `echo "ok" >`로 덮어쓰지 않도록, Task 5 픽스처가 존재하면 그대로 둔다 — `2>/dev/null || true`는 보호용). install 마커 검증은 Task 5가 담당하므로 여기서는 스키마 적합성만 본다.

수정: conformance.bats의 `echo "ok" > "$FIX/install-success.sh"` 줄은 Task 5 픽스처를 덮어쓰므로 제거하고, Task 5의 `install-success.sh`를 그대로 사용한다. 대신 detect의 인터넷 점검 대상은 항상 존재하는 파일이면 되므로 `LAUNCHER_NET_CHECK_URL="file://$HELPER"`를 사용한다.

최종 `conformance.bats`의 첫 테스트 앞부분을 다음으로 한다:

```bash
@test "full happy-path flow emits only schema-valid events" {
  : > "$TMP/all.jsonl"

  export LAUNCHER_NET_CHECK_URL="file://$HELPER"   # any readable file => internet true
  "$HELPER" detect >> "$TMP/all.jsonl"

  export HERMES_INSTALL_URL="file://$FIX/install-success.sh"
  "$HELPER" install-hermes >> "$TMP/all.jsonl"
  ...
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats helper/tests/conformance.bats`
Expected: 첫 실행에서 의도된 실패가 없을 수도 있다(구현이 이미 끝났으므로). 이 Task의 목적은 회귀 가드 추가 + 린트. shellcheck가 경고를 내면 그걸 빨강으로 간주하고 Step 3에서 고친다.

- [ ] **Step 3: Fix any shellcheck findings**

shellcheck 경고가 있으면 `helper/launcher-helper.sh`/스텁/픽스처에서 수정한다. 자주 나오는 항목과 대응:
- SC2086(따옴표 누락): emit 인자처럼 의도적으로 분할이 필요한 곳은 `# shellcheck disable=SC2086` 주석으로 명시. 그 외는 따옴표 추가.
- SC2155(선언+대입 분리): `local x; x="$(...)"`로 분리(이미 대부분 적용됨).
- 스텁의 `set -u`만 쓴 것은 의도(에러 분기 테스트). 필요 시 disable 주석.

Create `.github/workflows/helper.yml`:

```yaml
name: helper

on:
  push:
    paths:
      - "helper/**"
      - ".github/workflows/helper.yml"
  pull_request:
    paths:
      - "helper/**"
      - ".github/workflows/helper.yml"

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install bats, shellcheck, jsonschema
        run: |
          sudo apt-get update
          sudo apt-get install -y bats shellcheck python3-pip
          python3 -m pip install --user jsonschema
      - name: shellcheck
        run: shellcheck -x helper/launcher-helper.sh helper/tests/stubs/* helper/tests/fixtures/install-*.sh
      - name: bats
        run: bats helper/tests/
```

Create `helper/README.md`:

```markdown
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

## Running the tests

```bash
# deps: bats-core, python3 + jsonschema, shellcheck
bats helper/tests/
```

All upstream calls are overridable via env vars (see the helper header) so tests
run fully offline with stubs/fixtures.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats helper/tests/` (전체)
Expected: 모든 파일 PASS. `shellcheck -x helper/launcher-helper.sh helper/tests/stubs/* helper/tests/fixtures/install-*.sh` → exit 0.

- [ ] **Step 5: Commit**

```bash
git add helper/tests/conformance.bats .github/workflows/helper.yml helper/README.md helper/launcher-helper.sh helper/tests/stubs helper/tests/fixtures
git commit -m "test: full-flow schema conformance + shellcheck + helper CI

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage (설계 문서 대비):**
- 헬퍼 서브커맨드 detect/install-hermes/codex-login/slack-manifest/write-config/verify (설계 50~54줄) → Task 4·5·6·8·10·11. **추가**: `slack-verify`(설계 4-C의 `auth.test` 검증, 136~139줄)를 별도 서브커맨드로 분리 → Task 9. ✅
- "한 줄 = 1 JSON 이벤트"(54줄), JSONL 계약 단일 파일(67줄, 199줄) → Task 2 `events.schema.json` + `validate_events.py`. ✅
- 7절 이벤트 예시(step/codex_authed/codex_error/slack_manifest/slack_verified/done/error) → 스키마에 모두 포함 + codex_aborted/codex_timeout/slack_error 보강. ✅
- 멱등성(161줄): codex-login(auth.json 존재 시 통과), write-config(.env upsert·재실행 안전), install(install.sh 자체 멱등) → Task 6·10 테스트로 검증. ✅
- 에러 등급 recoverable/environment/fatal(164~168줄) → 스키마 `level` enum + 각 die 호출. ✅
- codex auth 폴링·타임아웃·중단(112~128줄) → Task 6·7. ✅
- TDD 적용(200줄) → 전 Task TDD 구조. ✅
- bats 테스트(193줄): 멱등성·JSONL 스키마·에러 종료코드 → 전반 커버. ✅
- **범위 밖(이 플랜 제외, Plan 2~4)**: Windows WSL 감지·distro 선택(Rust), state.json(Rust), Credential Manager(Rust), 5단계 UI(React), 패키징/서명/튜토리얼 스크린샷(Plan 4). 의도된 제외. ✅

**2. Placeholder scan:** "TBD/적절히/나중에" 류 없음. 모든 코드 스텝에 실제 코드 포함. Task 7은 "이미 구현된 분기의 회귀 테스트"임을 명시(코드 중복 회피, 단 분기 로직은 Task 6에 완전히 존재). Task 12 conformance.bats는 본문에서 install 픽스처 덮어쓰기 버그를 스스로 교정(`LAUNCHER_NET_CHECK_URL="file://$HELPER"` 사용). ✅

**3. Type/이름 일관성:**
- 이벤트 enum(`step` 값 7종)이 스키마 `$defs/step`과 각 서브커맨드의 `step=` 인자에서 동일: detect/install-hermes/codex-login/slack-manifest/slack-verify/write-config/verify. ✅
- `emit`의 raw 표기 `key:=value`(bool/number)와 string 표기 `key=value`가 emit.py 정규식과 일치. ✅
- 환경변수명(HERMES_HOME/CODEX_HOME/HERMES_INSTALL_URL/LAUNCHER_*)이 헤더·테스트·common.bash에서 동일. ✅
- `assert_valid_jsonl`(common.bash)·`VALIDATE` 경로(`tests/lib/validate_events.py`)·`SCHEMA` 경로 일관. ✅
- `cmd_*` 함수명 ↔ 디스패처 `case` 값 일관. ✅

발견·교정 사항: Task 12 conformance 첫 작성안의 픽스처 덮어쓰기 → 본문에서 교정안 제시. Task 7은 신규 구현이 아니라 Task 6 분기 회귀 → TDD 의미 보존을 위해 "실패 시 보정" 절차 명시.

---

## 실행 옵션

**Plan 1 (helper.sh + JSONL 계약) 작성 완료. 저장 위치: `docs/superpowers/plans/2026-05-20-hermes-launcher-helper.md`. 두 가지 실행 방식:**

**1. Subagent-Driven (추천)** — Task마다 새 서브에이전트를 디스패치하고 Task 사이에 리뷰, 빠른 반복.

**2. Inline Execution** — 이 세션에서 executing-plans로 체크포인트 배치 실행.

**어떤 방식으로 진행할까요?** (또는 먼저 이 플랜 자체를 리뷰/수정하고 싶으면 말씀해 주세요. Plan 2~4 작성은 Plan 1 확정 후 이어갑니다.)
