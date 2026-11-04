"use client";

import { type ReactNode, useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import Link from "next/link";

import { WOD_KEY, type CommunityClub, type WodLeaderboardEntry } from "@/api/community";
import { builtInChannel, channelName, clubInitials } from "@/components/community/community";
import { useWodToday } from "@/components/community/use-community";
import { WodLeaderboard } from "@/components/community/WodLeaderboard";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { TrainingLogDialog, type TrainingLogDialogState } from "@/components/training-log/TrainingLog";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatClock } from "@/lib/clock";
import { surfaceRoleForMembership, useOrganizationMemberships } from "@/lib/membership-role";
import { adminHref } from "@/lib/organization-slug";
import { useView } from "@/lib/view-mode";

type WodClass = { id: string; scheduled_at: string };

function byStart(classes: WodClass[]) {
  return [...classes].sort((a, b) => Date.parse(a.scheduled_at) - Date.parse(b.scheduled_at));
}

/**
 * Where a tap on the WOD banner goes (ANR 2026-11-04): the box schedule with
 * the class sheet of today's next class open (it shows the WOD); the last
 * class once all have started; the schedule alone when no class has it.
 * `day` (the gym day of the card) moves the schedule to that day, whatever
 * range or type filter it was left on.
 */
export function wodScheduleHref(slug: string | null, classes: WodClass[], day: string, now: Date) {
  const sorted = byStart(classes);
  const next = sorted.find((entry) => Date.parse(entry.scheduled_at) >= now.getTime()) ?? sorted.at(-1);
  const path = next
    ? `/box/schedule?open_slot=${encodeURIComponent(next.id)}&open_day=${encodeURIComponent(day)}`
    : "/box/schedule";
  return adminHref(path, slug);
}

/**
 * Milliseconds until the banner's destination changes (the next class
 * start), or null when no class is still to start. The card re-renders then,
 * so a feed left open does not keep pointing at a class that has begun.
 */
export function msUntilNextWodClass(classes: WodClass[], now: Date) {
  const next = byStart(classes).find((entry) => Date.parse(entry.scheduled_at) >= now.getTime());
  return next ? Math.max(0, Date.parse(next.scheduled_at) - now.getTime()) + 1 : null;
}

/**
 * Only club members and staff of the box may open its schedule (the page
 * guard); for anyone else in the gym club (e.g. an athlete) the banner stays
 * a plain banner rather than a link that bounces them home.
 */
export function canOpenBoxSchedule(role: "admin" | "member" | "athlete" | null) {
  return role === "admin" || role === "member";
}

// setTimeout takes at most a signed 32-bit delay.
const MAX_TIMEOUT_MS = 2_147_483_647;

/** The current time, refreshed at each class start of the card. */
function useWodNow(classes: WodClass[] | undefined) {
  const [now, setNow] = useState(() => new Date());
  useEffect(() => {
    if (!classes) return;
    const wait = msUntilNextWodClass(classes, now);
    if (wait === null) return;
    const timer = window.setTimeout(() => setNow(new Date()), Math.min(wait, MAX_TIMEOUT_MS));
    return () => window.clearTimeout(timer);
  }, [classes, now]);
  return now;
}

/**
 * The club's #wod-σήμερα card (ADR-138 D6, mockup «lbCard»): today's class
 * WOD, its classes, and the leaderboard of members who opted in, with the
 * member's own row and «Καταχώρησε το σκορ σου» until they log it. Shown
 * only when there is a workout today (ANR 2026-10-24, vision §4.2).
 * For people who opted in, the list takes the ADR-356 filters and the
 * percentile (`WodLeaderboard`, ANR mockup d2 A).
 */
