import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";

import { BoxProgrammes } from "@/components/programmes/BoxProgrammes";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const t = await getTranslations("Programmes");
  return { title: t("title"), alternates: { canonical: `/b/${encodeURIComponent(slug)}/programmes` } };
}

/** A box's programmes on sale (ADR-543): «Όλα τα προγράμματα (N)» from its website. */
export default async function BoxProgrammesRoute({ params }: Props) {
  const { slug } = await params;
  return <BoxProgrammes slug={slug} />;
}
