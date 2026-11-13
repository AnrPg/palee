import { afterEach, describe, expect, it, vi } from "vitest";

import { fetchFeed, fetchWodToday } from "@/api/community";

describe("fetchFeed", () => {
  afterEach(() => vi.restoreAllMocks());

  it("turns missing pinned and posts lists into empty lists", async () => {
    vi.spyOn(window, "fetch").mockResolvedValue(new Response(JSON.stringify({ next_cursor: null }), { status: 200 }));

    const page = await fetchFeed("token", {}, null);

    expect(page.pinned).toEqual([]);
    expect(page.posts).toEqual([]);
  });
});

describe("fetchWodToday", () => {
  afterEach(() => vi.restoreAllMocks());

  it("reads an empty answer as a card without a WOD and with empty lists", async () => {
    vi.spyOn(window, "fetch").mockResolvedValue(new Response("{}", { status: 200 }));
    const card = await fetchWodToday("token", "kypseli", "Europe/Athens");
    expect(card.workout).toBeUndefined();
    expect(card.classes).toEqual([]);
    expect(card.leaderboard).toEqual([]);
  });
});
