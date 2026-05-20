export type TokenCheck = { ok: true } | { ok: false; reason: string };

export function validateBotToken(token: string): TokenCheck {
  const t = token.trim();
  if (!t.startsWith("xoxb-")) {
    return { ok: false, reason: "Bot 토큰은 xoxb- 로 시작해야 합니다" };
  }
  if (t.length < 10) {
    return { ok: false, reason: "Bot 토큰이 너무 짧습니다" };
  }
  return { ok: true };
}

export function validateAppToken(token: string): TokenCheck {
  const t = token.trim();
  if (!t.startsWith("xapp-")) {
    return { ok: false, reason: "App-Level 토큰은 xapp- 로 시작해야 합니다" };
  }
  if (t.length < 10) {
    return { ok: false, reason: "App-Level 토큰이 너무 짧습니다" };
  }
  return { ok: true };
}
