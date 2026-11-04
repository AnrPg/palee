import { beforeEach, describe, expect, it, vi } from "vitest";

const apiRequest = vi.fn();
vi.mock("@/api/client", () => ({ apiRequest: (...args: unknown[]) => apiRequest(...args) }));

import { previewDayWorkout } from "@/api/day-workouts";

const request = { date: "2026-11-05", master_workout_id: "w-fran", class_type_ids: ["ct-1"] };

describe("previewDayWorkout", () => {
  beforeEach(() => apiRequest.mockReset());

  it("returns the server's lists", async () => {
    const item = { id: "s1", name: "CrossFit", scheduled_at: "2026-11-05T05:00:00Z" };
    apiRequest.mockResolvedValue({ inherit: [item], own: [], started: [] });
    await expect(previewDayWorkout("tok", request)).resolves.toEqual({ inherit: [item], own: [], started: [] });
  });

  it("reads a missing or malformed list as an empty one", async () => {
    apiRequest.mockResolvedValue({ own: "nope" });
    await expect(previewDayWorkout("tok", request)).resolves.toEqual({ inherit: [], own: [], started: [] });
    apiRequest.mockResolvedValue(null);
    await expect(previewDayWorkout("tok", request)).resolves.toEqual({ inherit: [], own: [], started: [] });
  });
});
