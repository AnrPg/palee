"use client";

/**
 * The pieces of the anatomy atlas (ADR-164) shared by the Ημερολόγιο page
 * and the atlas inside the WOD goals sheet (ADR-670): breadcrumb, lists,
 * the WOD's muscles by role, coverage lines and the box's exercises.
 */
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import { atlasNodeExercisesKey, fetchAtlasNodeExercises, type AtlasNodeExercise } from "@/api/atlas";
import { LoadingLine } from "@/components/client/ClientPage";
import { RoleDot } from "@/components/wod-goals/GoalChips";
import {
  atlasPath,
  coverageLevel,
  coverageSets,
  feltCount,
  WOD_ROLES,
  wodRoleOf,
  type AtlasRange,
  type CoverageIndex,
  type CoverageLevel,
  type WodMuscle,
} from "@/lib/anatomy/atlas";
import type { MuscleNodeId } from "@/lib/anatomy/taxonomy";

export const LEVEL_COLOR: Record<CoverageLevel, string> = {
  none: "var(--border)",
  low: "var(--anatomy-heat-low)",
  medium: "var(--anatomy-heat-medium)",
  high: "var(--anatomy-heat-high)",
};

const EXERCISES_SHOWN = 5;

export function HeatLegend() {
  const t = useTranslations("Atlas");
  return (
    <div className="flex flex-col gap-1">
      <ul className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs" style={{ color: "var(--text-soft)" }}>
        {(["low", "medium", "high"] as const).map((level) => (
          <li key={level} className="flex items-center gap-1.5">
            <LevelDot level={level} />
            {t(`level.${level}`)}
          </li>
        ))}
      </ul>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("legendNote")}</p>
    </div>
  );
}

export function LevelDot({ level }: { level: CoverageLevel }) {
  return <span aria-hidden="true" className="inline-block h-2.5 w-2.5 shrink-0 rounded-full" style={{ background: LEVEL_COLOR[level] }} />;
}

