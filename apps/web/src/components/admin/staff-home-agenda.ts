// Pure helpers for the staff home's «Σήμερα» agenda and the coach's own
// queues inside «Θέλει προσοχή» (staff home layout B, 2026-11-03): today's
// classes and the coach's appointments in one list by time, and the reply /
// technique-review / scaling queues as counted rows instead of three cards.

export type AgendaKind = "class" | "appointment";

export type AgendaItem<T> = { kind: AgendaKind; startsAt: string; entry: T };

/** Classes and appointments in one list, earliest first; classes win a tie. */
export function mergeAgenda<T>(
  classes: Array<{ startsAt: string; entry: T }>,
  appointments: Array<{ startsAt: string; entry: T }>,
): AgendaItem<T>[] {
  const items: AgendaItem<T>[] = [
    ...classes.map((item) => ({ kind: "class" as const, ...item })),
    ...appointments.map((item) => ({ kind: "appointment" as const, ...item })),
  ];
  return items.sort((a, b) => {
    const byTime = new Date(a.startsAt).getTime() - new Date(b.startsAt).getTime();
    if (byTime !== 0) return byTime;
    return a.kind === b.kind ? 0 : a.kind === "class" ? -1 : 1;
  });
}

type SlotLike = { starts_at: string; cancelled_at?: string | null };

/** Open (not cancelled) appointment slots, earliest first. Tolerates a malformed answer. */
export function openAppointmentSlots<T extends SlotLike>(slots: unknown): T[] {
  if (!Array.isArray(slots)) return [];
  return (slots as T[])
    .filter((slot) => slot && typeof slot.starts_at === "string" && !slot.cancelled_at)
    .sort((a, b) => a.starts_at.localeCompare(b.starts_at));
}

/** The slots that start on the same local day as `now`. */
export function slotsOnDay<T extends SlotLike>(slots: T[], now: Date = new Date()): T[] {
  return slots.filter((slot) => new Date(slot.starts_at).toDateString() === now.toDateString());
}

export type CoachQueueCounts = { replies: number; overdueReplies: number; formReviews: number; scaling: number };

/** Counts for the coach's queues; anything that is not a list counts as empty. */
export function coachQueueCounts(input: { replies?: unknown; formReviews?: unknown; scaling?: unknown }): CoachQueueCounts {
  const list = (value: unknown) => (Array.isArray(value) ? value : []);
  const replies = list(input.replies) as Array<{ overdue?: boolean } | null>;
  return {
    replies: replies.length,
    overdueReplies: replies.filter((item) => Boolean(item?.overdue)).length,
    formReviews: list(input.formReviews).length,
    scaling: list(input.scaling).length,
  };
}

/** Where each coach queue lives: the tabs of the coaching workspace. */
export const COACH_QUEUE_HREFS = {
  replies: "/admin/coaching?tab=replies",
  formReviews: "/admin/coaching?tab=form-reviews",
  scaling: "/admin/coaching?tab=scaling",
} as const;
