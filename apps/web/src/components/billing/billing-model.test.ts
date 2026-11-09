import { describe, expect, it } from "vitest";

import { billingTab, leaveState, sessionsLeft, totalsByCurrency, validityProgress } from "./billing-model";

const usage = (limit: number | "unlimited", remaining: number | "unlimited") => ({
  limit,
  remaining,
  period: "subscription_period",
  period_start: "2026-10-01",
  period_end: "2026-10-31",
  committed: 0,
  extensions: 0,
});

describe("billingTab", () => {
  it("reads a known tab and falls back to the package", () => {
    expect(billingTab("transactions")).toBe("transactions");
    expect(billingTab("offers")).toBe("offers");
    expect(billingTab("documents")).toBe("membership");
    expect(billingTab(null)).toBe("membership");
  });
});

describe("totalsByCurrency", () => {
  it("sums each currency, money back counting negative", () => {
    expect(
      totalsByCurrency([
        { amount_cents: 4000, currency: "EUR" },
        { amount_cents: -500, currency: "EUR" },
        { amount_cents: 1200, currency: "BGN" },
      ]),
    ).toEqual([
      { currency: "BGN", cents: 1200 },
      { currency: "EUR", cents: 3500 },
    ]);
    expect(totalsByCurrency([])).toEqual([]);
  });
});

describe("sessionsLeft", () => {
  it("prefers class visits and reports unlimited packages", () => {
    expect(sessionsLeft({ allowances: { bookings: usage(20, 3), class_visits: usage(12, 5) } })).toEqual({
      unlimited: false,
      remaining: 5,
      limit: 12,
    });
    expect(sessionsLeft({ allowances: { class_visits: usage("unlimited", "unlimited") } })).toEqual({ unlimited: true });
    expect(sessionsLeft({ allowances: {} })).toBeNull();
    expect(sessionsLeft(null)).toBeNull();
  });
});

describe("validityProgress", () => {
  it("is the share of the window that has passed", () => {
    expect(validityProgress("2026-10-01", "2026-10-31", new Date("2026-10-16T00:00:00Z"))).toBeCloseTo(0.5, 1);
    expect(validityProgress("2026-10-01", "2026-10-31", new Date("2026-12-01"))).toBe(1);
    expect(validityProgress(null, "2026-10-31", new Date())).toBeNull();
  });
});

describe("leaveState (ADR-595)", () => {
  const actions = (leave: boolean) => ({ self_service_leave: leave });
  const today = "2026-11-09";
  const current = [{ current: true, commitment_ends_on: null }];

  it("after leaving, keeps the package to its last day and tells apart who ended it", () => {
    expect(
      leaveState({ actions: actions(false), subscriptions: current, membership: { leaving_on: "2026-11-30", left_by: "member" } }, today),
    ).toEqual({ kind: "left", packageUntil: "2026-11-30", byStaff: false });
    expect(
      leaveState({ actions: actions(false), subscriptions: current, membership: { leaving_on: "2026-11-30", left_by: "staff" } }, today),
    ).toMatchObject({ byStaff: true });
  });

  it("keeps no package once it ended or when there was none", () => {
    expect(leaveState({ actions: actions(false), subscriptions: current, membership: { leaving_on: "2026-11-01" } }, today)).toMatchObject({
      packageUntil: null,
    });
    expect(leaveState({ actions: actions(false), subscriptions: [], membership: { leaving_on: today } }, today)).toMatchObject({
      packageUntil: null,
    });
  });

  it("offers leaving now with what stays: the package, a commitment and money owed", () => {
    expect(
      leaveState(
        {
          actions: actions(true),
          outstanding_cents: 5000,
          subscriptions: [{ current: true, commitment_ends_on: "2027-03-31" }],
          membership: { leaving_on: null, leave_preview_on: "2027-03-31" },
        },
        today,
      ),
    ).toEqual({ kind: "can_leave", packageUntil: "2027-03-31", commitmentUntil: "2027-03-31", owedCents: 5000 });
  });

  it("offers nothing without a membership", () => {
    expect(leaveState({ actions: actions(true), membership: null }, today)).toEqual({ kind: "none" });
    expect(leaveState({ actions: actions(false), membership: { leaving_on: null } }, today)).toEqual({ kind: "none" });
  });
});
