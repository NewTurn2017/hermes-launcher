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
