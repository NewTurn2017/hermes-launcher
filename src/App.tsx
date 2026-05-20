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
