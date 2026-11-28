"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useFormatter, useTranslations } from "next-intl";

import {
  classProgrammeLoadKey,
  clientAtlasKey,
  fetchClassProgrammeLoad,
  fetchClientAtlas,
  type ProgrammeLoadGroup,
} from "@/api/atlas";
import { AnatomyFigure } from "@/components/anatomy/AnatomyFigure";
import { LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { useSession } from "@/components/session-provider";
import { RoleLegend, Segmented } from "@/components/wod-goals/GoalChips";
import {
  aboutNodeId,
  atlasChildren,
  atlasHref,
  coverageLevel,
  DEFAULT_ATLAS_RANGE,
  exploreHighlights,
  heatHighlights,
  indexCoverage,
  programmeLoadHighlights,
  programmeLoadLevel,
  wodHighlights,
  type CoverageIndex,
  type WodMuscle,
} from "@/lib/anatomy/atlas";
import { childrenOf, groupOf, muscleNode, type MuscleNodeId } from "@/lib/anatomy/taxonomy";

import { Breadcrumb, ChildList, EmptyNote, HeatLegend, LevelDot, NodeExercises, WodMuscleList, WodRoleLine, YourSets } from "./atlas-parts";

/**
 * Where the WOD's atlas was opened from (ADR-670), which decides the one
 * extra view next to «Αυτό το WOD»:
 *
 * - `member`: a member's class, day or workout. No coverage here; «Ολόκληρος
 *   ο άτλαντας ›» opens their own atlas in the Ημερολόγιο.
 * - `library`: a WOD of the staff Αρχείο, owned by nobody yet.
 * - `class`: a scheduled class, with «Φορτίο προγράμματος» (what the same
 *   class worked the previous 7 days, from the programme).
 * - `athlete`: a WOD assigned to athletes, with each athlete's coverage
 *   (only what they share with the box's coaches).
 *
 * Staff never see their own coverage here: that lives in the Ημερολόγιο.
 */
export type WodAtlasContext =
  | { kind: "member" }
  | { kind: "library" }
  | { kind: "class"; classId: string }
  | { kind: "athlete"; athletes: ReadonlyArray<{ id: string; name: string }> };

type View = "wod" | "load" | "athlete" | "explore";

/** The atlas of one WOD inside the goals sheet: every muscle in its role, drill-down and the box's exercises. */
export function WodAtlasView({
  muscles,
  context,
  initialNode = null,
}: {
  muscles: WodMuscle[];
  context: WodAtlasContext;
  /** The muscle tapped in the goals, if any. */
  initialNode?: MuscleNodeId | null;
}) {
  const t = useTranslations("Atlas");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const [view, setView] = useState<View>("wod");
  const [selected, setSelected] = useState<MuscleNodeId | null>(muscleNode(initialNode) ? initialNode : null);
  const athletes = context.kind === "athlete" ? context.athletes : [];
  const [athleteId, setAthleteId] = useState<string | null>(athletes[0]?.id ?? null);
  const athlete = athletes.find((candidate) => candidate.id === athleteId) ?? null;
  const classId = context.kind === "class" ? context.classId : null;

  const load = useQuery({
    queryKey: classProgrammeLoadKey(classId ?? ""),
    enabled: Boolean(token && classId),
    queryFn: () => fetchClassProgrammeLoad(token!, classId!),
    staleTime: 60_000,
  });
  const coverage = useQuery({
    queryKey: clientAtlasKey(athleteId ?? "", DEFAULT_ATLAS_RANGE),
    enabled: Boolean(token && athleteId && view === "athlete"),
    queryFn: () => fetchClientAtlas(token!, athleteId!, DEFAULT_ATLAS_RANGE),
    placeholderData: (previous) => previous,
  });
  const index = useMemo(() => indexCoverage(coverage.data?.nodes), [coverage.data]);
  const loadGroups = useMemo(() => load.data?.muscles ?? [], [load.data]);

  const highlights = useMemo(() => {
    if (view === "load") return programmeLoadHighlights(loadGroups);
    if (view === "athlete") return heatHighlights(index, selected);
    if (view === "explore") return exploreHighlights(selected);
    return wodHighlights(muscles);
  }, [index, loadGroups, muscles, selected, view]);

  const options: Array<{ value: View; label: string }> = [
    { value: "wod", label: t("mode.wod") },
    ...(classId ? [{ value: "load" as const, label: t("load.title") }] : []),
    ...(athlete ? [{ value: "athlete" as const, label: t("athlete.mode", { name: athlete.name }) }] : []),
    { value: "explore", label: t("mode.explore") },
  ];

  return (
    <div className="flex flex-col gap-3" data-testid="wod-atlas">
      <Segmented<View> ariaLabel={t("mode.label")} value={view} onChange={setView} options={options} />
      {view === "athlete" && athletes.length > 1 ? (
        <div role="group" aria-label={t("athlete.pick")} className="flex flex-wrap gap-2">
          {athletes.map((candidate) => (
            <button
              key={candidate.id}
              type="button"
              aria-pressed={candidate.id === athleteId}
              onClick={() => setAthleteId(candidate.id)}
              className="min-h-9 rounded-full px-3 text-xs font-semibold"
              style={{
                background: candidate.id === athleteId ? "color-mix(in srgb, var(--primary) 16%, var(--panel))" : "var(--panel)",
                border: `1px solid ${candidate.id === athleteId ? "var(--primary)" : "var(--border)"}`,
                color: "var(--text)",
              }}
            >
              {candidate.name}
            </button>
          ))}
        </div>
      ) : null}
      <div className="flex flex-col gap-2" data-testid="wod-atlas-figure">
        <AnatomyFigure highlights={highlights} view="both" interactive size="card" focus={selected} selected={selected} onPick={(id) => setSelected(id)} />
        {view === "wod" ? <RoleLegend /> : view === "explore" ? null : <HeatLegend />}
      </div>
      <section
        aria-live="polite"
        data-testid="wod-atlas-panel"
        className="flex min-w-0 flex-col gap-3 rounded-2xl p-3"
        style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      >
        <Breadcrumb selected={selected} onSelect={setSelected} />
        {view === "load" ? (
          load.isPending && token ? (
            <LoadingLine />
          ) : load.isError ? (
            <QueryProblem error={load.error} onRetry={() => void load.refetch()} />
          ) : (
            <ProgrammeLoadPanel groups={loadGroups} wods={load.data?.wods ?? 0} muscles={muscles} selected={selected} onSelect={setSelected} />
          )
        ) : view === "athlete" ? (
          coverage.isPending && token ? (
            <LoadingLine />
          ) : coverage.isError ? (
            <QueryProblem error={coverage.error} onRetry={() => void coverage.refetch()} />
          ) : (
            <AthletePanel
              name={athlete?.name ?? ""}
              index={index}
              sessions={coverage.data?.sessions ?? 0}
              muscles={muscles}
              selected={selected}
              onSelect={setSelected}
              token={token}
            />
          )
        ) : (
          <NodeOrList view={view} muscles={muscles} selected={selected} onSelect={setSelected} token={token} />
        )}
      </section>
      {context.kind === "member" ? (
        <Link
          href={atlasHref(selected, muscles)}
          className="self-start text-sm font-semibold"
          style={{ color: "var(--primary)" }}
          data-testid="wod-atlas-full"
        >
          {t("fullAtlas")}
        </Link>
      ) : null}
    </div>
  );
}

/** «Αυτό το WOD» lists the WOD's muscles, «Εξερεύνηση» the regions; a node shows itself. */
function NodeOrList({
  view,
  muscles,
  selected,
  onSelect,
  token,
}: {
  view: View;
  muscles: WodMuscle[];
  selected: MuscleNodeId | null;
  onSelect: (id: MuscleNodeId | null) => void;
  token: string | null;
}) {
  const t = useTranslations("Atlas");
  if (!selected) {
    return view === "explore" ? (
      <>
        <Heading>{t("body.title")}</Heading>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("body.hint")}</p>
        <ChildList ids={atlasChildren(null).map((child) => child.id)} index={EMPTY_INDEX} onSelect={onSelect} label={t("regions")} />
      </>
    ) : (
      <>
        <Heading>{t("wod.title")}</Heading>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("wod.hint")}</p>
        <WodMuscleList wod={muscles} onSelect={onSelect} />
      </>
    );
  }
  return <NodeDetails nodeId={selected} muscles={muscles} onSelect={onSelect} token={token} />;
}

