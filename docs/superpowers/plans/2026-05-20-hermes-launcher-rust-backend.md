# Hermes Launcher — Plan 2: Tauri/Rust 백엔드 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plan 1의 `helper/launcher-helper.sh`를 WSL 안에서 구동하고 그 JSONL 이벤트를 파싱·검증하며, 위저드 상태를 영속화하고, Slack 토큰을 OS 보안 저장소에 보관하는 Tauri 2(Rust) 백엔드를 TDD로 구현한다.

**Architecture:** 모든 비즈니스 로직은 `src-tauri/src/`의 평범한 Rust 모듈(`events`/`state`/`wsl`/`secrets`/`runner`)에 두고, `#[tauri::command]`는 그 위의 얇은 래퍼로만 둔다. 덕분에 webview/Tauri 런타임 없이 `cargo test`로 로직을 검증한다. 헬퍼 이벤트 계약은 Plan 1의 `helper/events.schema.json`을 단일 진실의 출처로 공유하고, Rust↔스키마 적합성은 **Plan 1의 python 검증기(`validate_events.py`)를 재사용**해 강제한다(Rust용 JSON Schema 라이브러리 추가 없음).

**Tech Stack:** Tauri 2.11 (`tauri`/`tauri-build` `"2"`), serde + serde_json, `keyring = "3"`(features `apple-native`,`windows-native`; 테스트는 mock builder), `dirs = "6"`, `encoding_rs = "0.8"`, `tauri::ipc::Channel<T>` 스트리밍, std::process + BufReader. CI: `cargo test`/`clippy`/`fmt` (ubuntu+windows 매트릭스).

---

## 이 문서의 위치 (foundation-first 로드맵)

1. Plan 1 — helper.sh + JSONL 이벤트 계약. ✅ **완료·main 병합** (12 Task, 41 bats).
2. **Plan 2 (이 문서)** — Tauri/Rust 백엔드. Plan 1 계약을 소비.
3. Plan 3 — React 프론트엔드 (5단계 위저드).
4. Plan 4 — 통합 + 패키징/CI(`tauri-action`) + 튜토리얼 + E2E.

## 플랫폼 제약 (개발: macOS / 타깃: Windows+WSL2)

- 크로스플랫폼·`cargo test`로 macOS에서 검증 가능: `events`(파서), `state`(상태머신·영속화), `wsl`(파싱 함수·UTF-16LE 디코드), `secrets`(keyring + mock), `runner`(스트림 파싱).
- **Windows 전용**(`#[cfg(windows)]`, macOS 빌드에서 제외 → Parallels/Windows에서 검증): `wsl::list_distros`(`wsl.exe -l -v` 실제 호출), `runner::wsl_helper_command`(`wsl.exe -d … bash -lc`) 실제 spawn.
- 따라서 Windows 전용 함수는 얇게 유지하고, 그 안의 **로직(파싱·명령 조립 인자)**은 크로스플랫폼 함수로 분리해 테스트한다.

---

## File Structure

설계 문서 71~78줄의 `src-tauri/` 구조를 따른다.

- `src-tauri/Cargo.toml` — 의존성·lib 설정(`crate-type` 포함, plain `cargo test` 가능).
- `src-tauri/build.rs` — `tauri_build::build()`.
- `src-tauri/tauri.conf.json` — Tauri 2 앱 설정(번들 식별자, 윈도우).
- `src-tauri/src/main.rs` — `windows_subsystem` 속성 + `hermes_launcher_lib::run()` 호출.
- `src-tauri/src/lib.rs` — 모듈 선언, `#[tauri::command]` 얇은 래퍼, `run()`(Builder).
- `src-tauri/src/events.rs` — `HelperEvent`/`Step`/`Level` serde 타입 + `parse_line`. **계약의 Rust 측.**
- `src-tauri/src/state.rs` — `WizardState`/`StepStatus` + load/save + `default_state_path`.
- `src-tauri/src/wsl.rs` — `Distro`, `parse_list_verbose`, `decode_wsl_output`, `#[cfg(windows)] list_distros`.
- `src-tauri/src/secrets.rs` — keyring 래퍼 store/retrieve/delete.
- `src-tauri/src/runner.rs` — `stream_events`(리더→이벤트 sink), `#[cfg(windows)] wsl_helper_command`.
- `src-tauri/tests/contract.rs` — 통합 계약 테스트(직렬화 이벤트를 Plan 1 python 검증기로 검증).
- `.github/workflows/rust.yml` — cargo fmt/clippy/test (ubuntu + windows).

---

## 사전 준비

- Rust 툴체인(`rustup`, stable). macOS/Windows 공통.
- Tauri 2 시스템 의존성: macOS는 Xcode CLT만으로 `cargo test` 가능(로직 테스트는 webview 불필요). 전체 `cargo tauri dev`는 Plan 4에서.
- 테스트에 Plan 1 산출물(`helper/events.schema.json`, `helper/tests/lib/validate_events.py`) + `python3`+`jsonschema` 필요(이미 있음).

