# Hermes Launcher — 설계 문서

- **작성일**: 2026-05-20
- **상태**: 설계 합의 완료 (구현 계획 대기)
- **한 줄 요약**: Windows + WSL2 환경에서 hermes-agent 설치 → Codex OAuth → Slack 연결을 가이드된 5단계 위저드로 처리하는 일회용 Tauri 데스크톱 앱.

---

## 1. 목표와 범위

### 목표
Windows 네이티브 + WSL2가 이미 깔린 사용자가, hermes-agent를 **최소 클릭으로** 설치하고 Codex(OpenAI Codex CLI)와 Slack에 연결하도록 돕는 오픈소스 데스크톱 런처.

### 합의된 결정 사항
| 항목 | 결정 |
|---|---|
| 타깃 사용자 | 공개 오픈소스 배포 (GitHub Releases) |
| 자동화 수준 | 가이드된 5단계 위저드 (완전 자동화 불가능한 OAuth/Slack 단계는 안내 + 최대 자동화) |
| hermes 설치 전략 | WSL 안에서 upstream `install.sh` 래핑 (hermes 코드 수정 0) |
| Slack 연결 모델 | 사용자가 자신의 Slack 앱 생성 (manifest paste 방식), Socket Mode |
| 앱 수명 | 설치 전용 원타임 위저드 (설치 후 상주 안 함) |
| v1 범위 | Codex + Slack만 (다른 모델 공급자·메신저는 v2) |
| 아키텍처 | 하이브리드 — Rust 오케스트레이션 + WSL 안 helper 스크립트 (JSONL 이벤트) |

### 비목표 (v1 제외)
- 다른 모델 공급자(OpenRouter, Nous Portal 등) 설정 — 고급 설정에서 config 직접 편집 안내만
- 다른 메신저(Telegram, Discord 등)
- 자동 업데이트 (원타임 위저드라 불필요)
- 코드 서명 (v2 과제, v1은 SmartScreen 경고 안내)
- 상주 컨트롤 패널 / 채팅 UI
- macOS/Linux 런처 포팅 (helper.sh는 재사용 가능하도록 설계)
- Slack device-code flow, Codex `--no-browser` fallback (v2)

---

## 2. 시스템 아키텍처

### 레이어 구성
```
┌─────────────────────────────────────────────────────────┐
│ 상위: Tauri 앱 (Windows 네이티브, ~5MB MSI)               │
│  - Frontend (React/TS): 위저드 상태머신, 5단계 UI,        │
│    진행률·에러 표시, Slack manifest preview/copy          │
│  - Backend (Rust): WSL 감지·distro 선택, wsl.exe 호출,    │
│    helper.sh 구동, JSONL 이벤트 파싱, 토큰 보관           │
│    (Windows Credential Manager)                           │
└───────────────────────────┬─────────────────────────────┘
                            │ wsl.exe -d <distro> bash …
┌───────────────────────────▼─────────────────────────────┐
│ 중간: launcher-helper.sh (~200줄, WSL ext4에 설치)        │
│  서브커맨드: detect / install-hermes / codex-login /      │
│             slack-manifest / write-config / verify        │
│  출력: 한 줄 = 1 JSON 이벤트 (stdout)                     │
└───────────────────────────┬─────────────────────────────┘
                            │ 호출 (수정 없음)
┌───────────────────────────▼─────────────────────────────┐
│ 하위: 원본 도구들                                          │
│  - install.sh (upstream hermes)                           │
│  - codex CLI (codex login → ~/.codex/auth.json)           │
│  - hermes slack manifest (manifest JSON 생성기)           │
│  - hermes config writer (~/.hermes/config.yaml)           │
└─────────────────────────────────────────────────────────┘
```

### 핵심 원칙
- **hermes 코드 수정 0.** 우리는 그 위에 얇은 가이드 레이어만 얹는다.
- helper.sh ↔ Rust 사이의 **JSONL 이벤트 스키마를 단일 파일(`helper/events.schema.json`)로 고정**해 계약으로 삼는다.

### 저장소 구조
```
hermes-launcher/
├── src-tauri/              Rust 백엔드 + tauri.conf.json
│   ├── src/
│   │   ├── wsl.rs          WSL 감지·distro 선택·invocation
│   │   ├── events.rs       JSONL 이벤트 파서 (스키마 공유)
│   │   ├── state.rs        위저드 상태머신 + state.json 영속화
│   │   └── secrets.rs      Windows Credential Manager 연동
│   └── tauri.conf.json
├── src/                    React 프론트엔드 (5단계 위저드)
├── helper/
│   ├── launcher-helper.sh  서브커맨드 디스패처
│   ├── events.schema.json  JSONL 이벤트 계약
│   └── tests/              bats 테스트
└── docs/                   튜토리얼 마크다운 (한국어 우선, 영어 병기)
```