const EMPTY_INDEX: CoverageIndex = new Map();

function Heading({ children }: { children: React.ReactNode }) {
  return (
    <h3 className="text-lg font-extrabold" style={{ color: "var(--text)" }} data-testid="wod-atlas-title">
      {children}
    </h3>
  );
}

/** A node: its name, its role in the WOD, what it does, its heads or groups, the box's exercises. */
function NodeDetails({
  nodeId,
  muscles,
  onSelect,
  token,
  children,
}: {
  nodeId: MuscleNodeId;
  muscles: WodMuscle[];
  onSelect: (id: MuscleNodeId | null) => void;
  token: string | null;
  /** Coverage or load lines of the current view, under the description. */
  children?: React.ReactNode;
}) {
  const t = useTranslations("Atlas");
  const anatomy = useTranslations("Anatomy");
  const node = muscleNode(nodeId);
  if (!node) return null;
  const aboutId = aboutNodeId(node.id);
  const heads = node.kind === "region" ? [] : node.kind === "group" ? childrenOf(node.id) : childrenOf(node.groupId ?? "");
  return (
    <>
      <Heading>{anatomy(`muscle.${node.id}`)}</Heading>
      <WodRoleLine wod={muscles} nodeId={node.id} />
      {aboutId ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{anatomy(`about.${aboutId}`)}</p> : null}
      {children}
      {heads.length > 0 ? (
        <div className="flex flex-col gap-1">
          <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("heads")}</p>
          <div className="flex flex-wrap gap-1.5">
            {heads.map((head) => (
              <button
                key={head.id}
                type="button"
                aria-pressed={head.id === node.id}
                onClick={() => onSelect(head.id === node.id ? head.groupId : head.id)}
                className="inline-flex min-h-9 items-center rounded-full px-3 text-xs font-semibold"
                style={{
                  background: head.id === node.id ? "color-mix(in srgb, var(--primary) 18%, var(--panel))" : "var(--panel-raised, var(--card))",
                  border: `1px solid ${head.id === node.id ? "var(--primary)" : "var(--border)"}`,
                  color: "var(--text)",
                }}
              >
                {anatomy(`muscle.${head.id}`)}
              </button>
            ))}
          </div>
        </div>
      ) : null}
      {node.kind === "region" ? (
        <ChildList ids={childrenOf(node.id).map((child) => child.id)} index={EMPTY_INDEX} onSelect={onSelect} label={t("groups")} />
      ) : (
        <NodeExercises nodeId={node.id} token={token} />
      )}
    </>
  );
}

