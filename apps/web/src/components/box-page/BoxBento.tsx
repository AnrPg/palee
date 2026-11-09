import type { ReactNode } from "react";

/**
 * One block of the box page (ANR 2026-11-09, layout C «bento»). `wide`
 * blocks go in the left column on desktop, `narrow` ones in the right;
 * `plain` blocks get no card (a tab's own list); `desktopHidden` blocks show
 * only on phones (the info card already says it on desktop).
 */
export type BentoItem = { key: string; size: "wide" | "narrow"; node: ReactNode; plain?: boolean; desktopHidden?: boolean };

/**
 * Phones: one column in the given order (the owner's order on a website).
 * Desktop: two columns of rounded cards, wide on the left (7/12) and narrow
 * on the right (5/12) under `aside`. Each column keeps the given order, so a
 * tall card never leaves a hole beside it. The two column wrappers are
 * `display: contents` on phones and `order` puts the blocks back in the
 * given order there; a block with nothing to show leaves no empty card.
 */
export function BoxBento({ items, aside = null, testId = "box-bento" }: { items: BentoItem[]; aside?: ReactNode; testId?: string }) {
  const block = (item: BentoItem, index: number) => (
    <div
      key={item.key}
      className={`min-w-0 empty:hidden ${item.plain ? "" : "lg:rounded-3xl lg:border lg:border-(--border) lg:bg-(--panel) lg:p-6"} ${item.desktopHidden ? "lg:hidden" : ""}`}
      style={{ order: index }}
      data-bento={item.key}
    >
      {item.node}
    </div>
  );
  const indexed = items.map((item, index) => ({ item, index }));
  return (
    <div className="flex flex-col gap-8 lg:grid lg:grid-cols-[minmax(0,7fr)_minmax(0,5fr)] lg:items-start lg:gap-5" data-testid={testId}>
      <div className="contents lg:flex lg:min-w-0 lg:flex-col lg:gap-5">
        {indexed.filter(({ item }) => item.size === "wide").map(({ item, index }) => block(item, index))}
      </div>
      <div className="contents lg:flex lg:min-w-0 lg:flex-col lg:gap-5">
        {aside}
        {indexed.filter(({ item }) => item.size === "narrow").map(({ item, index }) => block(item, index))}
      </div>
    </div>
  );
}
