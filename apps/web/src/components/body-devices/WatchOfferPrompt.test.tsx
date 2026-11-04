import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { WatchOfferPrompt } from "./WatchOfferPrompt";

const requestWatchOffer = vi.fn();
const answerWatchOffer = vi.fn();
const watchStatus = vi.fn();
const startOnWatch = vi.fn();

vi.mock("next-intl", () => ({ useTranslations: () => (key: string) => key }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/api/body-devices", () => ({
  requestWatchOffer: (...args: unknown[]) => requestWatchOffer(...args),
  answerWatchOffer: (...args: unknown[]) => answerWatchOffer(...args),
}));
vi.mock("@/lib/platform/watch", () => ({
  watchStatus: () => watchStatus(),
  startOnWatch: (...args: unknown[]) => startOnWatch(...args),
}));

describe("WatchOfferPrompt (ANR's D8 rules)", () => {
  beforeEach(() => {
    for (const mock of [requestWatchOffer, answerWatchOffer, watchStatus, startOnWatch]) mock.mockReset();
    startOnWatch.mockResolvedValue(true);
  });

  it("asks nothing without a watch the phone sees right now", async () => {
    watchStatus.mockResolvedValue(null);
    const { container } = render(<WatchOfferPrompt executionId="e1" />);
    await waitFor(() => expect(watchStatus).toHaveBeenCalled());
    expect(requestWatchOffer).not.toHaveBeenCalled();
    expect(container).toBeEmptyDOMElement();
  });

  it("asks nothing when the watch is found but not connected", async () => {
    watchStatus.mockResolvedValue({ platform: "apple_watch", connected: false });
    render(<WatchOfferPrompt executionId="e1" />);
    await waitFor(() => expect(watchStatus).toHaveBeenCalled());
    expect(requestWatchOffer).not.toHaveBeenCalled();
  });

  it("asks when the server says so, and starts the watch on yes", async () => {
    watchStatus.mockResolvedValue({ platform: "apple_watch", connected: true });
    requestWatchOffer.mockResolvedValue({ mode: "ask", reason: "first_wods", answer: null, asked_count: 1, ask_limit: 5 });
    answerWatchOffer.mockResolvedValue({ mode: "start", answer: "yes" });
    render(<WatchOfferPrompt executionId="e1" />);
    expect(await screen.findByText("watch.offerTitle")).toBeInTheDocument();
    expect(requestWatchOffer).toHaveBeenCalledWith("tok", "e1", "apple_watch", true);
    fireEvent.click(screen.getByText("watch.offerYes"));
    await waitFor(() => expect(answerWatchOffer).toHaveBeenCalledWith("tok", "e1", "yes"));
    await waitFor(() => expect(startOnWatch).toHaveBeenCalledWith("e1"));
  });

  it("starts by itself after the first five WODs, without a question", async () => {
    watchStatus.mockResolvedValue({ platform: "wear_os", connected: true });
    requestWatchOffer.mockResolvedValue({ mode: "start", reason: "box_member_after_first_wods", answer: null, asked_count: 5, ask_limit: 5 });
    render(<WatchOfferPrompt executionId="e1" />);
    await waitFor(() => expect(startOnWatch).toHaveBeenCalledWith("e1"));
    expect(screen.queryByText("watch.offerTitle")).not.toBeInTheDocument();
  });

  it("leaves the watch alone on a class WOD without check-in", async () => {
    watchStatus.mockResolvedValue({ platform: "wear_os", connected: true });
    requestWatchOffer.mockResolvedValue({ mode: "none", reason: "not_checked_in", answer: null, asked_count: 0, ask_limit: 5 });
    render(<WatchOfferPrompt executionId="e1" />);
    await waitFor(() => expect(requestWatchOffer).toHaveBeenCalled());
    expect(startOnWatch).not.toHaveBeenCalled();
    expect(screen.queryByText("watch.offerTitle")).not.toBeInTheDocument();
  });
});
