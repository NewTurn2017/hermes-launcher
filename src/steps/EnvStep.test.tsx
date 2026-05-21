import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { EnvStep } from "./EnvStep";
import { initialModel } from "../wizard/model";
import { applyEvent } from "../wizard/reducer";

describe("EnvStep", () => {
  it("shows check rows from detect info", () => {
    const m = applyEvent(initialModel(), {
      event: "detect",
      internet: true,
      python3: true,
      wslview: true,
      cmd_exe: true,
      hermes_installed: false,
      codex_installed: true,
      codex_authed: false,
    });
    render(<EnvStep model={m} />);
    expect(screen.getByText(/인터넷 연결/)).toBeInTheDocument();
    expect(screen.getByText(/WSL 브라우저 연동/)).toBeInTheDocument();
  });

  it("surfaces a detect error instead of hanging on the placeholder", () => {
    const m = applyEvent(initialModel(), {
      event: "error",
      step: "detect",
      level: "environment",
      detail: "WSL distro를 찾을 수 없습니다",
    });
    render(<EnvStep model={m} />);
    expect(screen.getByText(/WSL distro를 찾을 수 없습니다/)).toBeInTheDocument();
    expect(screen.queryByText(/점검하는 중/)).not.toBeInTheDocument();
  });
});