표준 테스트 명령: `cd src-tauri && cargo test`.

---

## Task 1: Tauri 2 Rust 프로젝트 스캐폴드

`cargo test`가 도는 최소 Tauri 2 프로젝트 골격을 만든다.

**Files:**
- Create: `src-tauri/Cargo.toml`, `src-tauri/build.rs`, `src-tauri/src/main.rs`, `src-tauri/src/lib.rs`, `src-tauri/tauri.conf.json`
- Modify: `.gitignore` (이미 `/src-tauri/target/` 무시 — 확인만)

- [ ] **Step 1: Write the failing test**

Create `src-tauri/src/lib.rs`:

```rust
//! Hermes Launcher Tauri backend. Logic lives in plain modules so it is
//! testable with `cargo test` (no webview / Tauri runtime needed).

#[cfg(test)]
mod scaffold_tests {
    #[test]
    fn crate_builds_and_tests_run() {
        assert_eq!(2 + 2, 4);
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src-tauri && cargo test`
Expected: FAIL — `Cargo.toml`/`build.rs`가 없어 빌드 불가(컴파일 에러).

- [ ] **Step 3: Write minimal implementation**

Create `src-tauri/Cargo.toml`:

```toml
[package]
name = "hermes-launcher"
version = "0.1.0"
edition = "2021"

[lib]
name = "hermes_launcher_lib"
crate-type = ["staticlib", "cdylib", "rlib"]

[build-dependencies]
tauri-build = { version = "2", features = [] }

[dependencies]
tauri = { version = "2", features = [] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
dirs = "6"
encoding_rs = "0.8"
keyring = { version = "3", features = ["apple-native", "windows-native"] }

[profile.release]
codegen-units = 1
lto = true
opt-level = 3
panic = "abort"
strip = true
```

Create `src-tauri/build.rs`:

```rust
fn main() {
    tauri_build::build()
}
```

Create `src-tauri/src/main.rs`:

```rust
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    hermes_launcher_lib::run()
}
```

Append to `src-tauri/src/lib.rs` (above the `#[cfg(test)]` block):

```rust
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

Create `src-tauri/tauri.conf.json`:

```json
{
  "$schema": "https://schema.tauri.app/config/2",
  "productName": "Hermes Launcher",
  "version": "0.1.0",
  "identifier": "research.nous.hermes-launcher",
  "build": {
    "frontendDist": "../dist"
  },
  "app": {
    "windows": [
      {
        "title": "Hermes Launcher",
        "width": 720,
        "height": 560,
        "resizable": true
      }
    ],
    "security": {
      "csp": null
    }
  },
  "bundle": {
    "active": true,
    "targets": ["msi", "nsis"],
    "icon": ["icons/icon.ico"]
  }
}
```

> `generate_context!()`는 `frontendDist`(`../dist`)와 아이콘을 요구할 수 있다. Plan 4(프론트엔드/번들) 전까지 `cargo test`만 통과시키려면, 이 Task의 테스트는 `--lib`로 로직만 돌린다(아래 Step 4). 풀 `generate_context!` 빌드는 dist/아이콘이 생기는 Plan 3/4에서 검증한다. `run()`은 컴파일만 되면 충분하다.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src-tauri && cargo test --lib`
Expected: PASS (1 test). `generate_context!`가 dist/아이콘 부재로 컴파일 실패하면, 임시로 `icons/icon.ico` 플레이스홀더와 빈 `dist/index.html`을 만들거나, `run()` 본문을 Plan 3까지 `#[cfg(feature = "app")]`로 게이트한다. **로직 모듈 테스트(`cargo test --lib`)가 도는 것이 이 Task의 합격선.**

- [ ] **Step 5: Commit**

