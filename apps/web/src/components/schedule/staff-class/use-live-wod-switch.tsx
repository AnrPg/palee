"use client";

import { useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import {
  fetchClassTimer,
  sendClassTimerCommand,
  type ClassTimerPayload,
} from "@/api/class-timers";
import {
  classWorkouts,
  setClassLiveWorkout,
  type ScheduleSlot,
} from "@/api/schedule";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * ADR-746 (ANR pick 3A): «Κάνε το Τώρα» from the class page. The class timer
 * and every box screen follow «Τώρα», so while the current WOD's clock runs
 * the coach is asked first: stay, switch and pause it (its progress is kept),
 * or switch and let it keep running in the back.
 */
export function useLiveWodSwitch({
  slot,
  accessToken,
  onChanged,
}: {
  slot: ScheduleSlot;
  accessToken: string;
  onChanged?: () => void;
}) {
  const t = useTranslations("ClassWods");
  const i18n = useUiTranslations();
  const [pending, setPending] = useState<{
    workoutId: string;
    running: ClassTimerPayload;
  } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const workouts = classWorkouts(slot);
  const titleOf = (id: string | null | undefined) =>
    workouts.find((workout) => workout.id === id)?.title ?? t("untitled");

  async function save(workoutId: string, pause: ClassTimerPayload | null) {
    setPending(null);
    setBusy(true);
    setError(null);
    try {
      if (pause) {
        await sendClassTimerCommand(
          accessToken,
          slot.id,
          { command: "pause" },
          pause.timer.lock_version,
          pause.workout?.id ?? null,
        );
      }
      await setClassLiveWorkout(accessToken, slot.id, workoutId);
      onChanged?.();
    } catch (reason) {
      setError(localizeError(reason, i18n));
    } finally {
      setBusy(false);
    }
  }

  async function request(workoutId: string) {
    if (busy) return;
    setError(null);
    let current: ClassTimerPayload | null = null;
    try {
      current = await fetchClassTimer(accessToken, slot.id);
    } catch {
      // No timer to ask about (or none reachable): «Τώρα» still moves.
      current = null;
    }
    if (
      current?.timer.status === "running" &&
      current.workout?.id !== workoutId
    ) {
      setPending({ workoutId, running: current });
      return;
    }
    await save(workoutId, null);
  }

  const overlay: ReactNode = pending ? (
    <Dialog
      title={t("switchTitle", { title: titleOf(pending.workoutId) })}
      description={t("switchBody", {
        title: titleOf(pending.running.workout?.id),
      })}
      size="sm"
      testId="class-wod-switch-dialog"
      onClose={() => setPending(null)}
      footer={
        <>
          <DialogButton onClick={() => setPending(null)}>
            {t("switchStay")}
          </DialogButton>
          <DialogButton
            testId="class-wod-switch-keep"
            onClick={() => void save(pending.workoutId, null)}
          >
            {t("switchKeepRunning")}
          </DialogButton>
          <DialogButton
            tone="primary"
            testId="class-wod-switch-confirm"
            onClick={() => void save(pending.workoutId, pending.running)}
          >
            {t("switchAndPause")}
          </DialogButton>
        </>
      }
    >
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {t("switchKeepHint")}
      </p>
    </Dialog>
  ) : null;

  return { request, busy, error, overlay };
}
