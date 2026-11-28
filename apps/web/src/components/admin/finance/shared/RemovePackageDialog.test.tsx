import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import type { ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../../messages/en.json";
import type { PackageRemovalPreview } from "@/api/finance";

// ADR-660: «Αφαίρεση πακέτου»: what staff see before they confirm.

const api = vi.hoisted(() => ({
  fetchPackageRemovalPreview: vi.fn(),
  removeFinancePackage: vi.fn(),
  undoPackageRemoval: vi.fn(),
}));

vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));
vi.mock("@/api/finance", async (original) => ({ ...(await original<object>()), ...api }));

import { RemovePackageDialog, removalBody, removalReady } from "./RemovePackageDialog";
import { PackageRemovedToast, undoRemainingMs } from "./PackageRemovedToast";

function preview(overrides: Partial<PackageRemovalPreview> = {}): PackageRemovalPreview {
  return {
    package_name: "Monthly",
    untouched_invoices: [],
    kept_owed_cents: 0,
    paid_cents: 0,
    currency: "EUR",
    upcoming_bookings: 0,
    may_write_off: true,
    undo_seconds: 60,
    ...overrides,
  };
}

const removal = {
  id: "r1",
  subscription_id: "s1",
  package_name: "Monthly",
  removed_on: "2026-11-17",
  invoice_choice: "void" as const,
  voided_invoice_count: 1,
  undo_until: new Date(Date.now() + 60_000).toISOString(),
};

function wrap(ui: ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en}>
        {ui}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

function dialog(onRemoved = vi.fn()) {
  return wrap(
    <RemovePackageDialog
      userId="u1"
      memberName="tolaras"
      subscriptionId="s1"
      onClose={vi.fn()}
      onRemoved={onRemoved}
      onOpenRefund={vi.fn()}
    />,
  );
}

describe("removal rules", () => {
  const unpaid = [{ id: "i1", total_cents: 5_000 }];

  it("asks billing staff to choose for an untouched unpaid invoice, with nothing preselected", () => {
    expect(removalReady(undefined, null)).toBe(false);
    expect(removalReady(preview(), null)).toBe(true);
    expect(removalReady(preview({ untouched_invoices: unpaid }), null)).toBe(false);
    expect(removalReady(preview({ untouched_invoices: unpaid }), "keep")).toBe(true);
    // The front desk has nothing to choose: the debt stays.
    expect(removalReady(preview({ untouched_invoices: unpaid, may_write_off: false }), null)).toBe(true);
  });

  it("sends the choice only when one was asked, the reason only when written, and the share choice always", () => {
    expect(removalBody(preview(), "void", "  ", true)).toEqual({ reason_shared: true });
    expect(removalBody(preview({ untouched_invoices: unpaid }), "void", " Moved ", false)).toEqual({
      invoice_choice: "void",
      reason: "Moved",
      reason_shared: false,
    });
    expect(removalBody(preview({ untouched_invoices: unpaid, may_write_off: false }), "void", "", false)).toEqual({ reason_shared: false });
  });

  it("sends the package that takes the place of the removed one («Αλλαγή πακέτου»)", () => {
    expect(removalBody(preview(), null, "", false, { id: "p2", name: "Free" })).toEqual({
      replacement_package_id: "p2",
      reason_shared: false,
    });
  });

  it("keeps the undo toast until the server's minute closes", () => {
    const now = Date.parse("2026-11-17T10:00:00Z");
    expect(undoRemainingMs("2026-11-17T10:01:00Z", now)).toBe(60_000);
    expect(undoRemainingMs("2026-11-17T09:59:00Z", now)).toBe(0);
    expect(undoRemainingMs("not a date", now)).toBe(0);
  });
});

