import { describe, expect, it } from "vitest";

import { exercisesLine, leaderboardPlace, wrapText } from "./share-card";

describe("share card (ADR-565)", () => {
  it("lists the first exercises with absolute loads, skipping headers and repeats", () => {
    expect(
      exercisesLine([
        { item_type: "header", name: "21-15-9" },
        { name: "Thrusters", load_mode: "absolute", load_value: 43 },
        { name: "Pull-ups" },
        { name: "thrusters", load_mode: "absolute", load_value: 43 },
        { name: "Box jumps", load_mode: "bw", load_value: 1 },
        { name: "Row" },
        { name: "Burpees" },
      ]),
    ).toBe("Thrusters 43 kg · Pull-ups · Box jumps +2");
    expect(exercisesLine([{ name: " " }])).toBeNull();
  });

  it("finds the member's place only when they are on the board and opted in", () => {
    const rows = [
      { rank: 1, me: false, opted_in: true },
      { rank: 2, me: true, opted_in: true },
      { rank: 3, me: false, opted_in: true },
    ];
    expect(leaderboardPlace(rows)).toEqual({ rank: 2, total: 3 });
    expect(leaderboardPlace(rows.map((row) => ({ ...row, opted_in: !row.me })))).toBeNull();
    expect(leaderboardPlace([{ rank: 1, me: false, opted_in: true }])).toBeNull();
  });

  it("wraps text into at most the given lines and ends a cut line with …", () => {
    const measure = (value: string) => value.length * 10;
    expect(wrapText("one two three", 80, measure)).toEqual(["one two", "three"]);
    const cut = wrapText("aaaa bbbb cccc dddd eeee", 90, measure, 2);
    expect(cut).toHaveLength(2);
    expect(cut[1].endsWith("…")).toBe(true);
    expect(wrapText("averyveryverylongword", 50, measure)).toEqual(["averyveryverylongword"]);
  });
});
