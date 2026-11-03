import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";

import { LegalPage, LegalSection, legalPlaceholders } from "@/components/legal/LegalPage";

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

// Each section: its anchor, then the keys of its heading and of its paragraphs in `legal.terms`.
const SECTIONS = [
  { id: "account", heading: "accountTitle", texts: ["accountBody"] },
  { id: "boxes", heading: "boxesTitle", texts: ["boxesBody"] },
  // ADR-370/371 and the P2B Regulation: what a business using Palee answers for.
  { id: "business", heading: "businessTitle", texts: ["businessBody1", "businessBody2", "businessBody3"] },
  { id: "payments", heading: "paymentsTitle", texts: ["paymentsBody"] },
  // ADR-370/371: selling and buying a training programme.
  {
    id: "programmes",
    heading: "programmesTitle",
    texts: ["programmesBody1", "programmesBody2", "programmesBody3", "programmesBody4", "programmesBody5"],
  },
  { id: "content", heading: "contentTitle", texts: ["contentBody"] },
  // ADR-397 and DSA Art. 14: reviews, reports and who decides on them.
  {
    id: "reviews",
    heading: "reviewsTitle",
    texts: ["reviewsBody1", "reviewsBody2", "reviewsBody3", "reviewsBody4", "reviewsBody5"],
  },
  { id: "health", heading: "healthTitle", texts: ["healthBody"] },
  { id: "ai", heading: "aiTitle", texts: ["aiBody"] },
  { id: "availability", heading: "availabilityTitle", texts: ["availabilityBody"] },
  { id: "ending", heading: "endingTitle", texts: ["endingBody"] },
  { id: "liability", heading: "liabilityTitle", texts: ["liabilityBody"] },
  { id: "law", heading: "lawTitle", texts: ["lawBody"] },
  { id: "changes", heading: "changesTitle", texts: ["changesBody"] },
] as const;

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
      {SECTIONS.map((section) => (
        <LegalSection key={section.id} id={section.id} title={terms(section.heading)}>
          {section.texts.map((key) => (
            <p key={key}>{terms(key, values)}</p>
          ))}
        </LegalSection>
      ))}
    </LegalPage>
  );
}
