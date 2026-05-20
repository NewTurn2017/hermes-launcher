# Hermes Launcher — Plan 4: 통합 + 패키징/CI + 튜토리얼 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plan 1~3을 하나의 동작하는 Tauri 앱으로 묶는다 — 프론트(React)가 Tauri `invoke`+`Channel`로 백엔드(Rust)를 호출해 WSL 헬퍼의 JSONL 이벤트를 실시간 수신하고, `app` 피처로 실제 빌드되며, GitHub Actions `tauri-action`으로 Windows MSI/NSIS를 패키징하고, 한국어 튜토리얼·E2E 체크리스트를 제공한다.

**Architecture:** Plan 3의 `Bridge` 인터페이스에 실제 `tauriBridge`(`@tauri-apps/api`의 `invoke`/`Channel`)를 구현하고, App이 단계 진입 시 bridge로 헬퍼 서브커맨드를 구동한다. Rust에 `run_step` command(앱 피처)를 추가해 `runner`가 자식 stdout을 파싱한 `HelperEvent`를 `Channel`로 프론트에 흘려보낸다. `app` 피처 + 아이콘 + 프론트 `dist`가 갖춰지면 `generate_context!`가 성립해 실제 앱이 빌드된다. WSL 실제 구동·MSI 번들은 Windows(Parallels)/CI에서 검증.

**Tech Stack:** Tauri 2(`app` 피처), `@tauri-apps/api` `invoke`/`Channel`, `@tauri-apps/cli`(`tauri icon`, `tauri build`), `tauri-apps/tauri-action` CI, 아이콘은 kie 스킬 생성+배경제거.

---

## 이 문서의 위치 (foundation-first 로드맵)

1. Plan 1 — helper.sh + JSONL 계약. ✅ 병합.
2. Plan 2 — Tauri/Rust 백엔드. ✅ 병합.
3. Plan 3 — React 프론트엔드. ✅ 병합.
4. **Plan 4 (이 문서)** — 통합 + 패키징/CI + 튜토리얼. **마지막.**

## 플랫폼 제약

- macOS에서 검증: `tauriBridge` TS(+mock api 테스트), `cargo build --features app`(macOS .app까지), `npm run build`(dist), 아이콘 생성, CI YAML lint.
- Windows(Parallels)/CI에서 검증: 실제 `wsl.exe` 헬퍼 구동, `cargo tauri build` MSI/NSIS 번들, 전체 E2E.

---

## File Structure

- `src-tauri/icons/` — 앱 아이콘 세트(`tauri icon`이 생성: `icon.ico`/`icon.png`/`32x32.png`/`128x128.png`/`Square*` 등).
- `assets/icon-source.png` — 아이콘 원본(kie 생성, 배경제거 1024²).
- `src/bridge.ts` — `tauriBridge` 추가(기존 인터페이스/mock 유지).
- `src/bridge.tauri.test.ts` — `@tauri-apps/api` 모킹 테스트.
- `src/App.tsx` — bridge 주입 + 단계 구동(effect).
- `src-tauri/src/lib.rs` — `run_step` command(앱 피처) + 핸들러 등록.
- `.github/workflows/release.yml` — tauri-action 패키징(태그 트리거).
- `docs/tutorial-ko.md` — 한국어 튜토리얼.
- `docs/e2e-checklist.md` — 수동 E2E 체크리스트.
- `README.md` — 빌드·실행·릴리스 안내 갱신.

---

## Task 1: 앱 아이콘 (kie 생성 → tauri icon)

kie 스킬로 Hermes 테마 아이콘(보라 그라데이션)을 생성·배경제거하고, `tauri icon`으로 플랫폼 아이콘 세트를 만든다.

**Files:**
- Create: `assets/icon-source.png` (kie 산출, 1024×1024, 투명 배경)
- Create: `src-tauri/icons/*` (`npx tauri icon` 산출)

- [ ] **Step 1: 아이콘 원본 생성 (kie)**

kie 스킬(image-creator)로 생성: "Hermes(헤르메스) 날개 모티프 + 보라 그라데이션(#7c3aed→#a855f7), 미니멀 앱 아이콘, 정사각, 단색/투명 배경" → 배경 제거 → `assets/icon-source.png`(1024×1024 PNG, 알파).

