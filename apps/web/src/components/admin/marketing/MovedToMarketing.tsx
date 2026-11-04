"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { useUiTranslations } from "@/i18n/ui";
import { MARKETING_ROUTES, type MarketingArea } from "@/lib/marketing-routes";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { useMarketingAccess } from "./marketing-access";

/**
 * Οικονομικά › Προσφορές since 2026-11-04 (ANR): one quiet line saying the
 * offers moved to Μάρκετινγκ and a way to each of them, so they are still
 * found from here. Not a second copy of the pages.
 */
export function MovedToMarketing() {
  const t = useTranslations("MarketingHub");
  const i18n = useUiTranslations();
  const slug = useOrganizationSlug();
  const access = useMarketingAccess();
  const links: Array<[MarketingArea, string]> = [
    ["promotions", t("boxPromotions")],
    ["perks", t("partnerPerks")],
    ["referrals", i18n("referrals2b0e3a3")],
  ];
  const shown = links.filter(([area]) => access.opens(area));

  return (
    <section
      data-testid="offers-moved"
      className="flex flex-col gap-3 rounded-2xl px-5 py-4 sm:flex-row sm:flex-wrap sm:items-center"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <p className="text-sm sm:me-auto" style={{ color: "var(--muted)" }}>{t("movedLine")}</p>
      {shown.map(([area, label]) => (
        <Link
          key={area}
          href={adminHref(MARKETING_ROUTES[area], slug)}
          className="text-sm font-semibold"
          style={{ color: "var(--primary)" }}
        >
          {label} <span aria-hidden="true" className="inline-block rtl:rotate-180">→</span>
        </Link>
      ))}
    </section>
  );
}
