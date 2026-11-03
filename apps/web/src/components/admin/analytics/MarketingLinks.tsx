"use client";

import Link from "next/link";

import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

/** Promotions, referrals and packages, each opened in Finance (the «Μάρκετινγκ» tab and page). */
export function MarketingLinks() {
  const i18n = useUiTranslations();
  const slug = useOrganizationSlug();
  const links = [
    [i18n("promotions086e09b"), "/admin/finance?tab=promotions", i18n("createAndManagePromotionalOffers46d33bb")],
    [i18n("referrals2b0e3a3"), "/admin/finance?tab=referrals", i18n("reviewReferralActivityAndRewardActions8ea1271")],
    [i18n("packages0a99901"), "/admin/finance?tab=packages", i18n("manageThePackagesUsedByMembershipsAndEntitlementsb466c1f")],
  ] as const;
  return (
    <section className="grid gap-4 md:grid-cols-3">
      {links.map(([label, href, description]) => (
        <Link
          key={label}
          className="rounded-[2rem] p-6 transition-transform hover:-translate-y-0.5"
          href={adminHref(href, slug)}
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        >
          <p className="text-lg font-semibold" style={{ color: "var(--text)" }}>{label}</p>
          <p className="mt-3 text-sm leading-6" style={{ color: "var(--muted)" }}>{description}</p>
          <p className="mt-5 text-sm font-semibold" style={{ color: "var(--primary)" }}>{i18n("openInFinanceabe0a86")}</p>
        </Link>
      ))}
    </section>
  );
}
