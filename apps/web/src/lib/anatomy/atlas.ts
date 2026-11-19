/**
 * Pure logic of the anatomy atlas screen (ADR-164): the breadcrumb path of a
 * node, what the figure paints in explore and heat-map mode, and lookups into
 * the member's coverage (`GET /api/me/atlas`). Free of React and three.js.
 */
import type { AnatomyHighlights, AnatomyRole } from "./figure";
import { childrenOf, MUSCLE_NODES, muscleNode, type MuscleNode, type MuscleNodeId } from "./taxonomy";

export const ATLAS_RANGES = ["1w", "4w", "12w"] as const;
export type AtlasRange = (typeof ATLAS_RANGES)[number];
export const DEFAULT_ATLAS_RANGE: AtlasRange = "4w";

export const COVERAGE_LEVELS = ["none", "low", "medium", "high"] as const;
export type CoverageLevel = (typeof COVERAGE_LEVELS)[number];

/** «Αυτό το WOD» paints every muscle of the WOD a member or coach came from. */
export type AtlasMode = "wod" | "explore" | "heat";

/** One node of the member's coverage, as the API returns it (missing fields tolerated). */
export type NodeCoverage = {
  id: string;
  sets?: number;
  per_week?: number;
  level?: string;
  felt?: number;
  top_exercises?: Array<{ exercise_ref: string; label?: string; sets: number }>;
};

export type CoverageIndex = ReadonlyMap<string, NodeCoverage>;

export function isAtlasRange(value: unknown): value is AtlasRange {
  return typeof value === "string" && (ATLAS_RANGES as readonly string[]).includes(value);
}

export function indexCoverage(nodes: readonly NodeCoverage[] | null | undefined): CoverageIndex {
  return new Map((nodes ?? []).filter((node) => node && typeof node.id === "string").map((node) => [node.id, node]));
}

export function coverageLevel(index: CoverageIndex, id: string): CoverageLevel {
  const level = index.get(id)?.level;
  return (COVERAGE_LEVELS as readonly string[]).includes(level ?? "") ? (level as CoverageLevel) : "none";
}

export function coverageSets(index: CoverageIndex, id: string): number {
  const sets = index.get(id)?.sets;
  return typeof sets === "number" && Number.isFinite(sets) ? sets : 0;
}

export function feltCount(index: CoverageIndex, id: string): number {
  const felt = index.get(id)?.felt;
  return typeof felt === "number" && Number.isFinite(felt) ? felt : 0;
}

/** Root first: [region, group?, head?]; [] for the whole body or an unknown id. */
export function atlasPath(id: MuscleNodeId | null): MuscleNode[] {
  const path: MuscleNode[] = [];
  let node = muscleNode(id);
  while (node) {
    path.unshift(node);
    node = muscleNode(node.parentId);
  }
  return path;
}

/** What a level lists below it: regions for the body, groups for a region, heads for a group. */
export function atlasChildren(id: MuscleNodeId | null): MuscleNode[] {
  if (id == null) return MUSCLE_NODES.filter((node) => node.kind === "region");
  return childrenOf(id);
}

/** The group whose description a node shows (a head reuses its group's); null for regions. */
export function aboutNodeId(id: MuscleNodeId): MuscleNodeId | null {
  const node = muscleNode(id);
  if (!node || node.kind === "region") return null;
  return node.groupId;
}

export const HEAT_ROLE: Record<Exclude<CoverageLevel, "none">, AnatomyRole> = {
  low: "heat-low",
  medium: "heat-medium",
  high: "heat-high",
};

/**
 * Explore mode: the selected region lightly, the selected group strongly; a
 * selected head strongly inside its lightly painted group.
 */
export function exploreHighlights(selected: MuscleNodeId | null): AnatomyHighlights {
  const node = muscleNode(selected);
  if (!node) return {};
  if (node.kind === "region") return { [node.id]: "secondary" };
  if (node.kind === "group") return { [node.id]: "primary" };
  return node.groupId ? { [node.groupId]: "secondary", [node.id]: "primary" } : { [node.id]: "primary" };
}

