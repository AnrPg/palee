/**
 * Shared row layouts that never push content off a narrow phone (ANR
 * 2026-11-07: the unfollow confirm left the screen at 360px).
 *
 * Two shapes cover every row with buttons:
 *
 * - `itemRow`: who or what on the start side (`itemRowMain`), its actions on
 *   the end side (`itemRowActions`). When both no longer fit on one line the
 *   actions drop below and keep to the end side. When an action turns into an
 *   inline confirm (`ui/InlineConfirm`, marked `data-inline-confirm`), the
 *   actions take the whole line under the name, so the question is readable
 *   and the name it is about stays in view.
 * - `buttonRow`: two or more buttons side by side that wrap onto a second
 *   line rather than overflow. Long Greek and German labels need it.
 *
 * `components/ui/button-row-guard.test.ts` fails on a new button row that
 * cannot wrap.
 */

/** The row itself: wraps instead of overflowing. */
export const itemRow = "flex flex-wrap items-center gap-x-3 gap-y-2";

/** The name side: keeps at least 10rem (or the whole width) before the actions drop below. */
export const itemRowMain = "flex min-w-[min(100%,10rem)] flex-1 items-center gap-3";

/**
 * The actions side: never wider than the row, and the full line when one of
 * its actions asks to confirm.
 */
export const itemRowActions =
  "ms-auto flex min-w-0 max-w-full flex-wrap items-center justify-end gap-2 has-[[data-inline-confirm]]:basis-full";

/** Buttons side by side that wrap onto a second line on a narrow screen. */
export const buttonRow = "flex flex-wrap gap-2";
