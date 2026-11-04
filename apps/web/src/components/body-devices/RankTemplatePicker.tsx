"use client";

import { useMemo, useState } from "react";
import { useTranslations } from "next-intl";

import type { RankTemplate } from "@/api/body-devices";
import { Belt } from "@/components/body-devices/Belt";
import { useWorkoutTypeLabels, WorkoutTypeSelect } from "@/components/workouts/WorkoutTypeSelect";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import type { WorkoutType } from "@/lib/workout-types";

export type TemplateKind = { discipline: string; templates: RankTemplate[] };

/**
 * The kinds of training the catalogue covers, each with its templates: the
 * box's own kinds (its profile) first, the rest after, in catalogue order.
 * Malformed entries (an older server, a stub) are left out.
 */
export function templateKinds(templates: unknown[], boxDisciplines: readonly string[]): { mine: TemplateKind[]; rest: TemplateKind[] } {
  const byKind = new Map<string, RankTemplate[]>();
  for (const entry of templates) {
    const template = entry as RankTemplate;
    if (!template || typeof template !== "object" || typeof template.key !== "string" || typeof template.discipline !== "string") continue;
    byKind.set(template.discipline, [...(byKind.get(template.discipline) ?? []), template]);
  }
  const kinds = [...byKind].map(([discipline, list]) => ({ discipline, templates: list }));
  return {
    mine: kinds.filter((kind) => boxDisciplines.includes(kind.discipline)),
    rest: kinds.filter((kind) => !boxDisciplines.includes(kind.discipline)),
  };
}

/**
 * «Νέα κλίμακα βαθμών» (mockup «Επιλογή προτύπου», option Β): step 1 «Τι
 * διδάσκεις;» (kinds of training with their template count), step 2 «Ποιο
 * σύστημα;» (that kind's templates with their source, system and ranks),
 * then «Συνέχεια». A kind with one template goes straight to it. «Από το
 * μηδέν» starts an empty ladder of a chosen kind.
 */
