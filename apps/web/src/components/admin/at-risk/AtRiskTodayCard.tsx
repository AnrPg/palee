"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useRouter } from "next/navigation";

import { atRiskKey, fetchMembersAtRisk } from "@/api/leads";
import { CardLink, CountBadge, DashboardCard } from "@/components/admin/DashboardWidgets";
import { useSession } from "@/components/session-provider";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { AtRiskRow } from "./AtRiskRow";
import { contactedThisSpell } from "./risk-model";

/**
 * «Σήμερα» on the staff home (W2 p4, option Γ's card): how many members at
 * risk nobody has reached yet, the first of them, and a link to the list.
 * Nothing shows when there is no one to reach.
 */
export function AtRiskTodayCard() {
  const t = useTranslations("AtRisk");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const slug = useOrganizationSlug();
  const router = useRouter();
  const list = useQuery({
    queryKey: atRiskKey("all"),
    enabled: Boolean(token),
    queryFn: () => fetchMembersAtRisk(token!, "all"),
  });
  const waiting = (list.data?.members ?? []).filter((member) => !contactedThisSpell(member));
  if (waiting.length === 0) return null;
  const href = adminHref("/admin/users/at-risk", slug);

  return (
    <DashboardCard
      id="home-at-risk"
      eyebrow={t("title")}
      title={t("todayTitle", { count: waiting.length })}
      badge={<CountBadge value={waiting.length} tone="primary" />}
      action={<CardLink href={href}>{t("todayAll")}</CardLink>}
    >
      <AtRiskRow member={waiting[0]} compact onOpen={() => router.push(href)} />
    </DashboardCard>
  );
}
