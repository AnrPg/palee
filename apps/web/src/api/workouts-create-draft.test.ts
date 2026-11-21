import { beforeEach, describe, expect, it, vi } from "vitest";

const apiRequest = vi.fn();
vi.mock("@/api/client", () => ({ apiRequest: (...args: unknown[]) => apiRequest(...args) }));

import { createDraftWorkout } from "@/api/workouts";

describe("createDraftWorkout", () => {
  beforeEach(() => {
    apiRequest.mockReset();
    apiRequest.mockResolvedValue({ draft: { id: "d1" } });
  });

  it("sends no body for a plain draft at the library root", async () => {
    await expect(createDraftWorkout("tok")).resolves.toEqual({ id: "d1" });
    expect(apiRequest).toHaveBeenCalledWith("/admin/workouts", { method: "POST", token: "tok" });
  });

  it("sends the folder and, for a WOD made for one assignment, awaiting_filing (ADR-680)", async () => {
    await createDraftWorkout("tok", "f1");
    expect(apiRequest).toHaveBeenLastCalledWith("/admin/workouts", { method: "POST", token: "tok", body: { folder_id: "f1" } });
    await createDraftWorkout("tok", null, { awaitingFiling: true });
    expect(apiRequest).toHaveBeenLastCalledWith("/admin/workouts", { method: "POST", token: "tok", body: { awaiting_filing: true } });
  });
});
