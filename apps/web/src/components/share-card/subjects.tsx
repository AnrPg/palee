"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import type { ChallengeRecord } from "@/api/landing";
import { fetchWodToday } from "@/api/community";
import { fetchExecution, type WorkoutExecution } from "@/api/executions";
import type { PRRecord } from "@/api/gamification";
import { gymClubFor } from "@/components/community/community";
import { useMyClubs } from "@/components/community/use-community";
import { formatScore as formatPrScore } from "@/components/pantheon/PantheonCard";
import { useSession } from "@/components/session-provider";
import { formatScore } from "@/i18n/presentation";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { exercisesLine, leaderboardPlace, type CardExercise } from "@/lib/share-card";

import type { CardContent } from "./ShareCardPanel";

/** «9 Νοε 2026» in the member's language. */
export function cardDate(iso: string | null | undefined, locale: string): string {
  const at = iso ? new Date(iso) : new Date();
  return new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", year: "numeric" }).format(at);
}

/** The local calendar date (YYYY-MM-DD) of an instant in a time zone. */
export function localDate(iso: string, timeZone: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date(iso));
}

function exercisesOf(execution: WorkoutExecution): CardExercise[] {
  return (execution.workout?.sections ?? []).flatMap((section) => section.exercises ?? []);
}

/**
 * A finished WOD's card: the WOD, the first score, exercises and loads, the
 * box, and the member's place on that day's box leaderboard when the WOD is
 * the box's WOD of the day and they show on leaderboards.
 */
export function useWodCardContent(executionId: string): { content: CardContent | null; execution: WorkoutExecution | null } {
  const t = useTranslations("ShareCard");
  const tUi = useTranslations("Ui");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const execution = useQuery({
    queryKey: ["execution", executionId],
    enabled: Boolean(token),
    queryFn: () => fetchExecution(token!, executionId),
  });
  const clubs = useMyClubs();
  const club = gymClubFor(clubs.data ?? [], null);
  const slug = club?.organization_slug ?? null;
  const data = execution.data;
  const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const day = data?.completed_at_utc ? localDate(data.completed_at_utc, timeZone) : undefined;
  const wod = useQuery({
    queryKey: ["community", "wod-today", slug, day, "share"],
    enabled: Boolean(token && slug && data?.master_workout_id),
    queryFn: () => fetchWodToday(token!, slug!, timeZone, day),
    staleTime: 60_000,
  });
  if (!data) return { content: null, execution: null };

  const box = club?.name ?? null;
  const first = data.section_scores[0];
  const sameWod = Boolean(wod.data?.workout?.id && wod.data.workout.id === data.master_workout_id);
  const place = sameWod ? leaderboardPlace(wod.data?.leaderboard ?? []) : null;
  return {
    execution: data,
    content: {
      eyebrow: box ? t("eyebrowWod", { box }) : t("eyebrowWodAlone"),
      title: data.workout_title ?? data.workout?.title ?? t("workout"),
      score: first ? formatScore(first.value, first.score_type, first.unit, tUi) : null,
      detail: exercisesLine(exercisesOf(data)),
      badge: null,
      place: place && box ? t("place", { rank: place.rank, total: place.total, box }) : null,
      date: cardDate(data.completed_at_utc, locale),
    },
  };
}

/** A new PR's card. */
export function usePrCardContent(pr: PRRecord): CardContent {
  const t = useTranslations("ShareCard");
  const locale = useUiLocale();
  const clubs = useMyClubs();
  const box = pr.organization_id ? (gymClubFor(clubs.data ?? [], pr.organization_id)?.name ?? null) : null;
  return {
    eyebrow: box ? t("eyebrowPrAt", { box }) : t("eyebrowPr"),
    title: pr.name,
    score: formatPrScore(Number(pr.current_score), pr.unit),
    detail: null,
    badge: t("prBadge"),
    place: null,
    date: cardDate(pr.beaten_on, locale),
  };
}

/** A finished challenge's card. */
export function useChallengeCardContent(challenge: ChallengeRecord): CardContent {
  const t = useTranslations("ShareCard");
  const locale = useUiLocale();
  return {
    eyebrow: t("eyebrowChallenge"),
    title: challenge.title,
    score: `${challenge.progress}/${challenge.target}`,
    detail: challenge.badge_label || null,
    badge: t("challengeDone"),
    place: null,
    date: cardDate(challenge.completed_at, locale),
  };
}
