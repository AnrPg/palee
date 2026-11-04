import { describe, expect, it } from "vitest";

import {
  activeFilterCount,
  analyticsApiQuery,
  analyticsFilterSearch,
  analyticsRange,
  clearDimensions,
  emptyAnalyticsFilter,
  parseAnalyticsFilter,
} from "./analytics-filter";

const A = "11111111-1111-4111-8111-111111111111";
const B = "22222222-2222-4222-8222-222222222222";

describe("analytics filter URL state", () => {
  it("defaults to the last 30 days with no filters and an empty query", () => {
    const filter = parseAnalyticsFilter(new URLSearchParams(""));
    expect(filter).toEqual(emptyAnalyticsFilter());
    expect(analyticsFilterSearch(filter).toString()).toBe("");
  });

  it("round-trips period, dates and filter lists", () => {
    const search = `period=custom&from=2026-10-01&to=2026-10-31&location_ids=${B},${A}&genders=unknown,women&levels=advanced`;
    const filter = parseAnalyticsFilter(new URLSearchParams(search));
    expect(filter.period).toBe("custom");
    expect(filter.from).toBe("2026-10-01");
    expect(filter.location_ids).toEqual([A, B]);
    expect(filter.genders).toEqual(["unknown", "women"]);
    expect(parseAnalyticsFilter(analyticsFilterSearch(filter))).toEqual(filter);
  });

  it("drops unknown values, bad ids and bad dates, and swaps reversed dates", () => {
    const filter = parseAnalyticsFilter(
      new URLSearchParams("period=weird&location_ids=nope&genders=robots&levels=beginner"),
    );
    expect(filter.period).toBe("30");
    expect(filter.location_ids).toEqual([]);
    expect(filter.genders).toEqual([]);
    expect(filter.levels).toEqual(["beginner"]);

    const custom = parseAnalyticsFilter(new URLSearchParams("period=custom&from=2026-10-31&to=2026-10-01"));
    expect([custom.from, custom.to]).toEqual(["2026-10-01", "2026-10-31"]);
    expect(parseAnalyticsFilter(new URLSearchParams("period=custom&from=2026-02-31")).from).toBeNull();
  });

  it("builds the API query: days for presets, from/to for this year and custom", () => {
    const today = "2026-11-04";
    expect(analyticsApiQuery({ ...emptyAnalyticsFilter(), period: "90" }, today)).toEqual({ days: "90" });
    expect(analyticsApiQuery({ ...emptyAnalyticsFilter(), period: "ytd" }, today)).toEqual({ from: "2026-01-01", to: today });
    const custom = { ...emptyAnalyticsFilter(), period: "custom" as const, from: "2026-10-01", to: null, coach_ids: [B, A] };
    expect(analyticsApiQuery(custom, today)).toEqual({ from: "2026-10-01", to: today, coach_ids: `${A},${B}` });
  });

  it("counts the days compared and caps long ranges", () => {
    expect(analyticsRange({ ...emptyAnalyticsFilter(), period: "7" }, "2026-11-04")).toEqual({ from: "2026-10-29", to: "2026-11-04", days: 7 });
    const long = analyticsRange({ ...emptyAnalyticsFilter(), period: "custom", from: "2020-01-01", to: "2026-11-04" }, "2026-11-04");
    expect(long.days).toBe(731);
  });

  it("counts active groups and clears them, keeping the period", () => {
    const filter = { ...emptyAnalyticsFilter(), period: "7" as const, levels: ["beginner"], genders: ["men", "women"] };
    expect(activeFilterCount(filter)).toBe(2);
    expect(activeFilterCount(filter, ["levels"])).toBe(1);
    expect(clearDimensions(filter)).toEqual({ ...emptyAnalyticsFilter(), period: "7" });
  });
});
