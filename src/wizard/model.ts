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
