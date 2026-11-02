import { fireEvent, render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { afterEach, describe, expect, it, vi } from "vitest";

import { calendarOfferPending } from "@/lib/training-floor";

import { CalendarOfferSheet } from "./CalendarOfferSheet";

vi.mock("next-intl", () => ({
  useLocale: () => "en",
  useTranslations: () => (key: string) => key,
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/api/calendar", () => ({
  fetchCalendarExportLinks: vi.fn(async () => ({ webcal_url: "webcal://palee.app/feed.ics?t=1", https_url: "https://palee.app/feed.ics?t=1" })),
}));

function renderSheet() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  const onClose = vi.fn();
  render(<CalendarOfferSheet userId="u1" onClose={onClose} />, { wrapper });
  return { onClose };
}

describe("CalendarOfferSheet (ADR-359, mockup e4 A)", () => {
  afterEach(() => window.localStorage.clear());

  it("offers the private feed for Apple and Google, and «Όχι τώρα» as text", async () => {
    renderSheet();
    const apple = await screen.findByRole("link", { name: "calendarOfferApple" });
    await vi.waitFor(() => expect(apple).toHaveAttribute("href", "webcal://palee.app/feed.ics?t=1"));
    expect(screen.getByRole("link", { name: "calendarOfferGoogle" }).getAttribute("href")).toContain("calendar.google.com");
    expect(screen.getByRole("button", { name: "calendarOfferNotNow" })).toBeInTheDocument();
  });

  it("«Όχι τώρα» is an answer too: it is not asked again", async () => {
    const { onClose } = renderSheet();
    fireEvent.click(await screen.findByRole("button", { name: "calendarOfferNotNow" }));
    expect(onClose).toHaveBeenCalled();
    expect(calendarOfferPending("u1")).toBe(false);
  });
});
