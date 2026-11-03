import type { ChannelConnection, ChannelContact, ChannelPurpose, ChannelUsage, MyChannels } from "@/api/channels";

/*
 * Pure rules of the SMS screens (W3, ADR-348..351, 385): money, the month
 * bar, quiet hours, the sender name, who to ask after a booking.
 */

/** «3,64 €» in the reader's language. */
export function formatCents(cents: number, currency: string, locale: string): string {
  try {
    return new Intl.NumberFormat(locale, { style: "currency", currency, minimumFractionDigits: 2 }).format(cents / 100);
  } catch {
    return `${(cents / 100).toFixed(2)} ${currency}`;
  }
}

/** Whole hours for the quiet-hours pickers: «00:00» … «23:00». */
export const QUIET_HOURS = Array.from({ length: 24 }, (_, hour) => `${String(hour).padStart(2, "0")}:00`);

/** ADR-349 defaults: 21:00–09:00, 20 € a month. */
export const DEFAULT_QUIET_START = "21:00";
export const DEFAULT_QUIET_END = "09:00";
export const DEFAULT_BUDGET_CENTS = 2000;

/** Budget choices in whole euros; the saved value joins them when it is not one. */
export const BUDGET_EUROS = [5, 10, 20, 30, 50, 100, 200];

export function budgetChoices(currentCents: number | null | undefined): number[] {
  const euros = currentCents == null ? null : Math.round(currentCents / 100);
  if (euros == null || BUDGET_EUROS.includes(euros)) return BUDGET_EUROS;
  return [...BUDGET_EUROS, euros].sort((a, b) => a - b);
}

/**
 * The sender name the SMS shows: up to 11 Latin letters, digits or spaces,
 * with at least one letter (ADR-349); or a number in +E.164. Null is fine
 * (Palee's default sender).
 */
export function senderError(value: string): "tooLong" | "latinOnly" | "needsLetter" | null {
  const sender = value.trim();
  if (sender === "") return null;
  if (sender.startsWith("+")) return /^\+[1-9][0-9]{7,14}$/.test(sender) ? null : "latinOnly";
  if (sender.length > 11) return "tooLong";
  if (!/^[A-Za-z0-9 ]+$/.test(sender)) return "latinOnly";
  if (!/[A-Za-z]/.test(sender)) return "needsLetter";
  return null;
}

/** A sender suggestion from the box's name: Latin letters and digits, 11 at most. */
/** Shown as the sender field's example: a brand name, never translated. */
export const SENDER_EXAMPLE = "Palee";

export function suggestSender(name: string): string {
  const latin = name
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^A-Za-z0-9]/g, "");
  return latin.slice(0, 11);
}

export function smsSwitchedOn(connection: ChannelConnection | null | undefined): boolean {
  return Boolean(connection && connection.channels.includes("sms"));
}

/**
 * The provider to save with: the box's current one, else the first that
 * offers Palee's account (Brevo in production, the sandbox in development).
 */
export function providerFor(
  connection: ChannelConnection | null | undefined,
  providers: { provider: string; account_modes: string[] }[],
  mode: "palee" | "own" = "palee",
): string {
  if (connection?.provider) return connection.provider;
  const preferred = providers.find((entry) => entry.provider === "brevo" && entry.account_modes.includes(mode));
  return (preferred ?? providers.find((entry) => entry.account_modes.includes(mode)) ?? providers[0])?.provider ?? "brevo";
}

/** `YYYY-MM` of `at` on the box's clock. */
export function monthOf(at: Date, timeZone: string | null | undefined): string {
  try {
    const parts = new Intl.DateTimeFormat("en-CA", { timeZone: timeZone || undefined, year: "numeric", month: "2-digit" }).formatToParts(at);
    const year = parts.find((part) => part.type === "year")?.value;
    const month = parts.find((part) => part.type === "month")?.value;
    if (year && month) return `${year}-${month}`;
  } catch {
    // An unknown zone falls back to UTC below.
  }
  return at.toISOString().slice(0, 7);
}

/** This month and the `count - 1` before it, newest first. */
export function recentMonths(at: Date, timeZone: string | null | undefined, count = 3): string[] {
  const [year, month] = monthOf(at, timeZone).split("-").map(Number);
  return Array.from({ length: count }, (_, back) => {
    const date = new Date(Date.UTC(year, month - 1 - back, 1));
    return date.toISOString().slice(0, 7);
  });
}

/** «Νοέμβριος 2026» for `YYYY-MM`. */
export function monthLabel(month: string, locale: string): string {
  const [year, number] = month.split("-").map(Number);
  try {
    return new Intl.DateTimeFormat(locale, { month: "long", year: "numeric", timeZone: "UTC" }).format(new Date(Date.UTC(year, number - 1, 1)));
  } catch {
    return month;
  }
}

export type SpendSource = "automation" | "staff" | "system";
export const SPEND_SOURCES: SpendSource[] = ["automation", "staff", "system"];

export type SpendPart = { source: SpendSource; cents: number; count: number; percent: number };

