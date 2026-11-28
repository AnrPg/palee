import type { FinanceCleanupQuery, FinanceCleanupRecordType } from "@/api/finance";
import { addDaysToKey } from "@/lib/zoned-time";

// ADR-797: the filters of «Εκκαθάριση συναλλαγών» (Finance → Accounting and
// Settings → Finance). No filter is preset: without one the list shows the
// newest records, as before.

export type CleanupFilters = {
  /** Name, @handle, email or document number, in one field. */
  q: string;
  /** One customer (the «Πελάτης» filter). */
  userId: string;
  packageId: string;
  /** Inclusive ISO days on the gym's clock; "" = open. */
  from: string;
  to: string;
  kind: "" | FinanceCleanupRecordType;
};

export const EMPTY_CLEANUP_FILTERS: CleanupFilters = { q: "", userId: "", packageId: "", from: "", to: "", kind: "" };

export const CLEANUP_KINDS: FinanceCleanupRecordType[] = ["invoice", "receipt", "payment"];

export type CleanupQuickRange = "today" | "thisMonth" | "lastMonth" | "thisYear";

export const CLEANUP_QUICK_RANGES: CleanupQuickRange[] = ["today", "thisMonth", "lastMonth", "thisYear"];

/** Filters in force inside the filter form (the search text is not one). */
export function activeCleanupFilterCount(filters: CleanupFilters): number {
  return [filters.userId, filters.packageId, filters.from || filters.to, filters.kind].filter(Boolean).length;
}

/** The API query of the filters; `limit` and `cursor` are the page's. */
export function cleanupQuery(filters: CleanupFilters, page: { cursor?: string | null; limit?: number } = {}): FinanceCleanupQuery {
  const query: FinanceCleanupQuery = {};
  const q = filters.q.trim();
  if (q) query.q = q;
  if (filters.userId) query.user_id = filters.userId;
  if (filters.packageId) query.package_id = filters.packageId;
  if (filters.from) query.from = filters.from;
  if (filters.to) query.to = filters.to;
  if (filters.kind) query.kind = filters.kind;
  if (page.cursor) query.cursor = page.cursor;
  if (page.limit) query.limit = String(page.limit);
  return query;
}

/** The from–to days of a quick range, given today's ISO day on the gym's clock. */
export function quickRange(range: CleanupQuickRange, today: string): { from: string; to: string } {
  const [year, month] = today.split("-");
  const monthStart = `${year}-${month}-01`;

  switch (range) {
    case "today":
      return { from: today, to: today };
    case "thisMonth":
      return { from: monthStart, to: addDaysToKey(nextMonthStart(monthStart), -1) };
    case "lastMonth": {
      const lastMonthEnd = addDaysToKey(monthStart, -1);
      return { from: `${lastMonthEnd.slice(0, 7)}-01`, to: lastMonthEnd };
    }
    case "thisYear":
      return { from: `${year}-01-01`, to: `${year}-12-31` };
  }
}

/** The quick range the dates are exactly, if any (to highlight its chip). */
export function matchingQuickRange(filters: Pick<CleanupFilters, "from" | "to">, today: string): CleanupQuickRange | null {
  if (!filters.from || !filters.to) return null;
  return CLEANUP_QUICK_RANGES.find((range) => {
    const days = quickRange(range, today);
    return days.from === filters.from && days.to === filters.to;
  }) ?? null;
}

function nextMonthStart(monthStart: string): string {
  // The 28th plus 4 days is always in the next month.
  return `${addDaysToKey(addDaysToKey(monthStart, 27), 4).slice(0, 7)}-01`;
}
