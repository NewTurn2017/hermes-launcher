# Hermes Launcher — Plan 3: React 프론트엔드 (5단계 위저드) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 브레인스토밍 목업을 따르는 5단계 위저드 React/TS 프론트엔드를 구현한다. 헬퍼 JSONL 이벤트(Plan 1 계약)를 받아 UI 상태로 환원하는 순수 reducer와 토큰 형식 검증을 Vitest로 TDD하고, 다크 테마 바닐라 CSS로 목업을 재현한다.

**Architecture:** UI 로직(이벤트→상태 reducer, 위저드 내비게이션, 토큰 검증)을 순수 TS 모듈로 분리해 Vitest로 검증한다. Tauri 백엔드 호출은 `bridge.ts` 인터페이스 뒤로 추상화해, 테스트는 mock bridge를, 실제 앱은 Tauri `invoke`/`Channel` 구현을 쓴다(실제 배선은 Plan 4 `app` 피처). React 컴포넌트는 상태에서 렌더만 하고, 부수효과는 bridge를 통해 일으킨다. 의존성 최소화: React + Vite + TypeScript + Vitest + @testing-library/react, 스타일은 바닐라 CSS 한 파일.

**Tech Stack:** Vite 6, React 18, TypeScript 5, Vitest 2 + @testing-library/react + jsdom, 바닐라 CSS. Tauri 연동은 `@tauri-apps/api`(Plan 4에서 실제 배선). CI: tsc + vitest + `vite build`.

---

## 이 문서의 위치 (foundation-first 로드맵)

1. Plan 1 — helper.sh + JSONL 계약. ✅ 완료·병합.
2. Plan 2 — Tauri/Rust 백엔드. ✅ 완료·병합.
3. **Plan 3 (이 문서)** — React 프론트엔드. Plan 1 이벤트 계약을 TS로 미러링.
4. Plan 4 — 통합(Tauri `app` 피처로 프론트↔백 배선) + 패키징/CI + 튜토리얼 + E2E.

## 디자인 (브레인스토밍 목업 기반)

`.superpowers/brainstorm/.../content/wizard-flow.html` 목업을 따른다.
- 다크 테마: 배경 `#0f0f0f`/`#1a1a1a`, 카드 `#181818`, 텍스트 `#eee`, 보조 `#888`/`#666`.
- 강조: 보라 그라데이션 `linear-gradient(90deg,#7c3aed,#a855f7)` (진행바·기본 버튼).
- 레이아웃: 상단 nav(`Hermes Launcher · <단계>`) + 본문 카드(패딩 24px) + 하단 버튼 행.
- monospace 로그 박스(설치 로그 녹색 `#4ade80`, manifest 회색 `#ccc`).
- 단계: ① 환경 점검 체크리스트 ② 설치 진행(로그+진행바) ③ Codex 로그인(대기/재시도) ④ Slack(manifest 복사+토큰 입력+검증, Skip) ⑤ 완료(요약+다음 단계).

---

## File Structure

설계 문서 79줄 `src/` 프론트엔드.

- `package.json`, `vite.config.ts`, `tsconfig.json`, `tsconfig.node.json`, `index.html` — 스캐폴드.
- `src/main.tsx` — React 마운트.
- `src/App.tsx` — 위저드 셸(nav + 활성 스텝 렌더 + 내비 버튼).
- `src/styles.css` — 다크 테마 바닐라 CSS(목업 재현).
- `src/types.ts` — `HelperEvent`/`Step`/`Level` TS 미러(Plan 1 스키마와 일치).
- `src/wizard/model.ts` — `WizardModel`/`UiStepId`/`UiStatus` + 초기 상태.
- `src/wizard/reducer.ts` — `applyEvent(model, ev)` + `navigate(model, action)`. **순수, Vitest 핵심.**
- `src/wizard/tokens.ts` — `validateBotToken`/`validateAppToken`. 순수.
- `src/bridge.ts` — `Bridge` 인터페이스 + `mockBridge`(테스트) + `tauriBridge`(Plan 4 실제 배선 stub).
- `src/steps/EnvStep.tsx` / `InstallStep.tsx` / `CodexStep.tsx` / `SlackStep.tsx` / `DoneStep.tsx` — 단계 컴포넌트.
- `src/wizard/*.test.ts`, `src/steps/*.test.tsx` — Vitest.
- `.github/workflows/web.yml` — tsc + vitest + build.

---

## 사전 준비

- Node.js 20+ / npm. (`node --version`로 확인; 없으면 `brew install node`.)
- 프로젝트 루트에서 작업(프론트는 repo 루트의 `src/`, Vite 루트도 repo 루트; `tauri.conf.json`의 `frontendDist`는 `../dist`라 Vite `build.outDir`는 repo 루트 `dist`).

표준 명령: `npm test`(vitest run), `npm run build`(tsc + vite build), `npx tsc --noEmit`.

---

## Task 1: Vite + React + TS + Vitest 스캐폴드

`npm test`/`npm run build`가 도는 최소 프론트엔드 골격.

**Files:**
- Create: `package.json`, `vite.config.ts`, `tsconfig.json`, `tsconfig.node.json`, `index.html`, `src/main.tsx`, `src/App.tsx`, `src/styles.css`, `src/setupTests.ts`, `src/smoke.test.ts`
- Modify: `.gitignore` (이미 `node_modules`/`dist` 무시 — 확인)

