# Hermes Launcher

Windows + WSL2 환경에서 [hermes-agent](https://github.com/NousResearch/hermes-agent)를 **최소 클릭으로** 설치하고 Codex(OpenAI Codex CLI)와 Slack에 연결해 주는 가이드형 데스크톱 위저드.

> 상태: helper / Rust 백엔드 / React 프론트엔드 / 통합 구현 완료. 설계 문서 →
> [`docs/superpowers/specs/2026-05-20-hermes-launcher-design.md`](docs/superpowers/specs/2026-05-20-hermes-launcher-design.md) ·
> 구현 계획 → [`docs/superpowers/plans/`](docs/superpowers/plans/) · 튜토리얼 → [`docs/tutorial-ko.md`](docs/tutorial-ko.md)

## 무엇을 하나요

설치 전용 원타임 Tauri 앱이 5단계 위저드로 다음을 안내합니다.

1. **환경 점검** — Windows·WSL2·distro·인터넷 확인
2. **Hermes 설치** — WSL 안에서 공식 `install.sh`를 실행 (hermes 코드 수정 없음)
3. **Codex 로그인** — `codex login` 브라우저 OAuth 후 자동 감지
4. **Slack 연결** — `hermes slack manifest`로 manifest 생성 → 사용자가 자신의 Slack 앱 생성 → 토큰 주입 (Socket Mode, 선택 단계)
5. **완료** — hermes 실행·다음 단계 안내

## 아키텍처 (요약)

```
Tauri 앱 (Rust + React)
   │  wsl.exe -d <distro> bash …
launcher-helper.sh  (WSL 안, JSONL 이벤트 emit)
   │  호출 (수정 없음)
install.sh · codex CLI · hermes slack manifest · hermes config
```

핵심 원칙: **hermes 코드는 수정 0.** 그 위에 얇은 가이드 레이어만 얹습니다.

## v1 범위

- Codex + Slack만 (다른 모델 공급자·메신저는 v2)
- Windows 네이티브 + WSL2 (런처 자체는 Windows 전용, helper.sh는 재사용 가능하게 설계)

## 저장소 구성

| 경로 | 내용 | 테스트 |
|---|---|---|
| `helper/` | WSL 안 `launcher-helper.sh` + JSONL 이벤트 계약(`events.schema.json`) | bats |
| `src-tauri/` | Rust 백엔드(이벤트 파서·상태머신·WSL·keyring·러너) + Tauri 앱 | `cargo test` |
| `src/` | React 프론트엔드(5단계 위저드) | Vitest |
| `docs/` | 설계·구현 계획·튜토리얼·E2E 체크리스트 | — |

## 개발

```bash
# 프론트엔드
npm install
npm test            # vitest
npm run build       # tsc + vite build → dist/

# 백엔드
cd src-tauri
cargo test          # 로직 테스트(webview 불필요)

# 헬퍼
bats helper/tests/  # bats-core 필요

# 앱 실행 (Windows + WSL2 권장)
npm run build
cargo tauri dev --features app
```

> 백엔드는 `app` 피처로 실제 Tauri 컨텍스트를 켭니다. 피처 없이는 로직 라이브러리로 빌드·테스트됩니다.
> WSL 실제 구동(`run_step`)은 Windows 전용이며, 그 외 플랫폼에서는 환경 에러를 emit합니다.

## 빌드 & 릴리스

```bash
# 로컬 번들 (Windows)
npm ci && npm run build
cd src-tauri && cargo tauri build --features app   # MSI/NSIS

# 릴리스: 태그 푸시 → .github/workflows/release.yml (tauri-action, windows-latest)
git tag v0.1.0 && git push origin v0.1.0
```

> v1은 **미서명** → 실행 시 SmartScreen 경고가 뜹니다(`추가 정보` → `실행`). 코드 서명은 v2 과제입니다.

## CI

- `helper.yml` — bats + shellcheck + JSON Schema 검증
- `rust.yml` — cargo fmt/clippy/test (ubuntu + windows)
- `web.yml` — tsc + vitest + vite build
- `release.yml` — tauri-action MSI/NSIS (태그 트리거)

## 라이선스

MIT (예정)
