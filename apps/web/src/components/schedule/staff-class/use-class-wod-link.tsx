"use client";

import { useState, type ReactNode } from "react";
import { useLocale, useTranslations } from "next-intl";

import { classWorkouts, linkScheduleSlotWorkout, setClassWorkouts, type ScheduleSlot } from "@/api/schedule";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { ContextualWorkoutCreator } from "@/components/workouts/creation/ContextualWorkoutCreator";
import { WodPickerDialog, useWodSuggestions } from "@/components/schedule/WodPicker";
import { dateTimeLocalInZone, formatInZone } from "@/lib/zoned-time";

/**
 * Everything that puts a WOD on a class from its page (ADR-176): one tap on a
 * suggestion, the picker over the whole library, or «+ Νέο WOD» in the
 * editor, linked as soon as it is published. The page's empty WOD card, its
 * bottom bar and the WOD's ⋯ «Αλλαγή WOD» share this one state, so the
 * picker and the editor open once whoever asked.
 *
 * ADR-746: a class may hold several WODs. «+ WOD» adds one at the end, «Αλλαγή
 * WOD» replaces the one being viewed, and the WOD's ⋯ moves or removes it;
 * every change sends the whole ordered list, so two coaches never interleave.
 */
export function useClassWodLink({
  slot,
  accessToken,
  timeZone,
  onLinked,
}: {
  slot: ScheduleSlot;
  accessToken: string;
  timeZone: string | null;
  onLinked?: () => void;
}) {
  const i18n = useUiTranslations();
  const t = useTranslations("Schedule");
  const locale = useLocale();
  const [picking, setPicking] = useState(false);
  // ADR-746: what the next picked WOD does: replace the WOD at an index, or
  // join the list at the end («+ WOD»).
  const [target, setTarget] = useState<{ kind: "replace"; index: number } | { kind: "add" }>({
    kind: "replace",
    index: 0,
  });
  const ids = classWorkouts(slot).map((workout) => workout.id);
  const [creating, setCreating] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const date = dateTimeLocalInZone(slot.scheduled_at, timeZone).slice(0, 10) || null;
  const suggestions = useWodSuggestions(accessToken, date, slot.class_type_id);

  async function run(action: () => Promise<unknown>) {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      await action();
      onLinked?.();
    } catch (reason) {
      setError(localizeError(reason, i18n));
    } finally {
      setBusy(false);
    }
  }

  // The whole ordered list goes back; the first WOD alone keeps the
  // ADR-176 link (it also publishes a draft class).
  function saveList(next: string[]) {
    return run(() =>
      next.length === 1 && ids.length <= 1
        ? linkScheduleSlotWorkout(accessToken, slot.id, next[0]!)
        : setClassWorkouts(accessToken, slot.id, next),
    );
  }

  async function link(workoutId: string | null) {
    if (!workoutId || busy) return;
    if (target.kind === "add") {
      if (ids.includes(workoutId)) return;
      await saveList([...ids, workoutId]);
      return;
    }
    const next = ids.length ? ids.map((id, index) => (index === target.index ? workoutId : id)) : [workoutId];
    await saveList(next.filter((id, index) => next.indexOf(id) === index));
  }

  /** ADR-746: removes one WOD of the class (its people go back to «Θα αποφασίσω στο box»). */
  function remove(workoutId: string) {
    return saveList(ids.filter((id) => id !== workoutId));
  }

  /** ADR-746: moves one WOD a place earlier (-1) or later (+1). */
  function move(workoutId: string, step: -1 | 1) {
    const from = ids.indexOf(workoutId);
    const to = from + step;
    if (from < 0 || to < 0 || to >= ids.length) return Promise.resolve();
    const next = [...ids];
    [next[from], next[to]] = [next[to]!, next[from]!];
    return saveList(next);
  }

  // Only the WOD another class runs the same day (ANR, 2026-11-21: WODs are
  // almost never reused on another day, so recent ones are not offered here).
  const sameDay = suggestions.data?.same_day ?? [];
  const quick = sameDay.slice(0, 3);

  const overlays: ReactNode = (
    <>
      {picking ? (
        <WodPickerDialog
          label={i18n("classLinkWodLabel")}
          token={accessToken}
          value={target.kind === "replace" ? (ids[target.index] ?? null) : null}
          date={date}
          suggestions={suggestions.data}
          suggestionsLoading={suggestions.isLoading}
          onChoose={(choice) => {
            setPicking(false);
            void link(choice?.id ?? null);
          }}
          onCreateNew={() => {
            setPicking(false);
            setCreating(true);
          }}
          onClose={() => setPicking(false)}
        />
      ) : null}
      {creating ? (
        <ContextualWorkoutCreator
          target={[slot.class_type?.name ?? slot.name, formatInZone(slot.scheduled_at, timeZone, locale, "day-time")]
            .filter(Boolean)
            .join(" · ")}
          onPublished={link}
          onClose={() => setCreating(false)}
        />
      ) : null}
    </>
  );

  return {
    link,
    busy,
    error,
    quick,
    sameDay: sameDay.length > 0,
    quickLabel: t("wodPickerQuickSameDay"),
    openPicker: (index = 0) => {
      setTarget({ kind: "replace", index });
      setPicking(true);
    },
    /** ADR-746: «+ WOD». */
    openAdd: () => {
      setTarget({ kind: "add" });
      setPicking(true);
    },
    openCreator: () => {
      setTarget({ kind: "replace", index: 0 });
      setCreating(true);
    },
    remove,
    move,
    overlays,
  };
}

export type ClassWodLink = ReturnType<typeof useClassWodLink>;