```bash
git add src-tauri/Cargo.toml src-tauri/build.rs src-tauri/src/main.rs src-tauri/src/lib.rs src-tauri/tauri.conf.json
git commit -m "chore: scaffold Tauri 2 Rust backend (cargo test runs)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `events.rs` — 헬퍼 이벤트 타입 + 파서

Plan 1의 `events.schema.json`에 정확히 대응하는 serde 타입과 `parse_line`을 구현하고, 대표 이벤트 라인을 라운드트립한다.

**Files:**
- Create: `src-tauri/src/events.rs`
- Modify: `src-tauri/src/lib.rs` (`mod events;`)

- [ ] **Step 1: Write the failing test**

Create `src-tauri/src/events.rs` (test module only first):

```rust
// (types added in Step 3)

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_step_event() {
        let ev = parse_line(r#"{"event":"step","step":"install-hermes","progress":42,"msg":"cloning repo"}"#).unwrap();
        assert_eq!(ev, HelperEvent::Step { step: Step::InstallHermes, progress: 42, msg: "cloning repo".into() });
    }

    #[test]
    fn parses_detect_event() {
        let line = r#"{"event":"detect","internet":true,"python3":true,"wslview":false,"cmd_exe":true,"hermes_installed":false,"codex_installed":true,"codex_authed":false}"#;
        let ev = parse_line(line).unwrap();
        assert!(matches!(ev, HelperEvent::Detect { internet: true, cmd_exe: true, codex_installed: true, .. }));
    }

    #[test]
    fn parses_codex_variants() {
        assert_eq!(parse_line(r#"{"event":"codex_authed","email":"u@example.com"}"#).unwrap(),
                   HelperEvent::CodexAuthed { email: Some("u@example.com".into()) });
        assert_eq!(parse_line(r#"{"event":"codex_authed","email":null}"#).unwrap(),
                   HelperEvent::CodexAuthed { email: None });
        assert_eq!(parse_line(r#"{"event":"codex_aborted"}"#).unwrap(), HelperEvent::CodexAborted);
        assert_eq!(parse_line(r#"{"event":"codex_timeout"}"#).unwrap(), HelperEvent::CodexTimeout);
        assert_eq!(parse_line(r#"{"event":"codex_error","detail":"no subscription"}"#).unwrap(),
                   HelperEvent::CodexError { detail: "no subscription".into() });
    }

    #[test]
    fn parses_done_and_error() {
        assert_eq!(parse_line(r#"{"event":"done","step":"verify","ok":true}"#).unwrap(),
                   HelperEvent::Done { step: Step::Verify, ok: true });
        assert_eq!(parse_line(r#"{"event":"error","step":"install-hermes","level":"fatal","detail":"boom"}"#).unwrap(),
                   HelperEvent::Error { step: Step::InstallHermes, level: Level::Fatal, detail: "boom".into() });
    }

    #[test]
    fn round_trips_to_same_json() {
        let line = r#"{"event":"slack_verified","workspace":"Acme","bot":"hermes"}"#;
        let ev = parse_line(line).unwrap();
        assert_eq!(serde_json::to_string(&ev).unwrap(), line);
    }

    #[test]
    fn rejects_unknown_event() {
        assert!(parse_line(r#"{"event":"explode"}"#).is_err());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src-tauri && cargo test --lib events`
Expected: FAIL — `HelperEvent`/`Step`/`Level`/`parse_line` 미정의(컴파일 에러).

- [ ] **Step 3: Write minimal implementation**

Prepend to `src-tauri/src/events.rs`:

```rust
//! Rust side of the JSONL event contract (helper/events.schema.json).
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum Step {
    Detect,
    InstallHermes,
    CodexLogin,
    SlackManifest,
    SlackVerify,
    WriteConfig,
    Verify,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Level {
    Recoverable,
    Environment,
    Fatal,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum HelperEvent {
    Step { step: Step, progress: u8, msg: String },
    Detect {
        internet: bool,
        python3: bool,
        wslview: bool,
        cmd_exe: bool,
        hermes_installed: bool,
        codex_installed: bool,
        codex_authed: bool,
    },
    CodexAuthed {
        #[serde(default)]
        email: Option<String>,
    },
    CodexError { detail: String },
    CodexAborted,
    CodexTimeout,
    SlackManifest { json: String },
    SlackVerified { workspace: String, bot: String },
    SlackError { detail: String },
    Done { step: Step, ok: bool },
    Error { step: Step, level: Level, detail: String },
}

/// Parse one JSONL line into a `HelperEvent`.
pub fn parse_line(line: &str) -> Result<HelperEvent, serde_json::Error> {
    serde_json::from_str(line)
}
```

Add to `src-tauri/src/lib.rs` (top, before `run`):

```rust
pub mod events;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src-tauri && cargo test --lib events`
Expected: PASS (6 tests).

> 주의: `CodexAuthed`의 `email`이 `None`일 때 직렬화는 `{"event":"codex_authed","email":null}`이 된다(스키마가 허용). `round_trips_to_same_json`은 `slack_verified`로 검증해 이 차이를 피한다.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/events.rs src-tauri/src/lib.rs
git commit -m "feat(events): HelperEvent serde types + parse_line

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: 계약 적합성 통합 테스트 (Rust ↔ Plan 1 검증기)

Rust가 직렬화한 이벤트가 Plan 1의 `events.schema.json`을 만족함을, **Plan 1의 python 검증기를 그대로 호출**해 강제한다.

**Files:**
- Create: `src-tauri/tests/contract.rs`

- [ ] **Step 1: Write the failing test**

Create `src-tauri/tests/contract.rs`:

```rust
//! Integration contract test: every HelperEvent variant Rust serializes must
//! validate against helper/events.schema.json, using Plan 1's python validator
//! (the single source of truth shared by bats and Rust).
use hermes_launcher_lib::events::{HelperEvent, Level, Step};
use std::io::Write;
use std::process::{Command, Stdio};

fn schema_path() -> String {
    format!("{}/../helper/events.schema.json", env!("CARGO_MANIFEST_DIR"))
}
fn validator_path() -> String {
    format!("{}/../helper/tests/lib/validate_events.py", env!("CARGO_MANIFEST_DIR"))
}

fn validate(lines: &str) -> bool {
    let mut child = Command::new("python3")
        .arg(validator_path())
        .arg(schema_path())
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn python3 validator");
    child.stdin.as_mut().unwrap().write_all(lines.as_bytes()).unwrap();
    child.wait().expect("wait validator").success()
}

#[test]
fn all_variants_serialize_to_schema_valid_json() {
    let events = vec![
        HelperEvent::Step { step: Step::Detect, progress: 0, msg: "x".into() },
        HelperEvent::Detect { internet: true, python3: true, wslview: false, cmd_exe: true, hermes_installed: false, codex_installed: true, codex_authed: false },
        HelperEvent::CodexAuthed { email: Some("u@example.com".into()) },
        HelperEvent::CodexAuthed { email: None },
        HelperEvent::CodexError { detail: "no subscription".into() },
        HelperEvent::CodexAborted,
        HelperEvent::CodexTimeout,
        HelperEvent::SlackManifest { json: "{}".into() },
        HelperEvent::SlackVerified { workspace: "Acme".into(), bot: "hermes".into() },
        HelperEvent::SlackError { detail: "invalid_auth".into() },
        HelperEvent::Done { step: Step::WriteConfig, ok: true },
        HelperEvent::Error { step: Step::InstallHermes, level: Level::Fatal, detail: "boom".into() },
    ];
    let mut jsonl = String::new();
    for ev in &events {
        jsonl.push_str(&serde_json::to_string(ev).unwrap());
        jsonl.push('\n');
    }
    assert!(validate(&jsonl), "serialized events failed schema validation:\n{jsonl}");
}

#[test]
fn validator_rejects_bad_event() {
    assert!(!validate("{\"event\":\"explode\"}\n"));
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src-tauri && cargo test --test contract`
Expected: FAIL — `events` 모듈이 `pub`이 아니거나(이미 `pub mod events;`라 OK) 직렬화/스키마 불일치가 있으면 실패. 처음엔 통합 테스트 자체가 새로 추가되어 컴파일/실행되며, Task 2 타입이 스키마와 정확히 맞으면 통과한다. 불일치(예: 필드명/enum 값)가 있으면 여기서 빨강.

- [ ] **Step 3: Fix any mismatch**

`validate`가 실패하면 stderr를 보고(`Stdio::null()`을 잠시 `inherit`로) `events.rs`의 필드명/enum rename을 스키마에 맞춘다. 흔한 원인: `Step` 값 kebab-case 누락, `level` 값 snake_case 누락.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src-tauri && cargo test --test contract`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src-tauri/tests/contract.rs
git commit -m "test(events): contract test reusing Plan 1 python validator

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `state.rs` — 위저드 상태머신 + 영속화

설계 문서 153~158줄의 `state.json`(schema:1, wsl_distro, steps)을 구현한다. 멱등 머지·재개를 테스트.

**Files:**
- Create: `src-tauri/src/state.rs`
- Modify: `src-tauri/src/lib.rs` (`pub mod state;`)

- [ ] **Step 1: Write the failing test**

Create `src-tauri/src/state.rs` (test module first):

```rust
// (types added in Step 3)

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_to_schema_1_empty() {
        let s = WizardState::default();
        assert_eq!(s.schema, 1);
        assert!(s.steps.is_empty());
        assert!(s.wsl_distro.is_none());
    }

    #[test]
    fn save_then_load_round_trips() {
        let dir = std::env::temp_dir().join(format!("hl-state-{}", std::process::id()));
        let path = dir.join("state.json");
        let mut s = WizardState::default();
        s.wsl_distro = Some("Ubuntu-24.04".into());
        s.set_step("env", StepStatus::Ok);
        s.set_step("install", StepStatus::Ok);
        s.set_step("codex", StepStatus::Pending);
        s.save(&path).unwrap();

        let loaded = WizardState::load(&path);
        assert_eq!(loaded, s);
        assert!(loaded.is_complete("env"));
        assert!(!loaded.is_complete("codex"));
        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn load_missing_file_returns_default() {
        let s = WizardState::load(std::path::Path::new("/nonexistent/hl/state.json"));
        assert_eq!(s, WizardState::default());
    }

    #[test]
    fn skipped_counts_as_complete() {
        let mut s = WizardState::default();
        s.set_step("slack", StepStatus::Skipped);
        assert!(s.is_complete("slack"));
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src-tauri && cargo test --lib state`
Expected: FAIL — 타입 미정의.

- [ ] **Step 3: Write minimal implementation**

Prepend to `src-tauri/src/state.rs`:

```rust
//! Wizard state persisted to <localdata>/hermes-launcher/state.json.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StepStatus {
    Pending,
    Ok,
    Skipped,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WizardState {
    pub schema: u32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub wsl_distro: Option<String>,
    pub steps: BTreeMap<String, StepStatus>,
}

impl Default for WizardState {
    fn default() -> Self {
        WizardState { schema: 1, wsl_distro: None, steps: BTreeMap::new() }
    }
}

impl WizardState {
    pub fn load(path: &Path) -> Self {
        std::fs::read_to_string(path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let json = serde_json::to_string_pretty(self).expect("serialize WizardState");
        std::fs::write(path, json)
    }

    pub fn set_step(&mut self, step: &str, status: StepStatus) {
        self.steps.insert(step.to_string(), status);
    }

    pub fn is_complete(&self, step: &str) -> bool {
        matches!(self.steps.get(step), Some(StepStatus::Ok) | Some(StepStatus::Skipped))
    }
}

/// `<localdata>/hermes-launcher/state.json` — `%LOCALAPPDATA%` on Windows.
pub fn default_state_path() -> PathBuf {
    let base = dirs::data_local_dir().unwrap_or_else(|| PathBuf::from("."));
    base.join("hermes-launcher").join("state.json")
}
```

Add to `src-tauri/src/lib.rs`:

```rust
pub mod state;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src-tauri && cargo test --lib state`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/state.rs src-tauri/src/lib.rs
git commit -m "feat(state): WizardState persistence + step status

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `wsl.rs` — distro 파싱 + UTF-16LE 디코드

`wsl -l -v` 출력 파싱과 UTF-16LE 디코드를 크로스플랫폼으로 구현·테스트하고, 실제 `wsl.exe` 호출은 `#[cfg(windows)]`로 둔다.

**Files:**
- Create: `src-tauri/src/wsl.rs`
- Modify: `src-tauri/src/lib.rs` (`pub mod wsl;`)

- [ ] **Step 1: Write the failing test**

Create `src-tauri/src/wsl.rs` (test module first):

```rust
// (impl added in Step 3)

#[cfg(test)]
mod tests {
    use super::*;

    // `wsl -l -v` decoded text (header + two distros, default marked '*').
    const SAMPLE: &str = "  NAME            STATE           VERSION\n\
                          * Ubuntu-24.04    Running         2\n\
                            Debian          Stopped         2\n";

    #[test]
    fn parses_distros_with_default_flag() {
        let d = parse_list_verbose(SAMPLE);
        assert_eq!(d.len(), 2);
        assert_eq!(d[0].name, "Ubuntu-24.04");
        assert_eq!(d[0].state, "Running");
        assert_eq!(d[0].version, 2);
        assert!(d[0].default);
        assert_eq!(d[1].name, "Debian");
        assert!(!d[1].default);
    }

    #[test]
    fn skips_blank_and_short_lines() {
        let d = parse_list_verbose("NAME STATE VERSION\n\n  *  \n");
        assert!(d.is_empty());
    }

    #[test]
    fn decodes_utf16le_management_output() {
        // "Ab" in UTF-16LE = 0x41 0x00 0x62 0x00
        let bytes = [0x41u8, 0x00, 0x62, 0x00];
        assert_eq!(decode_wsl_output(&bytes), "Ab");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src-tauri && cargo test --lib wsl`
Expected: FAIL — 함수 미정의.

- [ ] **Step 3: Write minimal implementation**

Prepend to `src-tauri/src/wsl.rs`:

```rust
//! WSL distro discovery. Parsing/decoding are cross-platform & tested;
//! the actual `wsl.exe` call is Windows-only.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Distro {
    pub name: String,
    pub state: String,
    pub version: u8,
    pub default: bool,
}

/// Parse the UTF-8-decoded text of `wsl -l -v`.
pub fn parse_list_verbose(text: &str) -> Vec<Distro> {
    let mut out = Vec::new();
    for line in text.lines().skip(1) {
        let trimmed = line.trim_start();
        if trimmed.trim().is_empty() {
            continue;
        }
        let default = trimmed.starts_with('*');
        let cleaned = trimmed.trim_start_matches('*').trim();
        let cols: Vec<&str> = cleaned.split_whitespace().collect();
        if cols.len() < 3 {
            continue;
        }
        out.push(Distro {
            name: cols[0].to_string(),
            state: cols[1].to_string(),
            version: cols[2].parse::<u8>().unwrap_or(0),
            default,
        });
    }
    out
}

/// Decode `wsl.exe`'s UTF-16LE management output (`-l -v`, `--status`).
pub fn decode_wsl_output(bytes: &[u8]) -> String {
    let (text, _, _) = encoding_rs::UTF_16LE.decode(bytes);
    text.into_owned()
}

/// List installed distros by invoking `wsl.exe -l -v` (Windows only).
#[cfg(windows)]
pub fn list_distros() -> std::io::Result<Vec<Distro>> {
    let out = std::process::Command::new("wsl.exe")
        .args(["-l", "-v"])
        .output()?;
    Ok(parse_list_verbose(&decode_wsl_output(&out.stdout)))
}
```

Add to `src-tauri/src/lib.rs`:

```rust
pub mod wsl;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src-tauri && cargo test --lib wsl`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/wsl.rs src-tauri/src/lib.rs
git commit -m "feat(wsl): parse wsl -l -v + UTF-16LE decode (+ cfg(windows) list)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: `secrets.rs` — keyring 토큰 저장소

Slack 토큰을 OS 보안 저장소(Windows Credential Manager / macOS Keychain)에 보관한다. 테스트는 keyring mock builder로 인메모리.

**Files:**
- Create: `src-tauri/src/secrets.rs`
- Modify: `src-tauri/src/lib.rs` (`pub mod secrets;`)

- [ ] **Step 1: Write the failing test**

Create `src-tauri/src/secrets.rs` (test module first):

```rust
// (impl added in Step 3)

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Once;

    static INIT: Once = Once::new();
    fn use_mock() {
        // In-memory store: never touches the real Keychain (no prompts).
        INIT.call_once(|| {
            keyring::set_default_credential_builder(keyring::mock::default_credential_builder());
        });
    }

    #[test]
    fn store_retrieve_delete_round_trip() {
        use_mock();
        let key = "slack_bot_token_test_rt";
        assert_eq!(retrieve(key).unwrap(), None);
        store(key, "xoxb-secret").unwrap();
        assert_eq!(retrieve(key).unwrap(), Some("xoxb-secret".to_string()));
        delete(key).unwrap();
        assert_eq!(retrieve(key).unwrap(), None);
    }

    #[test]
    fn delete_missing_is_ok() {
        use_mock();
        assert!(delete("never_existed_key").is_ok());
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src-tauri && cargo test --lib secrets`
Expected: FAIL — 함수 미정의.

- [ ] **Step 3: Write minimal implementation**

Prepend to `src-tauri/src/secrets.rs`:

```rust
//! OS-native secret storage (Windows Credential Manager / macOS Keychain)
//! via the `keyring` crate. Tests use keyring's in-memory mock store.
use keyring::Entry;

const SERVICE: &str = "hermes-launcher";

pub fn store(key: &str, value: &str) -> keyring::Result<()> {
    Entry::new(SERVICE, key)?.set_password(value)
}

pub fn retrieve(key: &str) -> keyring::Result<Option<String>> {
    match Entry::new(SERVICE, key)?.get_password() {
        Ok(v) => Ok(Some(v)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(e) => Err(e),
    }
}

pub fn delete(key: &str) -> keyring::Result<()> {
    match Entry::new(SERVICE, key)?.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(e) => Err(e),
    }
}
```

Add to `src-tauri/src/lib.rs`:

```rust
pub mod secrets;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src-tauri && cargo test --lib secrets`
Expected: PASS (2 tests).

> 주의: keyring mock 저장소는 전역 인메모리다. 테스트 간 충돌을 피하려고 각 테스트는 고유 키를 쓴다. `set_default_credential_builder`는 `Once`로 1회만 호출.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/secrets.rs src-tauri/src/lib.rs
git commit -m "feat(secrets): keyring-backed token store (mock in tests)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: `runner.rs` — JSONL 스트림 파싱 + WSL 명령 조립

자식 프로세스의 stdout을 라인 단위로 읽어 `HelperEvent`로 파싱해 sink로 흘려보낸다. 비-이벤트 라인은 무시. WSL 명령 조립 인자는 크로스플랫폼으로 테스트.

**Files:**
- Create: `src-tauri/src/runner.rs`
- Modify: `src-tauri/src/lib.rs` (`pub mod runner;`)

- [ ] **Step 1: Write the failing test**

Create `src-tauri/src/runner.rs` (test module first):

```rust
// (impl added in Step 3)

#[cfg(test)]
mod tests {
    use super::*;
    use crate::events::{HelperEvent, Step};
    use std::io::Cursor;

    #[test]
    fn streams_and_parses_events_ignoring_noise() {
        let input = concat!(
            "{\"event\":\"step\",\"step\":\"detect\",\"progress\":0,\"msg\":\"x\"}\n",
            "some non-json log line\n",
            "\n",
            "{\"event\":\"done\",\"step\":\"detect\",\"ok\":true}\n",
        );
        let mut got = Vec::new();
        let n = stream_events(Cursor::new(input), |ev| got.push(ev)).unwrap();
        assert_eq!(n, 2);
        assert_eq!(got[0], HelperEvent::Step { step: Step::Detect, progress: 0, msg: "x".into() });
        assert_eq!(got[1], HelperEvent::Done { step: Step::Detect, ok: true });
    }

    #[test]
    fn builds_wsl_inner_command_string() {
        let cmd = wsl_inner_command("/home/u/launcher-helper.sh", "detect");
        assert_eq!(cmd, "/home/u/launcher-helper.sh detect");
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd src-tauri && cargo test --lib runner`
Expected: FAIL — 함수 미정의.

- [ ] **Step 3: Write minimal implementation**

Prepend to `src-tauri/src/runner.rs`:

```rust
//! Run the WSL helper and stream its JSONL events.
use crate::events::{parse_line, HelperEvent};
use std::io::{BufRead, BufReader, Read};

/// Read JSONL from `reader`, parse each non-empty line, and call `sink` for
/// every valid `HelperEvent`. Non-event lines are ignored. Returns parsed count.
pub fn stream_events<R: Read>(
    reader: R,
    mut sink: impl FnMut(HelperEvent),
) -> std::io::Result<usize> {
    let buf = BufReader::new(reader);
    let mut n = 0;
    for line in buf.lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }
        if let Ok(ev) = parse_line(&line) {
            sink(ev);
            n += 1;
        }
    }
    Ok(n)
}

/// The inner command string passed to `bash -lc` inside the distro.
pub fn wsl_inner_command(helper_path: &str, subcommand: &str) -> String {
    format!("{helper_path} {subcommand}")
}

/// Build the `wsl.exe -d <distro> bash -lc '<helper> <sub>'` command (Windows).
#[cfg(windows)]
pub fn wsl_helper_command(
    distro: &str,
    helper_path: &str,
    subcommand: &str,
) -> std::process::Command {
    let mut c = std::process::Command::new("wsl.exe");
    c.args(["-d", distro, "bash", "-lc", &wsl_inner_command(helper_path, subcommand)]);
    c.stdout(std::process::Stdio::piped());
    c
}
```

Add to `src-tauri/src/lib.rs`:

```rust
pub mod runner;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd src-tauri && cargo test --lib runner`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/runner.rs src-tauri/src/lib.rs
git commit -m "feat(runner): JSONL stream parsing + WSL command builder

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Tauri command 래퍼 + Rust CI

로직 모듈을 `#[tauri::command]` 얇은 래퍼로 노출하고, fmt/clippy/test CI를 추가한다.

**Files:**
- Modify: `src-tauri/src/lib.rs` (commands + invoke_handler)
- Create: `.github/workflows/rust.yml`

- [ ] **Step 1: Write the failing test**

Append to `src-tauri/src/lib.rs` test 영역:

```rust
#[cfg(test)]
mod command_tests {
    use crate::state::{StepStatus, WizardState};

    // The command wrappers are thin; we test the logic they delegate to.
    #[test]
    fn save_secret_then_state_resume_logic() {
        let mut s = WizardState::default();
        s.set_step("env", StepStatus::Ok);
        // resume target = first step not complete
        let order = ["env", "install", "codex", "slack", "done"];
        let next = order.iter().find(|st| !s.is_complete(st)).copied();
        assert_eq!(next, Some("install"));
    }
}
```

- [ ] **Step 2: Run test to verify it fails or passes**

Run: `cd src-tauri && cargo test --lib command_tests`
Expected: 로직 테스트는 통과할 것(상태 API는 Task 4에서 구현됨). 이 Task의 빨강 기준은 **clippy 경고**와 **command 래퍼 미배선**이다. Step 3에서 래퍼·핸들러를 추가하고 clippy를 통과시킨다.

- [ ] **Step 3: Write minimal implementation**

Replace the `run()` function in `src-tauri/src/lib.rs` and add command wrappers:

```rust
use crate::state::{StepStatus, WizardState};

/// Persist a wizard step status to the default state file.
#[tauri::command]
fn set_step(step: String, status: String) -> Result<(), String> {
    let parsed = match status.as_str() {
        "pending" => StepStatus::Pending,
        "ok" => StepStatus::Ok,
        "skipped" => StepStatus::Skipped,
        "failed" => StepStatus::Failed,
        other => return Err(format!("unknown status: {other}")),
    };
    let path = crate::state::default_state_path();
    let mut s = WizardState::load(&path);
    s.set_step(&step, parsed);
    s.save(&path).map_err(|e| e.to_string())
}

/// Store/clear a Slack token in the OS keychain.
#[tauri::command]
fn save_secret(key: String, value: Option<String>) -> Result<(), String> {
    match value {
        Some(v) => crate::secrets::store(&key, &v).map_err(|e| e.to_string()),
        None => crate::secrets::delete(&key).map_err(|e| e.to_string()),
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![set_step, save_secret])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

Create `.github/workflows/rust.yml`:

```yaml
name: rust

on:
  push:
    paths:
      - "src-tauri/**"
      - "helper/events.schema.json"
      - "helper/tests/lib/validate_events.py"
      - ".github/workflows/rust.yml"
  pull_request:
    paths:
      - "src-tauri/**"
      - ".github/workflows/rust.yml"

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest]
      fail-fast: false
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          components: clippy, rustfmt
      - name: Linux Tauri/keyring deps
        if: runner.os == 'Linux'
        run: |
          sudo apt-get update
          sudo apt-get install -y libglib2.0-dev pkg-config
      - name: fmt
        run: cargo fmt --manifest-path src-tauri/Cargo.toml -- --check
      - name: clippy
        run: cargo clippy --manifest-path src-tauri/Cargo.toml --lib --all-targets -- -D warnings
      - name: test
        run: cargo test --manifest-path src-tauri/Cargo.toml --lib --tests
```

> CI 매트릭스에 windows-latest를 넣어 `#[cfg(windows)]` 코드도 컴파일·테스트된다(개발 머신 macOS의 사각지대 보완). Linux/keyring은 secret-service 헤더가 필요할 수 있으니, secrets 테스트가 Linux에서 mock만 쓰도록 보장(이미 mock builder 사용).

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd src-tauri
cargo fmt -- --check
cargo clippy --lib --all-targets -- -D warnings
cargo test --lib --tests
```
Expected: fmt clean, clippy 무경고, 모든 테스트 PASS.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/lib.rs .github/workflows/rust.yml
git commit -m "feat: tauri command wrappers + rust CI (ubuntu+windows)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:**
- `wsl.rs` WSL 감지·distro 선택(설계 73줄, 103~106줄) → Task 5(파싱 + cfg(windows) 호출). ✅
- `events.rs` JSONL 파서, 스키마 공유(74줄, 67줄) → Task 2 + Task 3(검증기 재사용). ✅
- `state.rs` 상태머신 + state.json 영속화(75줄, 153~158줄) → Task 4. ✅
- `secrets.rs` Windows Credential Manager 연동(76줄, 141줄) → Task 6(keyring, Windows+macOS). ✅
- helper 구동·JSONL 파싱(48~54줄), 라이브 진행률 스트리밍 → Task 7(`stream_events`) + Task 8(Channel은 Plan 3 배선 시 실제 윈도우로). 스트리밍 sink는 테스트 가능 형태로 분리. ✅
- config 머지(195줄 cargo test 대상 "config 머지")는 Plan 1의 `write-config`(헬퍼)가 담당하므로 Rust 측은 호출만(Task 7/8 명령). 설계의 "config 머지" cargo test 항목은 헬퍼로 이동됨을 명시. ✅
- **범위 밖**: 5단계 UI(Plan 3), 번들/서명(Plan 4), 실제 `cargo tauri dev` 풀 빌드(dist/아이콘 생기는 Plan 3/4).

**2. Placeholder scan:** 모든 코드 스텝에 실제 Rust 코드 포함. Task 1의 `generate_context!` 빌드 한계는 명시하고 `cargo test --lib`를 합격선으로 고정(플레이스홀더 아님, 의도된 단계 경계). Task 3/8은 "이미 통과할 수 있음 + clippy/계약이 빨강 기준"임을 명시.

**3. Type/이름 일관성:**
- `Step` kebab-case 값 ↔ Plan 1 스키마 `$defs/step` enum(detect/install-hermes/codex-login/slack-manifest/slack-verify/write-config/verify) 동일. ✅
- `Level` snake_case(recoverable/environment/fatal) ↔ 스키마 `level` enum 동일. ✅
- `HelperEvent` 변형·필드명 ↔ 스키마 oneOf 브랜치 동일(detect의 `cmd_exe`/`python3` 포함). Task 3 계약 테스트가 이를 기계적으로 강제. ✅
- `parse_line`/`stream_events`/`WizardState`/`store`/`retrieve`/`delete` 시그니처가 Task 간 일관. ✅
- crate lib 이름 `hermes_launcher_lib` ↔ main.rs/contract.rs 참조 동일. ✅

---

## 실행 옵션

**Plan 2 (Tauri/Rust 백엔드) 작성 완료. 저장 위치: `docs/superpowers/plans/2026-05-20-hermes-launcher-rust-backend.md`.**

macOS에서 `cargo test`로 events/state/wsl/secrets/runner 전부 검증되고, `#[cfg(windows)]` 코드(`list_distros`, `wsl_helper_command` spawn)는 Windows(Parallels) 또는 CI windows-latest 매트릭스에서 검증된다.

실행 방식: **Subagent-Driven(추천)** 또는 **Inline**.
