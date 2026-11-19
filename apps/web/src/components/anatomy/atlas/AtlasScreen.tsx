"use client";

import { useMemo, useState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { fetchMyAtlas, myAtlasKey, type MyAtlas } from "@/api/atlas";
import { AnatomyFigure } from "@/components/anatomy/AnatomyFigure";
import { ClientPage, LoadingLine, QueryProblem } from "@/components/client/ClientPage";
import { useSession } from "@/components/session-provider";
import { BackButton } from "@/components/ui/BackLink";
import { RoleLegend, Segmented } from "@/components/wod-goals/GoalChips";
import {
  aboutNodeId,
  ATLAS_RANGES,
  atlasChildren,
  atlasHref,
  coverageLevel,
  DEFAULT_ATLAS_RANGE,
  exploreHighlights,
  heatHighlights,
  indexCoverage,
  parseWodMuscles,
  wodHighlights,
  type AtlasMode,
  type AtlasRange,
  type CoverageIndex,
  type WodMuscle,
} from "@/lib/anatomy/atlas";
import { childrenOf, isMuscleNodeId, muscleNode, type MuscleNodeId } from "@/lib/anatomy/taxonomy";

import {
  Breadcrumb,
  ChildList,
  EmptyNote,
  HeatLegend,
  LevelDot,
  NodeExercises,
  WodMuscleList,
  WodRoleLine,
  YourSets,
} from "./atlas-parts";

/**
 * Ημερολόγιο › Πρόοδος › Άτλαντας (ADR-164, vision §7.6): the rotatable body
 * with three levels (region › group › head), what each muscle does, the
 * member's own sets in the range with a coverage level, what they felt, and
 * the exercises that train it with the gym's videos. «Η κάλυψή μου» paints
 * the body by recent volume. `?node=` opens it on a node (WOD goals,
 * Πρόοδος › Μυϊκή κάλυψη); `?primary=&secondary=&stabilizer=` carry a WOD's
 * muscles and open «Αυτό το WOD», which paints them all in their roles.
 */
export function AtlasScreen() {
  const t = useTranslations("Atlas");
  const router = useRouter();
  const searchParams = useSearchParams();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;

  const initial = searchParams.get("node");
  // The WOD comes with the link and never changes on this page.
  const [wod] = useState<WodMuscle[]>(() => parseWodMuscles(searchParams));
  const hasWod = wod.length > 0;
  const [selected, setSelected] = useState<MuscleNodeId | null>(initial && isMuscleNodeId(initial) ? initial : null);
  const [mode, setMode] = useState<AtlasMode>(hasWod ? "wod" : "explore");
  const [range, setRange] = useState<AtlasRange>(DEFAULT_ATLAS_RANGE);

  const atlas = useQuery({
    queryKey: myAtlasKey(range),
    enabled: Boolean(token),
    queryFn: () => fetchMyAtlas(token!, range),
    placeholderData: (previous) => previous,
  });
  const index = useMemo(() => indexCoverage(atlas.data?.nodes), [atlas.data]);
  const highlights = useMemo(
    () => (mode === "heat" ? heatHighlights(index, selected) : mode === "wod" ? wodHighlights(wod) : exploreHighlights(selected)),
    [index, mode, selected, wod],
  );

  const select = (id: MuscleNodeId | null) => {
    setSelected(id);
    router.replace(atlasHref(id, wod), { scroll: false });
  };

  // Coming from a WOD, «Πίσω» returns to it (the class, the day, the workout);
  // opened directly, the page has no history and goes to Πρόοδος.
  const back = () => {
    if (window.history.length > 1) router.back();
    else router.push("/journal/progress");
  };

  return (
    <ClientPage
      title={t("title")}
      actions={
        hasWod ? (
          <BackButton onClick={back} data-testid="atlas-back">
            {t("backToWod")}
          </BackButton>
        ) : (
          <Link href="/journal/progress" className="text-sm font-semibold" style={{ color: "var(--primary)" }}>
            {t("back")}
          </Link>
        )
      }
    >
      <div className="flex flex-col gap-3">
        <Segmented<AtlasMode>
          ariaLabel={t("mode.label")}
          value={mode}
          onChange={setMode}
          options={[
            ...(hasWod ? [{ value: "wod" as const, label: t("mode.wod") }] : []),
            { value: "explore", label: t("mode.explore") },
            { value: "heat", label: t("mode.heat") },
          ]}
        />
        <div role="group" aria-label={t("range.label")} className="flex gap-2">
          {ATLAS_RANGES.map((value) => (
            <button
              key={value}
              type="button"
              aria-pressed={range === value}
              onClick={() => setRange(value)}
              className="min-h-9 rounded-full px-3 text-xs font-semibold"
              style={{
                background: range === value ? "color-mix(in srgb, var(--primary) 16%, var(--panel))" : "var(--panel)",
                border: `1px solid ${range === value ? "var(--primary)" : "var(--border)"}`,
                color: range === value ? "var(--text)" : "var(--text-soft)",
              }}
            >
              {t(`range.${value}`)}
            </button>
          ))}
        </div>
      </div>

      <div className="grid items-start gap-4 md:grid-cols-2">
        <div className="flex flex-col gap-2" data-testid="atlas-figure">
          <AnatomyFigure
            highlights={highlights}
            view="both"
            interactive
            size="full"
            // On a phone the panel sits under the figure; keep it in reach.
            className="max-md:h-[48vh]"
            focus={selected}
            onPick={(id) => select(id)}
          />
          {mode === "heat" ? <HeatLegend /> : mode === "wod" ? <RoleLegend /> : null}
        </div>
        <section
          aria-live="polite"
          data-testid="atlas-panel"
          className="flex min-w-0 flex-col gap-4 rounded-2xl p-4"
          style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
        >
          <Breadcrumb selected={selected} onSelect={select} />
          {atlas.isPending && token ? (
            <LoadingLine />
          ) : atlas.isError ? (
            <QueryProblem error={atlas.error} onRetry={() => void atlas.refetch()} />
          ) : (
            <NodePanel selected={selected} index={index} atlas={atlas.data ?? null} range={range} onSelect={select} token={token} wod={hasWod ? wod : null} wodMode={mode === "wod"} />
          )}
        </section>
      </div>
    </ClientPage>
  );
}

function NodePanel({
  selected,
  index,
  atlas,
  range,
  onSelect,
  token,
  wod,
  wodMode,
}: {
  selected: MuscleNodeId | null;
  index: CoverageIndex;
  atlas: MyAtlas | null;
  range: AtlasRange;
  onSelect: (id: MuscleNodeId | null) => void;
  token: string | null;
  /** The WOD the atlas was opened from, if any. */
  wod: WodMuscle[] | null;
  /** «Αυτό το WOD» is the view: the body level lists the WOD's muscles instead of the regions. */
  wodMode: boolean;
}) {
  const t = useTranslations("Atlas");
  const anatomy = useTranslations("Anatomy");
  const node = muscleNode(selected);
  const sessions = atlas?.sessions ?? 0;
  const unrecognized = atlas?.exercises?.unrecognized ?? 0;

  if (!node && wod && wodMode) {
    return (
      <>
        <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{t("wod.title")}</h2>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("wod.hint")}</p>
        <WodMuscleList wod={wod} onSelect={onSelect} />
      </>
    );
  }

  if (!node) {
    return (
      <>
        <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{t("body.title")}</h2>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("body.hint")}</p>
        {sessions === 0 ? <EmptyNote>{t("noData")}</EmptyNote> : null}
        <ChildList ids={atlasChildren(null).map((child) => child.id)} index={index} onSelect={onSelect} label={t("regions")} />
        {unrecognized > 0 ? (
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("unrecognized", { count: unrecognized })}</p>
        ) : null}
      </>
    );
  }

  const aboutId = aboutNodeId(node.id);
  const heads = node.kind === "region" ? [] : node.kind === "group" ? childrenOf(node.id) : childrenOf(node.groupId ?? "");
  return (
    <>
      <h2 className="text-xl font-extrabold" style={{ color: "var(--text)" }} data-testid="atlas-node-title">
        {anatomy(`muscle.${node.id}`)}
      </h2>
      {wod ? <WodRoleLine wod={wod} nodeId={node.id} /> : null}
      {aboutId ? <p className="text-sm" style={{ color: "var(--text-soft)" }}>{anatomy(`about.${aboutId}`)}</p> : null}
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
                className="inline-flex min-h-9 items-center gap-1.5 rounded-full px-3 text-xs font-semibold"
                style={{
                  background: head.id === node.id ? "color-mix(in srgb, var(--primary) 18%, var(--panel))" : "var(--panel-raised, var(--card))",
                  border: `1px solid ${head.id === node.id ? "var(--primary)" : "var(--border)"}`,
                  color: "var(--text)",
                }}
              >
                <LevelDot level={coverageLevel(index, head.id)} />
                {anatomy(`muscle.${head.id}`)}
              </button>
            ))}
          </div>
        </div>
      ) : null}
      <YourSets nodeId={node.id} index={index} range={range} sessions={sessions} />
      {node.kind === "region" ? (
        <ChildList ids={childrenOf(node.id).map((child) => child.id)} index={index} onSelect={onSelect} label={t("groups")} />
      ) : (
        <NodeExercises nodeId={node.id} token={token} />
      )}
    </>
  );
}

