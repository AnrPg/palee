"use client";

import { Fragment, type ReactNode } from "react";

import { useMediaQuery } from "@/lib/use-media-query";

/**
 * Αρχική on wider screens (ANR's picks 2026-11-09):
 * - from 1280px (Tailwind `xl`, 80rem), three columns: reminders and the
 *   quote on the left, the feed in the middle, «Ίσως γνωρίζεις» on the right;
 * - from 1024px (`lg`, 64rem), two columns: the reminders stay above the
 *   feed and «Ίσως γνωρίζεις» moves to the right;
 * - below that, the phone's one column in the same order as always.
 */
export const HOME_THREE_COLUMNS_QUERY = "(min-width: 80rem)";
export const HOME_TWO_COLUMNS_QUERY = "(min-width: 64rem)";

export type HomeLayout = "one" | "two" | "three";

export type HomeColumn = "reminders" | "feed" | "people";

export type HomeCard = { key: string; column: HomeColumn; node: ReactNode };

/**
 * Lays out Αρχική's cards. Each card keeps its relative order in its column,
 * and the DOM order is always the order on screen, so keyboard and
 * screen-reader order follow what is seen. Side columns stay in view while
 * the feed scrolls and scroll on their own when taller than the screen.
 */
export function HomeColumns({ cards, layout }: { cards: HomeCard[]; layout: HomeLayout }) {
  const nodes = (keep: (card: HomeCard) => boolean) =>
    cards.filter(keep).map((card) => <Fragment key={card.key}>{card.node}</Fragment>);
  if (layout === "one") return <>{nodes(() => true)}</>;
  const people = <div className={SIDE_CLASS_NAME} style={SIDE_STYLE} data-home-column="people">{nodes((card) => card.column === "people")}</div>;
  if (layout === "two") {
    return (
      <div className="grid grid-cols-[minmax(0,36rem)_20rem] items-start justify-center gap-6" data-home-columns="two">
        <div className="flex min-w-0 flex-col gap-4" data-home-column="feed">{nodes((card) => card.column !== "people")}</div>
        {people}
      </div>
    );
  }
  return (
    <div className="grid grid-cols-[18.75rem_minmax(0,36rem)_20rem] items-start justify-center gap-6" data-home-columns="three">
      <div className={SIDE_CLASS_NAME} style={SIDE_STYLE} data-home-column="reminders">{nodes((card) => card.column === "reminders")}</div>
      <div className="flex min-w-0 flex-col gap-4" data-home-column="feed">{nodes((card) => card.column === "feed")}</div>
      {people}
    </div>
  );
}

/** The layout for the current window width. */
export function useHomeLayout(): HomeLayout {
  const three = useMediaQuery(HOME_THREE_COLUMNS_QUERY);
  const two = useMediaQuery(HOME_TWO_COLUMNS_QUERY);
  return three ? "three" : two ? "two" : "one";
}

// Sticky under the member top bar (which sets --top-bar-space while it shows)
// and above the floating bottom bar; p-1 with a -0.25rem margin keeps focus
// rings unclipped.
const SIDE_CLASS_NAME =
  "sticky flex flex-col gap-4 overscroll-contain p-1 [scrollbar-width:thin]";
const SIDE_STYLE = {
  top: "calc(var(--top-bar-space) + 1rem)",
  maxHeight: "calc(100dvh - var(--top-bar-space) - var(--bottom-nav-space) - 2rem)",
  margin: "-0.25rem",
  overflowY: "auto" as const,
};
