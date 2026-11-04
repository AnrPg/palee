"use client";

import { useTranslations } from "next-intl";

import { MyRanksDetail, useMyRanks } from "@/components/body-devices/MyRanksCard";
import { ClientPage, LoadingLine } from "@/components/client/ClientPage";
import { useOrganizationSlug } from "@/lib/organization-slug";

/** `/me/ranks`: «Η πρόοδός μου» on the box's ladders (opened from the line on the profile). */
export function MyRanksPage() {
  const t = useTranslations("BodyDevices");
  const slug = useOrganizationSlug();
  const { token, standings, query } = useMyRanks(slug);
  return (
    <ClientPage title={t("ranks.my.title")}>
      {query.isPending && token ? <LoadingLine /> : null}
      {token && slug && standings.length > 0 ? <MyRanksDetail token={token} slug={slug} standings={standings} /> : null}
      {!query.isPending && standings.length === 0 ? (
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("ranks.noRankYet")}</p>
      ) : null}
    </ClientPage>
  );
}
