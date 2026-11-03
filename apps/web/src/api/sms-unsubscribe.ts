import { apiRequest } from "@/api/client";
import type { components } from "@/api/generated/schema";

/** ADR-390: the short link of a marketing SMS (public, no sign-in). */
export type SmsUnsubscribe = components["schemas"]["SmsUnsubscribe"];

/** The box behind the link and whether offers by SMS are already off. Changes nothing. */
export function fetchSmsUnsubscribe(token: string, signal?: AbortSignal) {
  return apiRequest<SmsUnsubscribe>(`/public/channels/unsubscribe/${encodeURIComponent(token)}`, { scope: "account", signal });
}

/** Stops offers by SMS from that box (the person's tap). */
export function confirmSmsUnsubscribe(token: string) {
  return apiRequest<SmsUnsubscribe>(`/public/channels/unsubscribe/${encodeURIComponent(token)}`, { method: "POST", scope: "account" });
}
