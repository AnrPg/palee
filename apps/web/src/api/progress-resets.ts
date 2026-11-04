import { ACCOUNT_PROGRESS_KEY } from "@/api/account-training";
import { apiRequest } from "@/api/client";
import type { operations } from "@/api/generated/schema";

/**
 * ADR-462 §5: a member resets one of their own Πρόοδος stats. It changes
 * only what the member sees; nothing is deleted and an undo brings the old
 * figures back. `/me/progress` and `/me/progress/depth` return the active
 * baselines as `metric_baselines` (metric key → ISO time).
 */

export const MEMBER_METRIC_KEYS = [
  "progress.totals",
  "progress.weekly",
  "progress.consistency",
  "progress.score_history",
  "progress.exercise_loads",
  "progress.by_source",
  "progress.pr_timeline",
  "progress.depth.coverage",
  "progress.depth.qualities",
  "progress.depth.load",
] as const;
export type MemberMetricKey = (typeof MEMBER_METRIC_KEYS)[number];

export function isMemberMetricKey(value: string): value is MemberMetricKey {
  return (MEMBER_METRIC_KEYS as readonly string[]).includes(value);
}

/** Metric key → ISO time of the active baseline; a stub may leave it out. */
export type MetricBaselines = Partial<Record<string, string>>;

type HistoryResponse =
  operations["PaleeWeb.ProgressMetricResetController.index"]["responses"][200]["content"]["application/json"];
export type ProgressResetHistory = HistoryResponse;
export type ProgressResetEntry = HistoryResponse["entries"][number];
export type ProgressReset =
  operations["PaleeWeb.ProgressMetricResetController.reset"]["responses"][201]["content"]["application/json"]["reset"];

export const PROGRESS_RESETS_KEY = ["me", "progress-resets"] as const;

/** Every query a member reset changes: Πρόοδος, its depth slots and the history. */
export const PROGRESS_RESET_AFFECTED_KEYS = [
  ACCOUNT_PROGRESS_KEY,
  ["me", "progress-depth"],
  PROGRESS_RESETS_KEY,
] as const;

export async function resetProgressMetric(token: string, metricKey: MemberMetricKey) {
  const data = await apiRequest<{ reset: ProgressReset }>(
    `/me/progress/metrics/${encodeURIComponent(metricKey)}/reset`,
    { token, scope: "account", method: "POST" },
  );
  return data.reset;
}

export async function undoProgressReset(token: string, id: string) {
  const data = await apiRequest<{ reset: ProgressReset }>(
    `/me/progress/resets/${encodeURIComponent(id)}/undo`,
    { token, scope: "account", method: "POST" },
  );
  return data.reset;
}

export function fetchProgressResets(token: string, page = 1, perPage = 50) {
  const query = new URLSearchParams({ page: String(page), per_page: String(perPage) });
  return apiRequest<ProgressResetHistory>(`/me/progress/resets?${query.toString()}`, { token, scope: "account" });
}
