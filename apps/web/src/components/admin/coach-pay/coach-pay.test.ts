import { describe, expect, it } from "vitest";

import type { PayItem, PayRule } from "@/api/coach-pay";

import {
  activeRules,
  addableItems,
  adjustmentBody,
  defaultBasis,
  emptyItemDraft,
  emptyLineDraft,
  emptyRuleDraft,
  groupKeyOf,
  groupSentence,
  itemBody,
  itemErrors,
  lineErrors,
  nextPeriodRange,
  overtimeItems,
  overtimeLineBody,
  overtimeTotal,
  parseBps,
  parseCents,
  parseHours,
  payFileName,
  payPeople,
  payslipLanguage,
  periodLabel,
  periodRangeError,
  primaryAction,
  ruleBody,
  ruleErrors,
  ruleSentence,
} from "./coach-pay";

const money = (cents: number) => `${(cents / 100).toFixed(2)} €`;
const percent = (bps: number) => `${bps / 100}%`;

const rule = (patch: Partial<PayRule> = {}) =>
  ({
    id: "r1",
    coach_user_id: "u1",
    coach_name: "Νίκος Α.",
    kind: "per_class",
    amount_cents: 1500,
    percent_bps: null,
    min_attendees: 0,
    count_statuses: [],
    sales_scope: null,
    frequency: null,
    starts_on: "2026-01-01",
    ends_on: null,
    amount_basis: "gross",
    archived_at: null,
    currency: "EUR",
    note: null,
    ...patch,
  }) as unknown as PayRule;

const item = (patch: Partial<PayItem> = {}) =>
  ({ id: "i1", kind: "allowance", name: "Μετακίνηση", amount_cents: 2000, unit: "per_period", roles: ["coach"], amount_basis: "gross", currency: "EUR", archived_at: null, ...patch }) as PayItem;

describe("pay rules", () => {
  it("reads every rule as a sentence", () => {
    expect(ruleSentence(rule(), money, percent)).toEqual({ key: "rulePerClass", values: { amount: "15.00 €" } });
    expect(ruleSentence(rule({ min_attendees: 3 }), money, percent)).toEqual({ key: "rulePerClassMin", values: { amount: "15.00 €", min: 3 } });
    expect(ruleSentence(rule({ kind: "percent_of_sales", percent_bps: 1000, sales_scope: "own_clients" }), money, percent)).toEqual({ key: "rulePercent_own_clients", values: { percent: "10%" } });
    expect(ruleSentence(rule({ kind: "fixed", amount_cents: 80000, frequency: "monthly" }), money, percent).key).toBe("ruleFixed_monthly");
  });

  it("keeps archived and ended rules out and puts people without a rule last", () => {
    const rules = [rule(), rule({ id: "r2", coach_user_id: "u3", ends_on: "2026-09-30" }), rule({ id: "r3", coach_user_id: "u4", archived_at: "2026-10-01T00:00:00Z" })];
    const active = activeRules(rules, "2026-10-15");
    expect(active.map((entry) => entry.id)).toEqual(["r1"]);
    const people = payPeople([{ id: "u2", name: "Άννα" }, { id: "u1", name: "Νίκος Α." }], active, "—");
    expect(people.map((person) => [person.userId, person.rules.length])).toEqual([["u1", 1], ["u2", 0]]);
  });

  it("parses amounts and percents in either decimal mark", () => {
    expect(parseCents("15,5")).toBe(1550);
    expect(parseCents("-20")).toBeNull();
    expect(parseCents("-20", true)).toBe(-2000);
    expect(parseBps("12,5")).toBe(1250);
    expect(parseBps("0")).toBeNull();
    expect(parseBps("101")).toBeNull();
  });

  it("keeps the rule form's errors under their fields", () => {
    const draft = emptyRuleDraft("2026-11-02");
    expect(ruleErrors(draft)).toEqual({ amount: "errorAmount" });
    expect(ruleErrors({ ...draft, kind: "percent_of_sales" })).toEqual({ percent: "errorPercent" });
    expect(ruleErrors({ ...draft, amount: "15", kind: "per_attendee", countStatuses: [] })).toEqual({ countStatuses: "errorCountStatuses" });
    expect(ruleErrors({ ...draft, amount: "15", endsOn: "2026-10-01" })).toEqual({ endsOn: "errorEndsBeforeStart" });
  });

  it("sends only the fields the kind uses, gross by default", () => {
    const draft = { ...emptyRuleDraft("2026-11-02"), amount: "15", minAttendees: "3" };
    expect(ruleBody(draft, "u1")).toEqual({
      coach_user_id: "u1",
      kind: "per_class",
      starts_on: "2026-11-02",
      ends_on: null,
      amount_basis: "gross",
      note: null,
      amount_cents: 1500,
      min_attendees: 3,
    });
    const percentBody = ruleBody({ ...draft, kind: "percent_of_sales", percent: "10", salesScope: "box_all" }, "u1");
    expect(percentBody).toMatchObject({ percent_bps: 1000, sales_scope: "box_all" });
    expect(percentBody).not.toHaveProperty("amount_cents");
  });
});

