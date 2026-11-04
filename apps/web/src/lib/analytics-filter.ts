/**
 * ADR-462: the one filter of every staff «Στατιστικά» page (period bar +
 * «Φίλτρα»), kept in the URL query so a view can be shared as a link. The
 * query uses the API's own parameter names; anything unknown drops out.
 */

export const ANALYTICS_PERIODS = ["7", "30", "90", "ytd", "custom"] as const;
export type AnalyticsPeriod = (typeof ANALYTICS_PERIODS)[number];

export const ANALYTICS_LEVELS = ["beginner", "all_levels", "advanced"] as const;
export const ANALYTICS_TIMES_OF_DAY = ["morning", "midday", "afternoon", "evening"] as const;
export const ANALYTICS_TENURE_BANDS = ["lt_3m", "3_12m", "gt_12m"] as const;
export const ANALYTICS_AGE_BANDS = ["under_18", "18_34", "35_44", "45_54", "55_64", "65_plus", "unknown"] as const;
export const ANALYTICS_GENDERS = ["women", "men", "unknown"] as const;

/** Every filter dimension, in the order the sheet shows them. */
export const ANALYTICS_DIMENSIONS = [
  "location_ids",
  "class_type_ids",
  "levels",
  "coach_ids",
  "time_of_day",
  "package_ids",
  "tenure_bands",
  "age_bands",
  "genders",
] as const;
export type AnalyticsDimension = (typeof ANALYTICS_DIMENSIONS)[number];

/** Dimensions whose values are a fixed list (the rest are ids from the box). */
export const FIXED_DIMENSION_VALUES: Partial<Record<AnalyticsDimension, readonly string[]>> = {
  levels: ANALYTICS_LEVELS,
  time_of_day: ANALYTICS_TIMES_OF_DAY,
  tenure_bands: ANALYTICS_TENURE_BANDS,
  age_bands: ANALYTICS_AGE_BANDS,
  genders: ANALYTICS_GENDERS,
};

export type AnalyticsFilter = {
  period: AnalyticsPeriod;
  /** Gym-local dates of «Από…έως» (YYYY-MM-DD), only for `custom`. */
  from: string | null;
  to: string | null;
} & Record<AnalyticsDimension, string[]>;

export const DEFAULT_PERIOD: AnalyticsPeriod = "30";
export const MAX_DAYS = 731;

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_IDS = 200;

export function emptyAnalyticsFilter(): AnalyticsFilter {
  return {
    period: DEFAULT_PERIOD,
    from: null,
    to: null,
    location_ids: [],
    class_type_ids: [],
    levels: [],
    coach_ids: [],
    time_of_day: [],
    package_ids: [],
    tenure_bands: [],
    age_bands: [],
    genders: [],
  };
}

type QueryLike = { get(name: string): string | null } | Record<string, string | string[] | undefined>;

function read(params: QueryLike, name: string): string | null {
  if (typeof (params as { get?: unknown }).get === "function") return (params as { get(name: string): string | null }).get(name);
  const value = (params as Record<string, string | string[] | undefined>)[name];
  if (Array.isArray(value)) return value.join(",");
  return typeof value === "string" ? value : null;
}

function validDate(value: string | null) {
  if (!value || !DATE.test(value)) return null;
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value ? null : value;
}

function list(value: string | null, keep: (item: string) => boolean) {
  if (!value) return [];
  const items = Array.from(new Set(value.split(",").map((item) => item.trim()).filter(Boolean)));
  return items.filter(keep).slice(0, MAX_IDS).sort();
}

