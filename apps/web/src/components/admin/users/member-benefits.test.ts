import { describe, expect, it } from "vitest";

import { EMPTY_DRAFT, draftReady, endPresets, grantBody, openInvoices, priceCents, revocable } from "./member-benefits";

const today = "2026-11-10";

describe("member benefits sheet (ADR-612)", () => {
  it("offers a week from today and the month's last day", () => {
    expect(endPresets(today)).toEqual({ week: "2026-11-17", monthEnd: "2026-11-30" });
    expect(endPresets("2026-12-28")).toEqual({ week: "2027-01-04", monthEnd: "2026-12-31" });
  });

  it("picks nothing for staff: every kind waits for its own answers", () => {
    expect(draftReady(EMPTY_DRAFT, today)).toBe(false);
    expect(draftReady({ ...EMPTY_DRAFT, kind: "grace" }, today)).toBe(false);
    expect(draftReady({ ...EMPTY_DRAFT, kind: "grace", ends_on: "2026-11-09" }, today)).toBe(false);
    expect(draftReady({ ...EMPTY_DRAFT, kind: "grace", ends_on: today }, today)).toBe(true);
    expect(draftReady({ ...EMPTY_DRAFT, kind: "extra_uses", allowance: "class_visits" }, today)).toBe(false);
    expect(draftReady({ ...EMPTY_DRAFT, kind: "extra_uses", allowance: "class_visits", period: "calendar_month" }, today)).toBe(true);
    expect(draftReady({ ...EMPTY_DRAFT, kind: "package", package_id: "p" }, today)).toBe(false);
    expect(draftReady({ ...EMPTY_DRAFT, kind: "package", package_id: "p", pricing: "price", price: "abc" }, today)).toBe(false);
    expect(draftReady({ ...EMPTY_DRAFT, kind: "package", package_id: "p", pricing: "price", price: "25,50" }, today)).toBe(true);
    expect(draftReady({ ...EMPTY_DRAFT, kind: "debt_forgiven" }, today)).toBe(false);
    expect(draftReady({ ...EMPTY_DRAFT, kind: "grace", ends_on: today, reason: "x".repeat(501) }, today)).toBe(false);
  });

  it("sends what the kind needs, and the reason only when written", () => {
    expect(grantBody({ ...EMPTY_DRAFT, kind: "grace", ends_on: "2026-11-30", reason: "  " }, "k")).toEqual({
      kind: "grace",
      reason: null,
      idempotency_key: "k",
      ends_on: "2026-11-30",
    });
    expect(grantBody({ ...EMPTY_DRAFT, kind: "package", package_id: "p", pricing: "price", price: "30" }, "k")).toMatchObject({
      package_id: "p",
      pricing: { mode: "price", price_cents: 3000 },
    });
    expect(grantBody({ ...EMPTY_DRAFT, kind: "debt_forgiven", invoice_ids: ["i1"], reason: "Bad month" }, "k")).toMatchObject({
      invoice_ids: ["i1"],
      reason: "Bad month",
    });
  });

  it("reads euros as cents", () => {
    expect(priceCents("12,5")).toBe(1250);
    expect(priceCents("0")).toBe(0);
    expect(priceCents("-1")).toBeNull();
  });

  it("lists only charges with something owed, oldest first", () => {
    const invoices = [
      { id: "a", status: "issued", balance_due_cents: 5000, due_date: "2026-11-01" },
      { id: "b", status: "paid", balance_due_cents: 0, due_date: "2026-10-01" },
      { id: "c", status: "overdue", balance_due_cents: 2000, due_date: "2026-10-01" },
      { id: "d", status: "draft", balance_due_cents: 1000, due_date: "2026-09-01" },
    ];
    expect(openInvoices(invoices).map((invoice) => invoice.id)).toEqual(["c", "a"]);
  });

  it("takes back only a grace, free access or extra uses that still count", () => {
    const base = { kind: "grace", state: "active" } as never;
    expect(revocable(base)).toBe(true);
    expect(revocable({ ...(base as object), state: "ended" } as never)).toBe(false);
    expect(revocable({ ...(base as object), kind: "package", state: "given" } as never)).toBe(false);
  });
});
