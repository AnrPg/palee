import type { Metadata } from "next";

import { SiteRoute, siteMetadata } from "@/components/box-site/site-route";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  return siteMetadata(slug, "en");
}

/** The box's website in English (ADR-388): the owner's English texts where written, the box's own otherwise. */
export default async function PublicBoxEnglishRoute({ params }: Props) {
  const { slug } = await params;
  return <SiteRoute slug={slug} language="en" />;
}
