import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/** ADR-364: the public status page now (no session; cacheable for 30 s). */
export type StatusOverview = components["schemas"]["StatusOverview"];
export type StatusHistory = components["schemas"]["StatusHistory"];
export type StatusIncident = components["schemas"]["StatusIncident"];
export type StatusConsole = components["schemas"]["StatusConsole"];
export type StatusTranslation = components["schemas"]["StatusTranslation"];
export type StatusIncidentCreate = components["schemas"]["StatusIncidentCreate"];

export function fetchStatusOverview(signal?: AbortSignal) {
  return apiRequest<StatusOverview>("/public/status", { scope: "account", signal });
}

/** Uptime per component and day over the last `days` days (1..90), and the incidents in them. */
export function fetchStatusHistory(days: number, signal?: AbortSignal) {
  return apiRequest<StatusHistory>(`/public/status/history?days=${days}`, { scope: "account", signal });
}

/** Double opt-in: always "accepted" for a valid address; the confirmation comes by email. */
export function subscribeToStatus(email: string, locale: string) {
  return apiRequest<{ status: string }>("/public/status/subscriptions", {
    method: "POST",
    scope: "account",
    body: { email, locale },
  });
}

export function confirmStatusSubscription(token: string) {
  return apiRequest<{ status: string }>("/public/status/subscriptions/confirm", {
    method: "POST",
    scope: "account",
    body: { token },
  });
}

export function unsubscribeFromStatus(token: string) {
  return apiRequest<{ status: string }>("/public/status/subscriptions/unsubscribe", {
    method: "POST",
    scope: "account",
    body: { token },
  });
}

// --- Platform console (vendors) -------------------------------------------

export function fetchStatusConsole(token: string) {
  return apiRequest<StatusConsole>("/platform/status", { token, scope: "account" });
}

/** ADR-366: the English preview of a title and note (machine translation). */
export function translateStatusText(token: string, text: { title?: string; body: string }) {
  return apiRequest<StatusTranslation>("/platform/status/translations", {
    method: "POST",
    token,
    scope: "account",
    body: text,
  });
}

export function publishStatusIncident(token: string, incident: StatusIncidentCreate) {
  return apiRequest<StatusIncident>("/platform/status/incidents", {
    method: "POST",
    token,
    scope: "account",
    body: incident,
  });
}

export function addStatusIncidentUpdate(
  token: string,
  id: string,
  update: components["schemas"]["StatusIncidentUpdateCreate"],
) {
  return apiRequest<StatusIncident>(`/platform/status/incidents/${encodeURIComponent(id)}/updates`, {
    method: "POST",
    token,
    scope: "account",
    body: update,
  });
}
