"use client";

import { useUiTranslations } from "@/i18n/ui";
import React, { useMemo, useState } from "react";

import { FreeTextTimerFields } from "@/components/workouts/creation/FreeTextTimerFields";
import { type FreeTextTimerPreset, QUICK_PRESETS } from "@/lib/free-text-timer";
import { getFormatLabels } from "@/types/workout";

type Draft = { source: "own" | string; preset: FreeTextTimerPreset };

type Props = {
  /** The class already has a timed workout (or a preset): the chooser starts folded as «Άλλο χρονόμετρο». */
  hasTimer: boolean;
  hasWorkout: boolean;
  presetActive: boolean;
  sending: boolean;
  onConfigure: (preset: FreeTextTimerPreset | null) => void;
};

// ANR 2026-11-04: the coach's own timer comes first, in Spark, and the common
// timers follow under «ή διάλεξε από συνηθισμένα χρονόμετρα:». Picking a common
// one explains what its name means (EMOM, AMRAP, time cap…) and opens the same
// fields, filled in, to change before use.

/** Pick the timer the class runs: your own, or one of the common ones. */
export function ClassTimerChooser({ hasTimer, hasWorkout, presetActive, sending, onConfigure }: Props) {
  const i18n = useUiTranslations();
  const formatLabels = useMemo(() => getFormatLabels(i18n), [i18n]);
  const [open, setOpen] = useState(!hasTimer);
  const [draft, setDraft] = useState<Draft | null>(null);

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-expanded={false}
        data-testid="remote-chooser-open"
        className="flex min-h-12 w-full items-center justify-between gap-3 rounded-3xl border px-5 text-start text-base font-black"
        style={{ borderColor: "var(--border)", background: "var(--panel)", color: "var(--text)" }}
      >
        {i18n("classTimerOtherTimer")}
        <span aria-hidden="true">▾</span>
      </button>
    );
  }

  const ownActive = draft?.source === "own";

  return (
    <section className="space-y-3 rounded-3xl border p-5" style={{ borderColor: "var(--border)", background: "var(--panel)" }} data-testid="remote-chooser">
      <div>
        <h2 className="text-base font-black">{hasTimer ? i18n("classTimerOtherTimer") : i18n("classTimerChooseTitle")}</h2>
        <p className="mt-1 text-sm" style={{ color: "var(--muted)" }}>
          {hasTimer ? i18n("classTimerInsteadOfWorkout") : i18n("classTimerNoTimedWorkout")}
        </p>
      </div>

      <button
        type="button"
        aria-pressed={ownActive}
        data-testid="remote-own-timer"
        onClick={() => setDraft(ownActive ? null : { source: "own", preset: { format: "untimed" } })}
        className="min-h-12 w-full rounded-2xl px-4 text-base font-extrabold"
        style={{ background: "var(--spark)", color: "var(--spark-contrast)", outline: ownActive ? "2px solid var(--text)" : undefined, outlineOffset: 2 }}
      >
        ＋ {i18n("classTimerOwnTimer")}
      </button>

      {ownActive && draft ? <DraftFields draft={draft} formatLabels={formatLabels} onChange={setDraft} sending={sending} onUse={() => onConfigure(draft.preset)} /> : null}

      <p className="text-sm" style={{ color: "var(--muted)" }}>
        {i18n("classTimerOrCommon")}
      </p>
      <div className="flex flex-wrap gap-2">
        {QUICK_PRESETS.map((quick) => {
          const active = draft?.source === quick.id;
          return (
            <button
              key={quick.id}
              type="button"
              aria-pressed={active}
              onClick={() => setDraft(active ? null : { source: quick.id, preset: quick.preset })}
              className="min-h-10 whitespace-nowrap rounded-full px-3 text-sm font-semibold"
              style={active ? { background: "var(--primary)", color: "var(--primary-contrast)" } : { border: "1px solid var(--border)", color: "var(--text-soft)" }}
            >
              {i18n(`timerPreset_${quick.id}`)}
            </button>
          );
        })}
      </div>

      {draft && !ownActive ? (
        <>
          <p data-testid="remote-preset-help" className="rounded-xl px-3 py-2 text-sm" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}>
            {i18n(`timerPresetHelp_${draft.source}`)}
          </p>
          <DraftFields draft={draft} formatLabels={formatLabels} onChange={setDraft} sending={sending} onUse={() => onConfigure(draft.preset)} />
        </>
      ) : null}

      {presetActive && hasWorkout ? (
        <button
          type="button"
          disabled={sending}
          onClick={() => onConfigure(null)}
          className="min-h-11 rounded-xl px-4 text-sm font-semibold disabled:opacity-40"
          style={{ border: "1px solid var(--border)", color: "var(--text-soft)" }}
        >
          {i18n("classTimerUseWorkout")}
        </button>
      ) : null}
    </section>
  );
}

function DraftFields({
  draft,
  formatLabels,
  onChange,
  sending,
  onUse,
}: {
  draft: Draft;
  formatLabels: ReturnType<typeof getFormatLabels>;
  onChange: (draft: Draft) => void;
  sending: boolean;
  onUse: () => void;
}) {
  const i18n = useUiTranslations();
  return (
    <div>
      <FreeTextTimerFields preset={draft.preset} formatLabels={formatLabels} onChange={(preset) => onChange({ ...draft, preset })} />
      <button
        type="button"
        disabled={sending}
        onClick={onUse}
        data-testid="remote-use-timer"
        className="mt-4 min-h-11 rounded-xl px-4 text-sm font-bold disabled:opacity-40"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {i18n("classTimerUsePreset")}
      </button>
    </div>
  );
}
