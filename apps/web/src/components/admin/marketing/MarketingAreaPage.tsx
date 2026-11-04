"use client";

import type { ReactNode } from "react";
import { useTranslations } from "next-intl";

import { PageHeader } from "@/components/PageHeader";
import { BackLink } from "@/components/ui/BackLink";
import { MARKETING_TAB_HREF } from "@/lib/marketing-routes";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

/** «← Μάρκετινγκ» back to the hub's Marketing tab (the link a Marketing page sits under). */
export function MarketingBackLink() {
  const t = useTranslations("MarketingHub");
  const slug = useOrganizationSlug();
  return <BackLink href={adminHref(MARKETING_TAB_HREF, slug)}>{t("back")}</BackLink>;
}

/** A page under Στατιστικά & Μάρκετινγκ › Μάρκετινγκ: the way back, the title and the area. */
export function MarketingAreaPage({ title, actions, children }: { title: string; actions?: ReactNode; children: ReactNode }) {
  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-14" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-7xl space-y-6">
        <MarketingBackLink />
        <PageHeader title={title} actions={actions} />
        {children}
      </div>
    </main>
  );
}
