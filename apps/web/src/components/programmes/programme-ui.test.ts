import { describe, expect, it } from "vitest";

import { ApiError } from "@/api/client";

import { programmeErrorKey, ratingLabel } from "./programme-ui";

describe("programme ui helpers", () => {
  it("names the programme refusals the API sends and nothing else", () => {
    const refusal = new ApiError(422, "refused", { code: "programme_start_consent_required", error: "x" });
    expect(programmeErrorKey(refusal)).toBe("programme_start_consent_required");
    expect(programmeErrorKey(new ApiError(422, "other", { code: "validation_failed", error: "x" }))).toBeNull();
    expect(programmeErrorKey(new Error("network"))).toBeNull();
  });

  it("shows a rating only when there are reviews", () => {
    expect(ratingLabel("el", 4.8, 23)).toBe("★ 4,8 (23)");
    expect(ratingLabel("en", null, 0)).toBeNull();
  });
});
