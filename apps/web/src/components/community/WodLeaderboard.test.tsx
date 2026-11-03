import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import type { WorkoutLeaderboard } from "@/api/training-floor";

import { WodLeaderboard } from "./WodLeaderboard";

const fetchWorkoutLeaderboard = vi.fn();

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string, values?: Record<string, unknown>) =>
    values ? `${key}:${Object.values(values).join(",")}` : key,
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({
    memberships: [{ organization: { id: "org", slug: "box" }, home_location_id: "loc-1" }],
  }),
}));
vi.mock("@/api/training-floor", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/training-floor")>()),
  fetchWorkoutLeaderboard: (...args: unknown[]) => fetchWorkoutLeaderboard(...args),
}));

const row = (overrides: Partial<WorkoutLeaderboard["rows"][number]>) => ({
  user_id: "u",
  me: false,
  nickname: "Nikos",
  rank: 1,
  percentile: null,
  top_percent: null,
  value: "3:10",
  unit: null,
  scale_level_slug: "rx",
  avatar_url: null,
  ...overrides,
});

function board(overrides: Partial<WorkoutLeaderboard> = {}): WorkoutLeaderboard {
  const me = row({ user_id: "me", me: true, nickname: "Maria", rank: 2, percentile: 80, top_percent: 15, value: "3:30" });
  return {
    opted_in: true,
    filters: { date: "2026-11-02", window: "day", scope: "box", buddies: false },
    me,
    rows: [row({ user_id: "u1" }), me],
    total: 12,
    profile: { division: "women", birth_year: 1989 },
    options: {
      age_groups: ["35_39"],
      divisions: ["women", "men"],
      scales: [{ slug: "rx", label: "RX" }],
      scopes: ["box", "branch"],
      windows: ["day", "week", "month", "year", "all"],
    },
    ...overrides,
  } as WorkoutLeaderboard;
}

function renderBoard() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  return render(<WodLeaderboard slug="box" workoutId="w1" date="2026-11-02" fallback={<p>old list</p>} />, { wrapper });
}

describe("WodLeaderboard (ADR-356, mockup d2 A)", () => {
  beforeEach(() => fetchWorkoutLeaderboard.mockReset());

  it("keeps the card's own list for someone who did not opt in", async () => {
    fetchWorkoutLeaderboard.mockResolvedValue(board({ opted_in: false, rows: [], me: null }));
    renderBoard();
    await waitFor(() => expect(fetchWorkoutLeaderboard).toHaveBeenCalled());
    expect(screen.getByText("old list")).toBeInTheDocument();
    expect(screen.queryByTestId("wod-leaderboard")).toBeNull();
  });

  it("shows the viewer's own chips and the percentile only on their row", async () => {
    fetchWorkoutLeaderboard.mockResolvedValue(board());
    renderBoard();
    const chips = await screen.findByRole("group", { name: "lbChipsAria" });
    expect(Array.from(chips.querySelectorAll("button")).map((button) => button.textContent)).toEqual([
      "lbChipAll",
      "division_women",
      "35–39",
      "RX",
    ]);
    expect(screen.getByRole("button", { name: "lbChipAll" })).toHaveAttribute("aria-pressed", "true");
    const own = screen.getByTestId("wod-leaderboard-me");
    expect(own).toHaveTextContent("lbTopPercent:15");
    expect(own).toHaveTextContent("lbBetterThan:80");
    expect(screen.getAllByText(/lbTopPercent/)).toHaveLength(1);
    expect(screen.queryByText("lbProfileLink")).toBeNull();
  });

  it("asks the API for the slice a chip picks", async () => {
    fetchWorkoutLeaderboard.mockResolvedValue(board());
    renderBoard();
    fireEvent.click(await screen.findByRole("button", { name: "division_women" }));
    await waitFor(() =>
      expect(fetchWorkoutLeaderboard).toHaveBeenLastCalledWith("tok", "box", "w1", expect.objectContaining({ division: "women" })),
    );
  });

  it("keeps the time window, branch and buddies under «Προχωρημένα»", async () => {
    fetchWorkoutLeaderboard.mockResolvedValue(board());
    renderBoard();
    const advanced = await screen.findByTestId("wod-leaderboard-advanced");
    expect(advanced).toBeInTheDocument();
    expect(screen.queryByRole("radiogroup", { name: "lbWindow" })).toBeNull();
  });

  it("without a score yet, says so in the viewer's place and points to the profile", async () => {
    fetchWorkoutLeaderboard.mockResolvedValue(board({ me: null, rows: [row({ user_id: "u1" })], profile: null }));
    renderBoard();
    expect(await screen.findByText("lbNoScore")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "lbProfileLink" })).toHaveAttribute("href", "/me/sharing#leaderboard");
  });
});
