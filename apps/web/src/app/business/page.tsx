import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";

import { BusinessLanding } from "@/components/business-landing/BusinessLanding";
import { audienceFromParam } from "@/components/business-landing/content";

export const dynamic = "force-dynamic";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("BusinessLanding");
  return {
    title: t("metaTitle"),
    description: t("metaDescription"),
    alternates: { canonical: "/business" },
  };
}

/** ADR-556: palee.app/business sells Palee to boxes and independent coaches. `?for=coach` opens the coach's side. */
export default async function BusinessLandingPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  return <BusinessLanding initialAudience={audienceFromParam(params.for)} />;
}
