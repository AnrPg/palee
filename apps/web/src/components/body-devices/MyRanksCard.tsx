"use client";

import Link from "next/link";
import { useState } from "react";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { fetchMyDiploma, fetchMyRanks, myRanksKey, type RankStanding } from "@/api/body-devices";
import { saveFile } from "@/components/admin/coach-pay/pay-ui";
import { Belt } from "@/components/body-devices/Belt";
import { NextRankCard, SkillWithExtras } from "@/components/body-devices/NextRankCard";
import { formatRankDate } from "@/components/body-devices/rank-dates";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { rankSkills, skillTicks } from "@/lib/body-devices";

/**
 * Where «Η πρόοδός μου» opens from the Box line: its own page (the product
 * owner's pick, pending confirmation) or an overlay on Box. One switch.
 */
export const MY_RANKS_OPENS_AS: "page" | "overlay" = "page";
export const MY_RANKS_HREF = "/me/ranks";

/** The standings the person has something on: a rank, or a history. */
export function myStandings(ladders: RankStanding[] | undefined): RankStanding[] {
  return (ladders ?? []).filter((standing) => standing && standing.ladder && (standing.current || (Array.isArray(standing.history) && standing.history.length > 0)));
}

export function useMyRanks(slug: string | null | undefined) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const ranks = useQuery({ queryKey: myRanksKey(slug ?? ""), enabled: Boolean(token && slug), queryFn: () => fetchMyRanks(token!, slug!), retry: false });
  return { token, standings: myStandings(ranks.data?.ladders), query: ranks };
}

/**
 * «Ο βαθμός μου» on the Box tab, under the membership (ADR-377, mockup «Η
 * πρόοδός μου», option Γ as the line): one calm line per ladder, «Μπλε ·
 * Προς Μωβ: 3 από 5 δεξιότητες ›», which opens the progress (option Α).
 * It sits on the profile (Εγώ), as ANR asked; no comparison (§4.4).
 * Nothing shows at a box without ladders.
 */
export function MyRanksCard({ slug }: { slug: string }) {
  const t = useTranslations("BodyDevices");
  const { token, standings } = useMyRanks(slug);
  const [overlay, setOverlay] = useState(false);
  if (!token || standings.length === 0) return null;
  const rows = standings.map((standing) => <RankLine key={standing.ladder.id} standing={standing} />);
  return (
    <HubCard eyebrow={t("ranks.my.title")}>
      <div className="flex flex-col" data-testid="my-ranks">
        {MY_RANKS_OPENS_AS === "page" ? (
          <Link href={MY_RANKS_HREF} className="flex flex-col" data-testid="my-ranks-open">
            {rows}
          </Link>
        ) : (
          <button type="button" onClick={() => setOverlay(true)} className="flex flex-col text-start" data-testid="my-ranks-open">
            {rows}
          </button>
        )}
      </div>
      {overlay ? (
        <Dialog onClose={() => setOverlay(false)} title={t("ranks.my.title")} titleId="my-ranks-overlay" variant="sheet" size="lg">
          <MyRanksDetail token={token} slug={slug} standings={standings} />
        </Dialog>
      ) : null}
    </HubCard>
  );
}

function RankLine({ standing }: { standing: RankStanding }) {
  const t = useTranslations("BodyDevices");
  const ticks = skillTicks(standing);
  const current = standing.current;
  const next = standing.next;
  const towards = next
    ? ticks.length > 0
      ? t("ranks.my.towardsSkills", { rank: next.name, done: ticks.filter((tick) => tick.checked).length, total: ticks.length })
      : t("ranks.my.towards", { rank: next.name })
    : null;
  return (
    <span className="flex min-h-12 items-center gap-3 py-1.5">
      {current ? <Belt color={current.rank.color} stripes={current.stripes} className="h-3 w-12" /> : null}
      <span className="flex min-w-0 flex-1 flex-col">
        <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
          {current ? current.rank.name : standing.ladder.name}
          {towards ? <span className="font-normal" style={{ color: "var(--text-soft)" }}> · {towards}</span> : null}
        </span>
      </span>
      <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
    </span>
  );
}

/**
 * The progress itself (option Α plus the browsing the product owner asked
 * for): per ladder the «Επόμενος βαθμός» card on top, then the path of
 * levels with their skills, then the diplomas.
 */
