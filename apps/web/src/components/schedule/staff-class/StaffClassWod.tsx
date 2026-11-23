"use client";

import { useTranslations } from "next-intl";

import type { ScheduleSlot, WorkoutPreview } from "@/api/schedule";
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
 *
 * ADR-746 (ANR picks 2A, 5A): a class may hold several WODs. A row of chips
 * above the hero picks which one it shows, «ΤΩΡΑ» marks the one the class
 * timer and the box screens follow, and «+ WOD» adds one (with a single WOD
 * only «+» shows, so the screen stays as calm as before).
 */
export function StaffClassWod({
  slot,
  accessToken,
  isPast,
  dayWorkout,
  wod,
  menuItems,
  onChanged,
  workout,
  workouts,
  liveId,
  onView,
}: {
  slot: ScheduleSlot;
  accessToken: string;
  isPast: boolean;
  dayWorkout: DayWorkout | null;
  wod: ClassWodLink;
  menuItems: MoreMenuItem[];
  onChanged?: () => void;
  /** ADR-746: the WOD the hero shows (one of `workouts`). */
  workout: WorkoutPreview | null;
  workouts: WorkoutPreview[];
  liveId: string | null;
  onView: (workoutId: string) => void;
}) {
  const t = useTranslations("StaffClass");

  if (!workout) return <EmptyWod slot={slot} wod={wod} menuItems={menuItems} />;

  return (
    <section
      data-surface="deep"
      data-testid="class-wod"
      aria-labelledby={`class-wod-${slot.id}`}
      className="rounded-[1.6rem] p-4 sm:p-5"
      style={{ background: "var(--bg)", color: "var(--text)", border: "1px solid var(--border)" }}
    >
      <ClassWodChips
        workouts={workouts}
        viewedId={workout.id}
        liveId={liveId}
        onView={onView}
        onAdd={wod.openAdd}
        busy={wod.busy}
      />
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
            {workout.title}
          </h3>
        </div>
        <div data-testid="workout-actions">
          <MoreMenu variant="pill" label={t("wodActions")} testId="workout-more-actions" items={menuItems} />
        </div>
      </div>
      <div className="mt-4">
        <WorkoutPreviewDetail
          sections={workout.sections}
          content={workout.content}
          authoringMode={workout.authoring_mode}
          freeTextBody={workout.free_text_body}
          freeTextDocument={workout.free_text_document}
        />
      </div>
      {/* ADR-670: the class's goals; its atlas adds «Φορτίο προγράμματος». */}
      <StaffWodGoalsStrip workoutId={workout.id} atlas={{ kind: "class", classId: slot.id }} className="mt-4" />
      {wod.error ? <ErrorNotice className="mt-3">{wod.error}</ErrorNotice> : null}
    </section>
  );
}

/**
 * ADR-746: one chip per WOD of the class, «ΤΩΡΑ» on the one the timer and
 * screens follow, then «+ WOD». With a single WOD only a small «+» shows.
 */
function ClassWodChips({
  workouts,
  viewedId,
  liveId,
  onView,
  onAdd,
  busy,
}: {
  workouts: WorkoutPreview[];
  viewedId: string;
  liveId: string | null;
  onView: (workoutId: string) => void;
  onAdd: () => void;
  busy: boolean;
}) {
  const t = useTranslations("ClassWods");
  const several = workouts.length > 1;
  const chip = "flex min-h-9 shrink-0 items-center gap-1.5 rounded-full px-3.5 text-sm font-semibold disabled:opacity-60";

  return (
    <div
      role="group"
      aria-label={t("classWodsLabel")}
      data-testid="class-wod-chips"
      className={several ? "-mx-1 mb-3 flex gap-2 overflow-x-auto px-1 pb-1" : "mb-2 flex justify-end"}
    >
      {several
        ? workouts.map((item) => {
            const viewed = item.id === viewedId;
            return (
              <button
                key={item.id}
                type="button"
                aria-pressed={viewed}
                data-testid="class-wod-chip"
                className={chip}
                style={
                  viewed
                    ? { background: "var(--text)", color: "var(--bg)" }
                    : { border: "1px solid var(--border)", color: "var(--text-soft)" }
                }
                onClick={() => onView(item.id)}
              >
                <span className="max-w-[11rem] truncate">{item.title}</span>
                {item.id === liveId ? (
                  <span
                    data-testid="class-wod-live"
                    className="rounded-full px-1.5 text-[0.65rem] font-black uppercase"
                    style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                  >
                    {t("now")}
                  </span>
                ) : null}
              </button>
            );
          })
        : null}
      <button
        type="button"
        disabled={busy}
        data-testid="class-wod-add-more"
        aria-label={t("addWod")}
        className={chip}
        style={{ border: "1px dashed var(--border-strong)", color: "var(--text-soft)" }}
        onClick={onAdd}
      >
        {several ? t("addWodChip") : "+"}
      </button>
    </div>
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
