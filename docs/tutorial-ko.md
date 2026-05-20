# Hermes Launcher 튜토리얼 (한국어)

Windows + WSL2에서 hermes-agent를 최소 클릭으로 설치하는 5단계 위저드 안내입니다.

> 사전 준비: Windows 10/11, WSL2 설치(`wsl --install`), 인터넷 연결.

## 0. 다운로드 & 실행

1. [GitHub Releases](https://github.com/NousResearch/hermes-launcher/releases)에서 `Hermes Launcher_x.y.z_x64-setup.exe`(NSIS) 또는 `.msi`를 받습니다.
2. 실행하면 **SmartScreen 경고**가 뜰 수 있습니다(v1은 미서명). `추가 정보` → `실행`을 누르세요.

![다운로드](images/00-download.png)

## 1. 환경 점검

앱이 자동으로 Windows·WSL2·기본 distro·인터넷을 점검합니다.

- 모두 ✓면 `다음 →`.
- distro가 없으면 `Ubuntu 설치하기`(`wsl --install -d Ubuntu`), WSL 미설치면 MS Store 링크가 안내됩니다.

![환경 점검](images/01-env.png)

## 2. Hermes 설치

WSL Ubuntu 안에서 공식 `install.sh`가 실행됩니다(5~10분). 라이브 로그와 진행률이 표시됩니다.

- 기존 설치가 있으면 자동으로 건너뜁니다(멱등).

![설치](images/02-install.png)

## 3. Codex 로그인

`브라우저 다시 열기`를 누르면 ChatGPT 로그인 페이지가 열립니다. 로그인을 완료하면 `~/.codex/auth.json`이 감지되어 **자동으로 다음 단계**로 넘어갑니다(최대 5분).

- 구독이 없으면 안내와 함께 구독 페이지로 유도합니다.

![Codex](images/03-codex.png)

## 4. Slack 연결 (선택)

1. 표시된 manifest를 `📋 복사`.
2. `api.slack.com/apps/new` → **From an app manifest** → 워크스페이스 선택 → 붙여넣기 → Create.
3. **Socket Mode** 켜기 → App-Level Token(`xapp-…`, scope `connections:write`) 생성.
4. Install → Bot Token(`xoxb-…`) 복사.
5. 두 토큰을 입력 → `검증 후 다음 →`. 워크스페이스 이름이 확인되면 성공.

> Slack은 **선택 단계**입니다. `건너뛰기`를 누르면 hermes는 터미널 TUI로 완전 동작합니다.

![Slack](images/04-slack.png)

## 5. 완료 & 다음 단계

설치 요약을 확인하고 다음을 시도하세요.

- 터미널에서 `hermes` 실행
- Slack에서 `/btw` 보내기
- 모델 전환: `hermes model`

![완료](images/05-done.png)

## 문제 해결

- 설치 실패: 완료 화면의 `로그 보기`로 로그를 복사해 GitHub 이슈에 첨부하세요.
- 로그 위치: `%LOCALAPPDATA%\hermes-launcher\logs\setup-<timestamp>.log`
- 상태 파일: `%LOCALAPPDATA%\hermes-launcher\state.json` (마지막 완료 단계부터 재개)
