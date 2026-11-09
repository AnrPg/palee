import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../messages/el.json";

import { fetchBoxFollowers, fetchFollowerInviteSummary, inviteFollowers } from "@/api/follower-invites";

import { FollowerInvitesCard } from "./FollowerInvitesCard";

vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "access" } }) }));
vi.mock("@/api/follower-invites", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/follower-invites")>()),
  fetchFollowerInviteSummary: vi.fn(),
  fetchBoxFollowers: vi.fn(),
  inviteFollowers: vi.fn(),
}));

const follower = (id: string, nickname: string, extra: Record<string, unknown> = {}) => ({
  person: { id, nickname, handle: null, avatar_url: null },
  followed_at: "2026-10-12T10:00:00Z",
  former_member: false,
  had_trial: false,
  invite: null,
  invitable: true,
  ...extra,
});

const page = {
  followers: [
    follower("u1", "Μαρία", { had_trial: true }),
    follower("u2", "Νίκος"),
    follower("u3", "Σοφία", { former_member: true, invitable: false, invite: { status: "declined", sent_at: "2026-09-01T10:00:00Z", next_invite_at: null } }),
  ],
  next_cursor: null,
  counts: { listed: 3, invitable: 2, trial: 1, former: 1 },
  offer: { packages: [{ id: "p1", name: "Απεριόριστο", price_cents: 7500, currency: "EUR", billing_period: "monthly" }], trial_available: true },
};

function renderCard() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el}>
        <FollowerInvitesCard />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("FollowerInvitesCard (ADR-580)", () => {
  beforeEach(() => {
    vi.mocked(fetchBoxFollowers).mockResolvedValue(page as never);
    vi.mocked(inviteFollowers).mockResolvedValue({ sent: 1, skipped: [] });
  });

  it("is not shown while nobody may be invited", async () => {
    vi.mocked(fetchFollowerInviteSummary).mockResolvedValue({ counts: { listed: 2, invitable: 0, trial: 0, former: 0 } });
    renderCard();
    await waitFor(() => expect(fetchFollowerInviteSummary).toHaveBeenCalled());
    expect(screen.queryByTestId("follower-invites")).toBeNull();
  });

  it("invites one follower with a message and a package", async () => {
    vi.mocked(fetchFollowerInviteSummary).mockResolvedValue({ counts: page.counts });
    renderCard();
    expect(await screen.findByText("3 ακόλουθοι δεν είναι ακόμα μέλη")).toBeInTheDocument();
    fireEvent.click(screen.getByTestId("follower-invites-toggle"));
    expect(await screen.findByText("Μαρία")).toBeInTheDocument();
    // Tags and the answer of someone who declined; no button for them.
    expect(screen.getAllByText("Δοκιμαστικό").length).toBeGreaterThan(0);
    expect(screen.getByText("Δεν θέλει προσκλήσεις")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Πρόσκληση: Σοφία" })).toBeNull();

    fireEvent.click(screen.getByRole("button", { name: "Πρόσκληση: Μαρία" }));
    const sheet = await screen.findByTestId("follower-invite-sheet");
    fireEvent.change(within(sheet).getByTestId("follower-invite-message"), { target: { value: "Έλα!" } });
    fireEvent.click(within(sheet).getByRole("radio", { name: /Απεριόριστο/ }));
    fireEvent.click(within(sheet).getByTestId("follower-invite-send"));
    await waitFor(() =>
      expect(inviteFollowers).toHaveBeenCalledWith("access", { user_ids: ["u1"], message: "Έλα!", package_id: "p1", offer_trial: false }),
    );
    expect(await screen.findByText(/Στάλθηκε 1 πρόσκληση/)).toBeInTheDocument();
  });

  it("invites many at once", async () => {
    vi.mocked(fetchFollowerInviteSummary).mockResolvedValue({ counts: page.counts });
    vi.mocked(inviteFollowers).mockResolvedValue({ sent: 2, skipped: [] });
    renderCard();
    fireEvent.click(await screen.findByTestId("follower-invites-toggle"));
    fireEvent.click(await screen.findByTestId("follower-invites-all"));
    fireEvent.click(screen.getByTestId("follower-invites-many"));
    const sheet = await screen.findByTestId("follower-invite-sheet");
    fireEvent.click(within(sheet).getByTestId("follower-invite-send"));
    await waitFor(() =>
      expect(inviteFollowers).toHaveBeenCalledWith("access", { user_ids: ["u1", "u2"], message: null, package_id: null, offer_trial: false }),
    );
  });
});
