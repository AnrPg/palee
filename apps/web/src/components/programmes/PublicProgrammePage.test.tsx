import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, within } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

const api = vi.hoisted(() => ({ fetchPublicProgramme: vi.fn() }));
const platform = vi.hoisted(() => ({ native: null as null | "ios" }));
vi.mock("@/api/programmes", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/lib/platform", async (original) => ({ ...(await original<object>()), nativePlatform: () => platform.native }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ status: "guest", tokens: null }) }));

import { PublicProgrammePage } from "./PublicProgrammePage";

const programme = {
  id: "p1",
  title: "Δύναμη σε 6 εβδομάδες",
  goal: "strength",
  level: "intermediate",
  price_cents: 3900,
  currency: "EUR",
  weeks: 6,
  sessions_per_week: 4,
  minutes_per_session: 45,
  main_equipment: ["barbell"],
  refund_policy: "before_start",
  cover_url: null,
  reviews: { average: 4.8, count: 23 },
  latest_reviews: [{ id: "r1", rating: 5, status: "published", version_number: 1, body: "Ανέβασα 15 κιλά στο squat.", author: { nickname: "Νίκος Π." } }],
  preview: [
    { day: 0, week: 1, weekday: 0, title: "Back squat 5×5" },
    { day: 1, week: 1, weekday: 1, title: "Fran" },
  ],
  coach_name: "Μαρία Κ.",
  week_outline: [1, 2, 3, 4, 5, 6].map((week) => ({
    week,
    sessions: 4,
    days: [0, 1, 2, 3, 4, 5, 6].map((weekday) => {
      const day = (week - 1) * 7 + weekday;
      const rest = [2, 4, 6].includes(weekday);
      return { day, weekday, rest, preview: day < 2, workout_type: rest ? null : weekday === 3 ? "strength" : null, minutes: rest ? null : weekday === 3 ? 50 : null };
    }),
  })),
};

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <PublicProgrammePage slug="akropoli" id="p1" />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

// Board 2κ/2μ A: facts, free days, reviews before the plan, week accordions, FAQ, buy bar.
describe("PublicProgrammePage", () => {
  beforeEach(() => {
    api.fetchPublicProgramme.mockReset();
    platform.native = null;
    Element.prototype.scrollIntoView = vi.fn();
  });

  it("shows the facts, the free days, the reviews before the weeks and the FAQ", async () => {
    api.fetchPublicProgramme.mockResolvedValue({ box: { name: "CrossFit Ακρόπολη", slug: "akropoli" }, programme });
    wrap();
    expect(await screen.findByRole("heading", { name: "Δύναμη σε 6 εβδομάδες", level: 1 })).toBeTruthy();
    expect(screen.getByText("CrossFit Ακρόπολη · coach Μαρία Κ. · ★ 4,8 · 23 κριτικές")).toBeTruthy();
    expect(screen.getByText("Δύναμη · Μεσαίοι")).toBeTruthy();
    expect(within(screen.getByTestId("programme-fact-minutes")).getByText("45′")).toBeTruthy();
    expect(within(screen.getByTestId("programme-fact-minutes")).getByText("περίπου ανά προπόνηση")).toBeTruthy();
    expect(within(screen.getByTestId("programme-fact-equipment")).getByText("Μπάρα")).toBeTruthy();

    const reviews = screen.getByTestId("programme-reviews");
    const weeks = screen.getByTestId("programme-weeks");
    expect(reviews.compareDocumentPosition(weeks) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();

    const first = screen.getByTestId("programme-week-1");
    expect(first.hasAttribute("open")).toBe(true);
    expect(within(first).getByText("Fran")).toBeTruthy();
    expect(within(screen.getByTestId("programme-outline-day-2")).getByText("Ξεκούραση")).toBeTruthy();
    expect(within(screen.getByTestId("programme-outline-day-3")).getByText("Δύναμη · ~50′")).toBeTruthy();
    expect(within(screen.getByTestId("programme-outline-day-5")).getByText("WOD")).toBeTruthy();
    expect(screen.getByTestId("programme-week-2").querySelectorAll("li")).toHaveLength(7);
    expect(within(screen.getByTestId("programme-week-3")).getByText("Εβδομάδες 3–6")).toBeTruthy();
    expect(within(screen.getByTestId("programme-week-3")).getByText(/16 WOD κλειδωμένα/)).toBeTruthy();
    expect(within(screen.getByTestId("programme-faq")).getByText("Παίρνεις πίσω όλη την τιμή μέχρι τη μέρα έναρξης.")).toBeTruthy();

    const bar = screen.getByTestId("programme-buy-bar");
    expect(within(bar).getByText("Επιστροφή μέχρι την έναρξη")).toBeTruthy();
    expect(within(bar).getByRole("button", { name: "Αγορά" })).toBeTruthy();
  });

  it("opens the first week from «Δες δωρεάν τις 2 πρώτες μέρες»", async () => {
    api.fetchPublicProgramme.mockResolvedValue({ box: { name: "Box" }, programme });
    wrap();
    const first = await screen.findByTestId("programme-week-1");
    fireEvent.click(within(first).getByText("Εβδομάδα 1"));
    first.removeAttribute("open");
    fireEvent(first, new Event("toggle"));
    expect(first.hasAttribute("open")).toBe(false);
    fireEvent.click(screen.getAllByRole("button", { name: "Δες δωρεάν τις 2 πρώτες μέρες" })[0]);
    expect(first.hasAttribute("open")).toBe(true);
    expect(Element.prototype.scrollIntoView).toHaveBeenCalled();
  });

  it("counts the locked WODs per week when the outline has no days (older API)", async () => {
    api.fetchPublicProgramme.mockResolvedValue({
      box: { name: "Box" },
      programme: { ...programme, coach_name: null, week_outline: [1, 2, 3, 4, 5, 6].map((week) => ({ week, sessions: 4 })) },
    });
    wrap();
    const first = await screen.findByTestId("programme-week-1");
    expect(within(first).getByText("Fran")).toBeTruthy();
    expect(within(first).getByText("2 WOD κλειδωμένα · ~45′ το καθένα")).toBeTruthy();
    expect(screen.getByText("Box · ★ 4,8 · 23 κριτικές")).toBeTruthy();
  });

  it("hides the minutes and the equipment the API does not know, and survives a bare payload", async () => {
    api.fetchPublicProgramme.mockResolvedValue({ programme: { title: "Λιτό", minutes_per_session: null, main_equipment: [] } });
    wrap();
    expect(await screen.findByRole("heading", { name: "Λιτό", level: 1 })).toBeTruthy();
    expect(screen.queryByTestId("programme-fact-minutes")).toBeNull();
    expect(screen.queryByTestId("programme-fact-equipment")).toBeNull();
    expect(screen.queryByTestId("programme-weeks")).toBeNull();
  });

  it("says the programme is not available for a stub that answers {}", async () => {
    api.fetchPublicProgramme.mockResolvedValue({});
    wrap();
    expect(await screen.findByText("Αυτό το πρόγραμμα δεν είναι διαθέσιμο.")).toBeTruthy();
  });

  it("shows no buy bar and no buy card in the store apps (ADR-256)", async () => {
    platform.native = "ios";
    api.fetchPublicProgramme.mockResolvedValue({ box: { name: "Box" }, programme });
    wrap();
    await screen.findByRole("heading", { name: "Δύναμη σε 6 εβδομάδες", level: 1 });
    expect(screen.queryByTestId("programme-buy-bar")).toBeNull();
    expect(screen.queryByTestId("programme-buy-card")).toBeNull();
    expect(screen.queryByRole("button", { name: "Αγορά" })).toBeNull();
  });
});
