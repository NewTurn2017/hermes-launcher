import { describe, it, expect } from "vitest";
import { initialModel, type WizardModel } from "./model";
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
    let m = applyEvent(initialModel(), { event: "slack_manifest", json: '{"a":1}' });
    expect(m.slackManifest).toBe('{"a":1}');
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
      internet: true,
      python3: true,
      wslview: true,
      cmd_exe: true,
      hermes_installed: false,
      codex_installed: true,
      codex_authed: false,
    });
    m = navigate(m, { type: "next" });
    expect(m.active).toBe("install");
  });

  it("back moves to previous step", () => {
    let m: WizardModel = { ...initialModel(), active: "codex" };
    m = navigate(m, { type: "back" });
    expect(m.active).toBe("install");
  });

  it("skip marks slack skipped and advances to done", () => {
    let m: WizardModel = { ...initialModel(), active: "slack" };
    m = navigate(m, { type: "skip" });
    expect(m.steps.slack.status).toBe("skipped");
    expect(m.active).toBe("done");
  });
});
