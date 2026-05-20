# E2E 수동 체크리스트

깨끗한 Windows 11 + WSL2(Ubuntu-24.04)에서 전체 흐름을 1회 검증합니다. 각 단계는 멱등이므로 재실행해도 안전합니다.

## 사전 조건
- [ ] Windows 11, WSL2 설치됨 (`wsl -l -v`로 distro 확인)
- [ ] 인터넷 연결
- [ ] 빌드한 인스톨러(`--features app`) 또는 `cargo tauri dev --features app`

## Step 1 — 환경 점검
- [ ] 앱 실행 시 자동으로 `detect` 이벤트 수신 → 체크리스트 표시
- [ ] 인터넷/python3/wslview·cmd.exe/codex 항목이 실제 환경과 일치
- [ ] distro 없음 시 "Ubuntu 설치하기" 노출 (있으면 `다음 →` 활성)

## Step 2 — Hermes 설치
- [ ] `install-hermes` 진행률 이벤트로 진행바가 0→100 증가
- [ ] 로그 박스에 단계 메시지(installing uv / cloning / venv / package / config) 표시
- [ ] `done(ok:true)` 후 `다음` 활성
- [ ] 재실행 시 install.sh가 기존 설치를 건너뜀

## Step 3 — Codex 로그인
- [ ] `브라우저 다시 열기` → Windows 기본 브라우저로 ChatGPT 로그인 페이지
- [ ] 로그인 완료 → `~/.codex/auth.json` 생성 → `codex_authed` 자동 수신 → 다음 단계
- [ ] 5분 초과 시 `codex_timeout` → "다시 시도"
- [ ] 구독 없음 시 `codex_error(no subscription)` → 안내

## Step 4 — Slack 연결 (선택)
- [ ] `slack_manifest` 이벤트로 manifest 표시, `📋 복사` 동작
- [ ] 잘못된 prefix 토큰은 `검증 후 다음` 비활성
- [ ] 올바른 xoxb/xapp 입력 → `slack-verify` → `slack_verified(workspace,bot)` → "✓ 연결됨"
- [ ] 토큰이 `~/.hermes/.env`(SLACK_BOT_TOKEN/SLACK_APP_TOKEN)에 기록됨
- [ ] `건너뛰기` → slack `skipped` → 완료 화면으로

## Step 5 — 완료
- [ ] `verify` → `done(ok:true)`
- [ ] 요약(hermes/codex/slack 상태) 정확
- [ ] 터미널에서 `hermes` 실행 확인, `hermes model` 동작

## 복구/상태
- [ ] 앱 재시작 시 `state.json`의 마지막 완료 단계부터 재개
- [ ] 치명적 오류 시 로그 파일 경로 안내 + "로그 복사"
