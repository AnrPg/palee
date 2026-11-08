import { describe, expect, it } from "vitest";

import { isPlaying, storyReducer, tapDirection } from "@/components/landing/story-player-state";

const reduce = storyReducer(7);
const start = { index: 0, paused: false, holding: false };

describe("guest landing stories (ADR-555)", () => {
  it("goes on, starts again after the last story and never goes back past the first", () => {
    expect(reduce(start, { type: "next" }).index).toBe(1);
    expect(reduce({ ...start, index: 6 }, { type: "next" }).index).toBe(0);
    expect(reduce(start, { type: "previous" }).index).toBe(0);
    expect(reduce({ ...start, index: 3 }, { type: "previous" }).index).toBe(2);
    expect(reduce(start, { type: "go", index: 99 }).index).toBe(6);
  });

  it("pauses with the button and while held, and a release keeps the story", () => {
    const paused = reduce(start, { type: "toggle" });
    expect(isPlaying(paused)).toBe(false);
    expect(isPlaying(reduce(paused, { type: "toggle" }))).toBe(true);

    const held = reduce({ ...start, index: 2 }, { type: "hold" });
    expect(isPlaying(held)).toBe(false);
    const released = reduce(held, { type: "release" });
    expect(released).toEqual({ index: 2, paused: false, holding: false });
  });

  it("goes back from the start third of the screen, and swaps sides right to left", () => {
    expect(tapDirection(50, 390, false)).toBe("previous");
    expect(tapDirection(200, 390, false)).toBe("next");
    expect(tapDirection(350, 390, true)).toBe("previous");
    expect(tapDirection(50, 390, true)).toBe("next");
  });
});
