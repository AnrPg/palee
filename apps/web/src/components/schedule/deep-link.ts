/**
 * The query of a link that opens one class in a schedule: `open_slot` names
 * the class, `open_day` (YYYY-MM-DD, the gym's day) the day it is on. The day
 * is optional, since some links only know the class; a malformed one is
 * ignored rather than trusted.
 */
export type ScheduleDeepLink = { slotId: string | null; day: string | null };

const DAY = /^\d{4}-\d{2}-\d{2}$/;

export function scheduleDeepLink(params: Record<string, string | string[] | undefined>): ScheduleDeepLink {
  const first = (value: string | string[] | undefined) => (Array.isArray(value) ? value[0] : value) ?? null;
  const slotId = first(params.open_slot) || null;
  const day = first(params.open_day);
  return { slotId, day: slotId && day && DAY.test(day) ? day : null };
}
