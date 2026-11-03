import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/*
 * Ρυθμίσεις › Συνδέσεις (ADR-378..380, ontology §4.28): API keys, webhooks
 * with their delivery log, and the box's email list. Staff calls go through
 * the selected box (`/admin/integrations/...`); the member's own email
 * consent names the box explicitly (`/org/:slug/me/marketing-consent`).
 * Secrets (key token, signing secret, list key) are answered once or never.
 */
type Schemas = components["schemas"];

export type IntegrationCatalog = Schemas["IntegrationCatalog"];
export type ApiKey = Schemas["ApiKey"];
export type ApiKeyWithToken = Schemas["ApiKeyWithToken"];
export type WebhookEndpoint = Schemas["WebhookEndpoint"];
export type WebhookEndpointWithSecret = Schemas["WebhookEndpointWithSecret"];
export type WebhookDelivery = Schemas["WebhookDelivery"];
export type WebhookDeliveryPage = Schemas["WebhookDeliveryPage"];
export type AudienceConnection = NonNullable<Schemas["AudienceConnection"]>;
export type AudienceProvider = AudienceConnection["provider"];
export type MarketingConsent = Schemas["MarketingConsent"];

export const INTEGRATION_CATALOG_KEY = ["admin", "integrations", "catalog"] as const;
export const API_KEYS_KEY = ["admin", "integrations", "api-keys"] as const;
export const WEBHOOKS_KEY = ["admin", "integrations", "webhooks"] as const;
export const EMAIL_LIST_KEY = ["admin", "integrations", "email-list"] as const;
export const deliveriesKey = (endpointId: string, status: string) => ["admin", "integrations", "deliveries", endpointId, status] as const;
export const deliveryKey = (id: string) => ["admin", "integrations", "delivery", id] as const;
export const marketingConsentKey = (slug: string) => ["me", "marketing-consent", slug] as const;

const base = "/admin/integrations";
const id = (value: string) => encodeURIComponent(value);

export function fetchIntegrationCatalog(token: string) {
  return apiRequest<IntegrationCatalog>(`${base}/catalog`, { token });
}

// API keys (ADR-378) ---------------------------------------------------------------

export async function fetchApiKeys(token: string) {
  return (await apiRequest<{ keys: ApiKey[] }>(`${base}/api-keys`, { token })).keys;
}

export function createApiKey(token: string, body: { name: string; scopes: string[]; expires_at?: string | null }) {
  return apiRequest<ApiKeyWithToken>(`${base}/api-keys`, { method: "POST", token, body });
}

export function rotateApiKey(token: string, keyId: string) {
  return apiRequest<ApiKeyWithToken>(`${base}/api-keys/${id(keyId)}/rotate`, { method: "POST", token });
}

export async function revokeApiKey(token: string, keyId: string) {
  return (await apiRequest<{ key: ApiKey }>(`${base}/api-keys/${id(keyId)}`, { method: "DELETE", token })).key;
}

// Webhooks (ADR-379) ---------------------------------------------------------------

export async function fetchWebhooks(token: string) {
  return (await apiRequest<{ webhooks: WebhookEndpoint[] }>(`${base}/webhooks`, { token })).webhooks;
}

export function createWebhook(token: string, body: { url: string; events: string[]; description?: string | null }) {
  return apiRequest<WebhookEndpointWithSecret>(`${base}/webhooks`, { method: "POST", token, body });
}

export async function updateWebhook(
  token: string,
  endpointId: string,
  body: { url?: string; events?: string[]; description?: string | null; status?: "active" | "disabled" },
) {
  return (await apiRequest<{ endpoint: WebhookEndpoint }>(`${base}/webhooks/${id(endpointId)}`, { method: "PATCH", token, body })).endpoint;
}

export function deleteWebhook(token: string, endpointId: string) {
  return apiRequest<{ ok: boolean }>(`${base}/webhooks/${id(endpointId)}`, { method: "DELETE", token });
}

export function rotateWebhookSecret(token: string, endpointId: string) {
  return apiRequest<WebhookEndpointWithSecret>(`${base}/webhooks/${id(endpointId)}/rotate-secret`, { method: "POST", token });
}

export async function testWebhook(token: string, endpointId: string) {
  return (await apiRequest<{ delivery: WebhookDelivery }>(`${base}/webhooks/${id(endpointId)}/test`, { method: "POST", token })).delivery;
}

export function fetchDeliveries(token: string, endpointId: string, status?: string) {
  const query = status ? `?status=${encodeURIComponent(status)}` : "";
  return apiRequest<WebhookDeliveryPage>(`${base}/webhooks/${id(endpointId)}/deliveries${query}`, { token });
}

export async function fetchDelivery(token: string, deliveryId: string) {
  return (await apiRequest<{ delivery: WebhookDelivery }>(`${base}/deliveries/${id(deliveryId)}`, { token })).delivery;
}

export async function replayDelivery(token: string, deliveryId: string) {
  return (await apiRequest<{ delivery: WebhookDelivery }>(`${base}/deliveries/${id(deliveryId)}/replay`, { method: "POST", token })).delivery;
}

// Email list (ADR-380) -------------------------------------------------------------

export async function fetchEmailList(token: string) {
  return (await apiRequest<{ connection: AudienceConnection | null }>(`${base}/email-list`, { token })).connection;
}

export async function saveEmailList(token: string, body: { provider: AudienceProvider; list_id: string; api_key?: string }) {
  return (await apiRequest<{ connection: AudienceConnection | null }>(`${base}/email-list`, { method: "PUT", token, body })).connection;
}

export function deleteEmailList(token: string) {
  return apiRequest<{ ok: boolean }>(`${base}/email-list`, { method: "DELETE", token });
}

export function syncEmailList(token: string) {
  return apiRequest<{ ok: boolean }>(`${base}/email-list/sync`, { method: "POST", token });
}

/** The provider's unsubscribe webhook address, shown once (ADR-380). */
export function rotateUnsubscribeUrl(token: string) {
  return apiRequest<{ url: string }>(`${base}/email-list/unsubscribe-url`, { method: "POST", token });
}

// The member's own yes or no (ADR-380) ---------------------------------------------

const myGym = (slug: string) => `/org/${encodeURIComponent(slug)}/me`;

export function fetchMarketingConsent(token: string, slug: string) {
  return apiRequest<MarketingConsent>(`${myGym(slug)}/marketing-consent`, { token });
}

export function saveMarketingConsent(token: string, slug: string, granted: boolean) {
  return apiRequest<MarketingConsent>(`${myGym(slug)}/marketing-consent`, { method: "PUT", token, body: { granted } });
}
