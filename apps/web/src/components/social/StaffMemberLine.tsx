"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchAdminUserFinance } from "@/api/admin-users";
import { StandingChip } from "@/components/finance/StandingBadge";
import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { adminHref } from "@/lib/organization-slug";
import { can } from "@/lib/role-navigation";

/** Staff who see money: they get the line; everyone else never asks for it. */
export function seesMemberFinance(membership: Parameters<typeof can>[0]) {
  return can(membership, "take_payments") || can(membership, "manage_billing") || can(membership, "view_finance_reports");
}

/**
 * ADR-784 (ANR pick 5): on a person's social profile, staff of their box see
 * one quiet line: that this is a member of their box, the status, and
 * «Οικονομικά μέλους» to the profile's «Οικονομικά» tab. No amounts, since
 * this page may be on screen beside other people. Nothing for anyone else.
 */
export function StaffMemberLine({ personId }: { personId: string }) {
  const t = useTranslations("MemberFinance");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const { membership } = useSelectedMembershipRole();
  const sees = Boolean(token && membership && seesMemberFinance(membership));
  const finance = useQuery({
    queryKey: ["admin", "users", personId, "finance"],
    enabled: sees,
    retry: false,
    queryFn: () => fetchAdminUserFinance(token, personId),
  });
  const standing = finance.data?.available ? finance.data.summary?.standing : null;
  if (!sees || !membership || !standing) return null;

  return (
    <div
      className="mx-4 mt-3 flex flex-wrap items-center justify-between gap-2 rounded-2xl px-3.5 py-2.5 text-sm"
      style={{ background: "color-mix(in srgb, var(--primary) 9%, transparent)" }}
      data-testid="staff-member-line"
    >
      <span className="flex min-w-0 flex-wrap items-center gap-2">
        <strong style={{ color: "var(--text)" }}>{t("staffLine")}</strong>
        <StandingChip status={standing.status} />
      </span>
      <Link
        href={adminHref(`/admin/users/${encodeURIComponent(personId)}?tab=finance`, membership.organization.slug)}
        className="rounded-full px-3.5 py-1.5 text-sm font-semibold"
        style={{ border: "1px solid var(--border)", color: "var(--text)", background: "var(--panel)" }}
      >
        {t("staffOpen")}
      </Link>
    </div>
  );
}