- [ ] **Step 1: Write the failing test**

Create `src/smoke.test.ts`:

```ts
import { describe, it, expect } from "vitest";

describe("scaffold", () => {
  it("runs vitest", () => {
    expect(2 + 2).toBe(4);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test`
Expected: FAIL — `package.json`/스크립트 부재로 실행 불가.

- [ ] **Step 3: Write minimal implementation**

Create `package.json`:

```json
{
  "name": "hermes-launcher-frontend",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc --noEmit && vite build",
    "preview": "vite preview",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc --noEmit"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "@tauri-apps/api": "^2"
  },
  "devDependencies": {
    "@testing-library/jest-dom": "^6.4.8",
    "@testing-library/react": "^16.0.1",
    "@types/react": "^18.3.5",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.1",
    "jsdom": "^25.0.0",
    "typescript": "^5.5.4",
    "vite": "^6.0.0",
    "vitest": "^2.1.0"
  }
}
```

Create `vite.config.ts`:

```ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  // tauri.conf.json frontendDist = "../dist" -> output to repo-root /dist
  build: { outDir: "dist", emptyOutDir: true },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/setupTests.ts"],
    globals: true,
  },
});
```

Create `tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "types": ["vitest/globals", "@testing-library/jest-dom"]
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

Create `tsconfig.node.json`:

```json
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true,
    "strict": true
  },
  "include": ["vite.config.ts"]
}
```

Create `index.html`:

```html
<!doctype html>
<html lang="ko">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Hermes Launcher</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```

Create `src/setupTests.ts`:

```ts
import "@testing-library/jest-dom/vitest";
```

Create `src/main.tsx`:

```tsx
import React from "react";
import ReactDOM from "react-dom/client";
import { App } from "./App";
import "./styles.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
```

Create `src/App.tsx`:

```tsx
export function App() {
  return <div className="app">Hermes Launcher</div>;
}
```

Create `src/styles.css`:

```css
:root {
  color-scheme: dark;
}
body {
  margin: 0;
  background: #0f0f0f;
  color: #eee;
  font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
}
.app {
  max-width: 680px;
  margin: 0 auto;
  padding: 24px;
}
```

Install deps:

```bash
npm install
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test`
Expected: PASS (1 test). Also `npm run build` produces `dist/` and `npx tsc --noEmit` is clean.

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json vite.config.ts tsconfig.json tsconfig.node.json index.html src/main.tsx src/App.tsx src/styles.css src/setupTests.ts src/smoke.test.ts
git commit -m "chore: scaffold Vite/React/TS frontend + Vitest

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: `types.ts` — HelperEvent TS 미러

Plan 1 스키마와 일치하는 판별 유니온을 정의한다(런타임 검증 아님; 형태 일치만).

**Files:**
- Create: `src/types.ts`, `src/types.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/types.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import type { HelperEvent } from "./types";
import { isHelperEvent } from "./types";

