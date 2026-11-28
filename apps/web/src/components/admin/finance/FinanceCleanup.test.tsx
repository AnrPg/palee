import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { NextIntlClientProvider } from "next-intl";
import { beforeEach, describe, expect, it, vi } from "vitest";

import en from "../../../../messages/en.json";

// ADR-797: «Εκκαθάριση συναλλαγών» filters, pages and the side panel.

const receipt = {
  id: "rec-1",
  record_type: "receipt" as const,
  code: "R-0042",
  amount_cents: 6000,
  currency: "EUR",
  status: "paid",
  occurred_on: "2026-11-24",
  user_id: "user-1",
  customer_name: "Maria P.",
  package_name: "Monthly",
};

const finance = vi.hoisted(() => ({
  fetchFinanceCleanupRecords: vi.fn(),
  fetchFinanceCleanupPackages: vi.fn(async () => ({
    packages: [
      { id: "pkg-1", name: "Monthly", active: true },
      { id: "pkg-2", name: "Summer", active: false },
    ],
  })),
  fetchFinanceCleanupRecord: vi.fn(),
  purgeFinanceRecord: vi.fn(),
}));

vi.mock("@/api/finance", async (original) => ({ ...(await original<object>()), ...finance }));
vi.mock("@/lib/organization-slug", async (original) => ({
  ...(await original<object>()),
  useOrganizationSlug: () => "box",
  useOrganizationTimeZone: () => "Europe/Athens",
}));

import { FinanceCleanupSection } from "./FinanceCleanup";

function wrap() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <NextIntlClientProvider locale="en" messages={en} timeZone="UTC">
        <FinanceCleanupSection token="token" />
      </NextIntlClientProvider>
    </QueryClientProvider>,
  );
  fireEvent.click(screen.getByRole("button", { name: en.FinanceCleanup.open }));
}

describe("FinanceCleanupSection", () => {
  beforeEach(() => {
    vi.useRealTimers();
    finance.fetchFinanceCleanupRecords.mockReset();
    finance.fetchFinanceCleanupRecord.mockReset();
    finance.fetchFinanceCleanupRecords.mockImplementation(async (_token: string, query: Record<string, string>) =>
      query.cursor
        ? { records: [{ ...receipt, id: "pay-1", record_type: "payment", code: "R-0042", payment_method: "cash" }], next_cursor: null }
        : { records: [receipt], next_cursor: "next" },
    );
  });

  it("shows who paid, for which package, in words, and loads more pages", async () => {
    wrap();

    const row = await screen.findByRole("button", { name: /Maria P\./ });
    expect(within(row).getByText(en.FinanceCleanup.kinds.receipt)).toBeInTheDocument();
    expect(within(row).getByText(en.FinanceCleanup.documentStatus.paid)).toBeInTheDocument();
    expect(within(row).getByText("Monthly")).toBeInTheDocument();
    expect(finance.fetchFinanceCleanupRecords).toHaveBeenLastCalledWith("token", { limit: "30" });

    fireEvent.click(screen.getByRole("button", { name: en.FinanceCleanup.more }));
    await waitFor(() => expect(screen.getAllByRole("button", { name: /Maria P\./ })).toHaveLength(2));
    expect(finance.fetchFinanceCleanupRecords).toHaveBeenLastCalledWith("token", { cursor: "next", limit: "30" });
    expect(screen.queryByRole("button", { name: en.FinanceCleanup.more })).not.toBeInTheDocument();
  });

  it("searches name, email and number in one field and filters by kind and quick range", async () => {
    wrap();
    await screen.findByRole("button", { name: /Maria P\./ });

    fireEvent.change(screen.getByRole("searchbox", { name: en.FinanceCleanup.searchAria }), { target: { value: "maria@" } });
    await waitFor(() =>
      expect(finance.fetchFinanceCleanupRecords).toHaveBeenLastCalledWith("token", { q: "maria@", limit: "30" }),
    );

    fireEvent.click(screen.getByRole("button", { name: /Filters/ }));
    fireEvent.click(screen.getByRole("button", { name: en.FinanceCleanup.quick.thisMonth }));
    await waitFor(() =>
      expect(finance.fetchFinanceCleanupRecords).toHaveBeenLastCalledWith(
        "token",
        expect.objectContaining({ q: "maria@", from: expect.stringMatching(/-01$/), to: expect.any(String) }),
      ),
    );
    expect(screen.getByRole("button", { name: en.FinanceCleanup.quick.thisMonth })).toHaveAttribute("aria-pressed", "true");

    fireEvent.click(screen.getByRole("combobox", { name: new RegExp(en.FinanceCleanup.kind) }));
    fireEvent.click(await screen.findByRole("option", { name: en.FinanceCleanup.kinds.payment }));
    await waitFor(() =>
      expect(finance.fetchFinanceCleanupRecords).toHaveBeenLastCalledWith("token", expect.objectContaining({ kind: "payment" })),
    );

    fireEvent.click(screen.getByRole("combobox", { name: new RegExp(en.FinanceCleanup.package) }));
    expect(await screen.findByRole("option", { name: "Summer (inactive)" })).toBeInTheDocument();
  });

  it("opens the details in a side panel, with the member and the linked payment", async () => {
    finance.fetchFinanceCleanupRecord.mockImplementation(async (_token: string, type: string, id: string) =>
      type === "receipt"
        ? {
            record: {
              ...receipt,
              customer_email: "maria@example.com",
              issued_on: "2026-11-24",
              created_by_name: "Giorgos",
              balance_due_cents: 0,
              lines: [{ id: "l1", description: "Monthly", quantity: 1, unit_amount_cents: 6000, total_cents: 6000 }],
              linked: [{ id: "pay-1", record_type: "payment", amount_cents: 6000, currency: "EUR", status: "paid", occurred_on: "2026-11-24" }],
            },
          }
        : {
            record: {
              ...receipt,
              id,
              record_type: "payment",
              payment_method: "card_terminal",
              lines: [],
              linked: [{ id: "rec-1", record_type: "receipt", code: "R-0042", amount_cents: 6000, currency: "EUR", status: "paid" }],
            },
          },
    );

    wrap();
    fireEvent.click(await screen.findByRole("button", { name: /Maria P\./ }));

    const panel = await screen.findByRole("dialog", { name: /€60\.00 · Maria P\./ });
    expect(within(panel).getByText("maria@example.com")).toBeInTheDocument();
    expect(within(panel).getByText("Giorgos")).toBeInTheDocument();
    expect(within(panel).getByRole("link", { name: /Open member/ })).toHaveAttribute(
      "href",
      "/org/box/admin/finance?tab=members&member=user-1",
    );
    // The cleanup stays closed until asked for.
    expect(within(panel).queryByLabelText(en.FinanceCleanup.password)).not.toBeInTheDocument();

    await act(async () => {
      fireEvent.click(within(panel).getByRole("button", { name: /Open Payment/ }));
    });
    const paymentPanel = await screen.findByRole("dialog", { name: /€60\.00 · Maria P\./ });
    expect(await within(paymentPanel).findByText(en.FinanceCleanup.method.card_terminal)).toBeInTheDocument();
    expect(finance.fetchFinanceCleanupRecord).toHaveBeenLastCalledWith("token", "payment", "pay-1");
  });
});