export function Breadcrumb({ selected, onSelect }: { selected: MuscleNodeId | null; onSelect: (id: MuscleNodeId | null) => void }) {
  const t = useTranslations("Atlas");
  const anatomy = useTranslations("Anatomy");
  const path = atlasPath(selected);
  const crumbs: Array<{ id: MuscleNodeId | null; label: string }> = [
    { id: null, label: t("crumbs.body") },
    ...path.map((node) => ({ id: node.id, label: anatomy(`muscle.${node.id}`) })),
  ];
  return (
    <nav aria-label={t("crumbs.label")}>
      <ol className="flex flex-wrap items-center gap-1 text-sm">
        {crumbs.map((crumb, position) => {
          const last = position === crumbs.length - 1;
          return (
            <li key={crumb.id ?? "body"} className="flex items-center gap-1">
              {last ? (
                <span aria-current="page" className="font-bold" style={{ color: "var(--text)" }}>{crumb.label}</span>
              ) : (
                <button type="button" onClick={() => onSelect(crumb.id)} className="font-semibold underline-offset-2 hover:underline" style={{ color: "var(--primary)" }}>
                  {crumb.label}
                </button>
              )}
              {last ? null : <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

/** «Σε αυτό το WOD: Κύριος» under the node's name, or that the WOD does not aim at it. */
export function WodRoleLine({ wod, nodeId }: { wod: WodMuscle[]; nodeId: MuscleNodeId }) {
  const t = useTranslations("Atlas");
  const role = wodRoleOf(wod, nodeId);
  return (
    <p className="flex items-center gap-1.5 text-sm font-semibold" style={{ color: "var(--text-soft)" }} data-testid="atlas-wod-role">
      {role ? <RoleDot role={role} /> : null}
      {role ? t("wod.role", { role: t(`wod.roles.${role}`) }) : t("wod.notInWod")}
    </p>
  );
}

/** The WOD's muscles by role; each opens its node. */
export function WodMuscleList({ wod, onSelect }: { wod: WodMuscle[]; onSelect: (id: MuscleNodeId) => void }) {
  const goals = useTranslations("WodGoals");
  const anatomy = useTranslations("Anatomy");
  return (
    <div className="flex flex-col gap-3" data-testid="atlas-wod-muscles">
      {WOD_ROLES.map((role) => {
        const muscles = wod.filter((muscle) => muscle.role === role);
        if (muscles.length === 0) return null;
        return (
          <section key={role} className="flex flex-col gap-1.5">
            <h3 className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{goals(`legend.${role}`)}</h3>
            <ul className="flex flex-col gap-1.5">
              {muscles.map((muscle) => (
                <li key={muscle.id}>
                  <button
                    type="button"
                    onClick={() => onSelect(muscle.id)}
                    className="flex min-h-11 w-full items-center gap-3 rounded-xl px-3 py-2 text-start"
                    style={{ background: "var(--panel-raised, var(--card))", border: "1px solid var(--border)" }}
                  >
                    <RoleDot role={role} />
                    <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{anatomy(`muscle.${muscle.id}`)}</span>
                    <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
                  </button>
                </li>
              ))}
            </ul>
          </section>
        );
      })}
    </div>
  );
}

export function YourSets({
  nodeId,
  index,
  range,
  sessions,
  title,
}: {
  nodeId: MuscleNodeId;
  index: CoverageIndex;
  range: AtlasRange;
  sessions: number;
  /** «Τα δικά σου · 4 εβδ.» unless another person's coverage is shown. */
  title?: string;
}) {
  const t = useTranslations("Atlas");
  const format = useFormatter();
  const level = coverageLevel(index, nodeId);
  const sets = coverageSets(index, nodeId);
  const felt = feltCount(index, nodeId);
  const top = index.get(nodeId)?.top_exercises ?? [];
  const perWeek = index.get(nodeId)?.per_week ?? 0;
  const number = (value: number) => format.number(value, { maximumFractionDigits: 1 });

  return (
    <div className="flex flex-col gap-1.5 rounded-xl p-3" style={{ background: "var(--bg)" }} data-testid="atlas-your-sets">
      <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{title ?? t("yours", { range: t(`range.${range}`) })}</p>
      {sessions === 0 ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noData")}</p>
      ) : sets === 0 ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noneHere")}</p>
      ) : (
        <>
          <p className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
            <span className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{t("sets", { sets: number(sets) })}</span>
            <span className="inline-flex items-center gap-1.5 text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
              <LevelDot level={level} />
              {t("levelLine", { level: t(`level.${level}`) })}
            </span>
            <span className="text-xs" style={{ color: "var(--dim)" }}>{t("perWeek", { perWeek: number(perWeek) })}</span>
          </p>
          {top.length > 0 ? (
            <p className="text-xs" style={{ color: "var(--text-soft)" }}>
              {t("from", { exercises: format.list(top.map((exercise) => exercise.label ?? exercise.exercise_ref)) })}
            </p>
          ) : null}
        </>
      )}
      {felt > 0 ? <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("felt", { count: felt })}</p> : null}
    </div>
  );
}

export function ChildList({ ids, index, onSelect, label }: { ids: MuscleNodeId[]; index: CoverageIndex; onSelect: (id: MuscleNodeId) => void; label: string }) {
  const t = useTranslations("Atlas");
  const anatomy = useTranslations("Anatomy");
  const format = useFormatter();
  return (
    <ul aria-label={label} className="flex flex-col gap-1.5">
      {ids.map((id) => {
        const level = coverageLevel(index, id);
        const sets = coverageSets(index, id);
        return (
          <li key={id}>
            <button
              type="button"
              onClick={() => onSelect(id)}
              className="flex min-h-11 w-full items-center gap-3 rounded-xl px-3 py-2 text-start"
              style={{ background: "var(--panel-raised, var(--card))", border: "1px solid var(--border)" }}
            >
              <LevelDot level={level} />
              <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{anatomy(`muscle.${id}`)}</span>
              <span className="shrink-0 text-xs" style={{ color: "var(--text-soft)" }}>
                {sets > 0 ? t("sets", { sets: format.number(sets, { maximumFractionDigits: 1 }) }) : t(`level.${level}`)}
              </span>
              <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

export function NodeExercises({ nodeId, token }: { nodeId: MuscleNodeId; token: string | null }) {
  const t = useTranslations("Atlas");
  const [expanded, setExpanded] = useState(false);
  const query = useQuery({
    queryKey: atlasNodeExercisesKey(nodeId),
    enabled: Boolean(token),
    queryFn: () => fetchAtlasNodeExercises(token!, nodeId),
    staleTime: 5 * 60_000,
    retry: false,
  });
  const exercises: AtlasNodeExercise[] = Array.isArray(query.data?.exercises) ? query.data.exercises : [];
  const shown = expanded ? exercises : exercises.slice(0, EXERCISES_SHOWN);

  return (
    <section className="flex flex-col gap-2" data-testid="atlas-exercises">
      <h3 className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("exercises.title")}</h3>
      {query.isPending && token ? (
        <LoadingLine />
      ) : query.isError ? (
        <EmptyNote>{t("exercises.unavailable")}</EmptyNote>
      ) : exercises.length === 0 ? (
        <EmptyNote>{t("exercises.empty")}</EmptyNote>
      ) : (
        <>
          <ul className="flex flex-col gap-1.5">
            {shown.map((exercise) => (
              <li
                key={exercise.exercise_ref}
                className="flex flex-col gap-1 rounded-xl px-3 py-2"
                style={{ background: "var(--panel-raised, var(--card))", border: "1px solid var(--border)" }}
              >
                <span className="flex items-center gap-2">
                  <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{exercise.label}</span>
                  <span className="shrink-0 text-[11px] font-semibold" style={{ color: "var(--dim)" }}>{t(`exercises.role.${exercise.role}`)}</span>
                </span>
                {(exercise.videos ?? []).map((video) => (
                  <a
                    key={video.id}
                    href={video.video_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-xs font-semibold underline-offset-2 hover:underline"
                    style={{ color: "var(--primary)" }}
                  >
                    {t("exercises.video", { title: video.title })}
                  </a>
                ))}
              </li>
            ))}
          </ul>
          {exercises.length > EXERCISES_SHOWN ? (
            <button
              type="button"
              onClick={() => setExpanded((value) => !value)}
              className="self-start text-xs font-semibold"
              style={{ color: "var(--primary)" }}
            >
              {expanded ? t("exercises.less") : t("exercises.more", { count: exercises.length })}
            </button>
          ) : null}
        </>
      )}
    </section>
  );
}

export function EmptyNote({ children }: { children: React.ReactNode }) {
  return (
    <p className="rounded-xl px-3 py-3 text-sm" style={{ background: "var(--panel-muted, var(--bg))", color: "var(--dim)" }}>
      {children}
    </p>
  );
}
