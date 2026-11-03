import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { RankStanding } from "@/api/body-devices";

import { ClientRanks } from "./ClientRanks";
import { ladderBody } from "./RankLaddersSettings";

const fetchClientRanks = vi.fn();
const awardRank = vi.fn();
const revokeRankAward = vi.fn();

vi.mock("next-intl", () => ({
  useLocale: () => "el",
  useTranslations: () => (key: string, values?: Record<string, unknown>) => (values ? `${key}:${Object.values(values).join(",")}` : key),
}));
vi.mock("@/api/body-devices", () => ({
  clientRanksKey: (slug: string, userId: string) => ["body-devices", "client-ranks", slug, userId],
  fetchClientRanks: (...args: unknown[]) => fetchClientRanks(...args),
  awardRank: (...args: unknown[]) => awardRank(...args),
  revokeRankAward: (...args: unknown[]) => revokeRankAward(...args),
  fetchClientDiploma: vi.fn(),
}));

const rank = (id: string, name: string, skills: string[] = []) => ({
  id,
  position: 0,
  name,
  color: "blue" as const,
  max_stripes: 4,
  requirements: skills.length ? { skills } : {},
  scale_level_slug: null,
});

const standing: RankStanding = {
  ladder: { id: "l", name: "BJJ", discipline: "bjj_grappling", style: "belt", class_type_ids: [], ranks: [rank("w", "Λευκή"), rank("b", "Μπλε", ["Armbar"])] },
  current: { award_id: "a1", rank: rank("w", "Λευκή"), stripes: 2, awarded_on: "2025-03-01" },
  next: rank("b", "Μπλε", ["Armbar"]),
  progress: { rank_id: "b", classes: { done: 80, needed: 80 }, days: { done: 730, needed: 730 }, skills: [], ready: true },
  history: [],
} as RankStanding;

function renderClient() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  render(<ClientRanks token="tok" slug="box" userId="u1" nickname="Μαρία" frame={(content) => content} />, { wrapper });
}

describe("ladderBody (mockup e2setup A)", () => {
  it("trims names, splits skills and leaves empty requirements out", () => {
    const body = ladderBody({
      name: " BJJ ",
      discipline: "bjj_grappling",
      class_type_ids: [],
      ranks: [
        { id: "r1", name: " Λευκή ", color: "white", max_stripes: 4, min_days: null, min_classes: null, skills: "", scale_level_slug: null },
        { name: "Μπλε", color: "blue", max_stripes: 4, min_days: 730, min_classes: 150, skills: "Armbar, , Triangle", scale_level_slug: "rx" },
      ],
    });
    expect(body.name).toBe("BJJ");
    expect(body.ranks[0]).toEqual({ id: "r1", name: "Λευκή", color: "white", max_stripes: 4, scale_level_slug: null, requirements: {} });
    expect(body.ranks[1]).toEqual({
      name: "Μπλε",
      color: "blue",
      max_stripes: 4,
      scale_level_slug: "rx",
      requirements: { min_days: 730, min_classes: 150, skills: ["Armbar", "Triangle"] },
    });
  });
});

describe("ClientRanks (mockup e2coach A)", () => {
  beforeEach(() => {
    fetchClientRanks.mockReset().mockResolvedValue({ ladders: [standing] });
    awardRank.mockReset().mockResolvedValue({});
    revokeRankAward.mockReset().mockResolvedValue({});
  });

  it("shows «Έτοιμος» as information and promotes to the next rank with the checked skills", async () => {
    renderClient();
    expect(await screen.findByText("ranks.ready")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "ranks.promote" }));
    const sheet = await screen.findByTestId("promote-sheet");
    expect(within(sheet).getByRole("button", { name: /ranks.plusStripe:3/ })).toHaveAttribute("aria-pressed", "true");
    fireEvent.click(within(sheet).getByRole("button", { name: /Μπλε/ }));
    fireEvent.click(within(sheet).getByRole("button", { name: "Armbar" }));
    const buttons = within(sheet).getAllByRole("button", { name: "ranks.promote" });
    fireEvent.click(buttons[buttons.length - 1]);
    await waitFor(() =>
      expect(awardRank).toHaveBeenCalledWith("tok", "box", "u1", expect.objectContaining({ ladder_id: "l", rank_id: "b", stripes: 0, skills_checked: ["Armbar"] })),
    );
  });

  it("asks for a reason before withdrawing an award", async () => {
    renderClient();
    fireEvent.click(await screen.findByRole("button", { name: "ranks.withdraw" }));
    const confirm = screen.getAllByRole("button", { name: "ranks.withdraw" });
    fireEvent.click(confirm[confirm.length - 1]);
    expect(screen.getByText("ranks.withdrawReasonRequired")).toBeInTheDocument();
    expect(revokeRankAward).not.toHaveBeenCalled();
    fireEvent.change(screen.getByLabelText(/ranks.withdrawReason/), { target: { value: "Λάθος καταχώριση" } });
    fireEvent.click(confirm[confirm.length - 1]);
    await waitFor(() => expect(revokeRankAward).toHaveBeenCalledWith("tok", "box", "a1", "Λάθος καταχώριση"));
  });
});
