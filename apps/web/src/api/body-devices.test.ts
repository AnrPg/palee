import { beforeEach, describe, expect, it, vi } from "vitest";

const apiRequest = vi.fn();
vi.mock("@/api/client", () => ({ apiRequest: (...args: unknown[]) => apiRequest(...args) }));

import { fetchClientRanks, fetchMyRanks, fetchRankLadders, fetchWatches } from "@/api/body-devices";

describe("body and devices lists", () => {
  beforeEach(() => apiRequest.mockReset());

  it("reads a malformed answer as an empty list, never a crash", async () => {
    apiRequest.mockResolvedValue({});
    expect((await fetchWatches("t")).watches).toEqual([]);
    expect((await fetchRankLadders("t", "box")).ladders).toEqual([]);
    expect((await fetchMyRanks("t", "box")).ladders).toEqual([]);
    expect((await fetchClientRanks("t", "box", "u-1")).ladders).toEqual([]);
  });

  it("keeps a real list and the rest of the answer", async () => {
    apiRequest.mockResolvedValue({ watches: [{ platform: "apple_watch" }], health_consent: true });
    expect(await fetchWatches("t")).toEqual({ watches: [{ platform: "apple_watch" }], health_consent: true });
  });
});
