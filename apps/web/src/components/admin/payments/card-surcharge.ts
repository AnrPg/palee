import type {
  SurchargeCard,
  SurchargeChannel,
  SurchargeLaw,
  SurchargeQuote,
  SurchargeStatus,
  SurchargeUpdate,
} from "@/api/card-surcharge";
import type { ApiErrorPayload } from "@/api/client";

/*
 * ADR-340 «Επιβάρυνση κάρτας», the pure parts of the screens: the three-step
 * guide in Ρυθμίσεις › Πληρωμές (mockup W1 s1, option B), the line in the
 * member's total (s2, A) and the «Τι κάρτα έδωσε;» question for «Κάρτα στο
 * POS» (s3, A). Amounts are integer cents, percents basis points.
 */

export const CHANNELS: SurchargeChannel[] = ["online", "terminal", "desk"];

/** «Κάρτα στο POS» is off until the owner turns it on (ANR 2026-11-02): the question then never shows at most boxes. */
export const DEFAULT_CHANNELS: SurchargeChannel[] = ["online", "terminal"];

export type GuideStep = 0 | 1 | 2;

export type GuideDraft = {
  percent: string;
  fixed: string;
  channels: SurchargeChannel[];
  atCost: boolean;
};

export type GuideField = "percent" | "fixed" | "atCost" | "channels" | "region";
export type GuideErrors = Partial<Record<GuideField, string>>;

/** 150 → «1,5» in Greek, «1.5» in English. */
export function percentInput(bps: number, locale: string): string {
  if (bps <= 0) return "";
  return new Intl.NumberFormat(locale, { maximumFractionDigits: 2, useGrouping: false }).format(bps / 100);
}

/** 150 → «1,5%». */
export function percentText(bps: number, locale: string): string {
  return new Intl.NumberFormat(locale, { style: "percent", maximumFractionDigits: 2 }).format(bps / 10000);
}

/** «1,5» or «1.5» → 150; empty → 0; anything else → null. */
export function parsePercentBps(text: string): number | null {
  const clean = text.trim().replace("%", "").replace(",", ".").trim();
  if (clean === "") return 0;
  if (!/^\d{1,2}(\.\d{1,2})?$/.test(clean)) return null;
  return Math.round(Number(clean) * 100);
}

/** «0,30» → 30 cents; empty → 0; anything else → null. */
export function parseFixedCents(text: string): number | null {
  const clean = text.trim().replace(/[€$£\s]/g, "").replace(",", ".");
  if (clean === "") return 0;
  if (!/^\d{1,3}(\.\d{1,2})?$/.test(clean)) return null;
  return Math.round(Number(clean) * 100);
}

export function centsInput(cents: number): string {
  return cents > 0 ? (cents / 100).toFixed(2) : "";
}

/** The guide starts from what is saved; a box that never saved gets the default channels (POS off). */
export function initialDraft(status: SurchargeStatus, locale: string): GuideDraft {
  const { settings } = status;
  return {
    percent: percentInput(settings.percent_bps, locale),
    fixed: centsInput(settings.fixed_cents),
    channels: status.saved && settings.channels.length > 0 ? CHANNELS.filter((channel) => settings.channels.includes(channel)) : DEFAULT_CHANNELS,
    atCost: settings.at_cost_confirmed,
  };
}

/** The highest percent the law allows here, or null when it sets none. */
export function capBps(law: SurchargeLaw): number | null {
  return typeof law.cap_bps === "number" ? law.cap_bps : null;
}

/**
 * What stops a step, field by field (message keys of `CardSurcharge`). The
 * amount step needs a percent or a fixed amount within the cap and, where the
 * law says «Έως το πραγματικό κόστος», the owner's confirmation; the last
 * step needs at least one channel.
 */
export function stepErrors(step: GuideStep, draft: GuideDraft, law: SurchargeLaw): GuideErrors {
  const errors: GuideErrors = {};
  if (step === 1) {
    const percent = parsePercentBps(draft.percent);
    const fixed = parseFixedCents(draft.fixed);
    const cap = capBps(law);
    if (percent === null || percent > 1000) errors.percent = "errorPercentInvalid";
    else if (cap !== null && percent > cap) errors.percent = "errorAboveCap";
    else if (percent === 0 && (fixed ?? 0) === 0) errors.percent = "errorPercentRequired";
    if (fixed === null || (fixed ?? 0) > 10000) errors.fixed = "errorFixedInvalid";
    if (law.at_cost && !draft.atCost) errors.atCost = "errorAtCostRequired";
  }
  if (step === 2 && draft.channels.length === 0) errors.channels = "errorChannelsRequired";
  return errors;
}

