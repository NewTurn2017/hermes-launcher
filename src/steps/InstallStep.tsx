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
