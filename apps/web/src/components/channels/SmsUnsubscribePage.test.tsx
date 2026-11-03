import { fireEvent, render, screen } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

import { ApiError } from "@/api/client";
import { confirmSmsUnsubscribe, fetchSmsUnsubscribe } from "@/api/sms-unsubscribe";

import { SmsUnsubscribePage } from "./SmsUnsubscribePage";

vi.mock("@/api/sms-unsubscribe", () => ({ fetchSmsUnsubscribe: vi.fn(), confirmSmsUnsubscribe: vi.fn() }));
vi.mock("@/components/auth/LanguagePicker", () => ({ LanguagePicker: () => null }));

function renderPage(token = "tok") {
  return render(
    <QueryClientProvider client={new QueryClient({ defaultOptions: { queries: { retry: false } } })}>
      <NextIntlClientProvider locale="el" messages={el} timeZone="Europe/Athens">
        <SmsUnsubscribePage token={token} />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("SMS unsubscribe page (ADR-390)", () => {
  beforeEach(() => vi.clearAllMocks());

  it("changes nothing on opening; the tap stops offers and says updates keep coming", async () => {
    vi.mocked(fetchSmsUnsubscribe).mockResolvedValue({ box_name: "Box Κυψέλη", locale: "el", withdrawn: false });
    vi.mocked(confirmSmsUnsubscribe).mockResolvedValue({ box_name: "Box Κυψέλη", locale: "el", withdrawn: true });
    renderPage();

    expect(await screen.findByText("Να σταματήσουν τα SMS με προσφορές από Box Κυψέλη;")).toBeTruthy();
    expect(confirmSmsUnsubscribe).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "Διακοπή" }));
    expect(await screen.findByText("Δεν θα λαμβάνετε πια SMS με προσφορές από Box Κυψέλη.")).toBeTruthy();
    expect(confirmSmsUnsubscribe).toHaveBeenCalledWith("tok");
    expect(screen.getByTestId("sms-unsubscribe-done").textContent).toContain("θα συνεχίσουν να έρχονται");
  });

  it("says when offers are already off, and when the link is not valid", async () => {
    vi.mocked(fetchSmsUnsubscribe).mockResolvedValueOnce({ box_name: "Box", locale: "el", withdrawn: true });
    const { unmount } = renderPage();
    expect(await screen.findByTestId("sms-unsubscribe-done")).toBeTruthy();
    expect(screen.queryByRole("button", { name: "Διακοπή" })).toBeNull();
    unmount();

    vi.mocked(fetchSmsUnsubscribe).mockRejectedValueOnce(new ApiError(404, "Not found", { code: "not_found" }));
    renderPage("bad");
    expect(await screen.findByText("Αυτός ο σύνδεσμος δεν ισχύει.")).toBeTruthy();
  });
});
