"use client";

import { useTranslations } from "next-intl";
import { useSearchParams } from "next/navigation";
import { useState } from "react";

import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

import { PayItemsCatalog } from "./PayItemsCatalog";
import { PayPeriodsView } from "./PayPeriodsView";
import { PayRulesView } from "./PayRulesView";

type View = "rules" | "periods" | "items";

/**
 * Οικονομικά › Αμοιβές coaches (ADR-341/382, mockup W1 s4–s5): the rules per
 * person, the pay periods and the overtime and allowances catalogue. Billing
 * staff edit rules and periods; the catalogue is a setting (ADR-382), so it
 * is edited by whoever manages settings, and read by the rest.
 */
export function CoachPayTab() {
  const t = useTranslations("CoachPay");
  const { membership } = useSelectedMembershipRole();
  // `?pay_view=periods` opens a view directly (the catalogue's «Περίοδοι» link from Settings).
  const requested = useSearchParams().get("pay_view");
  const [view, setView] = useState<View>(requested === "periods" || requested === "items" ? requested : "rules");
  const canBill = can(membership, "manage_billing");
  return (
    <div className="space-y-4" data-testid="coach-pay-tab">
      <SegmentPicker
        level="sub"
        ariaLabel={t("title")}
        value={view}
        onChange={setView}
        options={[
          { value: "rules", label: t("viewRules") },
          { value: "periods", label: t("viewPeriods") },
          { value: "items", label: t("viewItems") },
        ]}
      />
      {view === "rules" ? <PayRulesView canEdit={canBill} /> : null}
      {view === "periods" ? <PayPeriodsView canEdit={canBill} /> : null}
      {view === "items" ? (
        <PayItemsCatalog canEdit={can(membership, "manage_settings")} canAddOneOff={canBill} onOpenPeriods={() => setView("periods")} />
      ) : null}
    </div>
  );
}

/** Whether this person sees «Αμοιβές coaches» at all (the API's own gate). */
export function useSeesCoachPay(): boolean {
  const { membership } = useSelectedMembershipRole();
  return can(membership, "view_finance_reports") || can(membership, "manage_billing");
}
