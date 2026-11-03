import type { Metadata } from "next";

import { SiteRoute, siteMetadata } from "@/components/box-site/site-route";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  return siteMetadata(slug, "box");
}

/**
 * The public box page (ADR-142, plan §5a board 4): server-rendered so a
 * shared link previews well. Logged out, only «Σχετικά» is open (D2); with
 * the box's website on, «Σχετικά» is the website (ADR-388).
 */
export default async function PublicBoxRoute({ params }: Props) {
  const { slug } = await params;
  return <SiteRoute slug={slug} language="box" />;
}
