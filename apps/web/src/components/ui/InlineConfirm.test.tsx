import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { InlineConfirm } from "./InlineConfirm";

describe("ui/InlineConfirm", () => {
  it("asks a named question with keep and the step, and marks itself for host rows", () => {
    const cancel = vi.fn();
    const confirm = vi.fn();
    render(
      <InlineConfirm
        question="Να σταματήσεις να ακολουθείς το box;"
        cancelLabel="Άκυρο"
        confirmLabel="Άρση ακολούθησης"
        onCancel={cancel}
        onConfirm={confirm}
      />,
    );
    const group = screen.getByRole("group", { name: "Να σταματήσεις να ακολουθείς το box;" });
    expect(group).toHaveAttribute("data-inline-confirm");
    // The buttons sit in a row that wraps, so a long pair stacks on a narrow phone.
    expect(screen.getByRole("button", { name: "Άκυρο" }).parentElement).toHaveClass("flex-wrap");
    expect(screen.getByRole("button", { name: "Άρση ακολούθησης" })).toHaveStyle({ background: "var(--danger)" });

    fireEvent.click(screen.getByRole("button", { name: "Άκυρο" }));
    fireEvent.click(screen.getByRole("button", { name: "Άρση ακολούθησης" }));
    expect(cancel).toHaveBeenCalledOnce();
    expect(confirm).toHaveBeenCalledOnce();
  });

  it("blocks the step while busy and paints a safe step in the primary colour", () => {
    render(<InlineConfirm question="Νέος κωδικός;" cancelLabel="Άκυρο" confirmLabel="Νέος" tone="primary" busy framed onCancel={() => undefined} onConfirm={() => undefined} />);
    const step = screen.getByRole("button", { name: "Νέος" });
    expect(step).toBeDisabled();
    expect(step).toHaveStyle({ background: "var(--primary)" });
  });
});
