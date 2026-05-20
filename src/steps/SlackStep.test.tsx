import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { SlackStep } from "./SlackStep";
import { initialModel } from "../wizard/model";

describe("SlackStep", () => {
  it("disables verify until both tokens have valid prefixes", () => {
    const onVerify = vi.fn();
    render(<SlackStep model={initialModel()} onVerify={onVerify} />);
    const verify = screen.getByRole("button", { name: /검증/ });
    expect(verify).toBeDisabled();

    fireEvent.change(screen.getByPlaceholderText(/xoxb-/), {
      target: { value: "xoxb-123456789" },
    });
    fireEvent.change(screen.getByPlaceholderText(/xapp-/), {
      target: { value: "xapp-123456789" },
    });
    expect(verify).toBeEnabled();
    fireEvent.click(verify);
    expect(onVerify).toHaveBeenCalledWith("xoxb-123456789", "xapp-123456789");
  });
});
