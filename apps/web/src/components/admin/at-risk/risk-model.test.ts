import { describe, expect, it } from "vitest";

import type { MemberRisk, RiskReason } from "@/api/leads";

import { contactedThisSpell, personName, reasonLine, sortedReasons } from "./risk-model";

describe("reasonLine", () => {
  it("reads the numbers each reason needs from its facts", () => {
    expect(reasonLine({ code: "attendance_drop", facts: { per_week_now: 1, per_week_usual: 3 } })).toEqual({ key: "attendance_drop", values: { now: 1, usual: 3 } });
    expect(reasonLine({ code: "absent", facts: { days: 12 } })).toEqual({ key: "absent", values: { days: 12 } });
    expect(reasonLine({ code: "no_first_visit", facts: { member_for_days: 9 } })).toEqual({ key: "no_first_visit", values: { days: 9 } });
    expect(reasonLine({ code: "payment_overdue", facts: { invoices: 2 } })).toEqual({ key: "payment_overdue", values: { count: 2 } });
    expect(reasonLine({ code: "new_member_slow_start", facts: { member_for_days: 21, visits: 1 } })).toEqual({
      key: "new_member_slow_start",
      values: { days: 21, visits: 1 },
    });
  });

  it("falls back to zero when a fact is missing", () => {
    expect(reasonLine({ code: "package_ending", facts: {} })).toEqual({ key: "package_ending", values: { days: 0 } });
  });
});

describe("sortedReasons", () => {
  it("puts the reasons that weigh most first", () => {
    const reasons = [
      { code: "absent", points: 10, facts: {} },
      { code: "payment_overdue", points: 30, facts: {} },
    ] as RiskReason[];
    expect(sortedReasons({ reasons }).map((reason) => reason.code)).toEqual(["payment_overdue", "absent"]);
    expect(reasons[0].code).toBe("absent");
  });
});

describe("contactedThisSpell", () => {
  const since = "2027-05-01T00:00:00Z";
  it("counts a contact only from the current level on", () => {
    expect(contactedThisSpell({ contacted_at: null, level_since: since } as Pick<MemberRisk, "contacted_at" | "level_since">)).toBe(false);
    expect(contactedThisSpell({ contacted_at: "2027-04-30T00:00:00Z", level_since: since })).toBe(false);
    expect(contactedThisSpell({ contacted_at: "2027-05-02T00:00:00Z", level_since: since })).toBe(true);
  });
});

describe("personName", () => {
  it("prefers the display name, then the handle", () => {
    expect(personName({ display_name: "Anna", handle: "anna" })).toBe("Anna");
    expect(personName({ display_name: " ", handle: "anna" })).toBe("anna");
    expect(personName(null)).toBeNull();
  });
});