/** A gym day (`YYYY-MM-DD`) as midday UTC, so its weekday reads the same in every zone. */
function gymDay(date: string): Date {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day, 12));
}

/** «Φορτίο προγράμματος»: the groups the class's last 7 days aimed at, the WOD's own ones flagged. */
function ProgrammeLoadPanel({
  groups,
  wods,
  muscles,
  selected,
  onSelect,
}: {
  groups: ProgrammeLoadGroup[];
  wods: number;
  muscles: WodMuscle[];
  selected: MuscleNodeId | null;
  onSelect: (id: MuscleNodeId | null) => void;
}) {
  const t = useTranslations("Atlas");
  const anatomy = useTranslations("Anatomy");
  const format = useFormatter();
  const wodGroups = new Set(muscles.map((muscle) => groupOf(muscle.id) ?? muscle.id));
  const repeated = groups.filter((group) => wodGroups.has(group.id) && group.wods >= 2);
  const days = (group: ProgrammeLoadGroup) =>
    format.list(group.dates.map((date) => format.dateTime(gymDay(date), { weekday: "short", timeZone: "UTC" })));

  if (selected) {
    const group = groups.find((candidate) => candidate.id === (groupOf(selected) ?? selected));
    return (
      <NodeDetails nodeId={selected} muscles={muscles} onSelect={onSelect} token={null}>
        <p className="rounded-xl p-3 text-sm" style={{ background: "var(--bg)", color: "var(--text-soft)" }} data-testid="wod-atlas-load-line">
          {group ? t("load.node", { count: group.wods, days: days(group) }) : t("load.nodeNone")}
        </p>
      </NodeDetails>
    );
  }
  return (
    <>
      <Heading>{t("load.title")}</Heading>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("load.hint", { count: wods })}</p>
      {repeated.length > 0 ? (
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }} data-testid="wod-atlas-load-repeat">
          {t("load.repeat", { muscles: format.list(repeated.map((group) => anatomy(`muscle.${group.id}`))) })}
        </p>
      ) : null}
      {groups.length === 0 ? (
        <EmptyNote>{t("load.empty")}</EmptyNote>
      ) : (
        <ul className="flex flex-col gap-1.5" data-testid="wod-atlas-load">
          {groups.map((group) => (
            <li key={group.id}>
              <button
                type="button"
                onClick={() => onSelect(group.id)}
                className="flex min-h-11 w-full items-center gap-3 rounded-xl px-3 py-2 text-start"
                style={{ background: "var(--panel-raised, var(--card))", border: "1px solid var(--border)" }}
              >
                <LevelDot level={programmeLoadLevel(group.wods)} />
                <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {anatomy(`muscle.${group.id}`)}
                </span>
                <span className="shrink-0 text-xs" style={{ color: "var(--text-soft)" }}>{t("load.count", { count: group.wods })}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}

/** An athlete's coverage under the WOD: their level on each WOD muscle, and a node's sets. */
function AthletePanel({
  name,
  index,
  sessions,
  muscles,
  selected,
  onSelect,
  token,
}: {
  name: string;
  index: CoverageIndex;
  sessions: number;
  muscles: WodMuscle[];
  selected: MuscleNodeId | null;
  onSelect: (id: MuscleNodeId | null) => void;
  token: string | null;
}) {
  const t = useTranslations("Atlas");
  const anatomy = useTranslations("Anatomy");
  const title = t("athlete.yours", { name, range: t(`range.${DEFAULT_ATLAS_RANGE}`) });
  if (selected) {
    return (
      <NodeDetails nodeId={selected} muscles={muscles} onSelect={onSelect} token={token}>
        <YourSets nodeId={selected} index={index} range={DEFAULT_ATLAS_RANGE} sessions={sessions} title={title} />
      </NodeDetails>
    );
  }
  return (
    <>
      <Heading>{t("athlete.mode", { name })}</Heading>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("athlete.hint", { name })}</p>
      {sessions === 0 ? <EmptyNote>{t("noData")}</EmptyNote> : null}
      <ul className="flex flex-col gap-1.5" data-testid="wod-atlas-athlete">
        {muscles.map((muscle) => {
          const level = coverageLevel(index, muscle.id);
          return (
            <li key={muscle.id}>
              <button
                type="button"
                onClick={() => onSelect(muscle.id)}
                className="flex min-h-11 w-full items-center gap-3 rounded-xl px-3 py-2 text-start"
                style={{ background: "var(--panel-raised, var(--card))", border: "1px solid var(--border)" }}
              >
                <LevelDot level={level} />
                <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {anatomy(`muscle.${muscle.id}`)}
                </span>
                <span className="shrink-0 text-xs" style={{ color: "var(--text-soft)" }}>{t(`level.${level}`)}</span>
              </button>
            </li>
          );
        })}
      </ul>
    </>
  );
}