export function WodCard({ club, showOrigin = true }: { club: CommunityClub; showOrigin?: boolean }) {
  const t = useTranslations("Community");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const card = useWodToday(club.organization_slug);
  const [logDialog, setLogDialog] = useState<TrainingLogDialogState>({ mode: "closed" });
  const wod = builtInChannel(club, "wod");
  const time = (iso: string) => formatClock(new Date(iso), locale, { hour: "2-digit", minute: "2-digit" });
  const data = card.data;
  const mine = data?.leaderboard.find((row) => row.me) ?? null;
  const now = useWodNow(data?.classes);
  const view = useView();
  const membershipsQuery = useOrganizationMemberships();
  const memberships = Array.isArray(membershipsQuery.data) ? membershipsQuery.data : [];
  const boxMembership = memberships.find((entry) => entry.organization.slug === club.organization_slug) ?? null;
  const scheduleOpen = canOpenBoxSchedule(boxMembership ? surfaceRoleForMembership(boxMembership, view) : null);

  function closeLog() {
    setLogDialog({ mode: "closed" });
    void queryClient.invalidateQueries({ queryKey: WOD_KEY });
    void queryClient.invalidateQueries({ queryKey: ["training-floor", "leaderboard"] });
  }

  if (!data?.workout) return null;

  return (
    <HubCard eyebrow={showOrigin && wod ? `${club.name} › #${channelName(wod, t)}` : `#${channelName({ kind: "wod" }, t)}`}>
      <div className="flex flex-col gap-3">
        {/* The screen's hero (BRAND.md): the WOD on the deep surface, tagged in
            Spark, with a Dojo edge so Spark and Graphite never stand alone. */}
        <BannerShell href={scheduleOpen ? wodScheduleHref(club.organization_slug ?? null, data.classes, data.date, now) : null}>
          <span
            className="inline-block rounded-full px-2 py-0.5 text-[11px] font-extrabold uppercase tracking-[0.14em]"
            style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}
          >
            #{channelName({ kind: "wod" }, t)}
          </span>
          <h2 className="mt-2 text-xl font-extrabold">{data.workout.title}</h2>
          <p className="text-sm" style={{ opacity: 0.75 }}>
            {[...data.classes.map((entry) => time(entry.scheduled_at)), t("wodScoreCount", { count: data.leaderboard.length })].join(" · ")}
          </p>
        </BannerShell>
        {data.score && club.organization_slug ? (
          <WodLeaderboard
            slug={club.organization_slug}
            workoutId={data.workout.id}
            date={data.date}
            fallback={
              <ol className="flex flex-col gap-1" aria-label={t("wodLeaderboard")}>
                {data.leaderboard.map((row) => (
                  <LeaderboardRow key={row.user_id} row={row} />
                ))}
                {!mine ? (
                  <li className="flex items-center gap-3 rounded-xl px-2 py-1.5" style={{ background: "var(--panel-raised)" }}>
                    <span className="w-5 text-center font-mono text-sm" style={{ color: "var(--dim)" }}>–</span>
                    <b className="grow text-sm" style={{ color: "var(--text)" }}>{t("wodYou")}</b>
                    <span className="text-xs" style={{ color: "var(--dim)" }}>{t("wodNoScore")}</span>
                  </li>
                ) : null}
              </ol>
            }
          />
        ) : null}
        {mine && !mine.opted_in ? (
          <p className="text-xs" style={{ color: "var(--dim)" }}>
            {t("wodOptInHint")}{" "}
            <Link href="/me/sharing" className="font-semibold underline" style={{ color: "var(--primary)" }}>
              {t("wodOptInLink")}
            </Link>
          </p>
        ) : null}
        {!data.logged_by_me && token ? (
          <button
            type="button"
            onClick={() => setLogDialog({ mode: "pick" })}
            className="min-h-11 rounded-2xl text-sm font-semibold"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          >
            {t("wodLogScore")}
          </button>
        ) : null}
      </div>
      {logDialog.mode !== "closed" && token ? (
        <TrainingLogDialog state={logDialog} token={token} onNavigate={setLogDialog} onClose={closeLog} />
      ) : null}
    </HubCard>
  );
}

function BannerShell({ href, children }: { href: string | null; children: ReactNode }) {
  const props = {
    "data-testid": "wod-card-banner",
    className: "block rounded-2xl p-4",
    style: { background: "var(--deep)", color: "var(--deep-contrast)", borderInlineStart: "4px solid var(--primary)" },
  };
  return href ? (
    <Link href={href} {...props}>
      {children}
    </Link>
  ) : (
    <div {...props}>{children}</div>
  );
}

function LeaderboardRow({ row }: { row: WodLeaderboardEntry }) {
  const t = useTranslations("Community");
  const name = row.me ? t("wodYou") : (row.nickname ?? "?");
  const value = [row.value, row.unit].filter(Boolean).join(" ");

  return (
    <li
      className="flex items-center gap-3 rounded-xl px-2 py-1.5"
      style={{ background: row.me ? "var(--panel-raised)" : "transparent" }}
    >
      <span className="w-5 text-center font-mono text-sm font-bold" style={{ color: "var(--dim)" }}>{row.rank}</span>
      {row.avatar_url ? (
        // eslint-disable-next-line @next/next/no-img-element -- user-uploaded media origin
        <img src={row.avatar_url} alt="" className="h-8 w-8 shrink-0 rounded-full object-cover" />
      ) : (
        <span
          aria-hidden="true"
          className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-xs font-extrabold"
          style={{ background: "var(--panel-raised)", color: "var(--text)" }}
        >
          {clubInitials(row.nickname ?? "?")}
        </span>
      )}
      <b className="grow truncate text-sm" style={{ color: "var(--text)" }}>
        {name}
        {row.scale_level_slug ? (
          <span className="ml-1 text-xs font-normal" style={{ color: "var(--dim)" }}>{row.scale_level_slug}</span>
        ) : null}
      </b>
      <span className="font-mono text-sm" style={{ color: "var(--text)" }}>{value}</span>
    </li>
  );
}
