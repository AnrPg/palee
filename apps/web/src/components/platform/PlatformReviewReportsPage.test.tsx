import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";
import type { PlatformReviewReports } from "@/api/platform-review-reports";
import { chooseValue } from "@/components/ui/select-test-utils";

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));

const api = vi.hoisted(() => ({ fetchPlatformReviewReports: vi.fn(), decidePlatformReviewReport: vi.fn(), restorePlatformReview: vi.fn() }));
vi.mock("@/api/platform-review-reports", async (original) => ({ ...(await original<object>()), ...api }));

import { PlatformReviewReportsPage } from "./PlatformReviewReportsPage";

const open: PlatformReviewReports = {
  decisions: [],
  items: [
    {
      review_id: "review-1",
      organization: { id: "org-1", name: "CrossFit Κυψέλη" },
      author_name: "Νίκος",
      box_reported: true,
      reports_count: 2,
      first_reported_at: "2026-11-03T08:00:00Z",
      reasons: [
        { reason: "offensive", count: 1 },
        { reason: "not_genuine", count: 1 },
      ],
      notes: [{ role: "member", reason: "offensive", note: "Βρίζει τον coach με το όνομά του.", at: "2026-11-03T08:00:00Z" }],
      reported: { rating: 1, body: "Ο coach Γιώργος είναι άχρηστος." },
      current: { rating: 1, body: "Ο coach είναι άχρηστος.", edited_at: "2026-11-03T09:00:00Z" },
    },
  ],
};

const decided: PlatformReviewReports = {
  items: [],
  decisions: [
    {
      id: "decision-1",
      review_id: "review-1",
      organization: { id: "org-1", name: "CrossFit Κυψέλη" },
      outcome: "hide",
      ground: "offensive",
      statement: "Προσβάλλει έναν coach.",
      reports_count: 2,
      decided_by: "Άννα",
      decided_at: "2026-11-03T10:00:00Z",
      review_status: "hidden",
    },
    {
      id: "decision-2",
      review_id: "review-2",
      organization: { id: "org-2", name: "Box Πατησίων" },
      outcome: "keep",
      ground: "no_violation",
      statement: null,
      reports_count: 1,
      decided_by: "Άννα",
      decided_at: "2026-11-02T10:00:00Z",
      review_status: "visible",
    },
  ],
};

function renderPage() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <PlatformReviewReportsPage />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("PlatformReviewReportsPage (ADR-397)", () => {
  beforeEach(() => {
    api.fetchPlatformReviewReports.mockReset().mockImplementation((_token: string, status: string) => Promise.resolve(status === "decided" ? decided : open));
    api.decidePlatformReviewReport.mockReset().mockResolvedValue({ review_id: "review-1", outcome: "hide", ground: "offensive", resolved: 2 });
    api.restorePlatformReview.mockReset().mockResolvedValue({ review_id: "review-1", outcome: "restore", ground: "no_violation", resolved: 0 });
  });

  it("shows one card per review: who reported (member or box), the text as reported and as it is now", async () => {
    renderPage();
    expect(await screen.findByText("CrossFit Κυψέλη · Νίκος")).toBeTruthy();
    expect(screen.getByText("Το ανέφερε το box")).toBeTruthy();
    expect(screen.getByText("Ο coach Γιώργος είναι άχρηστος.")).toBeTruthy();
    expect(screen.getByText("Άλλαξε μετά την αναφορά. Τώρα:")).toBeTruthy();
    expect(screen.getByText(/«Βρίζει τον coach με το όνομά του.»/)).toBeTruthy();
    expect(screen.getByText(/2 αναφορές/)).toBeTruthy();
  });

  it("keeps a review in one tap, without a statement", async () => {
    renderPage();
    fireEvent.click(await screen.findByTestId("review-decision-keep"));
    await waitFor(() => expect(api.decidePlatformReviewReport).toHaveBeenCalledWith("token", "review-1", { outcome: "keep", ground: "no_violation", statement: null }));
  });

  it("asks for the author's text before hiding, inside the form, then sends ground and statement", async () => {
    renderPage();
    fireEvent.click(await screen.findByTestId("review-decision-hide"));
    fireEvent.click(screen.getByTestId("review-decision-confirm"));
    expect(await screen.findByText("Γράψε τι θα διαβάσει ο συντάκτης.")).toBeTruthy();
    expect(api.decidePlatformReviewReport).not.toHaveBeenCalled();
    chooseValue(screen.getByTestId("review-decision-ground"), "personal_data");
    fireEvent.change(screen.getByTestId("review-decision-statement"), { target: { value: "Ονομάζει coach." } });
    fireEvent.click(screen.getByTestId("review-decision-confirm"));
    await waitFor(() =>
      expect(api.decidePlatformReviewReport).toHaveBeenCalledWith("token", "review-1", { outcome: "hide", ground: "personal_data", statement: "Ονομάζει coach." }),
    );
    expect(await screen.findByText("Αποφασίστηκε. Έκλεισαν 2 αναφορές.")).toBeTruthy();
  });

  it("restores a hidden review from «Αποφασισμένες» only with a statement", async () => {
    renderPage();
    fireEvent.click(await screen.findByTestId("review-reports-tab-decided"));
    expect(await screen.findByText("CrossFit Κυψέλη · Απόκρυψη")).toBeTruthy();
    expect(screen.getAllByTestId("review-restore")).toHaveLength(1);
    fireEvent.click(screen.getByTestId("review-restore"));
    fireEvent.click(await screen.findByTestId("review-restore-confirm"));
    expect(await screen.findByText("Γράψε τι θα διαβάσει ο συντάκτης.")).toBeTruthy();
    fireEvent.change(screen.getByTestId("review-restore-statement"), { target: { value: "Μετά από νέο έλεγχο δεν παραβιάζει τους όρους." } });
    fireEvent.click(screen.getByTestId("review-restore-confirm"));
    await waitFor(() => expect(api.restorePlatformReview).toHaveBeenCalledWith("token", "review-1", "Μετά από νέο έλεγχο δεν παραβιάζει τους όρους."));
    expect(await screen.findByText("Η κριτική φαίνεται ξανά. Ο συντάκτης ειδοποιήθηκε.")).toBeTruthy();
  });
});