- [ ] **Step 2: 아이콘 세트 생성**

```bash
npx --yes @tauri-apps/cli@2 icon assets/icon-source.png
```
Expected: `src-tauri/icons/`에 `icon.ico`, `icon.png`, `32x32.png`, `128x128.png`, `128x128@2x.png`, `Square*Logo.png`, `StoreLogo.png` 생성. `tauri.conf.json`의 `bundle.icon`은 이미 `icons/icon.ico` 참조.

- [ ] **Step 3: 검증**

`src-tauri/icons/icon.ico`와 `icon.png` 존재 확인. `file src-tauri/icons/icon.png` → PNG 확인.

- [ ] **Step 4: Commit**

```bash
git add assets/icon-source.png src-tauri/icons
git commit -m "feat: app icon (kie-generated, tauri icon set)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `tauriBridge` (TS) + App 구동 배선

실제 Tauri 브리지를 구현하고, App이 단계 진입 시 헬퍼를 구동하도록 배선한다.

**Files:**
- Modify: `src/bridge.ts` (`tauriBridge` 추가)
- Create: `src/bridge.tauri.test.ts`
- Modify: `src/App.tsx` (bridge prop + 구동 effect)
- Create: `src/App.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/bridge.tauri.test.ts`:

```ts
import { describe, it, expect, vi, beforeEach } from "vitest";

const invokeMock = vi.fn();
class FakeChannel<T> {
  onmessage: (m: T) => void = () => {};
}
vi.mock("@tauri-apps/api/core", () => ({
  invoke: (...a: unknown[]) => invokeMock(...a),
  Channel: FakeChannel,
}));

import { makeTauriBridge } from "./bridge";
import type { HelperEvent } from "./types";

beforeEach(() => invokeMock.mockReset());

