import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { SiteRoute, siteMetadata } from "@/components/box-site/site-route";
import { isSubPage } from "@/components/box-site/templates/site-model";
import { siteLanguageFromSegment } from "@/lib/public-site";

type Props = { params: Promise<{ slug: string; lang: string; page: string }> };

function route(lang: string, page: string) {
  const language = siteLanguageFromSegment(lang);
  const pageKey = page.toLowerCase();
  return language && isSubPage(pageKey) ? { language, pageKey } : null;
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug, lang, page } = await params;
  const target = route(lang, page);
  return target ? siteMetadata(slug, target.language, target.pageKey) : {};
}

/** ADR-530: a page of the box's website in one of its translations (`/b/<slug>/en/schedule`). */
export default async function PublicSitePageRoute({ params }: Props) {
  const { slug, lang, page } = await params;
  const target = route(lang, page);
  if (!target) notFound();
  return <SiteRoute slug={slug} language={target.language} pageKey={target.pageKey} />;
}
