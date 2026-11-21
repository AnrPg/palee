"use client";

import { useTranslations } from "next-intl";

import type { ScheduleSlot } from "@/api/schedule";
import type { DayWorkout } from "@/api/day-workouts";
import { useUiTranslations } from "@/i18n/ui";
import { ClassDayWorkoutNote } from "@/components/schedule/ClassDayWorkoutNote";
import { classWorkoutNoticeKind } from "@/components/schedule/ClassWorkoutNotice";
import { resolveWorkoutIcon } from "@/components/workouts/library/library-folders";
import { WorkoutPreviewDetail } from "@/components/workouts/WorkoutPreviewDetail";
import { StaffWodGoalsStrip } from "@/components/wod-goals/WodGoalsStrip";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { MoreMenu, type MoreMenuItem } from "@/components/ui/MoreMenu";
import type { ClassWodLink } from "./use-class-wod-link";

/**
 * The class's WOD on its page (ANR pick A, 2026-11-21): the one Deep hero
 * card of the screen with every section and exercise, where it comes from
 * (the day's WOD or the class's own) and its own ⋯ menu. Without a WOD, a
 * calm card with the most likely WODs one tap away; choosing from the whole
 * library and «+ Νέο WOD» sit in the page's bottom bar.
 */
export function StaffClassWod({
  slot,
  accessToken,
  isPast,
  dayWorkout,
  wod,
  menuItems,
  onChanged,
}: {
  slot: ScheduleSlot;
  accessToken: string;
  isPast: boolean;
  dayWorkout: DayWorkout | null;
  wod: ClassWodLink;
  menuItems: MoreMenuItem[];
  onChanged?: () => void;
}) {
  const t = useTranslations("StaffClass");

  if (!slot.workout) return <EmptyWod slot={slot} wod={wod} menuItems={menuItems} />;

  return (
    <section
      data-surface="deep"
      data-testid="class-wod"
      aria-labelledby={`class-wod-${slot.id}`}
      className="rounded-[1.6rem] p-4 sm:p-5"
      style={{ background: "var(--bg)", color: "var(--text)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <ClassDayWorkoutNote
            slot={slot}
            dayWorkout={dayWorkout}
            accessToken={accessToken}
            isPast={isPast}
            onChanged={onChanged}
          />
          <h3 id={`class-wod-${slot.id}`} className="mt-2 text-xl font-semibold leading-tight">
            {slot.workout.title}
          </h3>
        </div>
        <div data-testid="workout-actions">
          <MoreMenu variant="pill" label={t("wodActions")} testId="workout-more-actions" items={menuItems} />
        </div>
      </div>
      <div className="mt-4">
        <WorkoutPreviewDetail
          sections={slot.workout.sections}
          content={slot.workout.content}
          authoringMode={slot.workout.authoring_mode}
          freeTextBody={slot.workout.free_text_body}
          freeTextDocument={slot.workout.free_text_document}
        />
      </div>
      {/* ADR-670: the class's goals; its atlas adds «Φορτίο προγράμματος». */}
      <StaffWodGoalsStrip workoutId={slot.workout.id} atlas={{ kind: "class", classId: slot.id }} className="mt-4" />
      {wod.error ? <ErrorNotice className="mt-3">{wod.error}</ErrorNotice> : null}
    </section>
  );
}

function EmptyWod({ slot, wod, menuItems }: { slot: ScheduleSlot; wod: ClassWodLink; menuItems: MoreMenuItem[] }) {
  const i18n = useUiTranslations();
  const t = useTranslations("StaffClass");
  const tSchedule = useTranslations("Schedule");
  // ADR-176: only a draft is a problem (members can't see it); a series class
  // without its WOD stays bookable and staff get reminders, so it stays calm.
  const draft = classWorkoutNoticeKind(slot) === "draft";

  return (
    <section
      data-testid={draft ? "class-wod-notice" : "class-wod-add"}
      role={draft ? "status" : undefined}
      aria-busy={wod.busy}
      className="rounded-[1.6rem] p-4 sm:p-5"
      style={{
        background: draft ? "color-mix(in srgb, var(--danger) 8%, var(--panel))" : "var(--panel)",
        border: `2px dashed ${draft ? "var(--danger)" : "var(--border-strong)"}`,
      }}
    >
      <div className="flex items-start justify-between gap-3">
        <h3 className="min-w-0 flex-1 text-lg font-semibold" style={{ color: draft ? "var(--danger)" : "var(--text)" }}>
          {draft ? i18n("classDraftTitle") : t("noWodTitle")}
        </h3>
        {/* «Ξεχωριστό WOD για άτομα» works without a class WOD too (ADR-201). */}
        {menuItems.length > 1 ? (
          <div data-testid="workout-actions">
            <MoreMenu variant="pill" label={t("wodActions")} testId="workout-more-actions" items={menuItems} />
          </div>
        ) : null}
      </div>
      <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }}>
        {draft ? i18n("classDraftBody") : t("noWodBody")}
      </p>
      {wod.quick.length ? (
        <div className="mt-4">
          <p className="text-xs font-semibold" style={{ color: "var(--muted)" }}>
            {wod.quickLabel}
          </p>
          <ul className="mt-2 space-y-2">
            {wod.quick.map((choice) => (
              <li key={choice.id}>
                <button
                  type="button"
                  disabled={wod.busy}
                  aria-label={tSchedule("wodPickerUse", { title: choice.title })}
                  className="flex min-h-12 w-full items-center gap-3 rounded-2xl px-4 py-2.5 text-start disabled:opacity-60"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                  onClick={() => void wod.link(choice.id)}
                >
                  <span aria-hidden="true" className="w-6 shrink-0 text-center text-lg">
                    {resolveWorkoutIcon(choice)}
                  </span>
                  <span className="min-w-0 flex-1 truncate text-sm font-semibold">{choice.title}</span>
                  <span aria-hidden="true" style={{ color: "var(--muted)" }}>
                    ›
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
      {wod.busy ? (
        <p className="mt-3 text-sm" role="status" style={{ color: "var(--muted)" }}>
          {i18n("classLinkWodSaving")}
        </p>
      ) : null}
      {wod.error ? <ErrorNotice className="mt-3">{wod.error}</ErrorNotice> : null}
    </section>
  );
}
