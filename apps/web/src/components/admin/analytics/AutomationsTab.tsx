"use client";

import { useTranslations } from "next-intl";

/**
 * «Αυτοματισμοί» in Στατιστικά & Μάρκετινγκ (W3 navigation decision). The
 * list of automatic messages is W2's screen (p3, ADR-346); until it lands
 * here the tab says what will appear. W2 replaces this component.
 */
export function AutomationsTab() {
  const t = useTranslations("Sms");
  return (
    <p className="rounded-[2rem] p-6 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }} data-testid="automations-tab">
      {t("automationsSoon")}
    </p>
  );
}
