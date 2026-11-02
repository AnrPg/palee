import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import type { ClassVisitPerson } from "@/api/training-floor";

import { DayAssignmentTagBadge } from "./DayAssignmentTagBadge";
import { NewTodayCard, VisitBadgeChips } from "./VisitBadges";

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${Object.values(values).join(",")}` : key,
}));

const person = (booking_id: string, badges: ClassVisitPerson["badges"], via: ClassVisitPerson["via"] = null): ClassVisitPerson => ({
  booking_id,
  user_id: booking_id,
  badges,
  via,
  brought_by: null,
  guest_name: null,
});

describe("visit badges (ADR-359, mockup e1 B)", () => {
  it("says who is new in words, and how they came as one chip", () => {
    render(<VisitBadgeChips badges={["first_visit", "came_via_referral"]} via={{ kind: "referral", by_nickname: "Maria" } as ClassVisitPerson["via"]} />);
    const chips = screen.getByTestId("visit-badges");
    expect(chips).toHaveTextContent("badgeFirstVisit");
    expect(chips).toHaveTextContent("viaMember:Maria");
    expect(chips).not.toHaveTextContent("badgeViaReferral");
  });

  it("leaves out the trial a roster row already tags, and shows nothing when nothing is left", () => {
    const { container } = render(<VisitBadgeChips badges={["trial"]} skipTrial />);
    expect(container).toBeEmptyDOMElement();
  });

  it("puts «Νέοι σήμερα» on top with a plural count, and hides it when nobody is new", () => {
    const people = [person("b1", ["first_visit"]), person("b2", ["trial"])];
    const { rerender } = render(<NewTodayCard people={people} nameFor={(entry) => `Name ${entry.booking_id}`} />);
    expect(screen.getByRole("heading", { name: "newTodayTitle:2" })).toBeInTheDocument();
    expect(screen.getByText("Name b1")).toBeInTheDocument();
    rerender(<NewTodayCard people={[]} nameFor={() => "x"} />);
    expect(screen.queryByTestId("new-today")).toBeNull();
  });
});

describe("day tag (ADR-357, mockup d3 A)", () => {
  it("says «Μερικά με WOD · 1/3» in words", () => {
    render(<DayAssignmentTagBadge day={{ date: "2026-11-02", tag: "mixed", classes: 3, with_wod: 1 }} />);
    expect(screen.getByTestId("day-tag-2026-11-02")).toHaveTextContent("dayTagMixed:1,3");
  });

  it("a day without classes is plain text", () => {
    render(<DayAssignmentTagBadge day={{ date: "2026-11-03", tag: "none", classes: 0, with_wod: 0 }} compact />);
    expect(screen.getByTestId("day-tag-2026-11-03")).toHaveTextContent("dayTagNone");
  });
});
