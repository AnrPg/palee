import { describe, expect, test } from "vitest";

import { earliestDateKey, formatDateKey } from "./local-date";

describe("formatDateKey", () => {
  test("shows a due date as a day in the reader's language", () => {
    expect(formatDateKey("el", "2026-11-28")).toMatch(/28/);
    expect(formatDateKey("el", "2026-11-28")).toMatch(/2026/);
    expect(formatDateKey("en-GB", "2026-11-28")).toBe("28 Nov 2026");
  });

  test("never shifts the day, whatever the time part or zone", () => {
    expect(formatDateKey("en-GB", "2026-01-01T23:30:00Z")).toBe("1 Jan 2026");
  });

  test("anything that is not a day reads as null", () => {
    for (const value of [null, undefined, "", "soon", 42, "2026-02-30"]) {
      expect(formatDateKey("en", value)).toBeNull();
    }
  });
});

describe("earliestDateKey", () => {
  test("picks the oldest day and ignores the rest", () => {
    expect(earliestDateKey(["2026-11-03", null, "2026-10-28", "x"])).toBe("2026-10-28");
    expect(earliestDateKey([])).toBeNull();
  });
});
