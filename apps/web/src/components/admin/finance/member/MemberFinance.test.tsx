import { fireEvent, render, screen, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import el from "../../../../../messages/el.json";

import { fetchFinanceMember, fetchFinancePackages } from "@/api/finance";
import { fetchMemberBenefits } from "@/api/member-benefits";
import { fetchDeskPackageRequests } from "@/api/package-requests";
import { useSelectedMembershipRole } from "@/lib/membership-role";

import { MemberFinance } from "./MemberFinance";

vi.mock("@/api/finance", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/finance")>()),
  fetchFinanceMember: vi.fn(),
  fetchFinancePackages: vi.fn(),
}));
vi.mock("@/api/member-benefits", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/member-benefits")>()),
  fetchMemberBenefits: vi.fn(),
}));
vi.mock("@/api/package-requests", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/api/package-requests")>()),
  fetchDeskPackageRequests: vi.fn(),
}));
vi.mock("@/components/session-provider", () => ({ useSession: () => ({ tokens: { access_token: "t" } }) }));
vi.mock("@/lib/organization-slug", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/lib/organization-slug")>()),
  useOrganizationSlug: () => "kypseli",
}));
vi.mock("@/lib/membership-role", () => ({ useSelectedMembershipRole: vi.fn() }));
// The payment form has its own tests; here it only says which charge it was opened on.
vi.mock("@/components/admin/finance/payments/ReceivePaymentDialog", () => ({
  ReceivePaymentDialog: ({ chargeId }: { chargeId?: string }) => <div data-testid="pay-dialog">{chargeId ?? "any"}</div>,
}));

const profile = {
  membership: { id: "m1" },
  standing: { status: "unpaid", grace_until: null, access_until: null, outstanding_cents: 5500, unpaid_since: "2026-10-28" },
  package_subscriptions: [],
  active_package_subscription: { id: "sub-1", status: "active", package_name: "8 επισκέψεις", price_cents_snapshot: 5000, current_period: { ends_on: "2026-12-27", renews: true } },
  invoices: [
    { id: "inv-dec", invoice_number: "INV-12", status: "issued", issue_date: "2026-11-28", total_cents: 5000, paid_cents: 1500, balance_due_cents: 3500, lines: [{ description: "Δεκέμβριος" }] },
    { id: "inv-nov", invoice_number: "INV-11", status: "partially_paid", issue_date: "2026-10-28", total_cents: 5000, paid_cents: 3000, balance_due_cents: 2000, lines: [{ description: "Νοέμβριος" }] },
  ],
  payments: [{ id: "pay-1", finance_invoice_id: "inv-nov", amount_cents: 3000, payment_status: "paid", payment_method: "cash", paid_on: "2026-10-30" }],
  payment_reversals: [],
  promotion_redemptions: [],
  credit_ledger_entries: [],
  credit_balance: 0,
};

function staff(capabilities: Record<string, boolean>) {
  vi.mocked(useSelectedMembershipRole).mockReturnValue({ membership: { capabilities, organization: { slug: "kypseli" } } } as never);
}

function renderFinance() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="el" messages={el} timeZone="Europe/Athens">
        <MemberFinance userId="u1" nickname="Μαρία" />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
}

describe("MemberFinance (ADR-784)", () => {
  beforeEach(() => {
    vi.mocked(fetchFinanceMember).mockResolvedValue(profile as never);
    vi.mocked(fetchFinancePackages).mockResolvedValue({ packages: [] } as never);
    vi.mocked(fetchMemberBenefits).mockResolvedValue([]);
    vi.mocked(fetchDeskPackageRequests).mockResolvedValue({ requests: [] } as never);
  });

  it("shows what is owed and one dated list, each open charge with its own payment", async () => {
    staff({ take_payments: true, manage_billing: true });
    renderFinance();
    expect(await screen.findByTestId("member-finance-owed")).toHaveTextContent("55,00");
    const rows = screen.getAllByTestId("member-finance-movement");
    expect(rows.map((row) => row.dataset.kind)).toEqual(["charge", "payment", "charge"]);
    expect(within(rows[2]).getByText(/απομένουν/)).toHaveTextContent("20,00");

    fireEvent.click(within(rows[2]).getByTestId("member-finance-charge-pay"));
    expect(screen.getByTestId("pay-dialog")).toHaveTextContent("inv-nov");
  });

  it("filters by kind", async () => {
    staff({ take_payments: true });
    renderFinance();
    fireEvent.click(await screen.findByTestId("member-finance-filter-payment"));
    expect(screen.getAllByTestId("member-finance-movement").map((row) => row.dataset.kind)).toEqual(["payment"]);
  });

  it("gives each action only to whoever already may do it", async () => {
    staff({ take_payments: true });
    renderFinance();
    expect(await screen.findByTestId("member-finance-pay")).toBeInTheDocument();
    expect(screen.queryByTestId("member-finance-new-charge")).toBeNull();
    expect(screen.queryByTestId("member-finance-refund")).toBeNull();
  });

  it("gives every held package its own removal", async () => {
    vi.mocked(fetchFinanceMember).mockResolvedValue({
      ...profile,
      package_subscriptions: [profile.active_package_subscription, { id: "sub-2", status: "paused", package_name: "Open gym", price_cents_snapshot: 3000 }],
    } as never);
    staff({ take_payments: true });
    renderFinance();
    const packages = await screen.findAllByTestId("member-finance-package");
    expect(packages).toHaveLength(2);
    expect(packages[1]).toHaveTextContent("Σε παύση");
    expect(screen.getAllByTestId("member-finance-remove-package")).toHaveLength(2);
  });

  it("lets staff who only read see the money without any button", async () => {
    staff({ view_finance_reports: true });
    renderFinance();
    expect(await screen.findByTestId("member-finance-owed")).toBeInTheDocument();
    expect(screen.queryByTestId("member-finance-pay")).toBeNull();
    expect(screen.queryByTestId("member-finance-charge-pay")).toBeNull();
  });
});
