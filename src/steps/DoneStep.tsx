import type { WizardModel } from "../wizard/model";

export function DoneStep({ model }: { model: WizardModel }) {
  return (
    <div className="centered">
      <div className="emoji">🎉</div>
      <h3>설치 완료</h3>
      <p className="muted">Hermes가 준비되었습니다.</p>
      <div className="check-list left">
        <div className="check-row ok">
          <span className="check-mark">✓</span> hermes-agent 설치됨
        </div>
        <div className="check-row ok">
          <span className="check-mark">✓</span> Codex 인증{" "}
          {model.codexEmail ? `(${model.codexEmail})` : "완료"}
        </div>
        <div className={`check-row ${model.slackVerified ? "ok" : "bad"}`}>
          <span className="check-mark">{model.slackVerified ? "✓" : "—"}</span>
          {model.slackVerified ? `Slack: ${model.slackVerified.workspace}` : "Slack 건너뜀"}
        </div>
      </div>
      <p className="muted small links">튜토리얼 보기 · 문제 해결 · GitHub</p>
    </div>
  );
}
