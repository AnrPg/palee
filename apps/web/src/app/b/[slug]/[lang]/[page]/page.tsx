import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { SiteRoute, siteMetadata } from "@/components/box-site/site-route";
import { siteRouteTarget } from "@/components/box-site/templates/site-route-target";

type Props = { params: Promise<{ slug: string; lang: string; page: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug, lang, page } = await params;
  const target = siteRouteTarget(lang, page);
  return target ? siteMetadata(slug, target.language, target.pageKey) : {};
}

/** ADR-530: a page of the box's website in one of its translations (`/b/<slug>/en/schedule`). */
export default async function PublicSitePageRoute({ params }: Props) {
  const { slug, lang, page } = await params;
  const target = siteRouteTarget(lang, page);
  if (!target) notFound();
  return <SiteRoute slug={slug} language={target.language} pageKey={target.pageKey} />;
}
