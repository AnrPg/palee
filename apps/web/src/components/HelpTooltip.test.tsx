import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

vi.mock("@/i18n/ui", () => ({ useUiTranslations: () => (key: string) => key }));

import { HelpPopover, HelpTooltip } from "@/components/HelpTooltip";
import { HelpIcon } from "@/components/InfoModal";

// ANR 2026-11-04: every «?» infobox trigger is subtle, on laptops and phones:
// no fill, no accent colour, only neutral theme tokens.
function expectSubtle(button: HTMLElement) {
  const style = button.getAttribute("style") ?? "";
  expect(style).not.toMatch(/--primary|--spark|--heat/);
  expect(button.style.background).toBe("transparent");
  expect(button.style.border).toContain("var(--border-strong)");
  expect(button.className).toContain("text-[var(--muted)]");
}

describe("help icons", () => {
  it("keeps the popover trigger subtle", () => {
    render(<HelpPopover label="Completion rate">Text</HelpPopover>);
    expectSubtle(screen.getByRole("button", { name: "Completion rate" }));
  });

  it("keeps the tooltip trigger subtle", () => {
    render(<HelpTooltip label="What is this">Text</HelpTooltip>);
    expectSubtle(screen.getByRole("button", { name: "What is this" }));
  });

  it("keeps the info-modal trigger subtle", () => {
    render(<HelpIcon tooltip="Totals" onClick={() => {}} />);
    expectSubtle(screen.getByRole("button", { name: "infoWithText" }));
  });
});
