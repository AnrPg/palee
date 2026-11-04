import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { SiteRoute, siteMetadata } from "@/components/box-site/site-route";
import { siteRouteTarget } from "@/components/box-site/templates/site-route-target";

type Props = { params: Promise<{ slug: string; lang: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug, lang } = await params;
  const target = siteRouteTarget(lang);
  return target ? siteMetadata(slug, target.language, target.pageKey) : {};
}

/**
 * The box's website in one of its translations (ADR-388 English, ADR-520 any
 * language the owner shows): the owner's texts where translated, the box's
 * own otherwise. A language the box does not show goes to its own page.
 * ADR-530: the same segment also names the website's pages in the box's
 * language (`/b/<slug>/schedule`); language codes and pages never collide.
 */
export default async function PublicBoxLanguageRoute({ params }: Props) {
  const { slug, lang } = await params;
  const target = siteRouteTarget(lang);
  if (!target) notFound();
  return <SiteRoute slug={slug} language={target.language} pageKey={target.pageKey} />;
}
