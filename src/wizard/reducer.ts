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
      const { event: _event, ...info } = ev;
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
      return patchStep(
        { ...model, slackVerified: { workspace: ev.workspace, bot: ev.bot } },
        "slack",
        { status: "ok" },
      );
    case "slack_error":
      return patchStep(model, "slack", { status: "failed", error: ev.detail });
  }
}

export type NavAction = { type: "next" } | { type: "back" } | { type: "skip" };

const COMPLETE = new Set(["ok", "skipped"]);

/** Whether the active step is finished, so "다음" may advance. */
export function canAdvance(model: WizardModel): boolean {
  return COMPLETE.has(model.steps[model.active].status);
}

/** Whether the active step is mid-run — used to block navigating away. */
export function isRunning(model: WizardModel): boolean {
  return model.steps[model.active].status === "running";
}

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
