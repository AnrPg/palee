"use client";

import { useTranslations } from "next-intl";
import { useState } from "react";

import { statusTone, toneStyle } from "@/components/admin/finance/shared/member-standing";
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";

import { localDay, standingParts, type Standing, type StandingPart } from "./standing";

/** ADR-595: the member's status as a badge, the same words for the member and for staff. */
export function StandingChip({ status }: { status: string }) {
  const t = useTranslations("MemberStanding");
  return (
    <span
      className="inline-flex shrink-0 items-center whitespace-nowrap rounded-full px-2 py-0.5 text-[11px] font-semibold"
      style={toneStyle(statusTone(status))}
      data-testid="standing-chip"
      data-status={status}
    >
      {t(`status_${status}` as "status_active")}
    </span>
  );
}

/** The one line under the badge (package kept, owed since, grace until), or nothing. */
export function StandingLine({ standing, currency = "EUR", className = "" }: { standing: Standing | null | undefined; currency?: string; className?: string }) {
  const t = useTranslations("MemberStanding");
  const locale = useUiLocale();
  const [today] = useState(() => localDay(new Date()));
  const parts = standingParts(standing, today);
  if (parts.length === 0) return null;

  const text = (part: StandingPart) => {
    switch (part.key) {
      case "linePackageUntil":
        return t("linePackageUntil", { date: formatDate(locale, part.date) });
      case "lineOwed":
        return t("lineOwed", { amount: formatMinorUnits(locale, part.cents, currency) });
      case "lineOwedSince":
        return t("lineOwedSince", { amount: formatMinorUnits(locale, part.cents, currency), date: formatDate(locale, part.date) });
      case "lineGrace":
      case "lineBoxGrace":
      case "lineBoxFree":
        return t(part.key, { date: formatDate(locale, part.date), days: part.days });
    }
  };

  return (
    <span className={`text-xs ${className}`} style={{ color: "var(--text-soft)" }} data-testid="standing-line">
      {parts.map(text).join(" · ")}
    </span>
  );
}

/** Badge and line together (ADR-595 4A). */
export function StandingBadge({ standing, currency, align = "start" }: { standing: Standing; currency?: string; align?: "start" | "end" }) {
  return (
    <span className={`flex min-w-0 flex-col gap-1 ${align === "end" ? "items-end text-end" : "items-start"}`}>
      <StandingChip status={standing.status} />
      <StandingLine standing={standing} currency={currency} />
    </span>
  );
}