export function MyRanksDetail({ token, slug, standings }: { token: string; slug: string; standings: RankStanding[] }) {
  return (
    <div className="flex flex-col gap-6" data-testid="my-ranks-detail">
      {standings.map((standing) => (
        <section key={standing.ladder.id} className="flex flex-col gap-3" aria-label={standing.ladder.name}>
          {standings.length > 1 ? (
            <h2 className="text-base font-bold" style={{ color: "var(--text)" }}>{standing.ladder.name}</h2>
          ) : null}
          {standing.next ? <NextRankCard standing={standing} /> : null}
          <LadderPath standing={standing} />
          <Diplomas token={token} slug={slug} standing={standing} />
        </section>
      ))}
    </div>
  );
}

/** Every rank of the ladder in order, the person's own marked, each with its skills to open. */
function LadderPath({ standing }: { standing: RankStanding }) {
  const t = useTranslations("BodyDevices");
  const [open, setOpen] = useState<string | null>(null);
  const ranks = Array.isArray(standing.ladder.ranks) ? standing.ladder.ranks : [];
  const currentPosition = standing.current?.rank.position ?? -1;
  if (ranks.length === 0) return null;
  return (
    <HubCard eyebrow={t("ranks.my.path")}>
      <ol className="flex flex-col" data-testid="my-ranks-path">
        {ranks.map((rank, index) => {
          const skills = rankSkills(rank);
          const state = rank.position < currentPosition ? "done" : rank.position === currentPosition ? "current" : rank.id === standing.next?.id ? "next" : "later";
          const expanded = open === rank.id;
          return (
            <li key={rank.id} style={index === 0 ? undefined : { borderTop: "1px solid var(--border)" }}>
              <button
                type="button"
                aria-expanded={skills.length > 0 ? expanded : undefined}
                disabled={skills.length === 0}
                onClick={() => setOpen(expanded ? null : rank.id)}
                className="flex min-h-12 w-full items-center gap-3 py-2 text-start"
              >
                {standing.ladder.style === "belt" ? <Belt color={rank.color} className="h-2.5 w-10" /> : null}
                <span className="flex min-w-0 flex-1 flex-col">
                  <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{rank.name}</span>
                  <span className="text-xs" style={{ color: "var(--dim)" }}>
                    {[state === "current" ? t("ranks.my.now") : state === "next" ? t("ranks.my.next") : null, skills.length ? t("ranks.picker.skillsCount", { count: skills.length }) : null]
                      .filter(Boolean)
                      .join(" · ")}
                  </span>
                </span>
                {skills.length > 0 ? <span aria-hidden="true" style={{ color: "var(--dim)" }}>{expanded ? "⌄" : "›"}</span> : null}
              </button>
              {expanded ? (
                <ul className="flex flex-col gap-2 pb-3 ps-2">
                  {skills.map((skill) => (
                    <li key={skill.id ?? skill.name}>
                      <SkillWithExtras name={skill.name} note={skill.note} video={skill.video} />
                    </li>
                  ))}
                </ul>
              ) : null}
            </li>
          );
        })}
      </ol>
    </HubCard>
  );
}

function Diplomas({ token, slug, standing }: { token: string; slug: string; standing: RankStanding }) {
  const t = useTranslations("BodyDevices");
  const locale = useLocale();
  const diploma = useMutation({
    mutationFn: (awardId: string) => fetchMyDiploma(token, slug, awardId),
    onSuccess: (blob, awardId) => saveFile(blob, `${awardId}.pdf`),
  });
  const awards = (Array.isArray(standing.history) ? standing.history : []).filter((award) => award && !award.revoked);
  if (awards.length === 0) return null;
  return (
    <HubCard eyebrow={t("ranks.my.diplomas")}>
      <ul className="flex flex-col" data-testid="my-ranks-diplomas">
        {awards.map((award, index) => (
          <li key={award.id} className="flex min-h-12 items-center gap-3 py-1.5" style={index === 0 ? undefined : { borderTop: "1px solid var(--border)" }}>
            <Belt color={award.color} stripes={award.stripes} className="h-2.5 w-10" />
            <span className="min-w-0 flex-1 truncate text-sm" style={{ color: "var(--text)" }}>
              {award.stripes > 0 ? t("ranks.historyStripe", { rank: award.rank_name ?? "", stripes: award.stripes }) : (award.rank_name ?? "")} ·{" "}
              {formatRankDate(award.awarded_on, locale)}
            </span>
            <button type="button" onClick={() => diploma.mutate(award.id)} className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
              {t("ranks.diploma")}
            </button>
          </li>
        ))}
      </ul>
      {diploma.isError ? <ErrorNotice variant="field">{t("errorGeneric")}</ErrorNotice> : null}
    </HubCard>
  );
}
