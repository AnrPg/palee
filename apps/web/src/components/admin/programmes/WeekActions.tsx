"use client";

import { useTranslations } from "next-intl";
import { useId, useState, type ReactNode } from "react";

import type { ProgrammeDay } from "@/api/programmes";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

import { copyWeek, copyWeekToNext, deleteWeek, moveWeek, trainingDays } from "./programme-editor-model";

export type WeeksChange = { days?: ProgrammeDay[]; weeks?: number };

type Open = { kind: "copyTo" | "move" | "delete"; week: number } | null;

/**
 * The actions of one week (board 1κ A «⋯», 1μ A row header), shared by the
 * phone sheet and the desktop row: copy to the next week, copy to several,
 * change its position and delete it. Copies fill only empty days (ADR-544).
 */
export function useWeekActions({
  days,
  weeks,
  onChange,
  onShowWeek,
  say,
}: {
  days: ProgrammeDay[];
  weeks: number;
  onChange: (change: WeeksChange) => void;
  /** After an action that moves the coach's attention to another week. */
  onShowWeek?: (week: number) => void;
  say: (text: string) => void;
}) {
  const t = useTranslations("Programmes.editor2");
  const tp = useTranslations("Programmes");
  const [open, setOpen] = useState<Open>(null);

  function copyNext(week: number) {
    const result = copyWeekToNext(days, weeks, week);
    onChange({ days: result.days, weeks: result.weeks });
    onShowWeek?.(result.week);
    say(t("copiedDays", { count: result.filled, week: result.week + 1 }));
  }

  function remove(week: number) {
    if (trainingDays(days, week) > 0) {
      setOpen({ kind: "delete", week });
      return;
    }
    const result = deleteWeek(days, weeks, week);
    onChange(result);
    onShowWeek?.(Math.min(week, result.weeks - 1));
    say(t("weekDeleted", { week: week + 1 }));
  }

  const dialogs: ReactNode =
    open?.kind === "copyTo" ? (
      <CopyToDialog
        week={open.week}
        weeks={weeks}
        onClose={() => setOpen(null)}
        onCopy={(targets) => {
          const result = copyWeek(days, open.week, targets);
          onChange({ days: result.days });
          setOpen(null);
          say(t("copiedDaysMany", { count: result.filled }));
        }}
      />
    ) : open?.kind === "move" ? (
      <MoveWeekDialog
        week={open.week}
        weeks={weeks}
        onClose={() => setOpen(null)}
        onMove={(to) => {
          onChange({ days: moveWeek(days, weeks, open.week, to) });
          onShowWeek?.(to);
          setOpen(null);
          say(t("weekMoved", { position: to + 1 }));
        }}
      />
    ) : open?.kind === "delete" ? (
      <Dialog
        onClose={() => setOpen(null)}
        title={t("deleteTitle", { week: open.week + 1 })}
        size="sm"
        variant="center"
        testId="programme-week-delete"
        footer={
          <>
            <DialogButton onClick={() => setOpen(null)}>{tp("cancel")}</DialogButton>
            <DialogButton
              tone="danger"
              testId="programme-week-delete-confirm"
              onClick={() => {
                const week = open.week;
                const result = deleteWeek(days, weeks, week);
                onChange(result);
                onShowWeek?.(Math.min(week, result.weeks - 1));
                setOpen(null);
                say(t("weekDeleted", { week: week + 1 }));
              }}
            >
              {t("deleteConfirm")}
            </DialogButton>
          </>
        }
      >
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("deleteBody")}</p>
      </Dialog>
    ) : null;

  return {
    copyNext,
    copyTo: (week: number) => setOpen({ kind: "copyTo", week }),
    move: (week: number) => setOpen({ kind: "move", week }),
    remove,
    canDelete: weeks > 1,
    canMove: weeks > 1,
    dialogs,
  };
}

function CopyToDialog({ week, weeks, onClose, onCopy }: { week: number; weeks: number; onClose: () => void; onCopy: (targets: number[]) => void }) {
  const t = useTranslations("Programmes.editor2");
  const tp = useTranslations("Programmes");
  const [chosen, setChosen] = useState<number[]>([]);
  const [touched, setTouched] = useState(false);
  const errorId = useId();
  const invalid = chosen.length === 0;
  return (
    <Dialog
      onClose={onClose}
      title={t("copyToTitle", { week: week + 1 })}
      description={t("copyNextHint")}
      size="sm"
      testId="programme-copy-to"
      onSubmit={() => {
        setTouched(true);
        if (!invalid) onCopy(chosen);
      }}
      footer={
        <>
          <DialogButton onClick={onClose}>{tp("cancel")}</DialogButton>
          <DialogButton tone="primary" type="submit" testId="programme-copy-to-confirm">{t("copyConfirm")}</DialogButton>
        </>
      }
    >
      <fieldset aria-invalid={touched && invalid} aria-describedby={touched && invalid ? errorId : undefined}>
        <legend className="sr-only">{t("copyToLegend")}</legend>
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">
          {Array.from({ length: weeks }, (_, index) => index)
            .filter((index) => index !== week)
            .map((index) => {
              const checked = chosen.includes(index);
              return (
                <label
                  key={index}
                  className="flex min-h-11 cursor-pointer items-center gap-2 rounded-xl px-3 text-sm font-semibold"
                  style={{ background: "var(--panel-muted)", border: `1px solid ${checked ? "var(--primary)" : "var(--border)"}`, color: "var(--text)" }}
                >
                  <input
                    type="checkbox"
                    checked={checked}
                    onChange={() => setChosen((current) => (checked ? current.filter((entry) => entry !== index) : [...current, index]))}
                    style={{ accentColor: "var(--primary)" }}
                  />
                  {t("weekTitle", { week: index + 1 })}
                </label>
              );
            })}
        </div>
      </fieldset>
      {touched && invalid ? (
        <ErrorNotice variant="field" className="mt-2">
          <span id={errorId}>{t("copyToNone")}</span>
        </ErrorNotice>
      ) : null}
    </Dialog>
  );
}

function MoveWeekDialog({ week, weeks, onClose, onMove }: { week: number; weeks: number; onClose: () => void; onMove: (to: number) => void }) {
  const t = useTranslations("Programmes.editor2");
  return (
    <Dialog onClose={onClose} title={t("moveTitle", { week: week + 1 })} description={t("moveLead")} size="sm" testId="programme-move-week">
      <div className="grid grid-cols-3 gap-2 sm:grid-cols-4">
        {Array.from({ length: weeks }, (_, index) => (
          <button
            key={index}
            type="button"
            disabled={index === week}
            aria-current={index === week ? "true" : undefined}
            onClick={() => onMove(index)}
            className="min-h-11 rounded-xl px-3 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--panel-muted)", border: `1px solid ${index === week ? "var(--primary)" : "var(--border)"}`, color: "var(--text)" }}
          >
            {t("position", { position: index + 1 })}
          </button>
        ))}
      </div>
    </Dialog>
  );
}
