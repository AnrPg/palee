// ADR-580: pure helpers for Χρήστες › «Ακόλουθοι, όχι μέλη».
import type { BoxFollower } from "@/api/follower-invites";

export type FollowerRowState = "invitable" | "sent" | "declined";

/** What a row offers: «Προσκάλεσε», «Εστάλη» (90 days before the next) or «Δεν θέλει προσκλήσεις». */
export function followerRowState(row: Pick<BoxFollower, "invitable" | "invite">): FollowerRowState {
  if (row.invitable) return "invitable";
  return row.invite?.status === "declined" ? "declined" : "sent";
}

/** The people on screen who may be invited now. */
export function selectableIds(rows: Pick<BoxFollower, "invitable" | "invite" | "person">[]): string[] {
  return rows.filter((row) => followerRowState(row) === "invitable").map((row) => row.person.id);
}

/**
 * «Επιλογή όλων»: picks every selectable person on screen (never more than
 * `max` in all), or clears them when all are already picked.
 */
export function toggleAll(current: Set<string>, selectable: string[], max: number): Set<string> {
  const next = new Set(current);
  if (selectable.length > 0 && selectable.every((id) => next.has(id))) {
    selectable.forEach((id) => next.delete(id));
    return next;
  }
  for (const id of selectable) {
    if (next.size >= max) break;
    next.add(id);
  }
  return next;
}
