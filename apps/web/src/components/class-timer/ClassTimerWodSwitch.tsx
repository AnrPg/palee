"use client";

import { useState } from "react";
import { useTranslations } from "next-intl";

import type { ClassTimerPayload } from "@/api/class-timers";
import { setClassLiveWorkout } from "@/api/schedule";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

/**
 * ADR-746 (ANR picks 1A, 3A, 2026-11-22): the class's WODs on the coach's
 * remote, one chip each, «ΤΩΡΑ» on the one every screen follows. Moving «Τώρα»
 * while the clock runs asks first: stay, switch and pause the running clock
 * (the default; its progress is kept), or switch and let it keep running in
 * the back, shown in a small bar with the way back.
 */
export function ClassTimerWodSwitch({
  payload,
  token,
  slotId,
  running,
  onPause,
}: {
  payload: ClassTimerPayload;
  token: string | null | undefined;
  slotId: string;
  running: boolean;
  onPause: () => Promise<boolean>;
}) {
  const t = useTranslations("ClassWods");
  const i18n = useUiTranslations();
  const [pending, setPending] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const workouts = payload.workouts ?? [];
  const live = payload.live_workout_id ?? payload.workout?.id ?? null;
  const titleOf = (id: string | null) =>
    workouts.find((workout) => workout.id === id)?.title ?? t("untitled");
  const runningBehind = (payload.other_timers ?? []).filter(
    (other) =>
      other.status === "running" &&
      other.workout_id &&
      other.workout_id !== live,
  );

  if (workouts.length < 2 || !token) return null;

  async function moveTo(workoutId: string, pauseFirst: boolean) {
    if (!token) return;
    setPending(null);
    setBusy(true);
    setError(null);
    try {
      if (pauseFirst) await onPause();
      await setClassLiveWorkout(token, slotId, workoutId);
    } catch (reason) {
      setError(localizeError(reason, i18n));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section
      aria-label={t("classWodsLabel")}
      className="space-y-2"
      data-testid="remote-wods"
    >
      <div
        role="group"
        aria-label={t("classWodsLabel")}
        className="flex flex-wrap gap-2"
      >
        {workouts.map((workout) => {
          const isLive = workout.id === live;
          return (
            <button
              key={workout.id}
              type="button"
              aria-pressed={isLive}
              disabled={busy}
              data-testid="remote-wod-chip"
              className="flex min-h-10 items-center gap-2 rounded-full px-4 text-sm font-semibold disabled:opacity-60"
              style={
                isLive
                  ? {
                      background: "var(--primary)",
                      color: "var(--primary-contrast)",
                    }
                  : {
                      border: "1px solid var(--border)",
                      color: "var(--text-soft)",
                    }
              }
              onClick={() => {
                if (isLive) return;
                if (running) setPending(workout.id);
                else void moveTo(workout.id, false);
              }}
            >
              <span className="max-w-[12rem] truncate">
                {workout.title ?? t("untitled")}
              </span>
              {isLive ? (
                <span
                  className="rounded-full px-1.5 text-[0.65rem] font-black uppercase"
                  style={{
                    background: "var(--primary-contrast)",
                    color: "var(--primary)",
                  }}
                >
                  {t("now")}
                </span>
              ) : null}
            </button>
          );
        })}
      </div>
      {runningBehind.map((other) => (
        <div
          key={other.workout_id}
          role="status"
          data-testid="remote-wod-running-behind"
          className="flex items-center justify-between gap-3 rounded-2xl px-4 py-2 text-sm"
          style={{ background: "var(--panel-muted)", color: "var(--text)" }}
        >
          <span className="min-w-0 truncate">
            {t("stillRunning", { title: titleOf(other.workout_id) })}
          </span>
          <button
            type="button"
            disabled={busy}
            className="shrink-0 rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-60"
            style={{
              border: "1px solid var(--border-strong)",
              color: "var(--text)",
            }}
            onClick={() => void moveTo(other.workout_id!, false)}
          >
            {t("backTo")}
          </button>
        </div>
      ))}
      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
      {pending ? (
        <Dialog
          title={t("switchTitle", { title: titleOf(pending) })}
          description={t("switchBody", { title: titleOf(live) })}
          size="sm"
          testId="remote-wod-switch-dialog"
          onClose={() => setPending(null)}
          footer={
            <>
              <DialogButton onClick={() => setPending(null)}>
                {t("switchStay")}
              </DialogButton>
              <DialogButton
                testId="remote-wod-switch-keep"
                onClick={() => void moveTo(pending, false)}
              >
                {t("switchKeepRunning")}
              </DialogButton>
              <DialogButton
                tone="primary"
                testId="remote-wod-switch-confirm"
                onClick={() => void moveTo(pending, true)}
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
      ) : null}
    </section>
  );
}