/** The body that turns the surcharge on with the guide's answers. */
export function enableBody(draft: GuideDraft): SurchargeUpdate {
  return {
    enabled: true,
    percent_bps: parsePercentBps(draft.percent) ?? 0,
    fixed_cents: parseFixedCents(draft.fixed) ?? 0,
    channels: CHANNELS.filter((channel) => draft.channels.includes(channel)),
    at_cost_confirmed: draft.atCost,
  };
}

/** The surcharge on `baseCents`, as the API rounds it (half up, then the fixed amount). */
export function surchargeOn(baseCents: number, percentBps: number, fixedCents: number): number {
  return Math.round((baseCents * percentBps) / 10000) + fixedCents;
}

/** What the API's refusal is about, so its reason shows under that field. */
export function fieldForSurchargeError(payload: ApiErrorPayload | undefined): GuideField | null {
  if (!payload) return null;
  if (payload.code === "card_surcharge_not_allowed") return payload.params?.reason === "above_cap" ? "percent" : null;
  if (payload.code !== "validation_failed" || !payload.errors) return null;
  const fields = payload.errors;
  if ("percent_bps" in fields) return "percent";
  if ("fixed_cents" in fields) return "fixed";
  if ("at_cost_confirmed" in fields) return "atCost";
  if ("channels" in fields) return "channels";
  if ("region_code" in fields) return "region";
  return null;
}

/** The plain sentence of the law of the box's country (message key and values). */
export function lawSentence(law: SurchargeLaw, locale: string): { key: string; values: Record<string, string> } {
  const cap = capBps(law);
  const capText = cap === null ? "" : percentText(cap, locale);
  if (law.region_required) return { key: "lawRegionRequired", values: {} };
  switch (law.rule) {
    case "eea_non_consumer":
      return { key: "lawEeaNonConsumer", values: {} };
    case "commercial_only":
      return { key: "lawCommercialOnly", values: {} };
    case "credit_only":
      return { key: cap === null ? "lawCreditOnlyNoCap" : "lawCreditOnly", values: { cap: capText } };
    case "any":
      return { key: cap === null ? "lawAnyNoCap" : "lawAny", values: { cap: capText } };
    default:
      return { key: "lawNone", values: {} };
  }
}

/** The country's name in the reader's language (GR → «Ελλάδα»), or the code when unknown. */
export function countryName(code: string | null | undefined, locale: string): string {
  if (!code) return "";
  try {
    return new Intl.DisplayNames([locale], { type: "region" }).of(code.toUpperCase()) ?? code;
  } catch {
    return code;
  }
}

// ── «Κάρτα στο POS» (mockup s3 A) ───────────────────────────────────────────

/** Reasons that mean the box adds nothing at the desk: no question is asked. */
const SILENT_REASONS = new Set(["off", "channel_off", "not_allowed_here", "zero"]);

/** Whether «Τι κάρτα έδωσε;» is asked: the box surcharges at the POS and the law allows some cards. */
export function asksCardKind(quote: SurchargeQuote | null | undefined): boolean {
  if (!quote) return false;
  if (quote.rule === "any") return false;
  return !SILENT_REASONS.has(quote.reason ?? "");
}

export type DeskCardKind = "consumer_eea" | "consumer" | "business" | "non_eea" | "debit" | "credit" | "unknown";

/**
 * ISO 3166 «ZZ» (unknown or unspecified territory): staff only know that the
 * card is from outside the EEA, not from where. The law reads only that.
 */
export const NON_EEA_COUNTRY = "ZZ";

/** The answers staff can give for the law's rule, «Δεν ξέρω» last (no surcharge). */
export function deskCardKinds(rule: SurchargeQuote["rule"]): DeskCardKind[] {
  switch (rule) {
    case "eea_non_consumer":
      return ["consumer_eea", "business", "non_eea", "unknown"];
    case "commercial_only":
      return ["consumer", "business", "unknown"];
    case "credit_only":
      return ["debit", "credit", "unknown"];
    default:
      return [];
  }
}

/** The card facts the law reads for an answer; «Δεν ξέρω» knows nothing. */
export function deskCard(kind: DeskCardKind): SurchargeCard {
  switch (kind) {
    case "consumer_eea":
    case "consumer":
      return { commercial: false };
    case "business":
      return { commercial: true };
    case "non_eea":
      return { country: NON_EEA_COUNTRY };
    case "debit":
      return { funding: "debit" };
    case "credit":
      return { funding: "credit" };
    case "unknown":
      return {};
  }
}
