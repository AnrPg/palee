"use client";

import { useState, type ReactNode } from "react";
import { useLocale, useTranslations } from "next-intl";

import { linkScheduleSlotWorkout, type ScheduleSlot } from "@/api/schedule";
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
  const [creating, setCreating] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const date = dateTimeLocalInZone(slot.scheduled_at, timeZone).slice(0, 10) || null;
  const suggestions = useWodSuggestions(accessToken, date, slot.class_type_id);

  async function link(workoutId: string | null) {
    if (!workoutId || busy) return;
    setBusy(true);
    setError(null);
    try {
      await linkScheduleSlotWorkout(accessToken, slot.id, workoutId);
      onLinked?.();
    } catch (reason) {
      setError(localizeError(reason, i18n));
    } finally {
      setBusy(false);
    }
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
          value={slot.master_workout_id}
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
    openPicker: () => setPicking(true),
    openCreator: () => setCreating(true),
    overlays,
  };
}

export type ClassWodLink = ReturnType<typeof useClassWodLink>;