describe("pay periods", () => {
  it("has one primary action per status", () => {
    expect(primaryAction("draft")).toBe("approve");
    expect(primaryAction("approved")).toBe("export");
    expect(primaryAction("exported")).toBeNull();
    // The accountant (finance reports only) may export an approved period, never approve.
    expect(primaryAction("draft", false)).toBeNull();
    expect(primaryAction("approved", false)).toBe("export");
  });

  it("suggests the month after the latest period, or last month", () => {
    expect(nextPeriodRange([{ ends_on: "2026-09-30" }, { ends_on: "2026-10-31" }], "2026-11-02")).toEqual({ startsOn: "2026-11-01", endsOn: "2026-11-30" });
    expect(nextPeriodRange([], "2026-11-02")).toEqual({ startsOn: "2026-10-01", endsOn: "2026-10-31" });
  });

  it("checks the dates of a period", () => {
    expect(periodRangeError("2026-10-01", "2026-10-31")).toBeNull();
    expect(periodRangeError("2026-10-31", "2026-10-01")).toBe("errorEndsBeforeStart");
    expect(periodRangeError("2026-01-01", "2026-06-30")).toBe("errorPeriodTooLong");
    expect(periodRangeError("", "2026-10-01")).toBe("errorDate");
  });

  it("names a whole month by its name", () => {
    expect(periodLabel("2026-10-01", "2026-10-31", "el")).toBe("Οκτώβριος 2026");
    expect(periodLabel("2026-10-01", "2026-10-15", "en")).toMatch(/Oct/);
  });

  it("explains a group as quantity × rate or a percent of a base", () => {
    const group = { key: "rule:r1:gross", kind: "per_class", amount_basis: "gross", amount_cents: 48000, line_count: 32, quantity: 32, unit_cents: 1500, terms: null } as never;
    expect(groupSentence(group, money, percent)).toEqual({ key: "group_per_class", values: { count: 32, unit: "15.00 €" } });
    const sales = { key: "rule:r2:gross", kind: "percent_of_sales", amount_basis: "gross", amount_cents: 2000, line_count: 2, quantity: 2, base_cents: 20000, terms: { percent_bps: 1000 } } as never;
    expect(groupSentence(sales, money, percent)).toEqual({ key: "groupPercent", values: { percent: "10%", base: "200.00 €" } });
  });

  it("keys a line the way the API groups it, basis included", () => {
    expect(groupKeyOf({ rule_id: "r1", pay_item_id: null, kind: "clawback", amount_basis: "gross" })).toBe("rule:r1:gross");
    expect(groupKeyOf({ rule_id: null, pay_item_id: "i1", kind: "allowance", amount_basis: "net" })).toBe("pay_item:i1:allowance:net");
    expect(groupKeyOf({ rule_id: null, pay_item_id: null, kind: "ad_hoc", amount_basis: "gross" })).toBe("manual:ad_hoc:gross");
  });

  it("names files and picks the payslip's language", () => {
    expect(payFileName("coach-pay", { starts_on: "2026-10-01", ends_on: "2026-10-31" }, "csv")).toBe("coach-pay-2026-10-01-2026-10-31.csv");
    expect(payslipLanguage("el")).toBe("el");
    expect(payslipLanguage("pt-PT")).toBe("pt-PT");
    expect(payslipLanguage("ar")).toBe("en");
  });
});

