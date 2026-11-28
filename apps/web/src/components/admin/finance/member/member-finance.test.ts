import { describe, expect, it } from "vitest";

import type { MemberBenefit } from "@/api/member-benefits";

import {
  availableFilters,
  filterMovements,
  heldSubscription,
  heldSubscriptions,
  movements,
  nextCharge,
  openDebtCents,
  refundableCents,
  showsHeaderPayment,
} from "./member-finance";

const profile = {
  invoices: [
    {
      id: "inv-dec",
      invoice_number: "INV-12",
      status: "issued",
      issue_date: "2026-11-28",
      due_date: "2026-11-28",
      total_cents: 5000,
      paid_cents: 1500,
      balance_due_cents: 3500,
      lines: [{ description: "8 visits a month, December" }],
      inserted_at: "2026-11-28T08:00:00Z",
    },
    {
      id: "inv-nov",
      invoice_number: "INV-11",
      status: "partially_paid",
      issue_date: "2026-10-28",
      total_cents: 5000,
      paid_cents: 3000,
      balance_due_cents: 2000,
      lines: [],
      notes: "November",
      inserted_at: "2026-10-28T08:00:00Z",
    },
    { id: "inv-void", status: "void", issue_date: "2026-10-01", total_cents: 900, balance_due_cents: 900, inserted_at: "2026-10-01T08:00:00Z" },
    { id: "inv-draft", status: "draft", issue_date: "2026-09-01", total_cents: 4000, balance_due_cents: 4000, inserted_at: "2026-09-01T08:00:00Z" },
  ],
  payments: [
    { id: "pay-1", finance_invoice_id: "inv-nov", amount_cents: 3000, net_amount_cents: 1000, payment_status: "paid", payment_method: "card_manual", paid_on: "2026-10-30", inserted_at: "2026-10-30T09:00:00Z" },
    { id: "pay-2", amount_cents: 1500, payment_status: "paid", payment_method: "cash", paid_on: "2026-11-26", inserted_at: "2026-11-26T09:00:00Z" },
  ],
  payment_reversals: [{ id: "rev-1", membership_payment_id: "pay-1", amount_cents: 2000, occurred_on: "2026-11-03", reason: "Double charge" }],
  credit_ledger_entries: [
    { id: "cr-1", entry_type: "grant", source_type: "manual_credit", amount_cents: 500, occurred_on: "2026-11-10" },
    { id: "cr-2", entry_type: "grant", source_type: "forgiveness", amount_cents: 700, occurred_on: "2026-11-11" },
    { id: "cr-3", entry_type: "application", source_type: "payment_application", amount_cents: 500, occurred_on: "2026-11-12" },
  ],
  active_package_subscription: {
    id: "sub-1",
    status: "active",
    package_name: "8 visits a month",
    price_cents_snapshot: 5000,
    current_period: { ends_on: "2026-12-27", renews: true },
  },
};

const gift = { id: "ben-1", kind: "extra_uses", given_at: "2026-11-14T10:00:00Z" } as MemberBenefit;

describe("member finance (ADR-784)", () => {
  it("owes every open charge's balance, never a void or draft one", () => {
    expect(openDebtCents(profile)).toBe(5500);
    expect(openDebtCents({})).toBe(0);
  });

  it("lists charges, payments, refunds, gifts and granted credits, newest first", () => {
    const list = movements(profile, [gift]);
    expect(list.map((movement) => `${movement.kind}:${movement.id}`)).toEqual([
      "charge:inv-dec",
      "payment:pay-2",
      "gift:ben-1",
      "credit:cr-1",
      "refund:rev-1",
      "payment:pay-1",
      "charge:inv-nov",
      "charge:inv-void",
      "charge:inv-draft",
    ]);
  });

  it("gives each open charge what is left and keeps a void one closed", () => {
    const [december] = movements(profile);
    expect(december).toMatchObject({ kind: "charge", open: true, balanceCents: 3500, paidCents: 1500, description: "8 visits a month, December" });
    const charges = movements(profile).filter((movement) => movement.kind === "charge");
    expect(charges.find((charge) => charge.id === "inv-nov")).toMatchObject({ open: true, description: "November" });
    expect(charges.find((charge) => charge.id === "inv-void")).toMatchObject({ open: false, voided: true });
    expect(charges.find((charge) => charge.id === "inv-draft")).toMatchObject({ open: false });
  });

  it("names the charge a payment went to and what can still be given back", () => {
    const payment = movements(profile).find((movement) => movement.id === "pay-1");
    expect(payment).toMatchObject({ kind: "payment", chargeNumber: "INV-11", refundableCents: 1000 });
    expect(refundableCents({ id: "p", amount_cents: 1000, payment_status: "paid" }, [{ membership_payment_id: "p", amount_cents: 400 }])).toBe(600);
    expect(refundableCents({ id: "p", amount_cents: 1000, payment_status: "pending" })).toBe(0);
  });

  it("offers only the filters the list needs", () => {
    expect(availableFilters(movements(profile, [gift]))).toEqual(["all", "charge", "payment", "refund", "gift", "credit"]);
    expect(availableFilters(movements({ invoices: profile.invoices }))).toEqual(["all", "charge"]);
    expect(filterMovements(movements(profile), "refund").map((movement) => movement.id)).toEqual(["rev-1"]);
  });

  it("puts the next charge the day after a renewing period, at its price", () => {
    expect(nextCharge(profile)).toEqual({ day: "2026-12-28", amountCents: 5000, packageName: "8 visits a month" });
    const ending = { active_package_subscription: { ...profile.active_package_subscription, current_period: { ends_on: "2026-12-27", renews: false } } };
    expect(nextCharge(ending)).toBeNull();
    expect(heldSubscription(profile)?.id).toBe("sub-1");
    expect(heldSubscription({ package_subscriptions: [{ id: "old", status: "ended" }, { id: "now", status: "active" }] })?.id).toBe("now");
  });

  it("lists every package still held, active or paused, the current one first", () => {
    const many = {
      active_package_subscription: { id: "now", status: "active" },
      package_subscriptions: [
        { id: "old", status: "ended" },
        { id: "now", status: "active" },
        { id: "rest", status: "paused" },
        { id: "second", status: "active" },
      ],
    };
    expect(heldSubscriptions(many).map((subscription) => subscription.id)).toEqual(["now", "rest", "second"]);
    expect(heldSubscriptions({})).toEqual([]);
  });

  it("shows the header payment only while something is owed and off the Finance tab", () => {
    expect(showsHeaderPayment({ owedCents: 100, onFinanceTab: false, canTakePayments: true })).toBe(true);
    expect(showsHeaderPayment({ owedCents: 100, onFinanceTab: true, canTakePayments: true })).toBe(false);
    expect(showsHeaderPayment({ owedCents: 0, onFinanceTab: false, canTakePayments: true })).toBe(false);
    expect(showsHeaderPayment({ owedCents: 100, onFinanceTab: false, canTakePayments: false })).toBe(false);
  });
});
