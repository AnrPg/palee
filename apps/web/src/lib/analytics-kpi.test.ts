import { describe, expect, it } from "vitest";

import { deltaTone, isResettable, kpiKeys, readKpi } from "./analytics-kpi";

describe("analytics KPIs", () => {
  it("colours a change by whether up is good for the metric", () => {
    expect(deltaTone("overview.active_members", 3)).toBe("good");
    expect(deltaTone("overview.active_members", -3)).toBe("bad");
    expect(deltaTone("training.no_show_rate", 2)).toBe("bad");
    expect(deltaTone("training.no_show_rate", -2)).toBe("good");
    expect(deltaTone("overview.churn_rate", -0.5)).toBe("good");
    expect(deltaTone("finance.days_sales_outstanding", 1)).toBe("bad");
    expect(deltaTone("training.class_fill_rate", 0)).toBe("flat");
    expect(deltaTone("training.class_fill_rate", null)).toBe("none");
  });

  it("reads a suppressed KPI without a number and tolerates missing fields", () => {
    const payload = {
      kpis: {
        "overview.churn_rate": { value: 4.2, previous: 5, delta: -0.8, since: "2026-11-04T00:00:00Z", suppressed: false },
        "overview.new_members": { value: 3, suppressed: true, rows: [{ key: "x" }] },
        "overview.unknown_metric": { value: 1 },
      },
    };
    const churn = readKpi(payload, "overview.churn_rate");
    expect(churn).toMatchObject({ value: 4.2, previous: 5, delta: -0.8, unit: "percent", since: "2026-11-04T00:00:00Z" });
    const suppressed = readKpi(payload, "overview.new_members");
    expect(suppressed).toMatchObject({ value: null, delta: null, suppressed: true, rows: [] });
    expect(readKpi({}, "finance.mrr")).toMatchObject({ value: null, previous: null, suppressed: false, rows: [] });
    expect(kpiKeys(payload)).toEqual(["overview.new_members", "overview.churn_rate"]);
  });

  it("refuses resets of snapshot metrics", () => {
    expect(isResettable("training.no_show_rate")).toBe(true);
    expect(isResettable("overview.active_members")).toBe(false);
    expect(isResettable("finance.mrr")).toBe(false);
    expect(isResettable("nope")).toBe(false);
  });
});
