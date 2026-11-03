"use client";

import { useTranslations } from "next-intl";

import { percentText } from "@/components/admin/payments/card-surcharge";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits as money } from "@/lib/finance-accounting";

/** The card surcharge the API quoted for this payment (`package_terms.surcharge`, `checkout_terms.surcharge`). */
export type MemberSurcharge = {
  applies: boolean;
  surcharge_cents: number;
  total_cents: number;
  percent_bps: number;
  fixed_cents: number;
  reason?: string | null;
};

/** Reasons that mean the box adds no surcharge at all: nothing is shown. */
const HIDDEN = new Set(["off", "channel_off", "not_allowed_here"]);

/**
 * ADR-340 (mockup W1 s2, option A): whether the total shows a «Επιβάρυνση
 * κάρτας» line. Only when the box surcharges online; a card the law
 * protects, or a new card Palee knows nothing about, reads «Χωρίς επιβάρυνση».
 */
export function surchargeShown(surcharge: MemberSurcharge | null | undefined): surcharge is MemberSurcharge {
  return Boolean(surcharge) && !HIDDEN.has(surcharge!.reason ?? "");
}

/** What the member pays: the amount plus a surcharge that applies. */
export function payableCents(amountCents: number, surcharge: MemberSurcharge | null | undefined): number {
  return surcharge?.applies ? amountCents + surcharge.surcharge_cents : amountCents;
}

/** «Πακέτο 60,00 € · Επιβάρυνση κάρτας (1,5%) 0,90 € · Σύνολο 60,90 €», above the pay button. */
export function SurchargeTotal({
  label,
  amountCents,
  currency,
  surcharge,
}: {
  label: string;
  amountCents: number;
  currency: string;
  surcharge: MemberSurcharge;
}) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  const row = "flex min-w-0 items-baseline justify-between gap-3 text-sm";
  const total = payableCents(amountCents, surcharge);
  return (
    <div className="flex flex-col gap-1.5 rounded-2xl p-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }} data-testid="pay-surcharge">
      <div className={row}>
        <span className="min-w-0 break-words" style={{ color: "var(--text-soft)" }}>{label}</span>
        <span className="shrink-0 tabular-nums" style={{ color: "var(--text)" }}>{money(locale, amountCents, currency)}</span>
      </div>
      <div className={row}>
        <span style={{ color: "var(--text-soft)" }}>
          {surcharge.applies && surcharge.percent_bps > 0
            ? t("surchargeLinePercent", { percent: percentText(surcharge.percent_bps, locale) })
            : t("surchargeLine")}
        </span>
        {surcharge.applies ? (
          <span className="shrink-0 tabular-nums" style={{ color: "var(--text)" }} data-testid="pay-surcharge-amount">
            {money(locale, surcharge.surcharge_cents, currency)}
          </span>
        ) : (
          <span className="shrink-0 text-xs" style={{ color: "var(--dim)" }}>{t("surchargeNone")}</span>
        )}
      </div>
      <div className={row + " border-t pt-1.5 font-bold"} style={{ borderColor: "var(--border)" }}>
        <span style={{ color: "var(--text)" }}>{t("surchargeTotal")}</span>
        <span className="shrink-0 tabular-nums" style={{ color: "var(--text)" }} data-testid="pay-surcharge-total">
          {money(locale, total, currency)}
        </span>
      </div>
      {surcharge.applies ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("surchargeNote")}</p> : null}
    </div>
  );
}
