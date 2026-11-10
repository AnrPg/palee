/**
 * ADR-595: one status for a member, worked out once on the server and shown
 * alike to the member and to staff: a badge, and one line under it saying
 * what it means and until when (the package kept after leaving, what is
 * owed and since when, the last day of a grace).
 */

export type Standing = {
  status: string;
  grace_until: string | null;
  access_until: string | null;
  outstanding_cents: number;
  unpaid_since: string | null;
  /** ADR-612: the grace or free access the box gave; its last day is `grace_until`. */
  benefit?: "grace" | "free_access" | null;
};

export type StandingPart =
  | { key: "linePackageUntil"; date: string }
  | { key: "lineOwed"; cents: number }
  | { key: "lineOwedSince"; cents: number; date: string }
  | { key: "lineGrace" | "lineBoxGrace" | "lineBoxFree"; date: string; days: number };

/** The local calendar day of `now`, as `YYYY-MM-DD`. */
export function localDay(now: Date) {
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

/** Whole days from `from` to `to` (both `YYYY-MM-DD`). */
export function daysBetween(from: string, to: string) {
  const day = (value: string) => {
    const [year, month, date] = value.slice(0, 10).split("-").map(Number);
    return Date.UTC(year, month - 1, date);
  };
  return Math.round((day(to) - day(from)) / 86_400_000);
}

/** The pieces of the line under the badge, in reading order; empty when there is nothing to add. */
export function standingParts(standing: Standing | null | undefined, today: string): StandingPart[] {
  if (!standing) return [];
  const parts: StandingPart[] = [];
  const access = standing.access_until?.slice(0, 10);
  if ((standing.status === "leaving" || standing.status === "former") && access && access >= today) {
    parts.push({ key: "linePackageUntil", date: access });
  }
  if (standing.outstanding_cents > 0) {
    parts.push(
      standing.unpaid_since
        ? { key: "lineOwedSince", cents: standing.outstanding_cents, date: standing.unpaid_since.slice(0, 10) }
        : { key: "lineOwed", cents: standing.outstanding_cents },
    );
  }
  const grace = standing.grace_until?.slice(0, 10);
  if (grace && grace >= today) {
    const key = standing.benefit === "grace" ? "lineBoxGrace" : standing.benefit === "free_access" ? "lineBoxFree" : "lineGrace";
    parts.push({ key, date: grace, days: daysBetween(today, grace) });
  }
  return parts;
}