/**
 * Heat-map mode: every group in the colour of its coverage level. Inside the
 * selected group (or the group of a selected head) its heads show their own
 * level instead, so drilling down reveals which head did the work.
 */
export function heatHighlights(index: CoverageIndex, selected: MuscleNodeId | null): AnatomyHighlights {
  const node = muscleNode(selected);
  const openGroup = node && node.kind !== "region" ? node.groupId : null;
  const highlights: AnatomyHighlights = {};
  for (const group of MUSCLE_NODES) {
    if (group.kind !== "group") continue;
    const heads = childrenOf(group.id);
    const targets = group.id === openGroup && heads.length > 0 ? heads : [group];
    for (const target of targets) {
      const level = coverageLevel(index, target.id);
      if (level !== "none") highlights[target.id] = HEAT_ROLE[level];
    }
  }
  return highlights;
}

/** A WOD's muscle in its role, as the atlas carries it in the URL. */
export const WOD_ROLES = ["primary", "secondary", "stabilizer"] as const;
export type WodRole = (typeof WOD_ROLES)[number];
export type WodMuscle = { id: MuscleNodeId; role: WodRole };

/**
 * The WOD's muscles as query params, one list per role
 * (`primary=a,b&secondary=c&stabilizer=d`): readable, bookmarkable, and
 * independent of who may fetch the workout (a coach's draft, a member's class).
 */
export function wodAtlasParams(muscles: readonly WodMuscle[]): URLSearchParams {
  const params = new URLSearchParams();
  for (const role of WOD_ROLES) {
    const ids = muscles.filter((muscle) => muscle.role === role && muscleNode(muscle.id)).map((muscle) => muscle.id);
    if (ids.length > 0) params.set(role, [...new Set(ids)].join(","));
  }
  return params;
}

/**
 * Reads the WOD's muscles back from the URL: unknown ids are dropped and a
 * muscle listed under two roles keeps the stronger one, in role order.
 */
export function parseWodMuscles(params: Pick<URLSearchParams, "get">): WodMuscle[] {
  const seen = new Set<MuscleNodeId>();
  const muscles: WodMuscle[] = [];
  for (const role of WOD_ROLES) {
    for (const raw of (params.get(role) ?? "").split(",")) {
      const id = raw.trim();
      if (!id || seen.has(id) || !muscleNode(id)) continue;
      seen.add(id);
      muscles.push({ id, role });
    }
  }
  return muscles;
}

/** The role a node plays in the WOD: its own, or else the strongest of the heads below it or the group above it. */
export function wodRoleOf(muscles: readonly WodMuscle[], id: MuscleNodeId | null): WodRole | null {
  const node = muscleNode(id);
  if (!node) return null;
  const direct = muscles.find((muscle) => muscle.id === node.id);
  if (direct) return direct.role;
  const related = muscles.filter((muscle) => {
    const other = muscleNode(muscle.id);
    if (!other) return false;
    if (node.kind === "region") return atlasPath(other.id)[0]?.id === node.id;
    if (node.kind === "group") return other.groupId === node.id;
    return other.id === node.groupId;
  });
  for (const role of WOD_ROLES) if (related.some((muscle) => muscle.role === role)) return role;
  return null;
}

/** «Αυτό το WOD»: every muscle of the WOD in its role colour, whatever is selected. */
export function wodHighlights(muscles: readonly WodMuscle[]): AnatomyHighlights {
  const highlights: AnatomyHighlights = {};
  for (const muscle of muscles) if (muscleNode(muscle.id)) highlights[muscle.id] = muscle.role;
  return highlights;
}

/**
 * `/journal/atlas`, optionally opened on a node (from WOD goals or Πρόοδος ›
 * Μυϊκή κάλυψη) and on a WOD's muscles («Αυτό το WOD»).
 */
export function atlasHref(nodeId?: MuscleNodeId | null, wod: readonly WodMuscle[] = []): string {
  const params = wodAtlasParams(wod);
  if (nodeId && muscleNode(nodeId)) params.set("node", nodeId);
  const query = params.toString().replace(/%2C/gi, ",");
  return query ? `/journal/atlas?${query}` : "/journal/atlas";
}
