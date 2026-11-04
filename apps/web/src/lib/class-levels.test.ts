import { describe, expect, it } from "vitest";

import { CLASS_LEVELS, classLevelsOf, suitsLevels } from "./class-levels";

describe("class levels (ADR-490)", () => {
  it("lists the three levels in display order, without «all levels»", () => {
    expect(CLASS_LEVELS).toEqual(["beginner", "intermediate", "advanced"]);
  });

  it("a class type with no levels suits every wanted level", () => {
    expect(suitsLevels([], ["advanced"])).toBe(true);
    expect(suitsLevels(undefined, ["beginner"])).toBe(true);
    expect(suitsLevels(null, ["beginner"])).toBe(true);
  });

  it("nothing wanted matches every class type", () => {
    expect(suitsLevels(["advanced"], [])).toBe(true);
  });

  it("matches when the lists overlap", () => {
    expect(suitsLevels(["beginner", "intermediate"], ["intermediate"])).toBe(true);
    expect(suitsLevels(["beginner", "intermediate"], ["advanced", "beginner"])).toBe(true);
    expect(suitsLevels(["advanced"], ["beginner"])).toBe(false);
  });

  it("keeps known levels once, in display order", () => {
    expect(classLevelsOf(["advanced", "beginner", "advanced", "all_levels"])).toEqual(["beginner", "advanced"]);
    expect(classLevelsOf(undefined)).toEqual([]);
  });
});
