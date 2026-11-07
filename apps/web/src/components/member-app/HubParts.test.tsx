import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { HubActionTile, HubButton } from "./HubParts";

describe("HubButton", () => {
  it("keeps its label on one centred line and grows inside a wrapping row (ANR 2026-11-02)", () => {
    render(<HubButton href="/me/payments">Συνδρομή & πληρωμές</HubButton>);
    const link = screen.getByRole("link", { name: "Συνδρομή & πληρωμές" });
    expect(link.className).toContain("whitespace-nowrap");
    expect(link.className).toContain("text-center");
    expect(link.className).toContain("flex-auto");
  });
});

describe("HubActionTile", () => {
  it("is a link while open, and a greyed, locked, unpressable tile while access is closed (ADR-551, mockup 3 B)", () => {
    const { rerender } = render(<HubActionTile href="/box/workouts" label="My workouts" icon={null} />);
    expect(screen.getByRole("link", { name: "My workouts" })).toHaveAttribute("href", "/box/workouts");

    rerender(<HubActionTile href="/box/workouts" label="My workouts" icon={null} lockedLabel="Opens once your membership is active" />);
    const tile = screen.getByRole("link", { name: "My workouts. Opens once your membership is active" });
    expect(tile).not.toHaveAttribute("href");
    expect(tile).toHaveAttribute("aria-disabled", "true");
    expect(tile.querySelector("svg")).not.toBeNull();
  });
});
