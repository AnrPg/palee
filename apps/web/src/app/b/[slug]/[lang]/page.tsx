import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { SiteRoute, siteMetadata } from "@/components/box-site/site-route";
import { isSubPage } from "@/components/box-site/templates/site-model";
import { siteLanguageFromSegment } from "@/lib/public-site";

type Props = { params: Promise<{ slug: string; lang: string }> };

/** `/b/<slug>/<segment>`: a page of the website in the box's language, or a translation's home. */
function route(segment: string) {
  const page = segment.toLowerCase();
  if (isSubPage(page)) return { language: "box" as const, pageKey: page };
  const language = siteLanguageFromSegment(segment);
  return language ? { language, pageKey: "home" as const } : null;
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug, lang } = await params;
  const target = route(lang);
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
  const target = route(lang);
  if (!target) notFound();
  return <SiteRoute slug={slug} language={target.language} pageKey={target.pageKey} />;
}
