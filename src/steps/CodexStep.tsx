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
            <span className="muted small">
              인증을 완료하면 자동으로 다음 단계로 넘어갑니다 (최대 5분)
            </span>
          </>
        )}
      </div>
      {s.error && <p className="error-text">{s.error}</p>}
      <div className="button-row">
        <button className="btn" onClick={onOpen}>
          브라우저 다시 열기
        </button>
      </div>
    </div>
  );
}
