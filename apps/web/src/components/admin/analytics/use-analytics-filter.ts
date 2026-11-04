"use client";

import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { useCallback, useMemo } from "react";

import {
  analyticsApiQuery,
  analyticsFilterSearch,
  analyticsQueryKey,
  analyticsRange,
  parseAnalyticsFilter,
  type AnalyticsFilter,
} from "@/lib/analytics-filter";
import { useOrganizationTimeZone } from "@/lib/organization-slug";
import { dateKeyInZone } from "@/lib/zoned-time";

export type AnalyticsFilterState = {
  filter: AnalyticsFilter;
  setFilter: (filter: AnalyticsFilter) => void;
  /** The summary endpoints' query for this filter. */
  apiQuery: Record<string, string>;
  /** A stable string of `apiQuery`, for query keys. */
  queryKey: string;
  /** Days in the period (and in the one it is compared with). */
  days: number;
  today: string;
};

/**
 * ADR-462: the page filter of a «Στατιστικά» page, read from and written to
 * the URL query (so a link opens the same view). Writing replaces the
 * history entry and keeps the scroll position.
 */
export function useAnalyticsFilter(): AnalyticsFilterState {
  const searchParams = useSearchParams();
  const pathname = usePathname();
  const router = useRouter();
  const zone = useOrganizationTimeZone();
  const today = dateKeyInZone(new Date(), zone);
  const search = searchParams?.toString() ?? "";

  const filter = useMemo(() => parseAnalyticsFilter(new URLSearchParams(search)), [search]);

  const setFilter = useCallback(
    (next: AnalyticsFilter) => {
      const query = analyticsFilterSearch(next).toString();
      if (query === search) return;
      router.replace(query ? `${pathname}?${query}` : pathname, { scroll: false });
    },
    [pathname, router, search],
  );

  const apiQuery = useMemo(() => analyticsApiQuery(filter, today), [filter, today]);
  const days = useMemo(() => analyticsRange(filter, today).days, [filter, today]);

  return { filter, setFilter, apiQuery, queryKey: analyticsQueryKey(apiQuery), days, today };
}
