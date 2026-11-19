"use client";

import { useId, useState } from "react";
import { useFormatter, useTranslations } from "next-intl";

import type { MemberWorkoutGoals } from "@/api/wod-goals";

/** What the strip reads: the member's goals or the coach's (saved or suggested). */
export type GoalsShown = Pick<MemberWorkoutGoals, "muscles" | "qualities" | "stimulus">;
import { AnatomyFigure } from "@/components/anatomy/AnatomyFigure";
import { AnatomyThumb } from "@/components/anatomy/AnatomyThumb";
import { Sheet, SheetButton } from "@/components/community/Sheet";
import { BackButton } from "@/components/ui/BackLink";
import { WodAtlasView, type WodAtlasContext } from "@/components/anatomy/atlas/WodAtlasView";
import type { MuscleNodeId } from "@/lib/anatomy/taxonomy";
import { goalHighlights, musclesByRole, summaryMuscleIds } from "@/lib/wod-goals/goals";

import { MuscleChip, RoleLegend, ToggleChip } from "./GoalChips";
import { useAdminWorkoutGoals, useWorkoutGoals } from "./use-wod-goals";

/**
 * The member's goals strip (Q3) inside a workout card: fetches the
 * workout's visible goals and renders nothing while they are missing,
 * hidden, loading or failed, so the card never changes shape for them.
 */
export function WodGoalsStrip({
  workoutId,
  className = "",
  atlas,
}: {
  workoutId: string | null | undefined;
  className?: string;
  /** Where the atlas inside the sheet was opened from (ADR-670); a member's by default. */
  atlas?: WodAtlasContext;
}) {
  const goals = useWorkoutGoals(workoutId);
  return <WodGoalsStripView goals={goals.data?.goals ?? null} className={className} atlas={atlas} />;
}

/**
 * Staff's goals block under a WOD they look at (the Αρχείο preview, a class
 * on the schedule): the coach's saved goals, else the live suggestion from
 * the exercises, in the same quiet block members see. `atlas` says where it
 * sits, which decides what the atlas adds (ADR-670).
 */
export function StaffWodGoalsStrip({
  workoutId,
  atlas,
  className = "",
}: {
  workoutId: string;
  atlas: WodAtlasContext;
  className?: string;
}) {
  const goals = useAdminWorkoutGoals(workoutId);
  return <WodGoalsStripView goals={goals.data?.goals ?? null} className={className} atlas={atlas} />;
}

/**
 * ADR-551 (mockup 4 A): a quiet «Στόχοι» block under the WOD, one row per
 * kind (label left, value right) like rendered markdown; a row without a
 * value is left out. The small figure opens the sheet with every muscle and
 * the atlas.
 */
export function WodGoalsStripView({
  goals,
  className = "",
  atlas = MEMBER_ATLAS,
}: {
  goals: GoalsShown | null;
  className?: string;
  atlas?: WodAtlasContext;
}) {
  const t = useTranslations("WodGoals");
  const anatomy = useTranslations("Anatomy");
  const format = useFormatter();
  const [open, setOpen] = useState(false);
  if (!goals || (goals.muscles.length === 0 && goals.qualities.length === 0 && !goals.stimulus)) return null;

  const names = summaryMuscleIds(goals.muscles).map((id) => anatomy(`muscle.${id}`));
  const rows = [
    { key: "muscles", label: t("muscles"), value: names.length > 0 ? format.list(names) : null },
    { key: "qualities", label: t("qualities"), value: goals.qualities.length > 0 ? goals.qualities.map((quality) => anatomy(`quality.${quality}`)).join(" · ") : null },
    { key: "stimulus", label: t("stimulus"), value: goals.stimulus || null },
  ].filter((row) => row.value);

  return (
    <section
      data-testid="wod-goals-strip"
      aria-label={t("title")}
      className={`border-t pt-3 ${className}`}
      style={{ borderColor: "var(--border)" }}
    >
      <p className="mb-1 text-[11px] font-bold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{t("title")}</p>
      <div className="flex items-start gap-3">
        <dl className="m-0 min-w-0 flex-1">
          {rows.map((row) => (
            <div key={row.key} className="grid grid-cols-[6rem_minmax(0,1fr)] gap-3 py-1 text-[13px] leading-snug">
              <dt className="font-semibold" style={{ color: "var(--dim)" }}>{row.label}</dt>
              <dd className="m-0 break-words" style={{ color: "var(--text-soft)" }}>{row.value}</dd>
            </div>
          ))}
        </dl>
        {goals.muscles.length > 0 ? (
          <button
            type="button"
            onClick={() => setOpen(true)}
            aria-label={t("strip.open")}
            title={t("strip.open")}
            data-testid="wod-goals-open"
            className="shrink-0 rounded-lg outline-none focus-visible:ring-2 focus-visible:ring-[var(--primary)]"
          >
            <AnatomyThumb highlights={goalHighlights(goals.muscles, ["primary", "secondary"])} view="both" height={56} />
          </button>
        ) : null}
      </div>
      {open ? <WodGoalsSheet goals={goals} atlas={atlas} onClose={() => setOpen(false)} /> : null}
    </section>
  );
}

