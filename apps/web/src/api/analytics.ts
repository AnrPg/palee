import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

export type AnalyticsSummary = Record<string, unknown>;

/** A query built by `analyticsApiQuery` (lib/analytics-filter): `days` or `from`/`to`, plus filter lists. */
export type AnalyticsApiQuery = Record<string, string>;

export type AnalyticsMetricReset = components["schemas"]["AnalyticsMetricReset"];
export type AnalyticsResetHistory = components["schemas"]["AdminAnalyticsResetHistory"];

/** Kept for the home and dashboard cards: the last `days` days, optionally narrowed to some branches. */
export async function fetchAdminAnalyticsSummary(token: string, days = 30, locationIds?: string) {
  const query: AnalyticsApiQuery = { days: String(days) };
  if (locationIds) query.location_ids = locationIds;
  return fetchStaffAnalyticsSummary(token, query);
}

/** ADR-462: the «Στατιστικά» summary for the page's period and filters. */
export async function fetchStaffAnalyticsSummary(token: string, query: AnalyticsApiQuery) {
  const params = new URLSearchParams(query);
  return apiRequest<AnalyticsSummary>(`/admin/analytics/summary?${params.toString()}`, { token });
}

/** Starts a metric again from now (owner and admins, `reset_analytics`). Nothing is deleted. */
export async function resetAnalyticsMetric(token: string, metricKey: string) {
  return apiRequest<{ reset: AnalyticsMetricReset }>(`/admin/analytics/metrics/${encodeURIComponent(metricKey)}/reset`, {
    method: "POST",
    token,
  });
}

export async function undoAnalyticsMetricReset(token: string, resetId: string) {
  return apiRequest<{ reset: AnalyticsMetricReset }>(`/admin/analytics/resets/${encodeURIComponent(resetId)}/undo`, {
    method: "POST",
    token,
  });
}

/** «Ιστορικό μηδενισμών»: newest first, with each metric over the days before its reset. */
export async function fetchAnalyticsResets(token: string, page = 1, perPage = 20) {
  const params = new URLSearchParams({ page: String(page), per_page: String(perPage) });
  return apiRequest<AnalyticsResetHistory>(`/admin/analytics/resets?${params.toString()}`, { token });
}
