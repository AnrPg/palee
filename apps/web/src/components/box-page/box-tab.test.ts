import { describe, expect, it } from "vitest";

import { boxTab } from "./PublicBoxView";

describe("boxTab (ADR-590)", () => {
  it("opens the club for its members and «Σχετικά» for everyone else", () => {
    expect(boxTab("", true)).toBe("club");
    expect(boxTab("", false)).toBe("about");
  });

  it("follows the hash, but never shows the club to a non-member", () => {
    expect(boxTab("schedule", true)).toBe("schedule");
    expect(boxTab("about", true)).toBe("about");
    expect(boxTab("club", false)).toBe("about");
    expect(boxTab("nonsense", false)).toBe("about");
  });
});
