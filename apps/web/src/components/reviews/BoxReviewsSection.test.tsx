import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

const api = vi.hoisted(() => ({ fetchMyBoxReviews: vi.fn(), deleteMyBoxReview: vi.fn(), reportBoxReview: vi.fn() }));
vi.mock("@/api/box-site", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));

import { BoxReviewsSection } from "./BoxReviewsSection";

const membership = { organization: { id: "org-1", name: "CrossFit Κυψέλη", slug: "kypseli" } } as unknown as Parameters<typeof BoxReviewsSection>[0]["membership"];

const review = (id: string, name: string, body: string) => ({
  id,
  rating: 2,
  body,
  author_name: name,
  created_at: "2026-11-02T09:00:00Z",
  edited_at: null,
  reply: null,
});

function renderSection() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <BoxReviewsSection membership={membership} providerKind="gym" />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("BoxReviewsSection", () => {
  it("shows nothing, without breaking Box, when the reviews answer is malformed", async () => {
    api.fetchMyBoxReviews.mockResolvedValue({ count: 3, can_review: true });
    const { container } = renderSection();
    await waitFor(() => expect(api.fetchMyBoxReviews).toHaveBeenCalled());
    expect(container.querySelector("[data-testid=box-reviews]")).toBeNull();
  });

  it("offers «Αναφορά» in the ⋯ of others' reviews and marks the ones already reported (ADR-397)", async () => {
    api.fetchMyBoxReviews.mockResolvedValue({
      count: 2,
      average: 2,
      can_review: true,
      has_more: false,
      google: null,
      mine: null,
      reported_ids: ["r-2"],
      reviews: [review("r-1", "Νίκος", "Μην πάτε."), review("r-2", "Μάρκος", "Πολύς κόσμος.")],
    });
    renderSection();
    expect(await screen.findByText("Το ανέφερες · περιμένει την ομάδα Palee")).toBeTruthy();
    const menus = screen.getAllByRole("button", { name: "Περισσότερα για την κριτική" });
    expect(menus).toHaveLength(1);
    fireEvent.click(menus[0]);
    fireEvent.click(await screen.findByTestId("box-review-report"));
    expect(await screen.findByText("Αναφορά κριτικής")).toBeTruthy();
  });

  it("shows the statement of reasons under «Η κριτική μου» and closes editing when the Palee team hid it", async () => {
    api.fetchMyBoxReviews.mockResolvedValue({
      count: 0,
      average: null,
      can_review: true,
      has_more: false,
      google: null,
      reported_ids: [],
      reviews: [],
      mine: {
        ...review("mine", "Νίκος", "Ο coach είναι άχρηστος."),
        moderation: {
          status: "hidden",
          moderated_at: "2026-11-03T10:00:00Z",
          decided_at: "2026-11-03T10:00:00Z",
          outcome: "hide",
          ground: "offensive",
          legal_basis: "terms",
          statement: "Η κριτική σου προσβάλλει έναν coach με το όνομά του.",
          after_report: true,
          automated: false,
          redress: ["contact_palee", "court"],
          contact: "moderation@palee.app",
        },
      },
    });
    renderSection();
    const notice = await screen.findByTestId("box-review-moderation");
    expect(notice.textContent).toContain("Κρυμμένη από την ομάδα Palee");
    expect(notice.textContent).toContain("Λόγος: Προσβλητικό ή υβριστικό (όροι χρήσης Palee).");
    expect(notice.textContent).toContain("Το αποφάσισε άνθρωπος, μετά από αναφορά.");
    expect(notice.textContent).toContain("moderation@palee.app");
    fireEvent.click(screen.getByRole("button", { name: el.BoxReviews.mineMenu }));
    expect(await screen.findByTestId("box-reviews-delete")).toBeTruthy();
    expect(screen.queryByTestId("box-reviews-edit")).toBeNull();
  });
});
