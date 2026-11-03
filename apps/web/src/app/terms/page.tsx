import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";

import { LegalPage, LegalSection, legalPlaceholders } from "@/components/legal/LegalPage";
import { TERMS_SECTIONS } from "@/components/legal/termsSections";

export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("legal");
  const title = t("termsTitle");
  const description = t("terms.intro");
  return {
    title,
    description,
    alternates: { canonical: "/terms" },
    openGraph: { title, description, url: "/terms" },
  };
}


/** ADR-267: Palee's terms of use, a draft for the law consultant. */
export default async function TermsPage() {
  const t = await getTranslations("legal");
  const terms = await getTranslations("legal.terms");
  const values = await legalPlaceholders();

  return (
    <LegalPage title={t("termsTitle")} intro={terms("intro")} current="terms">
      <LegalSection id="provider" title={terms("providerTitle")}>
        <p>{terms("providerBody", values)}</p>
      </LegalSection>
      {TERMS_SECTIONS.map((section) => (
        <LegalSection key={section.id} id={section.id} title={terms(section.heading)}>
          {section.texts.map((key) => (
            <p key={key}>{terms(key, values)}</p>
          ))}
        </LegalSection>
      ))}
    </LegalPage>
  );
}