describe("RemovePackageDialog", () => {
  beforeEach(() => {
    api.fetchPackageRemovalPreview.mockReset();
    api.removeFinancePackage.mockReset();
    api.undoPackageRemoval.mockReset();
  });

  it("says what happens and needs a choice for the unpaid invoice before removing", async () => {
    api.fetchPackageRemovalPreview.mockResolvedValue({
      removal: preview({ untouched_invoices: [{ id: "i1", total_cents: 5_000 }], upcoming_bookings: 2 }),
    });
    api.removeFinancePackage.mockResolvedValue({ removal });
    const onRemoved = vi.fn();
    dialog(onRemoved);

    expect(await screen.findByText(en.PackageRemoval.fromToday)).toBeTruthy();
    expect(screen.getByText(/2 upcoming bookings are cancelled/)).toBeTruthy();
    const confirm = screen.getByTestId("package-removal-confirm") as HTMLButtonElement;
    expect(confirm.disabled).toBe(true);
    expect(screen.getByTestId("package-removal-choice-void").getAttribute("aria-checked")).toBe("false");
    expect(screen.getByTestId("package-removal-choice-keep").getAttribute("aria-checked")).toBe("false");

    // ADR-760 (6A): «Let the member see it too» starts unticked and is sent either way.
    const share = screen.getByTestId("package-removal-share-reason") as HTMLInputElement;
    expect(share.checked).toBe(false);
    expect(screen.getByText(en.ActivityLog.shareWithMember)).toBeTruthy();
    fireEvent.change(screen.getByTestId("package-removal-reason"), { target: { value: "Moved away" } });
    fireEvent.click(share);

    fireEvent.click(screen.getByTestId("package-removal-choice-void"));
    expect(confirm.disabled).toBe(false);
    fireEvent.click(confirm);

    await waitFor(() => expect(onRemoved).toHaveBeenCalledWith(removal));
    expect(api.removeFinancePackage).toHaveBeenCalledWith("token", "u1", "s1", {
      invoice_choice: "void",
      reason: "Moved away",
      reason_shared: true,
    });
  });

  it("tells the front desk the debt stays and offers no choice", async () => {
    api.fetchPackageRemovalPreview.mockResolvedValue({
      removal: preview({
        untouched_invoices: [{ id: "i1", total_cents: 5_000 }],
        may_write_off: false,
        paid_cents: 2_000,
      }),
    });
    dialog();

    expect(await screen.findByText(/stays owed, with reminders/)).toBeTruthy();
    expect(screen.queryByTestId("package-removal-choice-void")).toBeNull();
    expect(screen.getByTestId("package-removal-refund")).toBeTruthy();
    expect((screen.getByTestId("package-removal-confirm") as HTMLButtonElement).disabled).toBe(false);
  });
});

describe("RemovePackageDialog as «Αλλαγή πακέτου»", () => {
  beforeEach(() => {
    api.fetchPackageRemovalPreview.mockReset();
    api.removeFinancePackage.mockReset();
  });

  it("names both packages, still asks about the unpaid invoice, and sends the new package", async () => {
    api.fetchPackageRemovalPreview.mockResolvedValue({
      removal: preview({ untouched_invoices: [{ id: "i1", total_cents: 5_000 }], upcoming_bookings: 2 }),
    });
    api.removeFinancePackage.mockResolvedValue({ removal });
    const onRemoved = vi.fn();
    wrap(
      <RemovePackageDialog
        userId="u1"
        memberName="Lam"
        subscriptionId="s1"
        replacement={{ id: "p2", name: "Free" }}
        onClose={vi.fn()}
        onRemoved={onRemoved}
        onOpenRefund={vi.fn()}
      />,
    );

    expect(await screen.findByText("Change «Monthly» to «Free»?")).toBeTruthy();
    expect(screen.getByText(/«Monthly» stops and is never charged again/)).toBeTruthy();
    // The new package keeps their access: no booking warning.
    expect(screen.queryByText(/upcoming bookings are cancelled/)).toBeNull();
    const confirm = screen.getByTestId("package-removal-confirm") as HTMLButtonElement;
    expect(confirm.textContent).toBe(en.PackageRemoval.confirmChange);
    expect(confirm.disabled).toBe(true);

    fireEvent.click(screen.getByTestId("package-removal-choice-void"));
    fireEvent.click(confirm);

    await waitFor(() => expect(onRemoved).toHaveBeenCalledWith(removal));
    expect(api.removeFinancePackage).toHaveBeenCalledWith("token", "u1", "s1", {
      replacement_package_id: "p2",
      invoice_choice: "void",
      reason_shared: false,
    });
  });
});

describe("PackageRemovedToast", () => {
  it("says the package changed when another one took its place", () => {
    wrap(
      <PackageRemovedToast
        userId="u1"
        nickname="Lam"
        removal={{ ...removal, replacement_package_name: "Free" }}
        onDone={vi.fn()}
      />,
    );
    expect(screen.getByText("«Monthly» is now «Free» · Lam")).toBeTruthy();
  });

  it("undoes the removal", async () => {
    api.undoPackageRemoval.mockResolvedValue({ removal: { ...removal, undone_at: "2026-11-17T10:00:10Z" } });
    const onDone = vi.fn();
    wrap(<PackageRemovedToast userId="u1" nickname="tolaras" removal={removal} onDone={onDone} />);

    fireEvent.click(screen.getByTestId("package-removed-undo"));
    await waitFor(() => expect(onDone).toHaveBeenCalled());
    expect(api.undoPackageRemoval).toHaveBeenCalledWith("token", "u1", "r1");
  });
});
