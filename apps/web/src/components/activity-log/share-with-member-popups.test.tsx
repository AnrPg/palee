import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../messages/en.json";

// ADR-760 (6A): every staff popup that asks for a reason about a member has
// «Let the member see it too», unticked when it opens, and always sends
// `reason_shared`.

const api = vi.hoisted(() => ({
  fetchAdminUserFreezes: vi.fn(),
  createAdminUserFreeze: vi.fn(),
  cancelAdminUserFreeze: vi.fn(),
  markFinanceMemberLeft: vi.fn(),
  undoFinanceMemberLeft: vi.fn(),
  setFinanceOverride: vi.fn(),
  resetFinanceOverride: vi.fn(),
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));
vi.mock("@/lib/membership-role", () => ({
  useSelectedMembershipRole: () => ({ membership: { role: "admin", capabilities: { manage_billing: "all" } }, isLoading: false }),
}));
vi.mock("@/api/admin-users", async (original) => ({
  ...(await original<object>()),
  fetchAdminUserFreezes: api.fetchAdminUserFreezes,
  createAdminUserFreeze: api.createAdminUserFreeze,
  cancelAdminUserFreeze: api.cancelAdminUserFreeze,
}));
vi.mock("@/api/finance", async (original) => ({
  ...(await original<object>()),
  markFinanceMemberLeft: api.markFinanceMemberLeft,
  undoFinanceMemberLeft: api.undoFinanceMemberLeft,
  setFinanceOverride: api.setFinanceOverride,
  resetFinanceOverride: api.resetFinanceOverride,
}));

import { MemberStatusCell, SubscriptionEndCell } from "@/components/admin/finance/shared/MemberStandingCells";
import { MembershipFreezes } from "@/components/admin/users/MembershipFreezes";
import { MembershipLeaving } from "@/components/admin/users/MembershipLeaving";
import { localIsoDate } from "@/components/admin/users/membership-freezes";
import { chooseValue } from "@/components/ui/select-test-utils";

function wrap(ui: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="UTC">
        {ui}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

const subscriptions = [{ id: "s1", status: "active", fields: { "perks.freeze_days_per_year": 30 } }];

describe("«Let the member see it too» on staff popups", () => {
  beforeEach(() => Object.values(api).forEach((fn) => fn.mockReset()));

  it("freeze: unticked by default, sent ticked when staff tick it", async () => {
    api.fetchAdminUserFreezes.mockResolvedValue([]);
    api.createAdminUserFreeze.mockResolvedValue({ freeze: {} });
    wrap(<MembershipFreezes token="token" userId="u1" subscriptions={subscriptions} onRefresh={async () => undefined} />);

    fireEvent.click(await screen.findByRole("button", { name: en.Ui.admFreezeMembership }));
    const share = screen.getByTestId("freeze-share-with-member") as HTMLInputElement;
    expect(share.checked).toBe(false);
    expect(screen.getByText(en.ActivityLog.shareWithMember)).toBeTruthy();
    fireEvent.change(screen.getByLabelText(en.Ui.admFreezeReason), { target: { value: "Sprained ankle" } });
    fireEvent.click(share);
    fireEvent.submit(share.closest("form")!);

    await waitFor(() =>
      expect(api.createAdminUserFreeze).toHaveBeenCalledWith("token", "u1", expect.objectContaining({ reason: "Sprained ankle", reason_shared: true })),
    );
  });

  it("freeze cancel: sends reason_shared false when left unticked", async () => {
    const today = localIsoDate();
    api.fetchAdminUserFreezes.mockResolvedValue([
      { id: "f1", starts_on: today, ends_on: "2999-01-01", extension_days: 5, reason: "Trip", cancelled_at: null },
    ]);
    api.cancelAdminUserFreeze.mockResolvedValue({ freeze: {} });
    wrap(<MembershipFreezes token="token" userId="u1" subscriptions={subscriptions} onRefresh={async () => undefined} />);

    const [open] = await screen.findAllByRole("button", { name: en.Ui.admFreezeCancel });
    fireEvent.click(open);
    expect((screen.getByTestId("freeze-cancel-share-with-member") as HTMLInputElement).checked).toBe(false);
    const buttons = screen.getAllByRole("button", { name: en.Ui.admFreezeCancel });
    fireEvent.click(buttons[buttons.length - 1]);
    await waitFor(() => expect(api.cancelAdminUserFreeze).toHaveBeenCalledWith("token", "u1", "f1", undefined, false));
  });

  it("leaving the box: sends the share choice with the reason", async () => {
    api.markFinanceMemberLeft.mockResolvedValue({});
    wrap(
      <MembershipLeaving
        token="token"
        userId="u1"
        membership={{}}
        subscriptions={[]}
        autoRenew={{}}
        onAutoRenewChange={() => undefined}
        changedRenewals={new Set()}
        onRefresh={async () => undefined}
      />,
    );
    fireEvent.click(screen.getByTestId("admin-leave-open"));
    fireEvent.click(screen.getByTestId("leave-share-with-member"));
    fireEvent.click(screen.getByTestId("admin-leave-confirm"));
    await waitFor(() => expect(api.markFinanceMemberLeft).toHaveBeenCalledWith("token", "u1", { reason: null, reason_shared: true }));
  });

  it("status override: unticked by default and sent with the value", async () => {
    api.setFinanceOverride.mockResolvedValue({ override: {} });
    wrap(<MemberStatusCell userId="u1" status="overdue" override={null} />);

    fireEvent.click(screen.getByRole("button", { name: en.MemberStanding.setStatus }));
    const share = (await screen.findByTestId("status-share-with-member")) as HTMLInputElement;
    expect(share.checked).toBe(false);
    chooseValue(screen.getByRole("combobox", { name: en.MemberStanding.setStatus }), "active");
    fireEvent.click(screen.getByRole("button", { name: en.MemberStanding.save }));
    await waitFor(() =>
      expect(api.setFinanceOverride).toHaveBeenCalledWith("token", "u1", "status", expect.objectContaining({ value: "active", reason_shared: false })),
    );
  });

  it("last-day override: sends reason_shared true once ticked", async () => {
    api.setFinanceOverride.mockResolvedValue({ override: {} });
    wrap(<SubscriptionEndCell userId="u1" subscriptionId="s1" endsOn="2026-11-30" renews={false} override={null} />);
    fireEvent.click(screen.getByRole("button", { name: en.MemberStanding.setEnd }));
    fireEvent.click(await screen.findByTestId("end-share-with-member"));
    expect((screen.getByTestId("end-share-with-member") as HTMLInputElement).checked).toBe(true);
  });
});
