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
        label: "Invoice INV-0007",
        amount_cents: 4500,
        currency: "EUR",
        status: "open",
        issued_on: "2026-11-01",
      },
    ],
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

    expect(screen.getByText(en.Ui.featureFinanceCleanupTitle)).toBeInTheDocument();
    expect(finance.fetchFinanceCleanupRecords).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: en.Ui.featureFinanceCleanupOpen }));
    fireEvent.click(await screen.findByRole("button", { name: /INV-0007/ }));

    const submit = screen.getByRole("button", { name: en.Ui.featureFinanceCleanupSubmit });
    expect(submit).toBeDisabled();
    expect(screen.getByRole("link", { name: en.authRecovery.forgotPasswordLink })).toHaveAttribute(
      "href",
      "/forgot-password",
    );

    fireEvent.change(screen.getByLabelText(en.Ui.featureFinanceCleanupPassword, { exact: false }), { target: { value: "secret" } });
    fireEvent.click(submit);

    await waitFor(() =>
      expect(finance.purgeFinanceRecord).toHaveBeenCalledWith("token", "inv-1", {
        record_type: "invoice",
        password: "secret",
        reason: en.Ui.featureFinanceCleanupDefaultReason,
      }),
    );
    expect(await screen.findByText(en.Ui.featureFinanceCleanupSuccess)).toBeInTheDocument();
  });
});
