"use client";

import { useTranslations } from "next-intl";

import { BranchFilterControl, BranchFilterNote, useBranchFilter } from "@/components/admin/BranchFilter";
import { PartnerPerksPanel } from "@/components/admin/finance/perks/PartnerPerksPanel";
import { ReferralsTab } from "@/components/admin/finance/tabs/ReferralsTab";
import { GuideButton } from "@/components/guides/GuideButton";
import { useUiTranslations } from "@/i18n/ui";

import { BoxPromotions } from "./BoxPromotions";
import { MarketingAreaPage } from "./MarketingAreaPage";

/** Μάρκετινγκ › Προσφορές του box, with the page branch filter it had in Οικονομικά (ADR-186 §7). */
export function BoxPromotionsPage() {
  const t = useTranslations("MarketingHub");
  const branchT = useTranslations("BranchScope");
  const filter = useBranchFilter("marketing-promotions");
  return (
    <MarketingAreaPage
      title={t("boxPromotions")}
      actions={
        <>
          <BranchFilterControl filter={filter} />
          <GuideButton guide="finance_offers" />
        </>
      }
    >
      {filter.param ? <BranchFilterNote>{branchT("filterNoteCovering")}</BranchFilterNote> : null}
      <BoxPromotions locationIds={filter.param} />
    </MarketingAreaPage>
  );
}

/** Μάρκετινγκ › Προσφορές συνεργατών (ADR-191). */
export function PartnerPerksPage() {
  const t = useTranslations("MarketingHub");
  return (
    <MarketingAreaPage title={t("partnerPerks")}>
      <PartnerPerksPanel />
    </MarketingAreaPage>
  );
}

/** Μάρκετινγκ › Συστάσεις (ADR-156), with its branch filter. */
export function ReferralsPage() {
  const i18n = useUiTranslations();
  const branchT = useTranslations("BranchScope");
  const filter = useBranchFilter("marketing-referrals");
  return (
    <MarketingAreaPage title={i18n("referrals2b0e3a3")} actions={<BranchFilterControl filter={filter} />}>
      {filter.param ? <BranchFilterNote>{branchT("filterNoteReferrals")}</BranchFilterNote> : null}
      <ReferralsTab locationIds={filter.param} />
    </MarketingAreaPage>
  );
}
