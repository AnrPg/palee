import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { PaleeLeaderboardSetting } from "./PaleeLeaderboardSetting";

const fetchPaleeConsent = vi.fn();
const putPaleeConsent = vi.fn();
const withdrawPaleeConsent = vi.fn();

vi.mock("next-intl", () => ({ useTranslations: () => (key: string) => key }));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "tok" } }) }));
vi.mock("@/api/training-floor", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/training-floor")>()),
  fetchPaleeConsent: (...args: unknown[]) => fetchPaleeConsent(...args),
  putPaleeConsent: (...args: unknown[]) => putPaleeConsent(...args),
  withdrawPaleeConsent: (...args: unknown[]) => withdrawPaleeConsent(...args),
}));

function renderSetting() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: ReactNode }) => <QueryClientProvider client={client}>{children}</QueryClientProvider>;
  return render(<PaleeLeaderboardSetting />, { wrapper });
}

describe("PaleeLeaderboardSetting (ADR-394, «Κοινοποίηση και ορατότητα»)", () => {
  beforeEach(() => {
    fetchPaleeConsent.mockReset();
    putPaleeConsent.mockReset();
    withdrawPaleeConsent.mockReset();
  });

  it("before any answer says it will be asked, and the switch puts the score on the board", async () => {
    fetchPaleeConsent.mockResolvedValue({ choice: null });
    putPaleeConsent.mockResolvedValue({ choice: "share" });
    renderSetting();
    expect(await screen.findByText("paleeSettingNotAsked")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "paleeSettingWithdraw" })).toBeNull();
    const toggle = screen.getByRole("switch", { name: /paleeSettingShare/ });
    expect(toggle).not.toBeChecked();
    fireEvent.click(toggle);
    await waitFor(() => expect(putPaleeConsent).toHaveBeenCalledWith("tok", "share"));
    await waitFor(() => expect(screen.getByRole("switch", { name: /paleeSettingShare/ })).toBeChecked());
  });

  it("off means only I see my place; «Έξοδος» withdraws the answer at once", async () => {
    fetchPaleeConsent.mockResolvedValue({ choice: "share" });
    putPaleeConsent.mockResolvedValue({ choice: "see_only" });
    withdrawPaleeConsent.mockResolvedValue({ choice: null });
    renderSetting();
    const toggle = await screen.findByRole("switch", { name: /paleeSettingShare/ });
    await waitFor(() => expect(toggle).toBeChecked());
    fireEvent.click(toggle);
    await waitFor(() => expect(putPaleeConsent).toHaveBeenCalledWith("tok", "see_only"));

    fireEvent.click(screen.getByRole("button", { name: "paleeSettingWithdraw" }));
    await waitFor(() => expect(withdrawPaleeConsent).toHaveBeenCalledWith("tok"));
    expect(await screen.findByText("paleeSettingNotAsked")).toBeInTheDocument();
  });
});