---

## 3. 위저드 5단계 흐름

| Step | 화면 | 핵심 동작 | 자동/수동 |
|---|---|---|---|
| 1 | 환경 점검 | Windows·WSL·distro·인터넷 검사 | 전자동 (실패 시 안내) |
| 2 | Hermes 설치 | install.sh 실행 + 라이브 로그·진행률 | 전자동 (5~10분) |
| 3 | Codex 로그인 | `codex login` 브라우저 열고 auth.json 폴링 | 사용자: ChatGPT 로그인만 |
| 4 | Slack 연결 | manifest 복사 → 사용자가 Slack 앱 생성 → 토큰 붙여넣기 | 반자동 (Slack 정책상 필연), **Skip 가능** |
| 5 | 완료 | hermes 실행 버튼·튜토리얼·다음 단계 카드 | 종료 화면 |

- **되돌아가기/재시도**: 각 단계는 멱등. 1단계로 돌아가 재실행해도 안전.
- **예상 소요**: 첫 설치 8~12분 (대부분 install.sh), 재실행 1~2분.

### Step 1 — 환경 점검
- 검사 항목: Windows 빌드, WSL2 설치 여부, 기본 distro, 인터넷 연결.
- 실패 처리: distro 없으면 "Ubuntu 설치" 버튼(`wsl --install -d Ubuntu`), WSL 미설치면 MS Store 링크.
- distro가 여럿이면 사용자가 선택 (`wsl -l -v` 파싱).

### Step 2 — Hermes 설치
- Rust → helper `install-hermes`. helper가 `curl -fsSL …/install.sh | bash` 실행.
- helper가 진행 단계를 JSONL로 emit → UI에 라이브 로그 + 진행률 바.
- install.sh가 기존 설치를 감지하면 스킵 (멱등).

### Step 3 — Codex OAuth 브릿지
1. Rust가 WSL 안에서 `codex login` 백그라운드 spawn.
2. codex가 로컬 callback 서버(예: `127.0.0.1:1455`)를 띄우고 Windows 기본 브라우저 오픈 (WSL `wslview` → `cmd.exe /c start`; backup으로 Rust `shell::open`).
3. 사용자가 ChatGPT 로그인 완료 → codex가 `~/.codex/auth.json` 저장 후 종료.
4. helper가 auth.json mtime을 1초 간격 폴링 (최대 300초) → 감지 시 `{"event":"codex_authed"}` emit.
5. localhost callback은 WSL2 localhostForwarding 덕분에 Windows 브라우저 ↔ WSL codex 사이 자동 도달.
6. 검증: `codex --version && codex models` 성공 확인.
7. hermes config에는 토큰 안 씀 — `codex app-server`가 auth.json 직접 읽음. config엔 `openai_runtime: codex_app_server` 한 줄만 추가.

**실패 처리**
| 상황 | 처리 |
|---|---|
| 5분 내 미완료 | "다시 시도" — codex 프로세스 kill 후 재spawn |
| 사용자가 브라우저 닫음 | codex 종료 감지 → `codex_aborted` → "다시 시도" |
| Codex 구독 없음 | codex 에러 종료 → `codex_error(no subscription)` → "구독 페이지 열기" 버튼 |
| 토큰 저장됐으나 검증 실패 | 단계 보류, 재시도 |

### Step 4 — Slack 연결
- 4-A: helper `slack-manifest` → WSL 안 `hermes slack manifest` 실행 → JSON 회신 → UI에 syntax-highlight + 복사 버튼.
- 4-B (사용자 액션, Slack 정책상 필연):
  - "Slack 열기" → `api.slack.com/apps/new`.
  - "From an app manifest" → 워크스페이스 선택 → manifest 붙여넣기 → Create.
  - Socket Mode 켜기 → App-Level Token(`xapp-…`, scope `connections:write`) 생성 → Install → Bot Token(`xoxb-…`) 복사.
  - 위저드에 접이식 체크리스트로 인라인 안내.
- 4-C: 토큰 검증 & 주입:
  - 입력칸 2개. prefix 즉시 1차 검증.
  - helper가 `auth.test`로 xoxb 검증 → 워크스페이스·봇 이름 회신 → "✓ Acme Workspace 연결됨".
  - xapp는 형식·세그먼트 검증 (호출 검증 제한적).
  - hermes config의 `platforms.slack.{bot_token, app_token}`에 주입.
  - 토큰은 기본 config 기입, "보안 저장" 토글 시 Windows Credential Manager 사용.
- **Slack은 선택 단계.** Skip 시 hermes는 터미널 TUI로 완전 동작. config엔 placeholder 주석만.

