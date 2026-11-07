import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import { SectionTabs } from "./SectionTabs";

vi.mock("next/link", () => ({
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  default: ({ href, children, ...rest }: any) => (
    <a href={href} {...{ ...rest, prefetch: undefined }}>
      {children}
    </a>
  ),
}));

describe("SectionTabs", () => {
  it("shows a locked tab greyed with a lock, and not as a link (ADR-551, mockup 3 B)", () => {
    render(
      <SectionTabs
        group={{
          id: "box",
          tabs: [
            { id: "boxToday", href: "/box", labelKey: "today", match: [] },
            { id: "myWorkouts", href: "/box/workouts", labelKey: "myWorkouts", match: ["/box/workouts"], locked: true },
          ],
        }}
        pathname="/box/schedule"
        hrefFor={(href) => href}
        labelFor={(key) => key}
        lockedLabel="Opens once your membership is active"
      />,
    );
    expect(screen.getByRole("link", { name: "today" })).toHaveAttribute("href", "/box");
    const locked = screen.getByRole("link", { name: "myWorkouts. Opens once your membership is active" });
    expect(locked).not.toHaveAttribute("href");
    expect(locked).toHaveAttribute("aria-disabled", "true");
  });
});
