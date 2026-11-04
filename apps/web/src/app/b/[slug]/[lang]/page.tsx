import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { SiteRoute, siteMetadata } from "@/components/box-site/site-route";
import { siteLanguageFromSegment } from "@/lib/public-site";

type Props = { params: Promise<{ slug: string; lang: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug, lang } = await params;
  const language = siteLanguageFromSegment(lang);
  return language ? siteMetadata(slug, language) : {};
}

/**
 * The box's website in one of its translations (ADR-388 English, ADR-520 any
 * language the owner shows): the owner's texts where translated, the box's
 * own otherwise. A language the box does not show goes to its own page.
 */
export default async function PublicBoxLanguageRoute({ params }: Props) {
  const { slug, lang } = await params;
  const language = siteLanguageFromSegment(lang);
  if (!language) notFound();
  return <SiteRoute slug={slug} language={language} />;
}
