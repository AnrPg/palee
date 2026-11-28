import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/** ADR-760: the box's «Αρχείο ενεργειών». */
export type ActivityLogEntry = components["schemas"]["ActivityLogEntry"];
export type ActivityLogPage = components["schemas"]["ActivityLogPage"];
export type ActivityArea = ActivityLogEntry["area"];
export type ActivityAction = ActivityLogEntry["action"];
/** What the member sees of a row staff shared with them (5A): never who on the staff did it. */
export type MemberActivityEntry = components["schemas"]["MemberActivityEntry"];
export type MemberActivityPage = components["schemas"]["MemberActivityPage"];

/** The list's filters, as the API takes them (all optional; dates are the box's days). */
export type ActivityLogFilters = {
  areas?: ActivityArea[];
  person_id?: string;
  actor_id?: string;
  from?: string;
  to?: string;
  q?: string;
};

/** The query string of a filter set (and a page's cursor); empty values are left out. */
export function activityLogQuery(filters: ActivityLogFilters, cursor?: string | null) {
  const search = new URLSearchParams();
  if (filters.areas && filters.areas.length > 0) search.set("areas", filters.areas.join(","));
  for (const key of ["person_id", "actor_id", "from", "to"] as const) {
    const value = filters[key];
    if (value) search.set(key, value);
  }
  const q = filters.q?.trim();
  if (q) search.set("q", q);
  if (cursor) search.set("cursor", cursor);
  const text = search.toString();
  return text ? `?${text}` : "";
}

// ADR-215: no token in the keys; the box is part of the scope.
export const activityLogKeys = {
  all: (slug: string | null) => ["activity-log", slug] as const,
  list: (slug: string | null, filters: ActivityLogFilters) => ["activity-log", slug, "list", filters] as const,
  mine: (slug: string | null) => ["activity-log", slug, "mine"] as const,
};

export function fetchActivityLog(token: string, filters: ActivityLogFilters, cursor?: string | null, signal?: AbortSignal) {
  return apiRequest<ActivityLogPage>(`/admin/activity-log${activityLogQuery(filters, cursor)}`, { token, signal });
}

/** The same rows as CSV (10A: only when the page said `can_export`). */
export function exportActivityLog(token: string, filters: ActivityLogFilters) {
  return apiRequest<Blob>(`/admin/activity-log/export${activityLogQuery(filters)}`, { token, responseType: "blob" });
}

/** The member's own rows of one box: only what staff shared with them. */
export function fetchMyActivity(token: string, slug: string, cursor?: string | null) {
  const query = cursor ? `?cursor=${encodeURIComponent(cursor)}` : "";
  return apiRequest<MemberActivityPage>(`/org/${encodeURIComponent(slug)}/me/membership/activity${query}`, { token });
}
