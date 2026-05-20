import { describe, it, expect, vi } from "vitest";
import { makeMockBridge } from "./bridge";
import type { HelperEvent } from "./types";

describe("mock bridge", () => {
  it("runStep streams the scripted events to the listener", async () => {
    const scripted: HelperEvent[] = [
      { event: "step", step: "install-hermes", progress: 50, msg: "x" },
      { event: "done", step: "install-hermes", ok: true },
    ];
    const bridge = makeMockBridge({ "install-hermes": scripted });
    const seen: HelperEvent[] = [];
    await bridge.runStep("install-hermes", [], (ev) => seen.push(ev));
    expect(seen).toEqual(scripted);
  });

  it("invoke resolves with the configured handler result", async () => {
    const bridge = makeMockBridge({}, { set_step: vi.fn().mockResolvedValue(undefined) });
    await expect(bridge.invoke("set_step", { step: "env", status: "ok" })).resolves.toBeUndefined();
  });
});
