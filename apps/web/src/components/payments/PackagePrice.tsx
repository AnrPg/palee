"use client";

import { useTranslations } from "next-intl";

import { useUiLocale } from "@/i18n/use-ui-locale";
import { SPARK_ACTIVE_STYLE } from "@/lib/spark";

import { perLabel } from "./BuyPackageSheet";
import { money } from "./PackageCheckout";

/** ADR-681: a package with a price of 0, shown by the box and never paid for. */
export function isFreePackage(pkg: { base_price_cents: number }): boolean {
  return pkg.base_price_cents === 0;
}

/**
 * A package's price with its period («75,00 €/μήνα»), or, for a free package,
 * «Δωρεάν» as an electric green tag in its place (ANR 2026-11-21, option 3A).
 */
export function PackagePrice({ pkg, large = false }: { pkg: { base_price_cents: number; currency: string; billing_period: string }; large?: boolean }) {
  const t = useTranslations("Pay");
  const locale = useUiLocale();
  if (isFreePackage(pkg)) return <FreeTag />;
  return (
    <>
      <span className={large ? "text-2xl font-extrabold tabular-nums" : "tabular-nums"} style={{ color: "var(--text)" }}>
        {money(locale, pkg.base_price_cents, pkg.currency)}
      </span>
      <span className={large ? "text-xs" : undefined} style={{ color: large ? "var(--dim)" : "var(--text)" }}>
        {perLabel(t, pkg.billing_period)}
      </span>
    </>
  );
}

/** «Δωρεάν» as a tag. */
export function FreeTag({ className = "" }: { className?: string }) {
  const t = useTranslations("Pay");
  return (
    <span
      className={`inline-flex w-fit items-center whitespace-nowrap rounded-full px-3 py-0.5 text-sm font-extrabold ${className}`}
      style={SPARK_ACTIVE_STYLE}
      data-testid="package-free"
    >
      {t("free")}
    </span>
  );
}
