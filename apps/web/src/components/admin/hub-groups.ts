// The staff home's tool groups («Διαχείριση», «Περιεχόμενο», «Στατιστικά &
// Μάρκετινγκ»). ANR (2026-11-03): a group a role sees with a single tile looks
// empty, so that tile joins the first group and the group is not shown.

export type HubGroupLike<T> = { label: string; items: T[] };

/** Drops empty groups and folds every one-tile group into the first group that stays. */
export function foldSingleTileGroups<T>(groups: HubGroupLike<T>[]): HubGroupLike<T>[] {
  const filled = groups.filter((group) => group.items.length > 0);
  const keep = filled.filter((group) => group.items.length > 1);
  if (keep.length === 0) {
    // Nothing big enough to absorb them: one group holds every tile.
    return filled.length > 0 ? [{ label: filled[0].label, items: filled.flatMap((group) => group.items) }] : [];
  }
  const strays = filled.filter((group) => group.items.length === 1).flatMap((group) => group.items);
  return keep.map((group, index) => (index === 0 ? { ...group, items: [...group.items, ...strays] } : group));
}
