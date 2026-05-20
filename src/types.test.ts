import { describe, it, expect } from "vitest";
import type { HelperEvent } from "./types";
import { isHelperEvent } from "./types";

describe("HelperEvent guard", () => {
  it("accepts known event objects", () => {
    const ev: HelperEvent = { event: "step", step: "install-hermes", progress: 42, msg: "x" };
    expect(isHelperEvent(ev)).toBe(true);
    expect(isHelperEvent({ event: "codex_aborted" })).toBe(true);
    expect(isHelperEvent({ event: "done", step: "verify", ok: true })).toBe(true);
  });

  it("rejects non-events", () => {
    expect(isHelperEvent({ event: "explode" })).toBe(false);
    expect(isHelperEvent(null)).toBe(false);
    expect(isHelperEvent({ foo: 1 })).toBe(false);
  });
});
