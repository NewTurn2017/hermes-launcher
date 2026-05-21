import { useState } from "react";
import type { WizardModel } from "../wizard/model";
import { validateAppToken, validateBotToken, validateSigningSecret } from "../wizard/tokens";

export function SlackStep({
  model,
  onVerify,
}: {
  model: WizardModel;
  onVerify: (bot: string, signing: string, app: string) => void;
}) {
  const [bot, setBot] = useState("");
  const [signing, setSigning] = useState("");
  const [app, setApp] = useState("");
  const botOk = validateBotToken(bot).ok;
  const signingOk = validateSigningSecret(signing).ok;
  const appOk = validateAppToken(app).ok;
  return (
    <div>
      <h3>Slack 앱 만들기</h3>
      <p className="muted">
        아래 manifest를 복사해 api.slack.com/apps/new 의 "From a manifest"에 붙여넣으세요.
      </p>
      <pre className="log-box manifest">{model.slackManifest ?? "manifest 생성 중…"}</pre>
      <div className="button-row left">
        <button
          className="btn"
          onClick={() =>
            model.slackManifest && navigator.clipboard?.writeText(model.slackManifest)
          }
        >
          📋 복사
        </button>
      </div>
      <h4>토큰 붙여넣기</h4>
      <input
        className="input"
        placeholder="Bot User OAuth Token (xoxb-...)"
        value={bot}
        onChange={(e) => setBot(e.target.value)}
      />
      <input
        className="input"
        placeholder="Signing Secret (32 hex)"
        value={signing}
        onChange={(e) => setSigning(e.target.value)}
      />
      <input
        className="input"
        placeholder="App-Level Token (xapp-...)"
        value={app}
        onChange={(e) => setApp(e.target.value)}
      />
      {model.slackVerified && (
        <p className="ok-text">
          ✓ {model.slackVerified.workspace} 연결됨 (봇: {model.slackVerified.bot})
        </p>
      )}
      <div className="button-row">
        <button
          className="btn primary"
          disabled={!botOk || !signingOk || !appOk}
          onClick={() => onVerify(bot, signing, app)}
        >
          검증 후 다음 →
        </button>
      </div>
    </div>
  );
}
