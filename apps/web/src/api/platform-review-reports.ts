import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/**
 * Platform console › «Αναφορές κριτικών» (ADR-397): reported box reviews
 * across every box, decided only by the Palee team (keep, hide, remove), and
 * restoring a hidden review from the decided ones.
 */
export type PlatformReviewReports = components["schemas"]["PlatformReviewReportsResponse"];
export type PlatformReviewReportItem = PlatformReviewReports["items"][number];
export type PlatformReviewDecision = PlatformReviewReports["decisions"][number];
export type PlatformReviewDecisionRequest = components["schemas"]["PlatformReviewDecisionRequest"];
export type PlatformReviewDecisionResponse = components["schemas"]["PlatformReviewDecisionResponse"];
export type ReviewOutcome = PlatformReviewDecisionRequest["outcome"];
export type ReviewReportStatus = "open" | "decided";

export const PLATFORM_REVIEW_REPORTS_KEY = ["platform", "review-reports"] as const;
export const REVIEW_STATEMENT_MAX = 1000;

export function fetchPlatformReviewReports(token: string, status: ReviewReportStatus = "open") {
  return apiRequest<PlatformReviewReports>(`/platform/review-reports?status=${encodeURIComponent(status)}`, { token, scope: "account" });
}

/** One decision closes every open report on that review. */
export function decidePlatformReviewReport(token: string, reviewId: string, body: PlatformReviewDecisionRequest) {
  return apiRequest<PlatformReviewDecisionResponse>(`/platform/review-reports/${encodeURIComponent(reviewId)}/decision`, {
    method: "POST",
    token,
    scope: "account",
    body,
  });
}

/** Shows a hidden review again; the author reads the statement. */
export function restorePlatformReview(token: string, reviewId: string, statement: string) {
  return apiRequest<PlatformReviewDecisionResponse>(`/platform/review-reports/${encodeURIComponent(reviewId)}/restore`, {
    method: "POST",
    token,
    scope: "account",
    body: { statement },
  });
}

/** Hide and remove need a ground and a statement before they can be sent. */
export function decisionReady(outcome: ReviewOutcome | null, ground: string | null, statement: string) {
  if (outcome === null) return false;
  if (outcome === "keep") return true;
  return ground !== null && ground !== "no_violation" && statement.trim().length > 0;
}
