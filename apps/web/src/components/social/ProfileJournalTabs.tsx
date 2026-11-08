"use client";

import type { ReactNode } from "react";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchPersonProgress, fetchPersonWorkouts, personKey, type PersonProfile } from "@/api/social";
import { useSession } from "@/components/session-provider";
import { LockedNote } from "@/components/social/SocialBits";
import { postsLockKey } from "@/components/social/social-model";
import { formatDurationMs } from "@/components/workouts/execution/progress";
import { useUiLocale } from "@/i18n/use-ui-locale";

/**
 * ADR-554 (amended): «Προπονήσεις», the latest completed workouts (title,
 * day, duration; never notes or scores, never one kept «Μόνο εγώ»), and
 * «Πρόοδος», the totals. The owner and their followers see them while the
 * owner shows the tab; the API decides, `locked` says why someone doesn't.
 */
export function ProfileWorkouts({ profile }: { profile: PersonProfile }) {
  const t = useTranslations("Social");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const workouts = useQuery({
    queryKey: [...personKey(profile.id), "workouts"],
    enabled: Boolean(token),
    queryFn: () => fetchPersonWorkouts(token!, profile.id),
  });

  if (workouts.isPending) return <Loading />;
  const lock = postsLockKey(profile);
  if (workouts.data?.locked && lock) return <Locked textKey={lock} />;
  const list = workouts.data?.workouts ?? [];
  if (list.length === 0) return <Empty>{profile.is_me ? t("myWorkoutsNone") : t("workoutsNone")}</Empty>;

  return (
    <ul className="flex flex-col gap-2 px-4" data-testid="profile-workouts">
      {list.map((workout) => {
        const day = new Date(workout.completed_at).toLocaleDateString(locale, {
          weekday: "short",
          day: "numeric",
          month: "short",
          timeZone: workout.completed_tz ?? undefined,
        });
        return (
          <li
            key={workout.id}
            className="flex flex-col gap-0.5 rounded-2xl px-4 py-3"
            style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
          >
            <span className="break-words text-sm font-bold" style={{ color: "var(--text)" }}>{workout.title ?? t("workoutUntitled")}</span>
            <span className="text-xs tabular-nums" style={{ color: "var(--dim)" }}>
              {workout.elapsed_ms > 0 ? t("workoutLine", { day, duration: formatDurationMs(workout.elapsed_ms) }) : day}
            </span>
          </li>
        );
      })}
    </ul>
  );
}

const PROGRESS_KEYS = [
  ["total_workouts", "totalWorkouts"],
  ["current_streak", "currentStreak"],
  ["longest_streak", "longestStreak"],
  ["total_prs", "totalPrs"],
] as const;

export function ProfileProgress({ profile }: { profile: PersonProfile }) {
  const t = useTranslations("Social");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const progress = useQuery({
    queryKey: [...personKey(profile.id), "progress"],
    enabled: Boolean(token),
    queryFn: () => fetchPersonProgress(token!, profile.id),
  });

  if (progress.isPending) return <Loading />;
  const lock = postsLockKey(profile);
  if (progress.data?.locked && lock) return <Locked textKey={lock} />;
  const totals = progress.data?.progress;
  if (!totals) return <Empty>{profile.is_me ? t("myProgressNone") : t("progressNone")}</Empty>;

  return (
    <ul className="grid grid-cols-2 gap-2 px-4" data-testid="profile-progress">
      {PROGRESS_KEYS.map(([field, key]) => (
        <li key={key} className="flex flex-col rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <span className="text-2xl font-extrabold tabular-nums" style={{ color: "var(--text)" }}>{totals[field]}</span>
          <span className="text-xs" style={{ color: "var(--dim)" }}>{t(`progressStat.${key}`, { count: totals[field] })}</span>
        </li>
      ))}
    </ul>
  );
}

function Loading() {
  const t = useTranslations("Social");
  return <p className="px-4" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
}

function Locked({ textKey }: { textKey: NonNullable<ReturnType<typeof postsLockKey>> }) {
  return (
    <div className="px-4">
      <LockedNote textKey={textKey} />
    </div>
  );
}

function Empty({ children }: { children: ReactNode }) {
  return (
    <p className="mx-4 rounded-3xl p-5 text-sm" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
      {children}
    </p>
  );
}
