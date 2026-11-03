import { apiRequest } from "@/api/client";

/*
 * Μηνύματα SMS (ADR-348..351, 368, 369, 385). Staff calls go through the
 * selected box (`/admin/channels/...`); the member's own number and consents
 * name the box explicitly (`/org/:slug/me/channels`), because a member may
 * belong to several. Wire shapes follow `PaleeWeb.Schemas.Channels` (see
 * `generated/schema.ts`). Secrets are written, never read back.
 */

export type ChannelName = "sms" | "viber" | "whatsapp";
export type ChannelPurpose = "service" | "marketing";

export type ChannelConnection = {
  provider: string;
  account_mode: "palee" | "own";
  account_id?: string | null;
  base_url?: string | null;
  channel_order: ChannelName[];
  channels: ChannelName[];
  checked_at?: string | null;
  currency?: string;
  default_country: string;
  error_code?: string | null;
  has_secret: boolean;
  last_error?: string | null;
  /** ADR-390: the cap the box typed; null until it does (then nothing is sent). */
  monthly_budget_cents: number | null;
  quiet_start?: string | null;
  quiet_end?: string | null;
  sms_sender?: string | null;
  status: "active" | "invalid";
  updated_at?: string | null;
  webhook_url?: string | null;
};

export type SpendLine = { cents: number; count: number };

export type ChannelUsage = {
  from: string;
  to: string;
  spent_cents: number;
  messages: number;
  segments?: number;
  by_channel: Record<string, SpendLine>;
  /** ADR-385: `automation`, `staff`, `system`. */
  by_source?: Record<string, SpendLine>;
  /** ADR-385: every message of the month by state. */
  by_status?: Record<string, number>;
  cap_cents?: number | null;
  currency: string;
  account_mode?: string | null;
  palee_charge_cents: number;
};

export type ChannelProvider = { provider: string; channels: ChannelName[]; account_modes: string[] };

export type ChannelSettings = {
  connection: ChannelConnection | null;
  providers: ChannelProvider[];
  usage: ChannelUsage;
};

export type ChannelCheck = { ok: boolean; error_code?: string | null; details: Record<string, unknown> };

export type ChannelSettingsUpdate = {
  provider: string;
  account_mode?: "palee" | "own";
  secret?: string;
  channels?: ChannelName[];
  sms_sender?: string | null;
  monthly_budget_cents?: number;
  quiet_start?: string | null;
  quiet_end?: string | null;
  rotate_webhook?: boolean;
};

export type ChannelConsent = {
  channel: ChannelName;
  purpose: ChannelPurpose;
  granted: boolean;
  granted_at?: string | null;
  withdrawn_at?: string | null;
  source?: string | null;
  text_version?: string | null;
};

export type ChannelContact = {
  id: string;
  user_id?: string | null;
  lead_id?: string | null;
  /** Masked for staff (`+30 •••••••678`), whole for the member. */
  phone: string;
  locale: string;
  country?: string | null;
  opted_out_at?: string | null;
  updated_at?: string | null;
  consents: ChannelConsent[];
};

export type ChannelMessage = {
  id: string;
  channel: ChannelName;
  status: "queued" | "sending" | "sent" | "delivered" | "failed" | "cancelled";
  body: string;
  to: string;
  template_key?: string;
  source?: string;
  source_ref?: string | null;
  purpose?: ChannelPurpose;
  segments?: number;
  estimated_cost_cents?: number;
  cost_cents?: number | null;
  currency?: string;
  error_code?: string | null;
  hold_reason?: string | null;
  next_attempt_at?: string | null;
  inserted_at?: string | null;
  sent_at?: string | null;
  delivered_at?: string | null;
};

export type ChannelTemplate = {
  key: string;
  builtin: boolean;
  purpose?: string | null;
  variables: string[];
  defaults: Record<string, string>;
  custom: { locale: string; channel: "any" | "whatsapp"; body: string; variable_names: string[] }[];
};

export type EmailConnection = {
  enabled: boolean;
  from_address: string;
  from_name?: string | null;
  reply_to?: string | null;
  host: string;
  port: number;
  tls_mode: "starttls" | "tls";
  username: string;
  has_secret: boolean;
  in_use: boolean;
  status: "unchecked" | "active" | "invalid";
  error_code?: string | null;
  checked_at?: string | null;
};

export type EmailDnsStep = { key: string; host: string | null; record: string | null };

export type EmailSettings = {
  connection: EmailConnection | null;
  dns_guidance?: { domain: string | null; steps: EmailDnsStep[] };
  ports?: number[];
  tls_modes?: string[];
};

export type EmailSettingsUpdate = {
  enabled?: boolean;
  from_address?: string;
  from_name?: string | null;
  reply_to?: string | null;
  host?: string;
  port?: 25 | 465 | 587 | 2525;
  tls_mode?: "starttls" | "tls";
  username?: string;
  secret?: string;
};

export type ClassNoticeKind = "cancelled" | "changed" | "free";

export type ClassNoticeRequest = {
  slot_id: string;
  kind: ClassNoticeKind;
  text?: string;
  urgent?: boolean;
  locale?: string;
  idempotency_key?: string;
};

export type ClassNotice = {
  slot_id: string;
  kind: ClassNoticeKind;
  urgent: boolean;
  participants?: number;
  in_app: number;
  sms: number;
  unreachable: number;
  unreachable_reasons: Record<string, number>;
  estimated_cost_cents: number;
  currency: string;
  budget: { spent_cents: number; cap_cents: number; currency: string } | null;
  sample: { body: string; segments: number; release_at: string; held_for_quiet_hours: boolean } | null;
  sms_blocked: string | null;
};

