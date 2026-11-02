import { describe, expect, it } from "vitest";

import type { UiTranslator } from "@/i18n/presentation";

import catalogJson from "./__fixtures__/package-catalog.json";
import { advancedGroupOf, fieldValueText } from "./package-ui";
import type { CatalogField } from "./package-catalog";

const fields = (catalogJson as unknown as { fields: CatalogField[] }).fields;
const spec = (key: string) => fields.find((field) => field.key === key)!;
const t = ((key: string, values?: Record<string, unknown>) => (values ? `${key}:${JSON.stringify(values)}` : key)) as unknown as UiTranslator;
const names = { coaches: [], packages: [{ id: "p1", name: "On-ramp" }, { id: "p2", name: "Unlimited" }] };

describe("package rules in «Προχωρημένα» (W1 s7)", () => {
  it("drops the weekly booking limit from the catalogue", () => {
    expect(fields.some((field) => field.key === "booking.weekly_limit")).toBe(false);
  });

  it("groups purchase rules with «μόνο νέα μέλη» and «μία φορά», and the booking limits together", () => {
    expect(advancedGroupOf(spec("terms.prerequisite_package_ids"))).toBe("purchase_rules");
    expect(advancedGroupOf({ key: "terms.new_members_only", section: "terms" })).toBe("purchase_rules");
    expect(advancedGroupOf({ key: "terms.once_per_person", section: "terms" })).toBe("purchase_rules");
    expect(advancedGroupOf(spec("booking.daily_limit"))).toBe("booking_limits");
    expect(advancedGroupOf({ key: "facility.open_gym", section: "facility" })).toBe("facility");
  });

  it("reads a limit as a number with its unit, or «Χωρίς όριο»", () => {
    expect(fieldValueText(t, spec("booking.daily_limit"), null, names)).toBe("pkgNoLimit");
    expect(fieldValueText(t, spec("booking.daily_limit"), 2, names)).toBe('2 pkgFieldBookingDailyLimitSuffix:{"count":2}');
  });

  it("reads prerequisites as package names", () => {
    expect(fieldValueText(t, spec("terms.prerequisite_package_ids"), ["p1"], names)).toBe("On-ramp");
    expect(fieldValueText(t, spec("terms.prerequisite_package_ids"), [], names)).toBe("pkgNone");
  });
});
