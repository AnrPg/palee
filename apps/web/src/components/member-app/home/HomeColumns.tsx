"use client";

import { Fragment, type ReactNode } from "react";

/**
 * Αρχική on wide screens (ANR 2026-11-09): reminders and the quote on the
 * left, the feed in the middle, «Ίσως γνωρίζεις» on the right. Matches
 * Tailwind's `xl` (80rem = 1280px), the first width where 300 + 320px side
 * columns fit without narrowing the feed. Below it Αρχική is the phone's one
 * column, in the same order as always.
 */
export const HOME_COLUMNS_QUERY = "(min-width: 80rem)";

export type HomeColumn = "reminders" | "feed" | "people";

export type HomeCard = { key: string; column: HomeColumn; node: ReactNode };

/**
 * Lays out Αρχική's cards: one column in the given order, or three columns
 * where each card keeps its relative order. The DOM order is always the
 * order on screen, so keyboard and screen-reader order follow what is seen.
 * The side columns stay in view while the feed scrolls and scroll on their
 * own when they are taller than the screen.
 */
export function HomeColumns({ cards, wide }: { cards: HomeCard[]; wide: boolean }) {
  if (!wide) {
    return (
      <>
        {cards.map((card) => (
          <Fragment key={card.key}>{card.node}</Fragment>
        ))}
      </>
    );
  }
  const column = (name: HomeColumn) =>
    cards.filter((card) => card.column === name).map((card) => <Fragment key={card.key}>{card.node}</Fragment>);
  return (
    <div className="grid grid-cols-[18.75rem_minmax(0,36rem)_20rem] items-start justify-center gap-6" data-home-columns>
      <div className={SIDE} data-home-column="reminders">{column("reminders")}</div>
      <div className="flex min-w-0 flex-col gap-4" data-home-column="feed">{column("feed")}</div>
      <div className={SIDE} data-home-column="people">{column("people")}</div>
    </div>
  );
}

// Sticky under the member top bar (which sets --top-bar-space while it shows)
// and above the floating bottom bar; p-1/-m-1 keeps focus rings unclipped.
const SIDE =
  "sticky top-[calc(var(--top-bar-space)+1rem)] -m-1 flex max-h-[calc(100dvh-var(--top-bar-space)-var(--bottom-nav-space)-2rem)] flex-col gap-4 overflow-y-auto overscroll-contain p-1 [scrollbar-width:thin]";
