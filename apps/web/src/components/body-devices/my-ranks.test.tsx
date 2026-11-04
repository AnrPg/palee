import { fireEvent, render, screen, within } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";

import type { RankStanding } from "@/api/body-devices";

import { myStandings } from "./MyRanksCard";
import { NextRankCard } from "./NextRankCard";

vi.mock("next-intl", () => ({
  useTranslations: () => (key: string, values?: Record<string, unknown>) => (values ? `${key}:${Object.values(values).join(",")}` : key),
}));

const rank = (id: string, position: number, name: string, requirements: Record<string, unknown> = {}) => ({
  id,
  position,
  name,
  color: "blue" as const,
  max_stripes: 4,
  requirements,
  scale_level_slug: null,
});

const next = rank("b", 1, "Μπλε", {
  min_days: 30,
  skills: ["Armbar", "Triangle", "Kimura"],
  skill_ids: ["s1", "s2", "s3"],
  skill_notes: [null, "Κράτα τα γόνατα κλειστά", null],
  skill_videos: [null, null, "javascript:alert(1)"],
});

const standing = {
  ladder: { id: "l", name: "BJJ", discipline: "bjj_grappling", style: "belt", class_type_ids: [], ready_criteria: ["days", "skills"], ranks: [rank("w", 0, "Λευκή"), next] },
  current: { award_id: "a1", rank: rank("w", 0, "Λευκή"), stripes: 1, awarded_on: "2026-01-01" },
  next,
  progress: {
    rank_id: "b",
    days: { done: 12, needed: 30 },
    classes: { done: 4, needed: 50 },
    skills: ["Armbar", "Triangle", "Kimura"],
    skills_checked: [{ skill: "Armbar", skill_id: "s1", checked_on: "2026-10-12", note: null }],
    ready: false,
  },
  history: [],
} as unknown as RankStanding;

describe("myStandings", () => {
  it("keeps the ladders the person has a rank or a history on, and drops malformed ones", () => {
    const none = { ...standing, current: null, history: [] } as unknown as RankStanding;
    expect(myStandings([standing, none, null as unknown as RankStanding])).toEqual([standing]);
    expect(myStandings(undefined)).toEqual([]);
  });
});

describe("NextRankCard (member progress, option Α)", () => {
  it("shows only what the ladder counts, the skills left first and what is done collapsed", () => {
    render(<NextRankCard standing={standing} />);
    const card = screen.getByTestId("next-rank-card");
    expect(within(card).getByText("Μπλε")).toBeInTheDocument();
    // One line per count, never joined with «·».
    expect(within(card).getByText("ranks.my.days:12,30")).toBeInTheDocument();
    expect(within(card).getByText("ranks.skillsDone:1,3")).toBeInTheDocument();
    expect(within(card).queryByText(/ranks.my.classes/)).not.toBeInTheDocument();
    expect(within(card).getByText("Triangle")).toBeInTheDocument();
    expect(within(card).getByText("Κράτα τα γόνατα κλειστά")).toBeInTheDocument();
    // Only https video links become links.
    expect(within(card).queryByText("ranks.my.openVideo")).not.toBeInTheDocument();
    const have = within(card).getByRole("button", { name: /ranks.my.have/ });
    expect(have).toHaveAttribute("aria-expanded", "false");
    fireEvent.click(have);
    expect(have).toHaveAttribute("aria-expanded", "true");
  });

  it("is empty at the top of the ladder", () => {
    const { container } = render(<NextRankCard standing={{ ...standing, next: null } as RankStanding} />);
    expect(container).toBeEmptyDOMElement();
  });
});
