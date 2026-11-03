import { describe, expect, it } from "vitest";

import { foldSingleTileGroups } from "@/components/admin/hub-groups";

const group = (label: string, items: string[]) => ({ label, items });

describe("foldSingleTileGroups", () => {
  it("keeps groups with two or more tiles as they are", () => {
    const groups = [group("ops", ["a", "b"]), group("content", ["c", "d"])];
    expect(foldSingleTileGroups(groups)).toEqual(groups);
  });

  it("moves a lone tile into the first group and hides its group", () => {
    expect(foldSingleTileGroups([group("ops", ["a", "b"]), group("content", ["c"]), group("stats", ["d", "e"])])).toEqual([
      group("ops", ["a", "b", "c"]),
      group("stats", ["d", "e"]),
    ]);
  });

  it("drops empty groups", () => {
    expect(foldSingleTileGroups([group("ops", []), group("content", ["c", "d"])])).toEqual([group("content", ["c", "d"])]);
  });

  it("joins lone tiles into one group when no group has two", () => {
    expect(foldSingleTileGroups([group("ops", ["a"]), group("content", ["c"])])).toEqual([group("ops", ["a", "c"])]);
    expect(foldSingleTileGroups([])).toEqual([]);
  });
});
