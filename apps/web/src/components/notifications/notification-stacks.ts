import type { NotificationRecord } from "@/api/notifications";

/**
 * ADR-600: the bell lists one row per stack of similar notifications (the
 * newest, with `stack`) and every notification that does not stack. These
 * helpers read such a row the same way whether it is a stack or not.
 */

/** How many notifications the row stands for. */
export function entryCount(entry: NotificationRecord) {
  return entry.stack?.count ?? 1;
}

/** How many of the row's notifications are unread. */
export function entryUnread(entry: NotificationRecord) {
  if (entry.stack) return entry.stack.unread_count;
  return entry.read_at ? 0 : 1;
}

/** A stack sits in «Νέο» while any of it is unread, else in «Αναγνωσμένα». */
export function isUnreadEntry(entry: NotificationRecord) {
  return entryUnread(entry) > 0;
}

/** Unread notifications across rows (every notification counts, not stacks). */
export function unreadAcross(entries: NotificationRecord[]) {
  return entries.reduce((sum, entry) => sum + entryUnread(entry), 0);
}

/** Notifications across rows. */
export function countAcross(entries: NotificationRecord[]) {
  return entries.reduce((sum, entry) => sum + entryCount(entry), 0);
}

/** The row with all of its notifications read (the closed eye). */
export function markEntryRead(entry: NotificationRecord, at: string): NotificationRecord {
  return {
    ...entry,
    read_at: entry.read_at ?? at,
    ...(entry.stack ? { stack: { ...entry.stack, unread_count: 0 } } : {}),
  };
}

/** Is the row a stack (as opposed to one notification)? */
export function isStack(entry: NotificationRecord): entry is NotificationRecord & {
  stack: NonNullable<NotificationRecord["stack"]>;
} {
  return Boolean(entry.stack);
}