const MEMBER_ATLAS: WodAtlasContext = { kind: "member" };

/**
 * All the goals, stabilizers included, on the interactive figure.
 * ADR-670: «Άτλαντας ›» (or a muscle) opens the WOD's atlas as a second step
 * of this same sheet, with every muscle of the WOD in its role; «‹ Στόχοι»
 * returns and «Κλείσιμο» leaves the person where they were (the preview,
 * the class), so staff never leave the admin and nobody loses the WOD.
 */
export function WodGoalsSheet({
  goals,
  onClose,
  atlas = MEMBER_ATLAS,
}: {
  goals: GoalsShown;
  onClose: () => void;
  atlas?: WodAtlasContext;
}) {
  const t = useTranslations("WodGoals");
  const anatomy = useTranslations("Anatomy");
  const labelId = useId();
  // null: the goals; otherwise the atlas, opened on a muscle or on the whole body ("body").
  const [atlasOn, setAtlasOn] = useState<MuscleNodeId | "body" | null>(null);

  if (atlasOn) {
    return (
      <Sheet title={t("sheet.atlasTitle")} labelId={labelId} onClose={onClose} footer={<SheetButton onClick={onClose}>{t("sheet.close")}</SheetButton>}>
        <div className="flex flex-col gap-3">
          <BackButton onClick={() => setAtlasOn(null)} className="min-h-11 self-start text-sm font-semibold" data-testid="wod-goals-atlas-back">
            {t("sheet.backToGoals")}
          </BackButton>
          <WodAtlasView muscles={goals.muscles} context={atlas} initialNode={atlasOn === "body" ? null : atlasOn} />
        </div>
      </Sheet>
    );
  }

  return (
    <Sheet title={t("sheet.title")} labelId={labelId} onClose={onClose} footer={<SheetButton onClick={onClose}>{t("sheet.close")}</SheetButton>}>
      <div className="flex flex-col gap-4">
        {goals.muscles.length > 0 ? (
          <>
            <AnatomyFigure highlights={goalHighlights(goals.muscles)} view="both" interactive size="card" />
            <div className="flex flex-wrap items-center justify-between gap-2">
              <RoleLegend />
              <button
                type="button"
                onClick={() => setAtlasOn("body")}
                className="text-xs font-semibold"
                style={{ color: "var(--primary)" }}
                data-testid="wod-goals-atlas-link"
              >
                {t("sheet.atlas")}
              </button>
            </div>
            {musclesByRole(goals.muscles).map(([role, muscles]) => (
              <div key={role} className="flex flex-col gap-1">
                <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t(`legend.${role}`)}</p>
                <div className="flex flex-wrap gap-1.5">
                  {muscles.map((muscle) => (
                    <MuscleChip
                      key={muscle.id}
                      label={anatomy(`muscle.${muscle.id}`)}
                      role={muscle.role}
                      onPress={() => setAtlasOn(muscle.id)}
                      pressLabel={t("sheet.openInAtlas", { muscle: anatomy(`muscle.${muscle.id}`) })}
                    />
                  ))}
                </div>
              </div>
            ))}
          </>
        ) : null}
        {goals.qualities.length > 0 ? (
          <section className="flex flex-col gap-1">
            <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("qualities")}</p>
            <div className="flex flex-wrap gap-1.5">
              {goals.qualities.map((quality) => (
                <ToggleChip key={quality} pressed>{anatomy(`quality.${quality}`)}</ToggleChip>
              ))}
            </div>
          </section>
        ) : null}
        {goals.stimulus ? (
          <section className="flex flex-col gap-1">
            <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("stimulus")}</p>
            <p className="text-sm" style={{ color: "var(--text)" }}>{goals.stimulus}</p>
          </section>
        ) : null}
      </div>
    </Sheet>
  );
}