describe("tauri bridge", () => {
  it("runStep wires a Channel and invokes run_step", async () => {
    invokeMock.mockResolvedValue(undefined);
    const bridge = makeTauriBridge();
    const seen: HelperEvent[] = [];
    const p = bridge.runStep("detect", [], (ev) => seen.push(ev));
    // simulate backend pushing through the channel
    const arg = invokeMock.mock.calls[0][1] as { onEvent: { onmessage: (m: HelperEvent) => void } };
    arg.onEvent.onmessage({ event: "done", step: "detect", ok: true });
    await p;
    expect(invokeMock).toHaveBeenCalledWith("run_step", expect.objectContaining({ subcommand: "detect" }));
    expect(seen).toEqual([{ event: "done", step: "detect", ok: true }]);
  });

  it("invoke delegates to tauri invoke", async () => {
    invokeMock.mockResolvedValue("ok");
    const bridge = makeTauriBridge();
    await expect(bridge.invoke("set_step", { step: "env", status: "ok" })).resolves.toBe("ok");
    expect(invokeMock).toHaveBeenCalledWith("set_step", { step: "env", status: "ok" });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test src/bridge.tauri.test.ts`
Expected: FAIL — `makeTauriBridge` 미존재.

- [ ] **Step 3: Write minimal implementation**

Append to `src/bridge.ts`:

```ts
import { invoke as tauriInvoke, Channel } from "@tauri-apps/api/core";

/** Real bridge backed by Tauri `invoke` + `Channel` (used in the packaged app). */
export function makeTauriBridge(): Bridge {
  return {
    async runStep(subcommand, args, onEvent) {
      const channel = new Channel<HelperEvent>();
      channel.onmessage = (msg) => onEvent(msg);
      await tauriInvoke("run_step", { subcommand, args, onEvent: channel });
    },
    invoke<T>(cmd: string, payload?: Record<string, unknown>) {
      return tauriInvoke<T>(cmd, payload);
    },
  };
}
```

Create `src/App.test.tsx`:

```tsx
import { describe, it, expect } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { App } from "./App";
import { makeMockBridge } from "./bridge";

describe("App wiring", () => {
  it("runs detect on mount and renders env checks", async () => {
    const bridge = makeMockBridge({
      detect: [
        {
          event: "detect",
          internet: true, python3: true, wslview: true, cmd_exe: true,
          hermes_installed: false, codex_installed: true, codex_authed: false,
        },
      ],
    });
    render(<App bridge={bridge} />);
    await waitFor(() => expect(screen.getByText(/인터넷 연결/)).toBeInTheDocument());
  });
});
```

Modify `src/App.tsx` to accept an injected bridge and run `detect` on mount (default to the real Tauri bridge):

```tsx
import { useEffect, useRef, useState } from "react";
import { initialModel, STEP_ORDER, type UiStepId } from "./wizard/model";
import { applyEvent, navigate } from "./wizard/reducer";
import { makeTauriBridge, type Bridge } from "./bridge";
import { EnvStep } from "./steps/EnvStep";
import { InstallStep } from "./steps/InstallStep";
import { CodexStep } from "./steps/CodexStep";
import { SlackStep } from "./steps/SlackStep";
import { DoneStep } from "./steps/DoneStep";

const TITLES: Record<UiStepId, string> = {
  env: "Setup", install: "Installing", codex: "Codex Auth", slack: "Slack", done: "Done",
};

export function App({ bridge }: { bridge?: Bridge }) {
  const br = useRef<Bridge>(bridge ?? makeTauriBridge()).current;
  const [model, setModel] = useState(initialModel());
  const stepIdx = STEP_ORDER.indexOf(model.active);

  // Run env detection once on mount.
  useEffect(() => {
    void br.runStep("detect", [], (ev) => setModel((m) => applyEvent(m, ev)));
  }, [br]);

  const runStep = (sub: string, args: string[] = []) =>
    br.runStep(sub, args, (ev) => setModel((m) => applyEvent(m, ev)));

  return (
    <div className="app">
      <div className="nav">Hermes Launcher · {TITLES[model.active]}</div>
      <div className="step-indicator">Step {stepIdx + 1} / {STEP_ORDER.length}</div>
      <div className="card">
        {model.active === "env" && <EnvStep model={model} />}
        {model.active === "install" && <InstallStep model={model} />}
        {model.active === "codex" && <CodexStep model={model} onOpen={() => void runStep("codex-login")} />}
        {model.active === "slack" && (
          <SlackStep
            model={model}
            onVerify={(bot, app) => {
              void br.invoke("save_secret", { key: "SLACK_BOT_TOKEN", value: bot });
              void br.invoke("save_secret", { key: "SLACK_APP_TOKEN", value: app });
              void runStep("slack-verify", [bot]);
            }}
          />
        )}
        {model.active === "done" && <DoneStep model={model} />}
      </div>
      <div className="button-row">
        {model.active !== "env" && model.active !== "done" && (
          <button className="btn" onClick={() => setModel(navigate(model, { type: "back" }))}>← 뒤로</button>
        )}
        {model.active === "slack" && (
          <button className="btn" onClick={() => setModel(navigate(model, { type: "skip" }))}>건너뛰기</button>
        )}
        {model.active !== "done" && (
          <button
            className="btn primary"
            onClick={() => {
              const next = navigate(model, { type: "next" });
              setModel(next);
              if (next.active === "install" && model.active === "env") void runStep("install-hermes");
              if (next.active === "slack" && model.active === "codex") void runStep("slack-manifest");
            }}
          >
            다음 →
          </button>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test src/bridge.tauri.test.ts src/App.test.tsx` then `npm test`(전체) + `npx tsc --noEmit`
Expected: PASS. (기존 reducer/step 테스트도 그대로 통과.)

- [ ] **Step 5: Commit**

```bash
git add src/bridge.ts src/bridge.tauri.test.ts src/App.tsx src/App.test.tsx
git commit -m "feat(bridge): tauriBridge (invoke+Channel) + App step wiring

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Rust `run_step` command (app 피처) — Channel 스트리밍

`runner`가 헬퍼 자식 stdout을 파싱한 `HelperEvent`를 Tauri `Channel`로 프론트에 스트리밍하는 command를 추가한다. WSL 실제 spawn은 `#[cfg(windows)]`, 그 외는 안내 에러 이벤트(컴파일 성립용).

**Files:**
- Modify: `src-tauri/src/lib.rs` (`run_step` command + 핸들러 등록)
- Modify: `src-tauri/src/runner.rs` (스트리밍 도우미가 필요하면 보강)

- [ ] **Step 1: 테스트 (로직은 Plan 2 `stream_events`가 이미 커버)**

`run_step`은 Tauri `Channel`을 요구해 webview 없이 단위 테스트가 어렵다. 스트리밍·파싱 로직은 Plan 2 `runner::stream_events` 테스트가 이미 보장하므로, 이 Task는 **컴파일 + clippy 통과 + (Windows)수동 E2E**가 합격선이다. macOS에서는 `cargo build --features app`이 성공해야 한다.

- [ ] **Step 2: Write implementation**

In `src-tauri/src/lib.rs`, inside `#[cfg(feature = "app")] mod commands`, add:

```rust
use crate::events::HelperEvent;
use tauri::ipc::Channel;

/// Run a WSL helper subcommand, streaming each parsed HelperEvent to the frontend.
#[tauri::command]
pub fn run_step(
    subcommand: String,
    args: Vec<String>,
    on_event: Channel<HelperEvent>,
) -> Result<(), String> {
    #[cfg(windows)]
    {
        use crate::runner::{stream_events, wsl_helper_command};
        use crate::state::WizardState;
        // distro from persisted state (set by env step); fall back to default distro.
        let state = WizardState::load(&crate::state::default_state_path());
        let distro = state.wsl_distro.unwrap_or_default();
        let helper = "$HOME/.hermes/launcher/launcher-helper.sh";
        let mut cmd = wsl_helper_command(&distro, helper, &args.iter().fold(subcommand.clone(), |a, b| format!("{a} {b}")));
        let mut child = cmd.spawn().map_err(|e| e.to_string())?;
        let stdout = child.stdout.take().ok_or("no stdout")?;
        let ch = on_event.clone();
        stream_events(stdout, move |ev| {
            let _ = ch.send(ev);
        })
        .map_err(|e| e.to_string())?;
        let _ = child.wait();
        Ok(())
    }
    #[cfg(not(windows))]
    {
        let _ = args;
        // Dev (non-Windows): WSL is unavailable; report an environment error.
        on_event
            .send(HelperEvent::Error {
                step: crate::events::Step::Detect,
                level: crate::events::Level::Environment,
                detail: format!("run_step('{subcommand}') requires Windows + WSL"),
            })
            .map_err(|e| e.to_string())?;
        Ok(())
    }
}
```

Register it in the handler:

```rust
.invoke_handler(tauri::generate_handler![
    commands::set_step,
    commands::save_secret,
    commands::run_step
])
```

> `HelperEvent`는 Plan 2에서 `Serialize`를 derive하므로 `Channel<HelperEvent>`로 전송 가능. `Channel`은 `Clone`이라 클로저로 이동 가능.

- [ ] **Step 3: Verify compile (macOS) + clippy**

```bash
cd src-tauri
cargo build --features app          # generate_context needs icons (Task 1) + ../dist (npm run build)
cargo clippy --features app --lib -- -D warnings
```
Expected: 컴파일·clippy 통과. (`../dist`가 없으면 먼저 repo 루트에서 `npm run build`. 아이콘은 Task 1 산출.)

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/lib.rs src-tauri/src/runner.rs
git commit -m "feat(app): run_step command streaming HelperEvent over Channel

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `app` 피처 빌드 검증 + helper 동봉 전략

앱이 WSL에 설치할 `launcher-helper.sh`를 번들 리소스로 동봉하고, `app` 피처 빌드를 검증한다.

**Files:**
- Modify: `src-tauri/tauri.conf.json` (`bundle.resources`에 helper 동봉)
- Create: `src-tauri/resources/` (빌드 시 `helper/`에서 복사하는 방법 문서화)

- [ ] **Step 1: helper 동봉 설정**

`tauri.conf.json`의 `bundle`에 추가:

```json
"resources": { "../helper/launcher-helper.sh": "helper/launcher-helper.sh", "../helper/lib": "helper/lib" }
```
> 런처는 첫 실행 시 이 리소스를 WSL ext4(`~/.hermes/launcher/`)로 복사한 뒤 구동한다(복사 로직은 `run_step`의 Windows 분기에서 `wsl.exe cp` 또는 `\\wsl$` 경로 사용 — Parallels에서 구현·검증).

- [ ] **Step 2: 빌드 검증 (macOS)**

```bash
npm run build                       # produces ../dist
cd src-tauri && cargo build --features app
```
Expected: 성공. 산출물 `target/debug/hermes-launcher`(.app 번들은 `cargo tauri build`).

- [ ] **Step 3: Commit**

```bash
git add src-tauri/tauri.conf.json
git commit -m "feat(app): bundle launcher-helper.sh as Tauri resource

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: 패키징 CI (tauri-action, Windows)

태그 푸시 시 Windows에서 MSI/NSIS를 빌드해 GitHub Release에 올린다.

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/release.yml`:

```yaml
name: release

on:
  push:
    tags:
      - "v*"
  workflow_dispatch:

jobs:
  bundle:
    runs-on: windows-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - uses: dtolnay/rust-toolchain@stable
      - run: npm ci
      - run: npm run build
      - uses: tauri-apps/tauri-action@v0
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          args: "--features app"
          tagName: ${{ github.ref_name }}
          releaseName: "Hermes Launcher ${{ github.ref_name }}"
          releaseDraft: true
          prerelease: false
```

> v1은 미서명 → SmartScreen 경고(README 안내). 서명은 v2.

- [ ] **Step 2: Validate YAML**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('yaml ok')"
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: tauri-action MSI/NSIS packaging on tag (windows)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: 튜토리얼 + E2E 체크리스트 + README

**Files:**
- Create: `docs/tutorial-ko.md`, `docs/e2e-checklist.md`
- Modify: `README.md`

- [ ] **Step 1: 튜토리얼 작성** — `docs/tutorial-ko.md`: 다운로드→SmartScreen 우회→5단계 진행→완료 후 `hermes` 실행/Slack `/btw`/`hermes model`. 각 단계 스크린샷 자리표시(`![](...)`)와 캡션.

- [ ] **Step 2: E2E 체크리스트** — `docs/e2e-checklist.md`: 깨끗한 Windows+Ubuntu에서 ① 환경 점검 통과 ② install 진행률·로그 ③ codex 브라우저 OAuth→자동 진행 ④ slack manifest 복사→토큰 검증 ⑤ verify→완료. 각 항목 체크박스 + 예상 이벤트.

- [ ] **Step 3: README 갱신** — 빌드(`npm ci && npm run build && cd src-tauri && cargo tauri build --features app`), 개발(`npm run dev` + `cargo tauri dev --features app`), 릴리스(태그 푸시→release.yml), 미서명 경고 안내.

- [ ] **Step 4: Commit**

```bash
git add docs/tutorial-ko.md docs/e2e-checklist.md README.md
git commit -m "docs: KO tutorial, E2E checklist, README build/release guide

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:** 프론트↔백 배선(설계 41~47줄) → Task 2·3. 라이브 진행률 스트리밍(94줄) → Channel(Task 3). codex 브라우저 열기·폴링(112~117줄) → onOpen→`codex-login`. slack manifest·토큰 주입(129~141줄) → onVerify→save_secret+slack-verify. 배포 GitHub Releases·tauri-action·미서명(177~181줄) → Task 5. 튜토리얼·다음 단계(183~187줄) → Task 6. 상태 영속화 distro(154줄) → run_step이 state에서 distro 로드. ✅

**2. Placeholder scan:** Task 1(아이콘)·3(Channel)·5(CI)·6(docs)는 webview/Windows 의존이라 "컴파일/빌드/수동 E2E"를 합격선으로 명시(코드 스텝엔 실제 코드 포함). helper 동봉 복사 로직은 Windows 분기로 Parallels 검증 명시.

**3. Type/이름 일관성:** `run_step`(Rust) ↔ `runStep`→`invoke("run_step")`(TS) 인자 `subcommand`/`args`/`onEvent`(camel) ↔ `on_event`(snake) Tauri 변환 일치. `Channel<HelperEvent>` ↔ `HelperEvent`(Plan 2 Serialize). `makeTauriBridge`/`makeMockBridge` 동일 `Bridge` 반환. `save_secret`/`set_step` 시그니처 Plan 2와 일치. ✅

---

## 실행 옵션 / 완료

**Plan 4 작성 완료.** macOS 검증분(tauriBridge·App 배선·app 피처 컴파일·아이콘·CI·docs) 구현 후, 실제 WSL 구동과 MSI 번들은 Parallels/CI(`release.yml`)에서 검증한다. 4개 플랜 완료 시 전체 제품(원타임 설치 위저드)이 동작한다.