/**
 * The month bar of screen 3 A: one part per source, as a share of the cap
 * (or of the spend when there is no cap), never more than 100 % in all.
 */
export function spendParts(usage: Pick<ChannelUsage, "by_source" | "spent_cents" | "cap_cents">): SpendPart[] {
  const whole = usage.cap_cents && usage.cap_cents > 0 ? usage.cap_cents : usage.spent_cents;
  let left = 100;
  return SPEND_SOURCES.flatMap((source) => {
    const line = usage.by_source?.[source];
    if (!line || line.cents <= 0) return [];
    const percent = whole > 0 ? Math.min(left, Math.round((line.cents / whole) * 1000) / 10) : 0;
    left = Math.max(0, left - percent);
    return [{ source, cents: line.cents, count: line.count, percent }];
  });
}

/** Arrived and did not arrive, from the month's states. */
export function deliveryCounts(byStatus: Record<string, number> | undefined) {
  const count = (status: string) => byStatus?.[status] ?? 0;
  return {
    delivered: count("delivered") + count("sent"),
    failed: count("failed"),
    waiting: count("queued") + count("sending"),
  };
}

/** How full the month is: «ok», «near» from 80 %, «full» at the cap. */
export function budgetState(spent: number, cap: number | null | undefined): "ok" | "near" | "full" {
  if (!cap || cap <= 0) return spent > 0 ? "full" : "ok";
  if (spent >= cap) return "full";
  return spent / cap >= 0.8 ? "near" : "ok";
}

export function consentGranted(contact: ChannelContact | null | undefined, purpose: ChannelPurpose): boolean {
  if (!contact || contact.opted_out_at) return false;
  return contact.consents.some((consent) => consent.channel === "sms" && consent.purpose === purpose && consent.granted);
}

/** Whether the person ever answered about this purpose (yes, no or STOP). */
export function consentAnswered(contact: ChannelContact | null | undefined, purpose: ChannelPurpose): boolean {
  if (!contact) return false;
  if (contact.opted_out_at) return true;
  return contact.consents.some((consent) => consent.channel === "sms" && consent.purpose === purpose);
}

/**
 * Screen 2 B: after a booking, ask once «Να σου στείλουμε SMS αν ακυρωθεί
 * το μάθημα;» — only when the box sends SMS, the member never answered
 * about updates, and never said «Όχι τώρα» here before.
 */
export function shouldAskAfterBooking(mine: MyChannels | null | undefined, declined: boolean): boolean {
  if (declined || !mine) return false;
  if (!Array.isArray(mine.channels) || !mine.channels.includes("sms")) return false;
  return !consentAnswered(mine.contact, "service");
}

const DECLINED_KEY = "palee:sms-ask-declined";

/** The «Όχι τώρα» of screen 2 B, per box and person, on this device. */
export function bookingAskDeclined(slug: string, userId: string | null | undefined): boolean {
  try {
    return window.localStorage.getItem(`${DECLINED_KEY}:${slug}:${userId ?? ""}`) === "1";
  } catch {
    return false;
  }
}

export function rememberBookingAskDeclined(slug: string, userId: string | null | undefined): void {
  try {
    window.localStorage.setItem(`${DECLINED_KEY}:${slug}:${userId ?? ""}`, "1");
  } catch {
    // Private mode: asked again next time on this device only.
  }
}

/** One key per press of «Ενημέρωση»: a retried request sends nothing twice. */
export function noticeKey(): string {
  const random = typeof crypto !== "undefined" && "randomUUID" in crypto ? crypto.randomUUID() : `${Date.now()}-${Math.random()}`;
  return random.slice(0, 80);
}

/** The API's codes the SMS screens explain in words; anything else is a general error. */
export const SMS_ERROR_CODES = [
  "channels_demo_mode",
  "channels_not_connected",
  "channels_connection_invalid",
  "channel_not_enabled",
  "channel_budget_exceeded",
  "channel_contact_missing",
  "channel_consent_missing",
  "channel_opted_out",
] as const;

export type SmsErrorCode = (typeof SMS_ERROR_CODES)[number];

export function smsErrorCode(code: string | null | undefined): SmsErrorCode | null {
  return SMS_ERROR_CODES.find((known) => known === code) ?? null;
}

/** A text field's look; red border when its value is wrong (the reason goes under it). */
export function inputStyle(invalid: boolean) {
  return {
    background: "var(--panel)",
    border: `1px solid ${invalid ? "var(--danger)" : "var(--border)"}`,
    color: "var(--text)",
  };
}

/** The 12 message languages (ADR-350); anything else is sent in English. */
export const SMS_LOCALES = ["el", "en", "de", "fr", "it", "es", "nl", "pt-PT", "bg", "ru", "ar", "he"];
export function smsLocale(locale: string): string {
  if (SMS_LOCALES.includes(locale)) return locale;
  if (locale.startsWith("pt")) return "pt-PT";
  const base = locale.split("-")[0];
  return SMS_LOCALES.includes(base) ? base : "en";
}

