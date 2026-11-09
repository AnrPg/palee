import type { TaxonomyTree } from "./taxonomy";

type SeedMuscle = { id: string; name: string; position: number; kind: "region" | "group" | "head"; ta2_ids: string[]; parent_id: string | null };
export type ReferenceSeed = { taxonomy_version: number; muscles: SeedMuscle[]; qualities: { id: string; position: number }[] };

/**
 * ADR-560: the muscle tree and the qualities of the API's reference catalog
 * seed (`apps/api/priv/repo/reference/exercise_catalog_seed_*.json`, the rows
 * the reference tables start from), in the tuple shape of `taxonomy.ts`.
 * Used by the test that keeps `taxonomy.ts` and `qualities.ts` in step.
 */
export function taxonomyFromSeed(seed: ReferenceSeed): { version: number; tree: TaxonomyTree; qualities: string[] } {
  const children = (parent: string | null) =>
    seed.muscles.filter((muscle) => muscle.parent_id === parent).sort((a, b) => a.position - b.position);
  const tree: TaxonomyTree = children(null).map((region) => [
    region.id,
    region.name,
    children(region.id).map((group) => [
      group.id,
      group.name,
      group.ta2_ids,
      children(group.id).map((head) => [head.id, head.name, head.ta2_ids] as const),
    ] as const),
  ] as const);
  const qualities = [...seed.qualities].sort((a, b) => a.position - b.position).map((quality) => quality.id);
  return { version: seed.taxonomy_version, tree, qualities };
}
