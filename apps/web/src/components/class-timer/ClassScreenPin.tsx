"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState, type CSSProperties, type ReactNode } from "react";

import {
  type BoxScreen,
  type BoxScreenOverrideView,
  type ClassScreenInput,
  type ClassScreenList,
  classScreensKey,
  listClassScreens,
  pinClassScreen,
  unpinClassScreen,
} from "@/api/box-screens";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { FRESHNESS } from "@/lib/query-policy";

// ADR-253 update 2026-10-29: «Στην οθόνη» on the class timer's remote. The
// class's own coach pins its timer, leaderboard or WOD on a box screen of the
// class's branch (or the whole box), today, and returns it to automatic. The
// API lists only the screens the person may change; with none the action is
// not shown at all.
//
// ADR-746 (ANR pick 7A): every screen says what it shows now. For each one
// the coach picks the view and, with several WODs, which WOD (or «Ακολουθεί
// το Τώρα»); with a class running at the same time the screen can be shared
// with it this once. Taking a screen that shows a running timer, the
// coach's own or another coach's, asks first.

const COACH_VIEWS: BoxScreenOverrideView[] = ["timer", "leaderboard", "wod"];

export function ClassScreenPin({
  token,
  slotId,
  className = "min-h-11 rounded-xl px-3 text-sm font-semibold",
  style = { border: "1px solid var(--border)", color: "var(--text-soft)" },
  hint,
}: {
  token: string | undefined;
  slotId: string;
  className?: string;
  style?: CSSProperties;
  /** A line under the label, e.g. in the remote's «Οθόνη τοίχου» sheet. */
  hint?: ReactNode;
}) {
  const t = useTranslations("BoxScreens");
  const [open, setOpen] = useState(false);
  const screens = useQuery({
    queryKey: classScreensKey(slotId),
    enabled: Boolean(token),
    staleTime: FRESHNESS.live,
    retry: false,
    queryFn: () => listClassScreens(token as string, slotId),
  });

  // A malformed answer (no `screens` list) shows nothing rather than crashing the remote.
  const data = screens.data;
  if (!token || !data || !Array.isArray(data.screens) || data.screens.length === 0) return null;

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        data-testid="class-screen-open"
        className={className}
        style={style}
      >
        <span>{t("onScreen")}</span>
        {hint}
      </button>
      {open ? (
        <ClassScreenDialog
          token={token}
          slotId={slotId}
          screens={data.screens}
          views={COACH_VIEWS.filter((view) => (data.views ?? []).includes(view))}
          workouts={data.workouts ?? []}
          together={data.together ?? []}
          onClose={() => setOpen(false)}
        />
      ) : null}
    </>
  );
}