/** Reads the filter back from a URL query, defensively. */
export function parseAnalyticsFilter(params: QueryLike): AnalyticsFilter {
  const filter = emptyAnalyticsFilter();
  const period = read(params, "period");
  filter.period = (ANALYTICS_PERIODS as readonly string[]).includes(period ?? "") ? (period as AnalyticsPeriod) : DEFAULT_PERIOD;
  if (filter.period === "custom") {
    const from = validDate(read(params, "from"));
    const to = validDate(read(params, "to"));
    if (from && to && from > to) {
      filter.from = to;
      filter.to = from;
    } else {
      filter.from = from;
      filter.to = to;
    }
  }
  for (const dimension of ANALYTICS_DIMENSIONS) {
    const allowed = FIXED_DIMENSION_VALUES[dimension];
    filter[dimension] = list(read(params, dimension), (item) => (allowed ? allowed.includes(item) : ID.test(item)));
  }
  return filter;
}

/** The URL query of a filter: only what differs from the default. */
export function analyticsFilterSearch(filter: AnalyticsFilter): URLSearchParams {
  const search = new URLSearchParams();
  if (filter.period !== DEFAULT_PERIOD) search.set("period", filter.period);
  if (filter.period === "custom") {
    if (filter.from) search.set("from", filter.from);
    if (filter.to) search.set("to", filter.to);
  }
  for (const dimension of ANALYTICS_DIMENSIONS) {
    if (filter[dimension].length > 0) search.set(dimension, [...filter[dimension]].sort().join(","));
  }
  return search;
}

/** Number of dimension groups in force (the period is always shown, so it is not counted). */
export function activeFilterCount(filter: AnalyticsFilter, dimensions: readonly AnalyticsDimension[] = ANALYTICS_DIMENSIONS) {
  return dimensions.filter((dimension) => filter[dimension].length > 0).length;
}

export function clearDimensions(filter: AnalyticsFilter): AnalyticsFilter {
  return { ...emptyAnalyticsFilter(), period: filter.period, from: filter.from, to: filter.to };
}

function addDays(day: string, days: number) {
  const date = new Date(`${day}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function daysBetween(from: string, to: string) {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000) + 1;
}

/**
 * The gym-local dates the filter covers, both included. `today` is the
 * gym's local date. «Από…έως» with a missing end runs to today; a range
 * longer than the API allows is cut at its start.
 */
export function analyticsRange(filter: AnalyticsFilter, today: string): { from: string; to: string; days: number } {
  if (filter.period === "ytd") {
    const from = `${today.slice(0, 4)}-01-01`;
    return { from, to: today, days: daysBetween(from, today) };
  }
  if (filter.period === "custom" && (filter.from || filter.to)) {
    const to = filter.to ?? (filter.from && filter.from > today ? filter.from : today);
    let from = filter.from ?? addDays(to, -(Number(DEFAULT_PERIOD) - 1));
    if (daysBetween(from, to) > MAX_DAYS) from = addDays(to, -(MAX_DAYS - 1));
    return { from, to, days: daysBetween(from, to) };
  }
  const days = filter.period === "custom" ? Number(DEFAULT_PERIOD) : Number(filter.period);
  return { from: addDays(today, -(days - 1)), to: today, days };
}

/** The API query (`/admin/analytics/summary`, `/admin/finance/summary`): lists comma-separated. */
export function analyticsApiQuery(filter: AnalyticsFilter, today: string | null): Record<string, string> {
  const query: Record<string, string> = {};
  if ((filter.period === "7" || filter.period === "30" || filter.period === "90") || !today) {
    query.days = filter.period === "7" || filter.period === "90" ? filter.period : DEFAULT_PERIOD;
  } else {
    const range = analyticsRange(filter, today);
    query.from = range.from;
    query.to = range.to;
  }
  for (const dimension of ANALYTICS_DIMENSIONS) {
    if (filter[dimension].length > 0) query[dimension] = [...filter[dimension]].sort().join(",");
  }
  return query;
}

/** A stable string of an API query, for React Query keys. */
export function analyticsQueryKey(query: Record<string, string>) {
  return Object.keys(query)
    .sort()
    .map((key) => `${key}=${query[key]}`)
    .join("&");
}
