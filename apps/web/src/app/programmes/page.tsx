import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";

import { ProgrammeCatalogue } from "@/components/programmes/ProgrammeCatalogue";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("Programmes");
  return { title: t("storeTitle"), alternates: { canonical: "/programmes" } };
}

/** «Αγορά προγραμμάτων» (ADR-370, mockup W8 s3): public, no account needed. */
export default function ProgrammesRoute() {
  return <ProgrammeCatalogue />;
}
