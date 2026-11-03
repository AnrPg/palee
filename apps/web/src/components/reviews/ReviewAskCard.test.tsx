import { fireEvent, render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

const api = vi.hoisted(() => ({ fetchReviewAsk: vi.fn(), respondToReviewAsk: vi.fn(async () => null), saveMyBoxReview: vi.fn() }));
vi.mock("@/api/box-site", async (original) => ({ ...(await original<object>()), ...api }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "token" } }) }));
vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({ membership: { organization: { id: "org-1", name: "CrossFit Κυψέλη", slug: "kypseli" } } }),
}));

import { ReviewAskCard } from "./ReviewAskCard";

const ASK = { id: "ask-1", milestone: 10, status: "shown", shown_at: "2026-11-02T10:00:00Z", google_review_url: "https://g.page/r/x/review", has_review: false, actions: ["opened", "later", "dismissed"] };

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <ReviewAskCard />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

// ANR s6 A, ADR-386: three answers for everyone, no gating; gone once answered.
describe("ReviewAskCard", () => {
  beforeEach(() => {
    api.fetchReviewAsk.mockReset();
    api.respondToReviewAsk.mockClear();
  });

  it("offers the in-app review, Google and a message to the box", async () => {
    api.fetchReviewAsk.mockResolvedValue(ASK);
    wrap();
    expect(await screen.findByText("10 προπονήσεις!")).toBeTruthy();
    expect(screen.getByTestId("review-ask-write").textContent).toBe("Γράψε κριτική");
    expect(screen.getByTestId("review-ask-google").getAttribute("href")).toBe(ASK.google_review_url);
    expect(screen.getByTestId("review-ask-message").getAttribute("href")).toBe("/b/kypseli/chat");
  });

  it("closes for good and records the answer", async () => {
    api.fetchReviewAsk.mockResolvedValue(ASK);
    wrap();
    fireEvent.click(await screen.findByTestId("review-ask-close"));
    expect(screen.queryByTestId("review-ask-card")).toBeNull();
    await vi.waitFor(() => expect(api.respondToReviewAsk).toHaveBeenCalledWith("token", "ask-1", "dismissed"));
  });

  it("opens the review sheet from «Γράψε κριτική»", async () => {
    api.fetchReviewAsk.mockResolvedValue(ASK);
    wrap();
    fireEvent.click(await screen.findByTestId("review-ask-write"));
    expect(screen.getByTestId("review-sheet")).toBeTruthy();
    await vi.waitFor(() => expect(api.respondToReviewAsk).toHaveBeenCalledWith("token", "ask-1", "opened"));
  });

  it("shows nothing when there is no ask", async () => {
    api.fetchReviewAsk.mockResolvedValue(null);
    wrap();
    await vi.waitFor(() => expect(api.fetchReviewAsk).toHaveBeenCalled());
    expect(screen.queryByTestId("review-ask-card")).toBeNull();
  });
});