export type MyChannels = { channels: ChannelName[]; contact: ChannelContact | null };

export type MyChannelsUpdate = {
  phone?: string;
  locale?: string;
  text_version?: string;
  consents?: { channel: ChannelName; purpose: ChannelPurpose; granted: boolean }[];
};

const slugPath = (slug: string) => `/org/${encodeURIComponent(slug)}`;

// ── Staff: settings, usage, templates ─────────────────────────────────────

export function fetchChannelSettings(token: string) {
  return apiRequest<ChannelSettings>("/admin/channels/settings", { token });
}

export function saveChannelSettings(token: string, update: ChannelSettingsUpdate) {
  return apiRequest<{ connection: ChannelConnection; check: ChannelCheck }>("/admin/channels/settings", {
    method: "PUT",
    token,
    body: update,
  });
}

export function checkChannelSettings(token: string) {
  return apiRequest<{ connection: ChannelConnection; check: ChannelCheck }>("/admin/channels/settings/check", {
    method: "POST",
    token,
  });
}

/** `month` is `YYYY-MM` on the box's clock. */
export function fetchChannelUsage(token: string, month: string) {
  return apiRequest<ChannelUsage>(`/admin/channels/usage?month=${encodeURIComponent(month)}`, { token });
}

export function fetchChannelTemplates(token: string) {
  return apiRequest<{ templates: ChannelTemplate[] }>("/admin/channels/templates", { token });
}

export function saveChannelTemplate(token: string, key: string, locale: string, body: string) {
  return apiRequest<unknown>(`/admin/channels/templates/${encodeURIComponent(key)}`, {
    method: "PUT",
    token,
    body: { locale, body },
  });
}

export function resetChannelTemplate(token: string, key: string, locale: string) {
  return apiRequest<null>(`/admin/channels/templates/${encodeURIComponent(key)}?locale=${encodeURIComponent(locale)}`, {
    method: "DELETE",
    token,
  });
}

export function fetchChannelMessages(token: string, params: { limit?: number; source_ref?: string } = {}) {
  const query = new URLSearchParams();
  if (params.limit) query.set("limit", String(params.limit));
  if (params.source_ref) query.set("source_ref", params.source_ref);
  const suffix = query.toString();
  return apiRequest<{ messages: ChannelMessage[]; total: number }>(`/admin/channels/messages${suffix ? `?${suffix}` : ""}`, { token });
}

// ── Staff: the box's own email provider (ADR-368) ────────────────────────

export function fetchEmailSettings(token: string) {
  return apiRequest<EmailSettings>("/admin/channels/email", { token });
}

export function saveEmailSettings(token: string, update: EmailSettingsUpdate) {
  return apiRequest<EmailSettings>("/admin/channels/email", { method: "PUT", token, body: update });
}

export function checkEmailSettings(token: string) {
  return apiRequest<{ check: { ok: boolean; error_code: string | null }; connection: EmailConnection }>("/admin/channels/email/check", {
    method: "POST",
    token,
  });
}

export function deleteEmailSettings(token: string) {
  return apiRequest<null>("/admin/channels/email", { method: "DELETE", token });
}

// ── Staff: a client's number and consents ────────────────────────────────

export function lookupChannelContact(token: string, userId: string) {
  return apiRequest<{ contact: ChannelContact | null }>(`/admin/channels/contacts/lookup?user_id=${encodeURIComponent(userId)}`, { token });
}

export function saveChannelContact(token: string, userId: string, phone: string) {
  return apiRequest<{ contact: ChannelContact | null }>("/admin/channels/contacts", {
    method: "PUT",
    token,
    body: { user_id: userId, phone },
  });
}

/** What the person told staff: recorded with source `staff`, the staff member and the time. */
export function recordStaffConsent(token: string, contactId: string, purpose: ChannelPurpose, granted: boolean) {
  return apiRequest<{ contact: ChannelContact | null }>(`/admin/channels/contacts/${encodeURIComponent(contactId)}/consents`, {
    method: "PUT",
    token,
    body: { channel: "sms", purpose, granted, source: "staff", text_version: STAFF_CONSENT_TEXT },
  });
}

// ── Staff: «Ενημέρωση συμμετεχόντων» (ADR-385) ───────────────────────────

export function previewClassNotice(token: string, request: ClassNoticeRequest) {
  return apiRequest<ClassNotice>("/admin/channels/class-notices/preview", { method: "POST", token, body: request });
}

export function sendClassNotice(token: string, request: ClassNoticeRequest & { idempotency_key: string }) {
  return apiRequest<ClassNotice>("/admin/channels/class-notices", { method: "POST", token, body: request });
}

// ── Member: my number and consents at one box ────────────────────────────

export function fetchMyChannels(token: string, slug: string) {
  return apiRequest<MyChannels>(`${slugPath(slug)}/me/channels`, { token });
}

export function saveMyChannels(token: string, slug: string, update: MyChannelsUpdate) {
  return apiRequest<MyChannels>(`${slugPath(slug)}/me/channels`, { method: "PUT", token, body: update });
}

/** The consent texts the screens show, recorded with each consent (ADR-350). */
export const MEMBER_CONSENT_TEXT = "member_settings_v1";
export const BOOKING_CONSENT_TEXT = "booking_prompt_v1";
export const STAFF_CONSENT_TEXT = "staff_desk_v1";
