import type { NotificationChannel, NotificationPreference } from "@/api/notifications";

/**
 * ADR-199: a change of one category's switches, as the screen shows it at
 * once. A push is made from the bell's notification, so turning the bell off
 * turns push off too. The booking email (ADR-392) does not depend on the bell.
 */
export function applyChange(
  channels: NotificationPreference["channels"],
  change: Partial<Record<NotificationChannel, boolean>>,
): NotificationPreference["channels"] {
  const next = { ...channels, ...change };
  return next.in_app === false ? { ...next, push: false } : next;
}

/**
 * ADR-392: «Email κράτησης με ημερολόγιο», the one email switch, shown under
 * a category only when the API offers that category an email channel (today
 * only bookings). Null when there is nothing to show.
 */
export function emailSwitch(row: NotificationPreference): { on: boolean } | null {
  if (row.locked || !("email" in row.channels)) return null;
  return { on: row.channels.email !== false };
}