function ClassScreenDialog({
  token,
  slotId,
  screens,
  views,
  workouts,
  together,
  onClose,
}: {
  token: string;
  slotId: string;
  screens: BoxScreen[];
  views: BoxScreenOverrideView[];
  workouts: NonNullable<ClassScreenList["workouts"]>;
  together: NonNullable<ClassScreenList["together"]>;
  onClose: () => void;
}) {
  const t = useTranslations("BoxScreens");
  const tWods = useTranslations("ClassWods");
  const [confirm, setConfirm] = useState<{ screen: BoxScreen; input: ClassScreenInput } | null>(null);
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const refresh = () => queryClient.invalidateQueries({ queryKey: classScreensKey(slotId) });

  const pin = useMutation({
    mutationFn: ({ screenId, input }: { screenId: string; input: ClassScreenInput }) =>
      pinClassScreen(token, slotId, screenId, input),
    onSuccess: refresh,
  });

  // A running timer on the screen (ours or another class's) is never
  // replaced without asking; showing that same timer again needs no question.
  function take(screen: BoxScreen, input: ClassScreenInput) {
    unpin.reset();
    const showing = screen.showing;
    const sameTimer = input.view === "timer" && showing?.slot_id === slotId;
    if (showing?.timer_running && !sameTimer) setConfirm({ screen, input });
    else pin.mutate({ screenId: screen.id, input });
  }
  const unpin = useMutation({
    mutationFn: (screenId: string) => unpinClassScreen(token, slotId, screenId),
    onSuccess: refresh,
  });
  const failure = pin.error ?? unpin.error;
  const busy = pin.isPending || unpin.isPending;

  return (
    <Dialog
      title={t("onScreenTitle")}
      description={t("onScreenHint")}
      size="md"
      testId="class-screen-dialog"
      error={failure ? localizeError(failure, ui) : null}
      onClose={onClose}
      footer={
        <DialogButton tone="primary" onClick={onClose} testId="class-screen-done">
          {t("done")}
        </DialogButton>
      }
    >
      <ul className="grid gap-3">
        {screens.map((screen) => {
          const override = screen.override;
          const ours = override?.slot_id === slotId;
          const pinnedWod = ours ? (override?.workout_id ?? null) : null;
          const pinnedSplit = ours ? (override?.split_slot_id ?? null) : null;
          const showing = screen.showing;
          const current = (view: BoxScreenOverrideView): ClassScreenInput => ({
            view,
            workout_id: pinnedWod,
            split_slot_id: pinnedSplit,
          });
          return (
            <li
              key={screen.id}
              className="grid gap-3 rounded-2xl p-4"
              style={{ background: "var(--panel-muted)" }}
              data-testid={`class-screen-${screen.id}`}
            >
              <div className="min-w-0">
                <p className="truncate text-base font-bold" style={{ color: "var(--text)" }}>{screen.name}</p>
                <p className="text-sm" style={{ color: "var(--muted)" }} data-testid="class-screen-shows">
                  {t("shows")}{" "}
                  {override
                    ? ours && views.includes(override.view)
                      ? t("pinned", { view: t(`classView.${override.view as "timer" | "leaderboard" | "wod"}`) })
                      : t("pinned", { view: t(`view.${override.view}`) })
                    : t("automatic")}
                </p>
                {showing && showing.slot_id && showing.slot_id !== slotId ? (
                  <p className="text-xs" style={{ color: "var(--muted)" }} data-testid="class-screen-now">
                    {[showing.class_name, showing.coach_name].filter(Boolean).join(" · ")}
                    {showing.timer_running ? ` · ${tWods("timerRunning")}` : ""}
                  </p>
                ) : null}
              </div>
              <div role="group" aria-label={t("showOnScreen")} className="flex flex-wrap gap-2">
                {views.map((view) => {
                  const active = ours && override?.view === view;
                  return (
                    <button
                      key={view}
                      type="button"
                      disabled={busy}
                      aria-pressed={active}
                      data-testid={`class-screen-view-${view}`}
                      onClick={() => take(screen, current(view))}
                      className="min-h-11 rounded-xl px-3 text-sm font-semibold disabled:opacity-40"
                      style={
                        active
                          ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                          : { border: "1px solid var(--border)", color: "var(--text-soft)" }
                      }
                    >
                      {t(`classView.${view as "timer" | "leaderboard" | "wod"}`)}
                    </button>
                  );
                })}
              </div>
              {workouts.length > 1 ? (
                <div role="group" aria-label={tWods("screenWhichWod")} className="flex flex-wrap gap-2" data-testid="class-screen-wods">
                  {[{ id: null as string | null, title: tWods("followsNow") }, ...workouts.map((workout) => ({ id: workout.id as string | null, title: workout.title ?? tWods("untitled") }))].map(
                    (option) => {
                      const active = ours && pinnedWod === option.id;
                      return (
                        <button
                          key={option.id ?? "now"}
                          type="button"
                          disabled={busy}
                          aria-pressed={active}
                          data-testid="class-screen-wod"
                          onClick={() =>
                            take(screen, {
                              view: ours && override ? override.view : "timer",
                              workout_id: option.id,
                              split_slot_id: pinnedSplit,
                            })
                          }
                          className="min-h-10 max-w-[12rem] truncate rounded-full px-3 text-sm font-semibold disabled:opacity-40"
                          style={
                            active
                              ? { background: "var(--text)", color: "var(--bg)" }
                              : { border: "1px solid var(--border)", color: "var(--text-soft)" }
                          }
                        >
                          {option.title}
                        </button>
                      );
                    },
                  )}
                </div>
              ) : null}
              {together.length > 0 ? (
                <div role="group" aria-label={tWods("shareScreen")} className="flex flex-wrap gap-2" data-testid="class-screen-split">
                  {together.map((other) => {
                    const active = pinnedSplit === other.id;
                    return (
                      <button
                        key={other.id}
                        type="button"
                        disabled={busy}
                        aria-pressed={active}
                        onClick={() =>
                          take(screen, {
                            view: ours && override ? override.view : "timer",
                            workout_id: pinnedWod,
                            split_slot_id: active ? null : other.id,
                          })
                        }
                        className="min-h-10 rounded-full px-3 text-sm font-semibold disabled:opacity-40"
                        style={
                          active
                            ? { background: "var(--text)", color: "var(--bg)" }
                            : { border: "1px dashed var(--border-strong)", color: "var(--text-soft)" }
                        }
                      >
                        {other.coach_name
                          ? tWods("shareWithCoach", { coach: other.coach_name })
                          : tWods("shareWithClass", { name: other.name ?? "" })}
                      </button>
                    );
                  })}
                </div>
              ) : null}
              {ours ? (
                <button
                  type="button"
                  disabled={busy}
                  data-testid="class-screen-auto"
                  onClick={() => {
                    pin.reset();
                    unpin.mutate(screen.id);
                  }}
                  className="min-h-11 justify-self-start rounded-xl px-3 text-sm font-semibold disabled:opacity-40"
                  style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
                >
                  {t("backToAuto")}
                </button>
              ) : null}
            </li>
          );
        })}
      </ul>
      {confirm ? (
        <Dialog
          title={tWods("takeScreenTitle", { screen: confirm.screen.name })}
          description={tWods("takeScreenBody", {
            name: confirm.screen.showing?.class_name ?? "",
            coach: confirm.screen.showing?.coach_name ?? "",
          })}
          size="sm"
          testId="class-screen-take-dialog"
          onClose={() => setConfirm(null)}
          footer={
            <>
              <DialogButton onClick={() => setConfirm(null)}>{tWods("switchStay")}</DialogButton>
              <DialogButton
                tone="primary"
                testId="class-screen-take-confirm"
                onClick={() => {
                  pin.mutate({ screenId: confirm.screen.id, input: confirm.input });
                  setConfirm(null);
                }}
              >
                {tWods("takeScreen")}
              </DialogButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {tWods("takeScreenHint")}
          </p>
        </Dialog>
      ) : null}
    </Dialog>
  );
}
