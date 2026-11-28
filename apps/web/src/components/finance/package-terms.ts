/**
 * ADR-770: how a changed term of a subscription package reads, for the
 * staff sheet «Ισχύει και για τα ενεργά μέλη;» and the member's
 * «Νέοι όροι από…». Values are the package contract's stored JSON.
 */
import type { UiTranslator } from "@/i18n/presentation";
import { fieldLabelKey } from "@/components/admin/finance/packages/package-catalog";
import { formatMinorUnits } from "@/lib/finance-accounting";

export const PRICE_KEY = "price";
export const BILLING_PERIOD_KEY = "billing_period";

/** The term's name: the price, the billing period or the contract field's label. */
export function termLabel(t: UiTranslator, key: string): string {
  if (key === PRICE_KEY) return t("pkgTermsPrice");
  if (key === BILLING_PERIOD_KEY) return t("pkgTermsBillingPeriod");
  return t(fieldLabelKey(key));
}

type Quota = { limit: number | "unlimited"; period?: string };
type Duration = { amount: number; unit: "day" | "week" | "month" };

function isQuota(value: unknown): value is Quota {
  return typeof value === "object" && value !== null && "limit" in value;
}

function isDuration(value: unknown): value is Duration {
  return typeof value === "object" && value !== null && "amount" in value && "unit" in value;
}

/**
 * One value of a term. `names` turns class type ids into names where the
 * caller knows them; otherwise a list reads as its count.
 */
export function termValue(
  t: UiTranslator,
  locale: string,
  key: string,
  value: unknown,
  names?: Map<string, string>,
): string {
  if (key === PRICE_KEY) return formatMinorUnits(locale, typeof value === "number" ? value : null);
  if (value === null || value === undefined) {
    return key.startsWith("booking.window") || key.startsWith("booking.cancellation") ? t("pkgTermsBoxDefault") : t("pkgNoLimit");
  }
  if (typeof value === "boolean") return value ? t("pkgYes") : t("pkgNo");
  if (typeof value === "number") return new Intl.NumberFormat(locale).format(value);
  if (value === "all") return t("pkgClassTypesAll");
  if (isQuota(value)) {
    if (value.limit === "unlimited") return t("pkgUnlimited");
    return value.period ? `${value.limit} ${t(`pkgPeriod_${value.period}`)}` : String(value.limit);
  }
  if (isDuration(value)) return t(`pkgDuration_${value.unit}`, { count: value.amount });
  if (Array.isArray(value)) {
    if (names && value.every((item) => typeof item === "string" && names.has(item))) {
      return value.map((item) => names.get(String(item))).join(", ");
    }
    return t("pkgTermsCount", { count: value.length });
  }
  return String(value);
}