### Step 5 — 완료 & 다음 단계
- 설치 요약 (hermes 버전, Codex 인증, Slack 연결 상태).
- 다음 단계 카드 3개: ① `hermes` 터미널 실행, ② Slack `/btw`, ③ `hermes model`.
- 튜토리얼·문제 해결·GitHub 링크.

---

## 4. 에러 처리 & 상태 복구

### 상태 영속화
- `%LOCALAPPDATA%\hermes-launcher\state.json` 에 단계별 commit. 앱 재시작 시 마지막 완료 단계부터 재개.
```json
{ "schema": 1, "wsl_distro": "Ubuntu-24.04",
  "steps": { "env": "ok", "install": "ok", "codex": "pending", "slack": "skipped" } }
```

### 멱등성
모든 helper 서브커맨드는 재실행 안전: install.sh 기존 설치 스킵, codex auth.json 있으면 통과, config writer는 기존 키 보존 머지.

### 에러 등급
| 등급 | 예 | UI 처리 |
|---|---|---|
| 복구 가능 | OAuth 타임아웃, 토큰 오타, 네트워크 끊김 | 인라인 "다시 시도" + 원인 |
| 환경 문제 | WSL 미설치, distro 손상, 디스크 부족 | 해결 가이드 + 외부 링크 |
| 치명적 | install.sh 비정상 종료 | "로그 복사" + GitHub 이슈 템플릿 자동 채움 |

### 로그
helper의 전체 stdout/stderr를 `%LOCALAPPDATA%\hermes-launcher\logs\setup-<timestamp>.log` 에 항상 기록. UI "로그 보기"에서 열람·복사.

---

## 5. 배포 & 튜토리얼

### 배포
- GitHub Releases에 Tauri MSI/NSIS 인스톨러. CI: GitHub Actions `tauri-action`.
- 코드 서명: v1 미서명 → SmartScreen 경고. README에 "추가 정보 → 실행" 안내. (서명은 v2)
- 버전 표기: launcher 버전 ↔ 설치되는 hermes 버전 분리.
- 자동 업데이트 없음 (원타임). 새 버전은 재다운로드.

### 튜토리얼
- 위저드 각 단계에 인라인 도움말 (접이식 "왜 필요한가요?").
- 완료 화면에 다음 단계 카드 3개.
- `docs/`에 스크린샷 포함 마크다운 가이드. 한국어 우선, 영어 병기.

---

## 6. 테스트 전략

| 레이어 | 도구 | 대상 |
|---|---|---|
| helper.sh | bats | 서브커맨드 멱등성, JSONL 출력 스키마, 에러 종료 코드 |
| Rust 백엔드 | cargo test | 이벤트 파서, 상태머신 전이, config 머지 |
| 프론트엔드 | Vitest | 위저드 단계 전이, 토큰 형식 검증 |
| 통합(E2E) | 수동 체크리스트 + (선택) WSL CI | 깨끗한 Ubuntu에서 전체 흐름 1회 |

- JSONL 이벤트 스키마를 Rust·bats 양쪽이 공유하는 단일 파일(`helper/events.schema.json`)로 고정 → 계약 위반 시 테스트 실패.
- helper 서브커맨드와 Rust 파서는 TDD (test-driven-development 스킬 적용).

---

## 7. 핵심 인터페이스: JSONL 이벤트 계약

helper.sh가 stdout으로 emit하고 Rust가 파싱하는 이벤트의 공통 형태:
```json
{ "event": "step",        "step": "install-hermes", "progress": 42, "msg": "cloning repo" }
{ "event": "codex_authed", "email": "user@example.com" }
{ "event": "codex_error",  "detail": "no subscription" }
{ "event": "slack_manifest","json": "{...}" }
{ "event": "slack_verified","workspace": "Acme", "bot": "hermes" }
{ "event": "done",         "step": "verify", "ok": true }
{ "event": "error",        "step": "install-hermes", "level": "fatal", "detail": "..." }
```
정확한 필드·enum은 `helper/events.schema.json`에 JSON Schema로 고정하고, Rust serde 타입과 bats 검증이 이를 참조한다.

---

## 8. 미해결/구현 시 확정할 사항
- codex CLI의 callback 포트가 고정인지 동적인지 확인 (폴링 전략에 영향 없음 — auth.json만 보면 됨).
- `wslview` 부재 환경 빈도 — Ubuntu-24.04 기본은 포함. 미포함 distro 대비 `cmd.exe /c start` fallback 필수.
- Windows Credential Manager 연동 시 Tauri 플러그인 vs Rust `windows` crate 직접 사용 결정.
- install.sh의 진행 단계를 어떻게 JSONL로 변환할지 — install.sh 출력 파싱 vs helper가 단계별로 install.sh를 쪼개 호출.
