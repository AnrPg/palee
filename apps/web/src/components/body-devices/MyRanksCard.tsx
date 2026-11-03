"use client";

import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { fetchMyDiploma, fetchMyRanks, myRanksKey, type RankStanding } from "@/api/body-devices";
import { saveFile } from "@/components/admin/coach-pay/pay-ui";
import { Belt } from "@/components/body-devices/Belt";
import { ProgressLines } from "@/components/body-devices/ClientRanks";
import { formatRankDate } from "@/components/body-devices/rank-dates";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

/**
 * «Ο βαθμός μου» on the Box tab, under the membership (ADR-377, mockup
 * e2member A): the rank is the box's (it gave it), so its home is the Box
 * (vision §4.1), not the Journal or the profile (no comparison, §4.4). The
 * belt, what is missing for the next one, the history and the diploma PDF.
 * Nothing shows at a box without ladders.
 */
export function MyRanksCard({ slug }: { slug: string }) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const ranks = useQuery({ queryKey: myRanksKey(slug), enabled: Boolean(token), queryFn: () => fetchMyRanks(token!, slug), retry: false });
  const standings = (ranks.data?.ladders ?? []).filter((standing) => standing.current || standing.history.length > 0);
  if (standings.length === 0) return null;
  return (
    <>
      {standings.map((standing) => (
        <StandingCard key={standing.ladder.id} token={token!} slug={slug} standing={standing} />
      ))}
    </>
  );
}

function StandingCard({ token, slug, standing }: { token: string; slug: string; standing: RankStanding }) {
  const t = useTranslations("BodyDevices");
  const locale = useLocale();
  const [history, setHistory] = useState(false);
  const current = standing.current;
  const diploma = useMutation({
    mutationFn: (awardId: string) => fetchMyDiploma(token, slug, awardId),
    onSuccess: (blob, awardId) => saveFile(blob, `${awardId}.pdf`),
  });
  const awards = standing.history.filter((award) => !award.revoked);

  return (
    <HubCard eyebrow={standing.ladder.name}>
      <div className="flex flex-col gap-2" data-testid="my-ranks">
        {current ? (
          <>
            <div className="flex items-center justify-between gap-3">
              <Belt color={current.rank.color} stripes={current.stripes} label={current.rank.name} />
              <button type="button" onClick={() => diploma.mutate(current.award_id)} className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
                {t("ranks.diploma")}
              </button>
            </div>
            <p className="text-sm" style={{ color: "var(--text)" }}>
              {t("ranks.currentLine", { rank: current.rank.name, stripes: current.stripes })} · {t("ranks.since", { date: formatRankDate(current.awarded_on, locale) })}
            </p>
          </>
        ) : null}
        {standing.next ? (
          <div className="flex flex-col gap-0.5">
            <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("ranks.towards", { rank: standing.next.name })}</p>
            <ProgressLines standing={standing} />
          </div>
        ) : null}
        {awards.length > 0 ? (
          <button type="button" aria-expanded={history} onClick={() => setHistory(!history)} className="self-start text-sm font-semibold" style={{ color: "var(--dim)" }}>
            {t("ranks.history")}
          </button>
        ) : null}
        {history ? (
          <ul className="flex flex-col gap-1 text-sm" style={{ color: "var(--text-soft)" }}>
            {awards.map((award) => (
              <li key={award.id} className="flex items-center gap-2">
                <Belt color={award.color} stripes={award.stripes} className="h-2.5 w-10" />
                <span>
                  {award.stripes > 0 ? t("ranks.historyStripe", { rank: award.rank_name ?? "", stripes: award.stripes }) : award.rank_name ?? ""} ·{" "}
                  {formatRankDate(award.awarded_on, locale)}
                </span>
              </li>
            ))}
          </ul>
        ) : null}
        {diploma.isError ? <ErrorNotice>{t("errorGeneric")}</ErrorNotice> : null}
      </div>
    </HubCard>
  );
}