describe("HelperEvent guard", () => {
  it("accepts known event objects", () => {
    const ev: HelperEvent = { event: "step", step: "install-hermes", progress: 42, msg: "x" };
    expect(isHelperEvent(ev)).toBe(true);
    expect(isHelperEvent({ event: "codex_aborted" })).toBe(true);
    expect(isHelperEvent({ event: "done", step: "verify", ok: true })).toBe(true);
  });

  it("rejects non-events", () => {
    expect(isHelperEvent({ event: "explode" })).toBe(false);
    expect(isHelperEvent(null)).toBe(false);
    expect(isHelperEvent({ foo: 1 })).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test src/types.test.ts`
Expected: FAIL — `types.ts` 미존재.

- [ ] **Step 3: Write minimal implementation**

Create `src/types.ts`:

```ts
// TS mirror of helper/events.schema.json (Plan 1 contract).
export type Step =
  | "detect"
  | "install-hermes"
  | "codex-login"
  | "slack-manifest"
  | "slack-verify"
  | "write-config"
  | "verify";

export type Level = "recoverable" | "environment" | "fatal";

export type HelperEvent =
  | { event: "step"; step: Step; progress: number; msg: string }
  | {
      event: "detect";
      internet: boolean;
      python3: boolean;
      wslview: boolean;
      cmd_exe: boolean;
      hermes_installed: boolean;
      codex_installed: boolean;
      codex_authed: boolean;
    }
  | { event: "codex_authed"; email?: string | null }
  | { event: "codex_error"; detail: string }
  | { event: "codex_aborted" }
  | { event: "codex_timeout" }
  | { event: "slack_manifest"; json: string }
  | { event: "slack_verified"; workspace: string; bot: string }
  | { event: "slack_error"; detail: string }
  | { event: "done"; step: Step; ok: boolean }
  | { event: "error"; step: Step; level: Level; detail: string };

const EVENT_NAMES = new Set([
  "step",
  "detect",
  "codex_authed",
  "codex_error",
  "codex_aborted",
  "codex_timeout",
  "slack_manifest",
  "slack_verified",
  "slack_error",
  "done",
  "error",
]);

export function isHelperEvent(x: unknown): x is HelperEvent {
  return (
    typeof x === "object" &&
    x !== null &&
    "event" in x &&
    typeof (x as { event: unknown }).event === "string" &&
    EVENT_NAMES.has((x as { event: string }).event)
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test src/types.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/types.ts src/types.test.ts
git commit -m "feat(types): TS mirror of HelperEvent contract + guard

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `tokens.ts` — Slack 토큰 형식 검증

설계 문서 137~139줄: prefix 즉시 1차 검증.

**Files:**
- Create: `src/wizard/tokens.ts`, `src/wizard/tokens.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/wizard/tokens.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { validateBotToken, validateAppToken } from "./tokens";

describe("token validation", () => {
  it("accepts well-formed bot token", () => {
    expect(validateBotToken("xoxb-123-456-abcDEF")).toEqual({ ok: true });
  });
  it("rejects bot token with wrong prefix", () => {
    const r = validateBotToken("xapp-123");
    expect(r.ok).toBe(false);
    expect((r as { ok: false; reason: string }).reason).toMatch(/xoxb-/);
  });
  it("rejects empty/short bot token", () => {
    expect(validateBotToken("").ok).toBe(false);
    expect(validateBotToken("xoxb-").ok).toBe(false);
  });
  it("accepts well-formed app token and rejects wrong prefix", () => {
    expect(validateAppToken("xapp-1-A0B1-2345-deadbeef")).toEqual({ ok: true });
    expect(validateAppToken("xoxb-1").ok).toBe(false);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test src/wizard/tokens.test.ts`
Expected: FAIL — 모듈 미존재.

- [ ] **Step 3: Write minimal implementation**

Create `src/wizard/tokens.ts`:

```ts
export type TokenCheck = { ok: true } | { ok: false; reason: string };

export function validateBotToken(token: string): TokenCheck {
  const t = token.trim();
  if (!t.startsWith("xoxb-")) {
    return { ok: false, reason: "Bot 토큰은 xoxb- 로 시작해야 합니다" };
  }
  if (t.length < 10) {
    return { ok: false, reason: "Bot 토큰이 너무 짧습니다" };
  }
  return { ok: true };
}

export function validateAppToken(token: string): TokenCheck {
  const t = token.trim();
  if (!t.startsWith("xapp-")) {
    return { ok: false, reason: "App-Level 토큰은 xapp- 로 시작해야 합니다" };
  }
  if (t.length < 10) {
    return { ok: false, reason: "App-Level 토큰이 너무 짧습니다" };
  }
  return { ok: true };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test src/wizard/tokens.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/wizard/tokens.ts src/wizard/tokens.test.ts
git commit -m "feat(tokens): Slack token prefix validation

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `model.ts` + `reducer.ts` — 위저드 상태머신

헬퍼 이벤트와 내비 액션을 UI 상태로 환원하는 순수 reducer. **Plan 3의 핵심 로직.**

**Files:**
- Create: `src/wizard/model.ts`, `src/wizard/reducer.ts`, `src/wizard/reducer.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/wizard/reducer.test.ts`:

```ts
import { describe, it, expect } from "vitest";
import { initialModel } from "./model";
import { applyEvent, navigate } from "./reducer";

describe("wizard reducer — events", () => {
  it("detect event fills env info and marks env ok", () => {
    const m = applyEvent(initialModel(), {
      event: "detect",
      internet: true,
      python3: true,
      wslview: true,
      cmd_exe: true,
      hermes_installed: false,
      codex_installed: true,
      codex_authed: false,
    });
    expect(m.detect?.internet).toBe(true);
    expect(m.steps.env.status).toBe("ok");
  });

  it("install step events update progress + log; done marks ok", () => {
    let m = initialModel();
    m = applyEvent(m, { event: "step", step: "install-hermes", progress: 35, msg: "cloning" });
    expect(m.steps.install.progress).toBe(35);
    expect(m.steps.install.log).toContain("cloning");
    m = applyEvent(m, { event: "done", step: "install-hermes", ok: true });
    expect(m.steps.install.status).toBe("ok");
    expect(m.steps.install.progress).toBe(100);
  });

  it("codex_authed marks codex ok and stores email; error marks failed", () => {
    let m = applyEvent(initialModel(), { event: "codex_authed", email: "u@example.com" });
    expect(m.steps.codex.status).toBe("ok");
    expect(m.codexEmail).toBe("u@example.com");
    m = applyEvent(initialModel(), { event: "codex_error", detail: "no subscription" });
    expect(m.steps.codex.status).toBe("failed");
    expect(m.steps.codex.error).toMatch(/no subscription/);
  });

  it("slack_manifest stores text; slack_verified marks ok", () => {
    let m = applyEvent(initialModel(), { event: "slack_manifest", json: "{\"a\":1}" });
    expect(m.slackManifest).toBe("{\"a\":1}");
    m = applyEvent(m, { event: "slack_verified", workspace: "Acme", bot: "hermes" });
    expect(m.steps.slack.status).toBe("ok");
    expect(m.slackVerified).toEqual({ workspace: "Acme", bot: "hermes" });
  });

  it("error event marks the mapped step failed with detail", () => {
    const m = applyEvent(initialModel(), {
      event: "error",
      step: "install-hermes",
      level: "fatal",
      detail: "boom",
    });
    expect(m.steps.install.status).toBe("failed");
    expect(m.steps.install.error).toBe("boom");
  });
});

describe("wizard reducer — navigation", () => {
  it("next advances only when current step is complete", () => {
    let m = initialModel();
    expect(m.active).toBe("env");
    m = navigate(m, { type: "next" }); // env not ok yet -> no move
    expect(m.active).toBe("env");
    m = applyEvent(m, {
      event: "detect",
      internet: true, python3: true, wslview: true, cmd_exe: true,
      hermes_installed: false, codex_installed: true, codex_authed: false,
    });
    m = navigate(m, { type: "next" });
    expect(m.active).toBe("install");
  });

  it("back moves to previous step", () => {
    let m = { ...initialModel(), active: "codex" as const };
    m = navigate(m, { type: "back" });
    expect(m.active).toBe("install");
  });

  it("skip marks slack skipped and advances to done", () => {
    let m = { ...initialModel(), active: "slack" as const };
    m = navigate(m, { type: "skip" });
    expect(m.steps.slack.status).toBe("skipped");
    expect(m.active).toBe("done");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test src/wizard/reducer.test.ts`
Expected: FAIL — 모듈 미존재.

- [ ] **Step 3: Write minimal implementation**

Create `src/wizard/model.ts`:

```ts
export type UiStepId = "env" | "install" | "codex" | "slack" | "done";
export type UiStatus = "idle" | "running" | "ok" | "skipped" | "failed";

export const STEP_ORDER: UiStepId[] = ["env", "install", "codex", "slack", "done"];

export interface DetectInfo {
  internet: boolean;
  python3: boolean;
  wslview: boolean;
  cmd_exe: boolean;
  hermes_installed: boolean;
  codex_installed: boolean;
  codex_authed: boolean;
}

export interface StepView {
  status: UiStatus;
  progress: number;
  log: string[];
  error?: string;
}

export interface WizardModel {
  active: UiStepId;
  steps: Record<UiStepId, StepView>;
  detect?: DetectInfo;
  codexEmail?: string | null;
  slackManifest?: string;
  slackVerified?: { workspace: string; bot: string };
}

function blankStep(): StepView {
  return { status: "idle", progress: 0, log: [] };
}

export function initialModel(): WizardModel {
  return {
    active: "env",
    steps: {
      env: blankStep(),
      install: blankStep(),
      codex: blankStep(),
      slack: blankStep(),
      done: blankStep(),
    },
  };
}
```

Create `src/wizard/reducer.ts`:

```ts
import type { HelperEvent, Step } from "../types";
import { STEP_ORDER, type UiStepId, type WizardModel } from "./model";

// Map a backend Step to the UI step it belongs to.
function uiStepFor(step: Step): UiStepId {
  switch (step) {
    case "detect":
      return "env";
    case "install-hermes":
      return "install";
    case "codex-login":
      return "codex";
    case "slack-manifest":
    case "slack-verify":
    case "write-config":
      return "slack";
    case "verify":
      return "done";
  }
}

function patchStep(
  m: WizardModel,
  id: UiStepId,
  patch: Partial<WizardModel["steps"][UiStepId]>,
): WizardModel {
  return { ...m, steps: { ...m.steps, [id]: { ...m.steps[id], ...patch } } };
}

export function applyEvent(model: WizardModel, ev: HelperEvent): WizardModel {
  switch (ev.event) {
    case "detect": {
      const { event: _e, ...info } = ev;
      return patchStep({ ...model, detect: info }, "env", { status: "ok" });
    }
    case "step": {
      const id = uiStepFor(ev.step);
      const log = ev.msg ? [...model.steps[id].log, ev.msg] : model.steps[id].log;
      return patchStep(model, id, { status: "running", progress: ev.progress, log });
    }
    case "done": {
      const id = uiStepFor(ev.step);
      return patchStep(model, id, { status: ev.ok ? "ok" : "failed", progress: 100 });
    }
    case "error": {
      const id = uiStepFor(ev.step);
      return patchStep(model, id, { status: "failed", error: ev.detail });
    }
    case "codex_authed":
      return patchStep({ ...model, codexEmail: ev.email ?? null }, "codex", { status: "ok" });
    case "codex_error":
      return patchStep(model, "codex", { status: "failed", error: ev.detail });
    case "codex_aborted":
      return patchStep(model, "codex", { status: "idle", error: "사용자가 취소했습니다" });
    case "codex_timeout":
      return patchStep(model, "codex", { status: "failed", error: "시간이 초과되었습니다 (5분)" });
    case "slack_manifest":
      return { ...model, slackManifest: ev.json };
    case "slack_verified":
      return patchStep({ ...model, slackVerified: { workspace: ev.workspace, bot: ev.bot } }, "slack", {
        status: "ok",
      });
    case "slack_error":
      return patchStep(model, "slack", { status: "failed", error: ev.detail });
  }
}

export type NavAction = { type: "next" } | { type: "back" } | { type: "skip" };

const COMPLETE = new Set(["ok", "skipped"]);

export function navigate(model: WizardModel, action: NavAction): WizardModel {
  const idx = STEP_ORDER.indexOf(model.active);
  switch (action.type) {
    case "next": {
      if (!COMPLETE.has(model.steps[model.active].status)) return model;
      const next = STEP_ORDER[Math.min(idx + 1, STEP_ORDER.length - 1)];
      return { ...model, active: next };
    }
    case "back": {
      const prev = STEP_ORDER[Math.max(idx - 1, 0)];
      return { ...model, active: prev };
    }
    case "skip": {
      if (model.active !== "slack") return model;
      const skipped = patchStep(model, "slack", { status: "skipped" });
      return { ...skipped, active: "done" };
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test src/wizard/reducer.test.ts`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add src/wizard/model.ts src/wizard/reducer.ts src/wizard/reducer.test.ts
git commit -m "feat(wizard): event->state reducer + navigation state machine

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: `bridge.ts` — Tauri 호출 추상화

백엔드 호출/이벤트 스트림을 인터페이스 뒤로 두어 테스트는 mock을, 앱은 Tauri를 쓴다(실제 Tauri 배선은 Plan 4).

**Files:**
- Create: `src/bridge.ts`, `src/bridge.test.ts`

- [ ] **Step 1: Write the failing test**

Create `src/bridge.test.ts`:

```ts
import { describe, it, expect, vi } from "vitest";
import { makeMockBridge } from "./bridge";
import type { HelperEvent } from "./types";

describe("mock bridge", () => {
  it("runStep streams the scripted events to the listener", async () => {
    const scripted: HelperEvent[] = [
      { event: "step", step: "install-hermes", progress: 50, msg: "x" },
      { event: "done", step: "install-hermes", ok: true },
    ];
    const bridge = makeMockBridge({ "install-hermes": scripted });
    const seen: HelperEvent[] = [];
    await bridge.runStep("install-hermes", [], (ev) => seen.push(ev));
    expect(seen).toEqual(scripted);
  });

  it("invoke resolves with the configured handler result", async () => {
    const bridge = makeMockBridge({}, { set_step: vi.fn().mockResolvedValue(undefined) });
    await expect(bridge.invoke("set_step", { step: "env", status: "ok" })).resolves.toBeUndefined();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test src/bridge.test.ts`
Expected: FAIL — 모듈 미존재.

- [ ] **Step 3: Write minimal implementation**

Create `src/bridge.ts`:

```ts
import type { HelperEvent } from "./types";

export type EventListener = (ev: HelperEvent) => void;

/** Abstraction over the Tauri backend so the UI is testable without a webview. */
export interface Bridge {
  /** Run a helper subcommand inside WSL, streaming JSONL events to `onEvent`. */
  runStep(subcommand: string, args: string[], onEvent: EventListener): Promise<void>;
  /** Invoke a one-shot Tauri command (e.g. set_step, save_secret). */
  invoke<T = unknown>(cmd: string, payload?: Record<string, unknown>): Promise<T>;
}

/** In-memory bridge for tests: scripted event streams + stubbed invoke handlers. */
export function makeMockBridge(
  scripts: Record<string, HelperEvent[]> = {},
  handlers: Record<string, (payload?: Record<string, unknown>) => Promise<unknown>> = {},
): Bridge {
  return {
    async runStep(subcommand, _args, onEvent) {
      for (const ev of scripts[subcommand] ?? []) onEvent(ev);
    },
    async invoke<T>(cmd: string, payload?: Record<string, unknown>) {
      const h = handlers[cmd];
      return (h ? await h(payload) : undefined) as T;
    },
  };
}
```

> 실제 Tauri 브리지(`@tauri-apps/api`의 `invoke` + `Channel`)는 Plan 4에서 `tauriBridge`로 구현해 `app` 피처와 함께 배선한다. Plan 3는 mock으로 전 로직을 검증한다.

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test src/bridge.test.ts`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/bridge.ts src/bridge.test.ts
git commit -m "feat(bridge): Bridge interface + in-memory mock for tests

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: 단계 컴포넌트 + 위저드 셸 + 스타일

목업을 재현하는 5개 단계 컴포넌트와 App 셸을 만들고, 핵심 컴포넌트는 Testing Library로 검증한다.

**Files:**
- Create: `src/steps/EnvStep.tsx`, `InstallStep.tsx`, `CodexStep.tsx`, `SlackStep.tsx`, `DoneStep.tsx`
- Modify: `src/App.tsx`, `src/styles.css`
- Create: `src/steps/EnvStep.test.tsx`, `src/steps/SlackStep.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/steps/EnvStep.test.tsx`:

```tsx
import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { EnvStep } from "./EnvStep";
import { initialModel } from "../wizard/model";
import { applyEvent } from "../wizard/reducer";

describe("EnvStep", () => {
  it("shows check rows from detect info", () => {
    const m = applyEvent(initialModel(), {
      event: "detect",
      internet: true, python3: true, wslview: true, cmd_exe: true,
      hermes_installed: false, codex_installed: true, codex_authed: false,
    });
    render(<EnvStep model={m} />);
    expect(screen.getByText(/인터넷 연결/)).toBeInTheDocument();
    expect(screen.getByText(/WSL 브라우저 연동/)).toBeInTheDocument();
  });
});
```

Create `src/steps/SlackStep.test.tsx`:

```tsx
import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { SlackStep } from "./SlackStep";
import { initialModel } from "../wizard/model";

describe("SlackStep", () => {
  it("disables verify until both tokens have valid prefixes", () => {
    const onVerify = vi.fn();
    render(<SlackStep model={initialModel()} onVerify={onVerify} />);
    const verify = screen.getByRole("button", { name: /검증/ });
    expect(verify).toBeDisabled();

    fireEvent.change(screen.getByPlaceholderText(/xoxb-/), { target: { value: "xoxb-123456789" } });
    fireEvent.change(screen.getByPlaceholderText(/xapp-/), { target: { value: "xapp-123456789" } });
    expect(verify).toBeEnabled();
    fireEvent.click(verify);
    expect(onVerify).toHaveBeenCalledWith("xoxb-123456789", "xapp-123456789");
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npm test src/steps`
Expected: FAIL — 컴포넌트 미존재.

- [ ] **Step 3: Write minimal implementation**

Create `src/steps/EnvStep.tsx`:

```tsx
import type { WizardModel } from "../wizard/model";

function CheckRow({ ok, label }: { ok: boolean; label: string }) {
  return (
    <div className={`check-row ${ok ? "ok" : "bad"}`}>
      <span className="check-mark">{ok ? "✓" : "✗"}</span>
      {label}
    </div>
  );
}

export function EnvStep({ model }: { model: WizardModel }) {
  const d = model.detect;
  return (
    <div>
      <h3>시작하기 전에</h3>
      <p className="muted">설치 환경을 자동으로 점검합니다.</p>
      {d ? (
        <div className="check-list">
          <CheckRow ok={d.internet} label="인터넷 연결" />
          <CheckRow ok={d.python3} label="python3 (WSL)" />
          <CheckRow ok={d.wslview || d.cmd_exe} label="WSL 브라우저 연동 (wslview/cmd.exe)" />
          <CheckRow ok={d.codex_installed} label="Codex CLI" />
        </div>
      ) : (
        <div className="placeholder">환경을 점검하는 중…</div>
      )}
    </div>
  );
}
```

Create `src/steps/InstallStep.tsx`:

```tsx
import type { WizardModel } from "../wizard/model";

export function InstallStep({ model }: { model: WizardModel }) {
  const s = model.steps.install;
  return (
    <div>
      <h3>Hermes 설치 중…</h3>
      <p className="muted">WSL Ubuntu에 hermes-agent 공식 인스톨러를 실행합니다.</p>
      <pre className="log-box">{s.log.length ? s.log.join("\n") : "설치 준비 중…"}</pre>
      <div className="progress-track">
        <div className="progress-fill" style={{ width: `${s.progress}%` }} />
      </div>
      {s.error && <p className="error-text">{s.error}</p>}
    </div>
  );
}
```

Create `src/steps/CodexStep.tsx`:

```tsx
import type { WizardModel } from "../wizard/model";

export function CodexStep({ model, onOpen }: { model: WizardModel; onOpen: () => void }) {
  const s = model.steps.codex;
  return (
    <div>
      <h3>Codex에 로그인하세요</h3>
      <p className="muted">
        "브라우저 열기"를 누르면 ChatGPT 로그인 페이지가 열립니다. 완료까지 기다려주세요.
      </p>
      <div className="placeholder left">
        {s.status === "ok" ? (
          <strong>✓ 인증 완료 {model.codexEmail ? `(${model.codexEmail})` : ""}</strong>
        ) : (
          <>
            <strong>대기 중…</strong>
            <br />
            <span className="muted small">인증을 완료하면 자동으로 다음 단계로 넘어갑니다 (최대 5분)</span>
          </>
        )}
      </div>
      {s.error && <p className="error-text">{s.error}</p>}
      <div className="button-row">
        <button className="btn" onClick={onOpen}>브라우저 다시 열기</button>
      </div>
    </div>
  );
}
```

Create `src/steps/SlackStep.tsx`:

```tsx
import { useState } from "react";
import type { WizardModel } from "../wizard/model";
import { validateAppToken, validateBotToken } from "../wizard/tokens";

export function SlackStep({
  model,
  onVerify,
}: {
  model: WizardModel;
  onVerify: (bot: string, app: string) => void;
}) {
  const [bot, setBot] = useState("");
  const [app, setApp] = useState("");
  const botOk = validateBotToken(bot).ok;
  const appOk = validateAppToken(app).ok;
  return (
    <div>
      <h3>Slack 앱 만들기</h3>
      <p className="muted">아래 manifest를 복사해 api.slack.com/apps/new 의 "From a manifest"에 붙여넣으세요.</p>
      <pre className="log-box manifest">{model.slackManifest ?? "manifest 생성 중…"}</pre>
      <div className="button-row left">
        <button
          className="btn"
          onClick={() => model.slackManifest && navigator.clipboard?.writeText(model.slackManifest)}
        >
          📋 복사
        </button>
      </div>
      <h4>토큰 붙여넣기</h4>
      <input className="input" placeholder="Bot User OAuth Token (xoxb-...)" value={bot} onChange={(e) => setBot(e.target.value)} />
      <input className="input" placeholder="App-Level Token (xapp-...)" value={app} onChange={(e) => setApp(e.target.value)} />
      {model.slackVerified && (
        <p className="ok-text">✓ {model.slackVerified.workspace} 연결됨 (봇: {model.slackVerified.bot})</p>
      )}
      <div className="button-row">
        <button className="btn primary" disabled={!botOk || !appOk} onClick={() => onVerify(bot, app)}>
          검증 후 다음 →
        </button>
      </div>
    </div>
  );
}
```

Create `src/steps/DoneStep.tsx`:

```tsx
import type { WizardModel } from "../wizard/model";

export function DoneStep({ model }: { model: WizardModel }) {
  return (
    <div className="centered">
      <div className="emoji">🎉</div>
      <h3>설치 완료</h3>
      <p className="muted">Hermes가 준비되었습니다.</p>
      <div className="check-list left">
        <div className="check-row ok"><span className="check-mark">✓</span> hermes-agent 설치됨</div>
        <div className="check-row ok"><span className="check-mark">✓</span> Codex 인증 {model.codexEmail ? `(${model.codexEmail})` : "완료"}</div>
        <div className={`check-row ${model.slackVerified ? "ok" : "bad"}`}>
          <span className="check-mark">{model.slackVerified ? "✓" : "—"}</span>
          {model.slackVerified ? `Slack: ${model.slackVerified.workspace}` : "Slack 건너뜀"}
        </div>
      </div>
      <p className="muted small links">튜토리얼 보기 · 문제 해결 · GitHub</p>
    </div>
  );
}
```

Replace `src/App.tsx`:

```tsx
import { useState } from "react";
import { initialModel, STEP_ORDER, type UiStepId } from "./wizard/model";
import { navigate } from "./wizard/reducer";
import { EnvStep } from "./steps/EnvStep";
import { InstallStep } from "./steps/InstallStep";
import { CodexStep } from "./steps/CodexStep";
import { SlackStep } from "./steps/SlackStep";
import { DoneStep } from "./steps/DoneStep";

const TITLES: Record<UiStepId, string> = {
  env: "Setup",
  install: "Installing",
  codex: "Codex Auth",
  slack: "Slack",
  done: "Done",
};

export function App() {
  const [model, setModel] = useState(initialModel());
  const stepIdx = STEP_ORDER.indexOf(model.active);

  return (
    <div className="app">
      <div className="nav">Hermes Launcher · {TITLES[model.active]}</div>
      <div className="step-indicator">
        Step {stepIdx + 1} / {STEP_ORDER.length}
      </div>
      <div className="card">
        {model.active === "env" && <EnvStep model={model} />}
        {model.active === "install" && <InstallStep model={model} />}
        {model.active === "codex" && <CodexStep model={model} onOpen={() => {}} />}
        {model.active === "slack" && <SlackStep model={model} onVerify={() => {}} />}
        {model.active === "done" && <DoneStep model={model} />}
      </div>
      <div className="button-row">
        {model.active !== "env" && model.active !== "done" && (
          <button className="btn" onClick={() => setModel(navigate(model, { type: "back" }))}>
            ← 뒤로
          </button>
        )}
        {model.active === "slack" && (
          <button className="btn" onClick={() => setModel(navigate(model, { type: "skip" }))}>
            건너뛰기
          </button>
        )}
        {model.active !== "done" && (
          <button className="btn primary" onClick={() => setModel(navigate(model, { type: "next" }))}>
            다음 →
          </button>
        )}
      </div>
    </div>
  );
}
```

Append to `src/styles.css`:

```css
.nav {
  font-size: 13px;
  color: #aaa;
  padding-bottom: 4px;
  border-bottom: 1px solid #2a2a2a;
}
.step-indicator { font-size: 12px; color: #7c3aed; margin: 12px 0; }
.card { background: #181818; border: 1px solid #2a2a2a; border-radius: 10px; padding: 24px; }
h3 { margin: 0 0 8px; }
h4 { margin: 24px 0 8px; font-size: 14px; }
.muted { color: #888; margin: 0 0 16px; }
.small { font-size: 13px; }
.placeholder { background: #111; border: 1px solid #2a2a2a; border-radius: 6px; padding: 16px; text-align: center; color: #aaa; }
.placeholder.left { text-align: left; }
.check-list { display: flex; flex-direction: column; gap: 8px; }
.check-list.left { text-align: left; }
.check-row { background: #111; border: 1px solid #2a2a2a; border-radius: 6px; padding: 12px 16px; text-align: left; }
.check-row.ok .check-mark { color: #4ade80; }
.check-row.bad .check-mark { color: #f87171; }
.check-mark { margin-right: 8px; font-weight: 700; }
.log-box { background: #0a0a0a; border-radius: 6px; padding: 12px; font-family: ui-monospace, monospace; font-size: 12px; color: #4ade80; text-align: left; white-space: pre-wrap; max-height: 160px; overflow: auto; }
.log-box.manifest { color: #ccc; }
.progress-track { margin-top: 16px; background: #222; border-radius: 4px; overflow: hidden; height: 6px; }
.progress-fill { height: 6px; background: linear-gradient(90deg, #7c3aed, #a855f7); transition: width 0.2s; }
.input { width: 100%; box-sizing: border-box; margin-top: 8px; padding: 10px 12px; background: #111; border: 1px solid #2a2a2a; border-radius: 6px; color: #eee; font-family: ui-monospace, monospace; font-size: 13px; }
.button-row { margin-top: 24px; display: flex; gap: 8px; justify-content: flex-end; }
.button-row.left { justify-content: flex-start; margin-top: 8px; }
.btn { padding: 8px 16px; background: #222; border: 1px solid #3a3a3a; border-radius: 6px; color: #eee; cursor: pointer; font-size: 14px; }
.btn:hover { background: #2a2a2a; }
.btn:disabled { opacity: 0.45; cursor: not-allowed; }
.btn.primary { background: linear-gradient(90deg, #7c3aed, #a855f7); border: none; }
.error-text { color: #f87171; margin-top: 12px; }
.ok-text { color: #4ade80; margin-top: 12px; }
.centered { text-align: center; }
.emoji { font-size: 48px; }
.links { margin-top: 16px; color: #666; }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm test src/steps` then `npm test`(전체) + `npx tsc --noEmit`
Expected: 컴포넌트 테스트 PASS, 전체 PASS, tsc 클린.

- [ ] **Step 5: Commit**

```bash
git add src/steps src/App.tsx src/styles.css
git commit -m "feat(ui): 5-step wizard components + dark vanilla CSS (mockup)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: 프론트엔드 CI

tsc + vitest + build를 CI로 고정.

**Files:**
- Create: `.github/workflows/web.yml`

- [ ] **Step 1: Write the failing test**

(이 Task는 CI 워크플로 추가. "빨강 기준"은 로컬에서 `npm run build`/`npm test`/`npx tsc --noEmit` 중 하나라도 실패하면 그것을 고치는 것.)

- [ ] **Step 2: Run the gate locally**

Run:
```bash
npx tsc --noEmit
npm test
npm run build
```
Expected: 모두 통과. 실패 시 해당 파일 수정.

- [ ] **Step 3: Write the workflow**

Create `.github/workflows/web.yml`:

```yaml
name: web

on:
  push:
    paths:
      - "src/**"
      - "package.json"
      - "package-lock.json"
      - "vite.config.ts"
      - "tsconfig*.json"
      - "index.html"
      - ".github/workflows/web.yml"
  pull_request:
    paths:
      - "src/**"
      - "package.json"
      - ".github/workflows/web.yml"

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npx tsc --noEmit
      - run: npm test
      - run: npm run build
```

- [ ] **Step 4: Verify**

Run: `npm test && npm run build`
Expected: PASS + `dist/` 생성.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/web.yml
git commit -m "ci: frontend tsc + vitest + build workflow

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review

**1. Spec coverage:**
- 5단계 위저드 UI(설계 89~97줄) → Task 6 컴포넌트 + App 셸. ✅
- 위저드 상태머신·단계 전이(설계 99줄 멱등/되돌아가기) → Task 4 `navigate`(next/back/skip). ✅
- JSONL 이벤트→진행률·로그(설계 109~110줄, 196줄 Vitest "위저드 단계 전이") → Task 4 `applyEvent`. ✅
- 토큰 형식 검증(설계 137~139줄, 196줄 "토큰 형식 검증") → Task 3. ✅
- Slack manifest preview/copy(설계 44줄, 130줄) → Task 6 SlackStep. ✅
- Skip 가능(설계 96줄, 142줄) → Task 4 skip + App 버튼. ✅
- 완료 화면 다음 단계(설계 144~147줄) → Task 6 DoneStep. ✅
- **범위 밖(Plan 4)**: 실제 Tauri `invoke`/`Channel` 배선, `app` 피처 빌드, 번들/서명, 스크린샷 튜토리얼, E2E. bridge는 인터페이스+mock까지(Task 5).

**2. Placeholder scan:** 모든 코드 스텝에 실제 코드 포함. Task 7은 CI 워크플로로 코드 스텝이 없음을 명시하고 로컬 게이트를 합격선으로 둠. App의 `onOpen`/`onVerify`가 Plan 3에서는 no-op(`() => {}`)인 것은 의도(실제 bridge 호출은 Plan 4 배선) — SlackStep 자체의 onVerify 콜백 동작은 Task 6 테스트로 검증.

**3. Type/이름 일관성:**
- `Step`/`Level`/`HelperEvent`(types.ts) ↔ Plan 1 스키마 + Plan 2 Rust enum 동일 형태. ✅
- `UiStepId`(env/install/codex/slack/done)와 `uiStepFor` 매핑이 reducer·App·컴포넌트에서 일관. ✅
- `WizardModel`/`StepView` 필드가 reducer·컴포넌트에서 일관(status/progress/log/error, detect/codexEmail/slackManifest/slackVerified). ✅
- `Bridge.runStep/invoke` 시그니처가 mock·(Plan 4)실제에서 공유. ✅
- `validateBotToken/validateAppToken` 반환 `TokenCheck`가 SlackStep에서 일관 사용. ✅

---

## 실행 옵션

**Plan 3 (React 프론트엔드) 작성 완료. 저장 위치: `docs/superpowers/plans/2026-05-20-hermes-launcher-frontend.md`.**

전부 macOS에서 Vitest/tsc/vite build로 검증된다(프론트는 플랫폼 독립). 실제 Tauri 배선·E2E는 Plan 4.

실행 방식: **Subagent-Driven(추천)** 또는 **Inline**.