export function RankTemplatePicker({
  templates,
  boxDisciplines,
  pending,
  failed,
  onTemplate,
  onScratch,
  onClose,
}: {
  templates: unknown[];
  boxDisciplines: readonly string[];
  pending: boolean;
  failed: boolean;
  onTemplate: (template: RankTemplate) => void;
  onScratch: (discipline: WorkoutType) => void;
  onClose?: () => void;
}) {
  const t = useTranslations("BodyDevices");
  const labels = useWorkoutTypeLabels();
  const { mine, rest } = useMemo(() => templateKinds(templates, boxDisciplines), [templates, boxDisciplines]);
  const [kind, setKind] = useState<TemplateKind | null>(null);
  const [picked, setPicked] = useState<string | null>(null);
  const [scratch, setScratch] = useState(false);
  const [scratchType, setScratchType] = useState<WorkoutType | "">("");

  const open = (next: TemplateKind) => {
    setKind(next);
    setPicked(next.templates.length === 1 ? next.templates[0].key : null);
  };
  const chosen = kind?.templates.find((template) => template.key === picked) ?? null;

  const tile = (entry: TemplateKind) => (
    <li key={entry.discipline}>
      <button
        type="button"
        onClick={() => open(entry)}
        className="flex min-h-16 w-full flex-col items-start justify-center gap-0.5 rounded-2xl px-3 py-2 text-start"
        style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
      >
        <span className="text-sm font-semibold">{labels.type(entry.discipline)}</span>
        <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t("ranks.picker.count", { count: entry.templates.length })}</span>
      </button>
    </li>
  );

  return (
    <section className="flex flex-col gap-3 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="rank-template-picker">
      <div className="flex items-center justify-between gap-2">
        <b className="text-sm" style={{ color: "var(--text)" }}>{t("ranks.newLadder")}</b>
        {onClose ? (
          <button type="button" onClick={onClose} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>
            {t("cancel")}
          </button>
        ) : null}
      </div>
      {!kind ? (
        <>
          <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("ranks.picker.step1")}</p>
          {mine.length > 0 ? (
            <>
              <span className="text-xs" style={{ color: "var(--dim)" }}>{t("ranks.picker.forYourBox")}</span>
              <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3" data-testid="rank-kinds-mine">{mine.map(tile)}</ul>
              {rest.length > 0 ? <span className="text-xs" style={{ color: "var(--dim)" }}>{t("ranks.picker.otherKinds")}</span> : null}
            </>
          ) : null}
          <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3" data-testid="rank-kinds">{rest.map(tile)}</ul>
          {scratch ? (
            <div className="flex flex-wrap items-center gap-2">
              <WorkoutTypeSelect value={scratchType} onChange={setScratchType} placeholder={t("ranks.fromScratch")} className="min-h-11 min-w-56" />
              <button
                type="button"
                disabled={pending || !scratchType}
                onClick={() => scratchType && onScratch(scratchType)}
                className="min-h-11 rounded-2xl px-4 text-sm font-semibold disabled:opacity-50"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              >
                {t("ranks.create")}
              </button>
            </div>
          ) : (
            <button type="button" onClick={() => setScratch(true)} className="self-start text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
              {t("ranks.picker.scratch")}
            </button>
          )}
        </>
      ) : (
        <>
          <div className="flex items-center gap-2">
            <button type="button" onClick={() => setKind(null)} className="min-h-9 text-sm font-semibold" style={{ color: "var(--dim)" }} aria-label={t("ranks.picker.back")}>
              ‹
            </button>
            <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
              {t("ranks.picker.step2")} · {labels.type(kind.discipline)}
            </p>
          </div>
          <ul className="flex flex-col gap-2" role="radiogroup" aria-label={t("ranks.picker.step2")}>
            {kind.templates.map((template) => {
              const on = template.key === picked;
              return (
                <li key={template.key}>
                  <button
                    type="button"
                    role="radio"
                    aria-checked={on}
                    onClick={() => setPicked(template.key)}
                    className="flex w-full flex-col items-start gap-1 rounded-2xl p-3 text-start"
                    style={{ background: on ? "var(--panel-raised)" : "var(--panel-muted)", border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`, color: "var(--text)" }}
                  >
                    <span className="flex w-full flex-wrap items-center justify-between gap-2">
                      <span className="text-sm font-semibold">{template.name || template.key}</span>
                      <span className="rounded-full px-2 py-0.5 text-[11px] font-bold" style={{ background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border)" }}>
                        {template.source === "palee" ? t("ranks.picker.sourcePalee") : t("ranks.picker.sourceFederation")}
                      </span>
                    </span>
                    {template.system ? <span className="text-xs" style={{ color: "var(--text-soft)" }}>{template.system}</span> : null}
                    <RanksPreview template={template} />
                  </button>
                </li>
              );
            })}
          </ul>
          <button
            type="button"
            disabled={pending || !chosen}
            onClick={() => chosen && onTemplate(chosen)}
            className="min-h-11 self-end rounded-2xl px-5 text-sm font-bold disabled:opacity-50"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("ranks.picker.continue")}
          </button>
        </>
      )}
      {failed ? <ErrorNotice variant="field">{t("errorGeneric")}</ErrorNotice> : null}
    </section>
  );
}

/** Belt swatches for a belt ladder (up to 12), else how many levels and skills. */
function RanksPreview({ template }: { template: RankTemplate }) {
  const t = useTranslations("BodyDevices");
  const ranks = Array.isArray(template.ranks) ? template.ranks : [];
  const skills = ranks.reduce((sum, rank) => sum + (Array.isArray(rank.requirements?.skills) ? rank.requirements.skills.length : 0), 0);
  if (template.style === "belt" && ranks.some((rank) => rank.color)) {
    return (
      <span className="flex flex-wrap items-center gap-1" aria-label={t("ranks.picker.ranksCount", { count: ranks.length })}>
        {ranks.slice(0, 12).map((rank, index) => (
          <Belt key={`${rank.name}-${index}`} color={rank.color} className="h-2.5 w-7" />
        ))}
        {ranks.length > 12 ? <span className="text-xs" style={{ color: "var(--dim)" }}>+{ranks.length - 12}</span> : null}
      </span>
    );
  }
  return (
    <span className="text-xs" style={{ color: "var(--dim)" }}>
      {t("ranks.picker.levelsCount", { count: ranks.length })}
      {skills > 0 ? ` · ${t("ranks.picker.skillsCount", { count: skills })}` : ""}
    </span>
  );
}
