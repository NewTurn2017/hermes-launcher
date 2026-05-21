import { describe, it, expect } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { App } from "./App";
import { makeMockBridge } from "./bridge";

describe("App wiring", () => {
  it("runs detect on mount and renders env checks", async () => {
    const bridge = makeMockBridge({
      detect: [
        {
          event: "detect",
          internet: true,
          python3: true,
          wslview: true,
          cmd_exe: true,
          hermes_installed: false,
          hpk_installed: true,
          codex_installed: true,
          codex_authed: false,
        },
      ],
    });
    render(<App bridge={bridge} />);
    await waitFor(() => expect(screen.getByText(/인터넷 연결/)).toBeInTheDocument());
  });
});
