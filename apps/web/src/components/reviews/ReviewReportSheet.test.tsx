import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

const api = vi.hoisted(() => ({ reportBoxReview: vi.fn(), reportBoxReviewAsBox: vi.fn() }));
vi.mock("@/api/box-site", async (original) => ({ ...(await original<object>()), ...api }));

import { ReviewReportSheet } from "./ReviewReportSheet";

function renderSheet(asBox = false) {
  const onClose = vi.fn();
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <ReviewReportSheet token="token" reviewId="review-1" asBox={asBox} onClose={onClose} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
  return { onClose };
}

describe("ReviewReportSheet (ADR-397)", () => {
  beforeEach(() => {
    api.reportBoxReview.mockReset().mockResolvedValue({ review_id: "review-1", status: "open" });
    api.reportBoxReviewAsBox.mockReset().mockResolvedValue({ review_id: "review-1", status: "open" });
  });

  it("lists the six reasons and says only the Palee team sees the report", () => {
    renderSheet();
    expect(screen.getAllByRole("radio")).toHaveLength(6);
    expect(screen.getByText("Τη βλέπει μόνο η ομάδα Palee. Η κριτική μένει μέχρι να αποφασίσει.")).toBeTruthy();
    expect(screen.getByRole("button", { name: "Στείλε αναφορά" })).toBeTruthy();
  });

  it("asks for a reason inside the form and sends nothing without one", async () => {
    renderSheet();
    fireEvent.click(screen.getByTestId("review-report-send"));
    expect(await screen.findByText("Διάλεξε έναν λόγο.")).toBeTruthy();
    expect(screen.getByRole("radiogroup").getAttribute("aria-invalid")).toBe("true");
    expect(api.reportBoxReview).not.toHaveBeenCalled();
  });

  it("needs a few words for «Κάτι άλλο», then sends the member report and thanks", async () => {
    renderSheet();
    fireEvent.click(screen.getByTestId("review-report-reason-other"));
    expect(screen.getByText("Τι συμβαίνει;")).toBeTruthy();
    fireEvent.click(screen.getByTestId("review-report-send"));
    expect(await screen.findByText("Γράψε δυο λόγια για να καταλάβουμε τι συμβαίνει.")).toBeTruthy();
    expect(screen.getByTestId("review-report-note").getAttribute("aria-invalid")).toBe("true");
    fireEvent.change(screen.getByTestId("review-report-note"), { target: { value: "  Ψεύτικος λογαριασμός  " } });
    fireEvent.click(screen.getByTestId("review-report-send"));
    await waitFor(() => expect(api.reportBoxReview).toHaveBeenCalledWith("token", "review-1", { reason: "other", note: "Ψεύτικος λογαριασμός" }));
    expect(await screen.findByText("Ευχαριστούμε")).toBeTruthy();
  });

  it("keeps the note optional for other reasons and reports as the box when asked", async () => {
    renderSheet(true);
    expect(screen.getByText(/Το box δεν μπορεί να κρύψει μια κριτική μόνο του/)).toBeTruthy();
    fireEvent.click(screen.getByTestId("review-report-reason-offensive"));
    fireEvent.click(screen.getByTestId("review-report-send"));
    await waitFor(() => expect(api.reportBoxReviewAsBox).toHaveBeenCalledWith("token", "review-1", { reason: "offensive", note: null }));
    expect(api.reportBoxReview).not.toHaveBeenCalled();
  });
});
