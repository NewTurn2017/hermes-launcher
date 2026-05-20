# Hermes Launcher

Windows + WSL2 환경에서 [hermes-agent](https://github.com/NousResearch/hermes-agent)를 **최소 클릭으로** 설치하고 Codex(OpenAI Codex CLI)와 Slack에 연결해 주는 가이드형 데스크톱 위저드.

> 상태: 설계 합의 완료, 구현 계획 단계. 설계 문서 →
> [`docs/superpowers/specs/2026-05-20-hermes-launcher-design.md`](docs/superpowers/specs/2026-05-20-hermes-launcher-design.md)

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

## 라이선스

MIT (예정)