describe("lines added by hand", () => {
  it("starts «Μη φορολογητέο» as net and the rest as gross", () => {
    expect(defaultBasis("non_taxable_reimbursement")).toBe("net");
    expect(defaultBasis("adjustment")).toBe("gross");
    expect(defaultBasis("ad_hoc")).toBe("gross");
  });

  it("lets only a correction be negative and needs a reason", () => {
    const draft = emptyLineDraft();
    expect(lineErrors({ ...draft, amount: "-20", note: "Λάθος" }, null)).toEqual({});
    expect(lineErrors({ ...draft, kind: "ad_hoc", amount: "-20", note: "x" }, null)).toEqual({ amount: "errorPositive" });
    expect(lineErrors({ ...draft, amount: "20" }, null)).toEqual({ note: "errorNoteRequired" });
    expect(lineErrors({ ...draft, kind: "allowance" }, null)).toEqual({ itemId: "errorItem" });
    expect(lineErrors({ ...draft, kind: "allowance", quantity: "0" }, item({ unit: "per_occurrence" }))).toEqual({ quantity: "errorWholeNumber" });
  });

  it("checks one-off overtime: an overtime item, hours, an optional rate and a reason", () => {
    const draft = { ...emptyLineDraft(), kind: "overtime" as const };
    const overtime = item({ id: "o1", kind: "overtime", unit: "per_hour", amount_cents: 1200 });
    expect(lineErrors(draft, null)).toEqual({ itemId: "errorOvertimeItem", hours: "errorHours", note: "errorNoteRequired" });
    expect(lineErrors({ ...draft, hours: "2,5", note: "Αγώνας" }, overtime)).toEqual({});
    expect(lineErrors({ ...draft, hours: "2,5", rate: "0", note: "Αγώνας" }, overtime)).toEqual({ rate: "errorAmount" });
  });

  it("reads hours as decimals or h:mm, up to a week", () => {
    expect(parseHours("2")).toBe(120);
    expect(parseHours("2,5")).toBe(150);
    expect(parseHours("2.25")).toBe(135);
    expect(parseHours("2:30")).toBe(150);
    expect(parseHours("168")).toBe(10080);
    for (const bad of ["", "0", "0:00", "169", "2:75", "abc", "-1"]) expect(parseHours(bad)).toBeNull();
  });

  it("pays one-off overtime at the item's rate unless another is typed", () => {
    const overtime = item({ id: "o1", kind: "overtime", unit: "per_hour", amount_cents: 1200 });
    const draft = { ...emptyLineDraft(), kind: "overtime" as const, itemId: "o1", hours: "2:30", note: " Αγώνας " };
    expect(overtimeTotal(draft, overtime)).toBe(3000);
    expect(overtimeLineBody(draft, "u1", overtime)).toEqual({ user_id: "u1", pay_item_id: "o1", minutes: 150, note: "Αγώνας", amount_basis: "gross" });
    expect(overtimeLineBody({ ...draft, rate: "15" }, "u1", overtime)).toMatchObject({ minutes: 150, unit_cents: 1500 });
    expect(overtimeTotal({ ...draft, rate: "15" }, overtime)).toBe(3750);
    expect(overtimeItems([overtime, item(), item({ id: "o2", kind: "overtime", archived_at: "2026-10-01T00:00:00Z" })])).toEqual([overtime]);
  });

  it("sends a correction with its sign, note and basis", () => {
    expect(adjustmentBody({ ...emptyLineDraft(), amount: "-20", note: " Λάθος ", basis: "net" }, "u1")).toEqual({
      coach_user_id: "u1",
      kind: "adjustment",
      amount_cents: -2000,
      note: "Λάθος",
      amount_basis: "net",
    });
  });
});

describe("overtime and allowances", () => {
  it("needs a weekly threshold for overtime and at least one role", () => {
    const overtime = emptyItemDraft("overtime");
    expect(overtime.unit).toBe("per_hour");
    expect(itemErrors({ ...overtime, name: "Υπερωρία", amount: "12" })).toEqual({ threshold: "errorThreshold" });
    expect(itemErrors({ ...emptyItemDraft(), name: "Μετακίνηση", amount: "20", roles: [] })).toEqual({ roles: "errorRoles" });
  });

  it("sends roles in a fixed order and no threshold for an allowance", () => {
    const body = itemBody({ ...emptyItemDraft(), name: " Μετακίνηση ", amount: "20", roles: ["janitor", "coach"] });
    expect(body).toMatchObject({ kind: "allowance", name: "Μετακίνηση", amount_cents: 2000, weekly_threshold: null, roles: ["coach", "janitor"] });
    expect(itemBody({ ...emptyItemDraft("overtime"), name: "Υ", amount: "12", threshold: "20" })).toMatchObject({ unit: "per_hour", weekly_threshold: 20 });
  });

  it("offers only active allowances by hand", () => {
    expect(addableItems([item(), item({ id: "i2", kind: "overtime" }), item({ id: "i3", archived_at: "2026-10-01T00:00:00Z" })]).map((entry) => entry.id)).toEqual(["i1"]);
  });
});
