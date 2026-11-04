import type { ApiKey, WebhookDelivery, WebhookEndpoint } from "@/api/integrations";

/*
 * Pure rules of Ρυθμίσεις › Συνδέσεις (W10 screens 1–3, ADR-378..380):
 * the key wizard's purposes and the fewest scopes each needs, a webhook's
 * health for its list badge, and how a delivery reads.
 */

export const SCOPES = [
  "members:read",
  "members:write",
  "classes:read",
  "classes:write",
  "bookings:read",
  "bookings:write",
  "packages:read",
  "packages:write",
  "payments:read",
  "webhooks:write",
] as const;
export type Scope = (typeof SCOPES)[number];

/** The objects of the scope grid, each with the access it offers (payments: read only). */
export const SCOPE_OBJECTS = ["members", "classes", "bookings", "packages", "payments", "webhooks"] as const;
export type ScopeObject = (typeof SCOPE_OBJECTS)[number];

export function scopesOf(object: ScopeObject): Scope[] {
  return SCOPES.filter((scope) => scope.startsWith(`${object}:`));
}

/** W10 screen 1 B: «Για τι το θέλεις;». The purpose picks the fewest scopes it needs. */
export const KEY_PURPOSES = ["zapier", "website", "own"] as const;
export type KeyPurpose = (typeof KEY_PURPOSES)[number];

export const PURPOSE_SCOPES: Record<KeyPurpose, Scope[]> = {
  zapier: ["bookings:read", "classes:read", "members:read", "webhooks:write"],
  website: ["classes:read"],
  own: ["members:read", "members:write", "packages:read"],
};

export function toggleScope(scopes: string[], scope: Scope): string[] {
  return scopes.includes(scope) ? scopes.filter((item) => item !== scope) : [...scopes, scope].sort();
}

/** «palee_live_k3m9…» for the list: the stored prefix, never a secret. */
export function keyLabel(key: Pick<ApiKey, "masked" | "prefix">) {
  return key.masked || `${key.prefix}…`;
}

export type WebhookHealth = "ok" | "failing" | "off";

/**
 * The small badge on each webhook of the list (W10 screen 2: A, with C's
 * health): off when Palee or the box closed it, failing after any failure
 * newer than the last success.
 */
export function webhookHealth(endpoint: Pick<WebhookEndpoint, "status" | "consecutive_failures" | "last_success_at" | "last_failure_at">): WebhookHealth {
  if (endpoint.status !== "active") return "off";
  if ((endpoint.consecutive_failures ?? 0) > 0) return "failing";
  const failure = endpoint.last_failure_at ? Date.parse(endpoint.last_failure_at) : null;
  const success = endpoint.last_success_at ? Date.parse(endpoint.last_success_at) : null;
  if (failure !== null && (success === null || failure > success)) return "failing";
  return "ok";
}

export type DeliveryState = "delivered" | "retrying" | "failed";

/** «Παραδόθηκε», «Νέα προσπάθεια hh:mm» or «Απέτυχε». */
export function deliveryState(delivery: Pick<WebhookDelivery, "status">): DeliveryState {
  if (delivery.status === "succeeded") return "delivered";
  if (delivery.status === "pending") return "retrying";
  return "failed";
}

/** The delivery log's filter chips map to the API's `status`. */
export const DELIVERY_FILTERS = ["all", "pending", "failed"] as const;
export type DeliveryFilter = (typeof DELIVERY_FILTERS)[number];

export function deliveryStatusParam(filter: DeliveryFilter) {
  return filter === "all" ? undefined : filter;
}

/** A receiver must be https (the API also refuses private addresses). */
export function webhookUrlError(value: string): "required" | "https" | null {
  const url = value.trim();
  if (!url) return "required";
  try {
    return new URL(url).protocol === "https:" ? null : "https";
  } catch {
    return "https";
  }
}

/** Shortens a receiver's address for a list row: host and the end of the path. */
export function shortUrl(value: string) {
  try {
    const url = new URL(value);
    const parts = url.pathname.split("/").filter(Boolean);
    return parts.length > 1 ? `${url.host}/…/${parts[parts.length - 1]}` : `${url.host}${url.pathname === "/" ? "" : url.pathname}`;
  } catch {
    return value;
  }
}

/** Error codes of the Connections API that have their own sentence. */
const KNOWN_ERRORS = [
  "invalid_api_key_name",
  "invalid_scopes",
  "too_many_api_keys",
  "invalid_webhook_url",
  "blocked_address",
  "invalid_events",
  "too_many_webhooks",
  "webhook_disabled",
  "delivery_pending",
  "invalid_audience_list",
  "audience_key_required",
  "audience_unauthorized",
  "audience_list_not_found",
  "audience_unavailable",
  "invalid_door_name",
  "invalid_door_settings",
  "invalid_door_rules",
  "door_offline",
  "door_unauthorized",
  "door_refused",
  "door_disabled",
  "forbidden",
] as const;

export function integrationErrorKey(code: string | undefined): string {
  return code && (KNOWN_ERRORS as readonly string[]).includes(code) ? `errors.${code}` : "errors.generic";
}
