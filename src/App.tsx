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
  env: "Setup",
  install: "Installing",
  codex: "Codex Auth",
  slack: "Slack",
  done: "Done",
};

export function App({ bridge }: { bridge?: Bridge }) {
  const br = useRef<Bridge>(bridge ?? makeTauriBridge()).current;
  const [model, setModel] = useState(initialModel());
  const stepIdx = STEP_ORDER.indexOf(model.active);

  const runStep = (sub: string, args: string[] = []) =>
    br.runStep(sub, args, (ev) => setModel((m) => applyEvent(m, ev)));

  // Run env detection once on mount.
  useEffect(() => {
    void br.runStep("detect", [], (ev) => setModel((m) => applyEvent(m, ev)));
  }, [br]);

  return (
    <div className="app">
      <div className="nav">Hermes Launcher · {TITLES[model.active]}</div>
      <div className="step-indicator">
        Step {stepIdx + 1} / {STEP_ORDER.length}
      </div>
      <div className="card">
        {model.active === "env" && <EnvStep model={model} />}
        {model.active === "install" && <InstallStep model={model} />}
        {model.active === "codex" && (
          <CodexStep model={model} onOpen={() => void runStep("codex-login")} />
        )}
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
          <button
            className="btn primary"
            onClick={() => {
              const next = navigate(model, { type: "next" });
              setModel(next);
              if (model.active === "env" && next.active === "install") void runStep("install-hermes");
              if (model.active === "codex" && next.active === "slack") void runStep("slack-manifest");
            }}
          >
            다음 →
          </button>
        )}
      </div>
    </div>
  );
}
