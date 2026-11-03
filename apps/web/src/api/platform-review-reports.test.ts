import { describe, expect, it } from "vitest";

import { reportNoteRequired, REVIEW_REPORT_REASONS } from "./box-site";
import { decisionReady } from "./platform-review-reports";
import { topReason } from "@/components/platform/PlatformReviewReportsPage";

describe("review reports (ADR-397)", () => {
  it("has the six fixed reasons, and a note is needed only for illegal content and «Κάτι άλλο»", () => {
    expect(REVIEW_REPORT_REASONS).toEqual(["offensive", "personal_data", "not_genuine", "spam", "illegal", "other"]);
    expect(REVIEW_REPORT_REASONS.filter(reportNoteRequired)).toEqual(["illegal", "other"]);
    expect(reportNoteRequired(null)).toBe(false);
  });

  it("lets keep through at once and asks hide and remove for a ground and a statement", () => {
    expect(decisionReady(null, null, "")).toBe(false);
    expect(decisionReady("keep", null, "")).toBe(true);
    expect(decisionReady("hide", "offensive", "  ")).toBe(false);
    expect(decisionReady("remove", "no_violation", "Λόγος")).toBe(false);
    expect(decisionReady("remove", "personal_data", "Έχει το κινητό της.")).toBe(true);
  });

  it("starts the ground from the reason reported most", () => {
    expect(topReason({ reasons: [] })).toBeNull();
    expect(
      topReason({
        reasons: [
          { reason: "spam", count: 1 },
          { reason: "offensive", count: 3 },
          { reason: "not_genuine", count: 2 },
        ],
      }),
    ).toBe("offensive");
  });
});
