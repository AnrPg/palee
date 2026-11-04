import { afterEach, describe, expect, it, vi } from "vitest";

import { fetchFeed } from "@/api/community";

describe("fetchFeed", () => {
  afterEach(() => vi.restoreAllMocks());

  it("turns missing pinned and posts lists into empty lists", async () => {
    vi.spyOn(window, "fetch").mockResolvedValue(new Response(JSON.stringify({ next_cursor: null }), { status: 200 }));

    const page = await fetchFeed("token", {}, null);

    expect(page.pinned).toEqual([]);
    expect(page.posts).toEqual([]);
  });
});
