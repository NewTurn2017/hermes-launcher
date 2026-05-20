import { describe, it, expect, vi, beforeEach } from "vitest";

// vi.mock is hoisted above imports, so the factory's dependencies must be
// hoisted too (vi.hoisted) and the fake Channel defined inside the factory.
const { invokeMock } = vi.hoisted(() => ({ invokeMock: vi.fn() }));
vi.mock("@tauri-apps/api/core", () => {
  class FakeChannel<T> {
    onmessage: (m: T) => void = () => {};
  }
  return {
    invoke: (...a: unknown[]) => invokeMock(...a),
    Channel: FakeChannel,
  };
});

import { makeTauriBridge } from "./bridge";
import type { HelperEvent } from "./types";

beforeEach(() => invokeMock.mockReset());

describe("tauri bridge", () => {
  it("runStep wires a Channel and invokes run_step", async () => {
    invokeMock.mockResolvedValue(undefined);
    const bridge = makeTauriBridge();
    const seen: HelperEvent[] = [];
    const p = bridge.runStep("detect", [], (ev) => seen.push(ev));
    const arg = invokeMock.mock.calls[0][1] as {
      onEvent: { onmessage: (m: HelperEvent) => void };
    };
    arg.onEvent.onmessage({ event: "done", step: "detect", ok: true });
    await p;
    expect(invokeMock).toHaveBeenCalledWith(
      "run_step",
      expect.objectContaining({ subcommand: "detect" }),
    );
    expect(seen).toEqual([{ event: "done", step: "detect", ok: true }]);
  });

  it("invoke delegates to tauri invoke", async () => {
    invokeMock.mockResolvedValue("ok");
    const bridge = makeTauriBridge();
    await expect(bridge.invoke("set_step", { step: "env", status: "ok" })).resolves.toBe("ok");
    expect(invokeMock).toHaveBeenCalledWith("set_step", { step: "env", status: "ok" });
  });
});
