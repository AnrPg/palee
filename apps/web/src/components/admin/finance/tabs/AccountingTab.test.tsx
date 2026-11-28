import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../../messages/en.json";

// The Accounting tab offers the same password-confirmed finance cleanup as
// Settings → Finance (one shared component, FinanceCleanupSection).

const finance = vi.hoisted(() => ({
  fetchFinanceCleanupRecords: vi.fn(async () => ({
    records: [
      {
        id: "inv-1",
        record_type: "invoice" as const,
        code: "INV-0007",
        amount_cents: 4500,
        currency: "EUR",
        status: "issued",
        issued_on: "2026-11-01",
        occurred_on: "2026-11-01",
        customer_name: "Maria P.",
        package_name: "Monthly",
      },
    ],
    next_cursor: null,
  })),
  fetchFinanceCleanupPackages: vi.fn(async () => ({ packages: [] })),
  fetchFinanceCleanupRecord: vi.fn(async () => ({
    record: {
      id: "inv-1",
      record_type: "invoice" as const,
      code: "INV-0007",
      amount_cents: 4500,
      currency: "EUR",
      status: "issued",
      occurred_on: "2026-11-01",
      user_id: "user-1",
      customer_name: "Maria P.",
      lines: [],
      linked: [],
    },
  })),
  purgeFinanceRecord: vi.fn(async () => ({ record: { id: "inv-1" } })),
}));

vi.mock("@/api/finance", async (original) => ({ ...(await original<object>()), ...finance }));
vi.mock("@/api/finance-accounting", async (original) => ({
  ...(await original<object>()),
  listRefundReceipts: vi.fn(async () => ({ refund_receipts: [] })),
  listReconciliationRecords: vi.fn(async () => ({ reconciliation_records: [] })),
  listAccountingExports: vi.fn(async () => ({ accounting_exports: [] })),
}));
vi.mock("@/components/admin/collect/TipsSummaryCard", () => ({ TipsSummaryCard: () => null }));
vi.mock("@/lib/organization-slug", async (original) => ({
  ...(await original<object>()),
  useOrganizationSlug: () => "box",
  useOrganizationTimeZone: () => "Europe/Athens",
}));
vi.mock("@/components/session-provider", () => ({
  useSession: () => ({ status: "authenticated", tokens: { access_token: "token" } }),
}));

import { AccountingTab } from "./AccountingTab";

function wrap(ui: React.ReactNode) {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en}>
        {ui}
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("AccountingTab finance cleanup", () => {
  beforeEach(() => {
    finance.fetchFinanceCleanupRecords.mockClear();
    finance.purgeFinanceRecord.mockClear();
  });

  it("purges a record after the password is re-entered", async () => {
    wrap(<AccountingTab />);

    expect(screen.getByText(en.FinanceCleanup.title)).toBeInTheDocument();
    expect(finance.fetchFinanceCleanupRecords).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: en.FinanceCleanup.open }));
    fireEvent.click(await screen.findByRole("button", { name: /Maria P\./ }));
    fireEvent.click(await screen.findByRole("button", { name: en.FinanceCleanup.startCleanup }));

    const submit = screen.getByRole("button", { name: en.FinanceCleanup.submit });
    expect(submit).toBeDisabled();
    expect(screen.getByRole("link", { name: en.authRecovery.forgotPasswordLink })).toHaveAttribute(
      "href",
      "/forgot-password",
    );

    fireEvent.change(screen.getByLabelText(en.FinanceCleanup.password, { exact: false }), { target: { value: "secret" } });
    fireEvent.click(submit);

    await waitFor(() =>
      expect(finance.purgeFinanceRecord).toHaveBeenCalledWith("token", "inv-1", {
        record_type: "invoice",
        password: "secret",
        reason: en.FinanceCleanup.defaultReason,
      }),
    );
    expect(await screen.findByText(en.FinanceCleanup.success)).toBeInTheDocument();
  });
});
