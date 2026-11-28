import type { ActivityArea, ActivityLogEntry, MemberActivityEntry } from "@/api/activity-log";
import type { MembershipLike } from "@/lib/role-navigation";

/** ADR-760: the eleven areas, in the order the filter lists them. */
export const ACTIVITY_AREAS: readonly ActivityArea[] = [
  "members",
  "money",
  "packages",
  "classes",
  "training",
  "spaces",
  "shop",
  "community",
  "communication",
  "staff_pay",
  "settings",
];

/** Whether a membership reads any area of the log (`view_activity_<area>`, any scope). */
export function canReadActivityLog(membership: MembershipLike | null | undefined) {
  const capabilities = membership?.capabilities ?? {};
  return ACTIVITY_AREAS.some((area) => Boolean(capabilities[`view_activity_${area}`]));
}

/** The areas to offer in the filter: the reader's, in the canonical order. */
export function readableAreas(areas: readonly string[] | undefined): ActivityArea[] {
  const allowed = new Set(areas ?? []);
  return ACTIVITY_AREAS.filter((area) => allowed.has(area));
}

const dayFormatters = new Map<string, Intl.DateTimeFormat>();

/** The calendar day ("2026-11-23") a moment falls on in `zone` (the box's clock), or the device's. */
export function dayKey(iso: string, zone?: string | null) {
  const cacheKey = zone ?? "";
  let formatter = dayFormatters.get(cacheKey);
  if (!formatter) {
    try {
      formatter = new Intl.DateTimeFormat("en-CA", { year: "numeric", month: "2-digit", day: "2-digit", ...(zone ? { timeZone: zone } : {}) });
    } catch {
      formatter = new Intl.DateTimeFormat("en-CA", { year: "numeric", month: "2-digit", day: "2-digit" });
    }
    dayFormatters.set(cacheKey, formatter);
  }
  return formatter.format(new Date(iso));
}

export type DayGroup<T> = { day: string; entries: T[] };

/** Entries (newest first) grouped by the box's day, keeping their order (2A). */
export function groupByDay<T extends { occurred_at: string }>(entries: T[], zone?: string | null): DayGroup<T>[] {
  const groups: DayGroup<T>[] = [];
  for (const entry of entries) {
    const day = dayKey(entry.occurred_at, zone);
    const last = groups[groups.length - 1];
    if (last && last.day === day) last.entries.push(entry);
    else groups.push({ day, entries: [entry] });
  }
  return groups;
}

/** "today", "yesterday" or null for an older day, against `now` on the same clock. */
export function relativeDay(day: string, now: Date, zone?: string | null): "today" | "yesterday" | null {
  const today = dayKey(now.toISOString(), zone);
  if (day === today) return "today";
  const yesterday = dayKey(new Date(now.getTime() - 86_400_000).toISOString(), zone);
  return day === yesterday ? "yesterday" : null;
}

export type Change = { field: string; before: string | null; after: string | null };

/** What changed, before → after, as the use case noted it (redacted rows have none). */
export function changesOf(entry: Pick<ActivityLogEntry, "details" | "redacted">): Change[] {
  if (entry.redacted) return [];
  const raw = entry.details?.changes;
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((change) => change && typeof change.field === "string")
    .map((change) => ({ field: change.field, before: change.before ?? null, after: change.after ?? null }));
}

/** A period the row names (a freeze, a grace), as ISO days. */
export function periodOf(entry: Pick<ActivityLogEntry, "details" | "redacted">): { from: string; to: string | null } | null {
  if (entry.redacted) return null;
  const from = entry.details?.starts_on;
  const to = entry.details?.ends_on;
  if (typeof from === "string" && from) return { from, to: typeof to === "string" && to ? to : null };
  return null;
}

/** The person's name; a deleted account reads «Διαγραμμένο μέλος» (9A). */
export function personName(
  entry: Pick<MemberActivityEntry, "person" | "redacted">,
  deletedLabel: string,
): string | null {
  if (!entry.person) return null;
  if (entry.redacted || !entry.person.name) return deletedLabel;
  return entry.person.name;
}

/** A redacted row keeps no reason (9A), whatever the server sent. */
export function shownReason(entry: Pick<MemberActivityEntry, "reason" | "redacted">): string | null {
  if (entry.redacted) return null;
  const reason = entry.reason?.trim();
  return reason ? reason : null;
}

/** Roles the log names an actor by, most senior first. */
const ROLE_ORDER = ["owner", "admin", "accountant", "front_desk", "coach", "janitor"] as const;
export type StaffRole = (typeof ROLE_ORDER)[number];

export function mainRole(roles: readonly string[] | undefined): StaffRole | null {
  return ROLE_ORDER.find((role) => roles?.includes(role)) ?? null;
}

/** Staff seen in the loaded rows, for the «Ποιος» filter, by name. */
export function actorsOf(entries: ActivityLogEntry[]): Array<{ id: string; name: string }> {
  const seen = new Map<string, string>();
  for (const entry of entries) {
    if (entry.actor?.id && entry.actor.name && !seen.has(entry.actor.id)) seen.set(entry.actor.id, entry.actor.name);
  }
  return [...seen.entries()].map(([id, name]) => ({ id, name }));
}

/** The request body fields of the «Να το δει και το μέλος» choice (6A): always sent, unticked by default. */
export function sharedField(shared: boolean) {
  return { reason_shared: shared };
}
