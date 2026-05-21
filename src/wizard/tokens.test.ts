import { describe, it, expect } from "vitest";
import { validateAppToken, validateBotToken, validateSigningSecret } from "./tokens";

describe("token validation", () => {
  it("accepts well-formed bot token", () => {
    expect(validateBotToken("xoxb-123-456-abcDEF")).toEqual({ ok: true });
  });
  it("rejects bot token with wrong prefix", () => {
    const r = validateBotToken("xapp-123");
    expect(r.ok).toBe(false);
    expect((r as { ok: false; reason: string }).reason).toMatch(/xoxb-/);
  });
  it("rejects empty/short bot token", () => {
    expect(validateBotToken("").ok).toBe(false);
    expect(validateBotToken("xoxb-").ok).toBe(false);
  });
  it("accepts well-formed app token and rejects wrong prefix", () => {
    expect(validateAppToken("xapp-1-A0B1-2345-deadbeef")).toEqual({ ok: true });
    expect(validateAppToken("xoxb-1").ok).toBe(false);
  });
  it("accepts 32-hex signing secret and rejects other values", () => {
    expect(validateSigningSecret("a".repeat(32))).toEqual({ ok: true });
    expect(validateSigningSecret("not-hex").ok).toBe(false);
  });
});
