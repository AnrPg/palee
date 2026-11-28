"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import { MemberFinance } from "@/components/admin/finance/member/MemberFinance";
import { SidePanel } from "@/components/admin/finance/shared/SidePanel";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

/**
 * The ledger's side panel for one person (Οικονομικά › Μέλη). ADR-784 (ANR
 * pick 3): it shows the very component of the profile's «Οικονομικά» tab, so
 * money looks and works the same in both places; what is not money (dates,
 * freezes, gifts, leaving) is one press away on the profile.
 */
export function MemberPanel({
  userId,
  nickname,
  onClose,
}: {
  userId: string;
  nickname: string;
  onClose: () => void;
}) {
  const i18n = useUiTranslations();
  const t = useTranslations("MemberFinance");
  const slug = useOrganizationSlug();

  return (
    <SidePanel title={nickname} subtitle={i18n("memberFinanceProfile6f16152")} onClose={onClose}>
      <div className="space-y-3">
        <Link
          href={adminHref(`/admin/users/${encodeURIComponent(userId)}?tab=finance`, slug)}
          className="inline-flex text-sm font-semibold"
          style={{ color: "var(--primary)" }}
          data-testid="member-panel-open-profile"
        >
          {t("openProfile")}
        </Link>
        <MemberFinance userId={userId} nickname={nickname} compact />
      </div>
    </SidePanel>
  );
}
