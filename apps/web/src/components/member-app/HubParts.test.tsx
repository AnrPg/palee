import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { HubButton } from "./HubParts";

describe("HubButton", () => {
  it("keeps its label on one centred line and grows inside a wrapping row (ANR 2026-11-02)", () => {
    render(<HubButton href="/me/payments">Συνδρομή & πληρωμές</HubButton>);
    const link = screen.getByRole("link", { name: "Συνδρομή & πληρωμές" });
    expect(link.className).toContain("whitespace-nowrap");
    expect(link.className).toContain("text-center");
    expect(link.className).toContain("flex-auto");
  });
});
