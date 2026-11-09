import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { describe, expect, it, vi } from "vitest";

import el from "../../../messages/el.json";

import { declineFollowerInvite, fetchMyFollowerInvite } from "@/api/follower-invites";

import { FollowerInviteNotice } from "./FollowerInviteNotice";

vi.mock("@/api/follower-invites", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/follower-invites")>()),
  fetchMyFollowerInvite: vi.fn(),
  declineFollowerInvite: vi.fn(),
}));

function renderNotice() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <FollowerInviteNotice token="access" slug="kypseli" />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("FollowerInviteNotice (ADR-580)", () => {
  it("shows nothing without an invitation", async () => {
    vi.mocked(fetchMyFollowerInvite).mockResolvedValue(null);
    renderNotice();
    await waitFor(() => expect(fetchMyFollowerInvite).toHaveBeenCalled());
    expect(screen.queryByTestId("box-follower-invite")).toBeNull();
  });

  it("shows the box's words and package, and «Όχι, ευχαριστώ» hides it", async () => {
    vi.mocked(fetchMyFollowerInvite).mockResolvedValue({
      id: "i1",
      status: "sent",
      sent_at: "2026-11-09T10:00:00Z",
      message: "Έλα να προπονηθούμε μαζί!",
      offer_trial: true,
      package: { id: "p1", name: "Απεριόριστο", price_cents: 7500, currency: "EUR", billing_period: "monthly" },
      box: { slug: "kypseli", name: "CrossFit Κυψέλη" },
    });
    vi.mocked(declineFollowerInvite).mockResolvedValue({ invite: null });
    renderNotice();
    expect(await screen.findByText("Το CrossFit Κυψέλη σε προσκαλεί να γίνεις μέλος")).toBeInTheDocument();
    expect(screen.getByText("«Έλα να προπονηθούμε μαζί!»")).toBeInTheDocument();
    expect(screen.getByTestId("box-follower-invite-package")).toHaveTextContent("Απεριόριστο");
    expect(screen.getByText(/δωρεάν δοκιμαστικό/)).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("box-follower-invite-decline"));
    await waitFor(() => expect(declineFollowerInvite).toHaveBeenCalledWith("access", "kypseli"));
    await waitFor(() => expect(screen.queryByTestId("box-follower-invite")).toBeNull());
  });
});
