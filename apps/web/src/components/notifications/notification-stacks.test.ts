import { describe, expect, it } from "vitest";

import type { NotificationRecord } from "@/api/notifications";
import {
  countAcross,
  entryCount,
  entryUnread,
  isStack,
  isUnreadEntry,
  markEntryRead,
  unreadAcross,
} from "./notification-stacks";

function row(overrides: Partial<NotificationRecord> = {}): NotificationRecord {
  return {
    id: "n1",
    user_id: "u1",
    organization_id: null,
    type: "class_workout_missing",
    payload: {},
    read_at: null,
    inserted_at: "2026-11-10T10:00:00Z",
    ...overrides,
  };
}

const stack = row({ id: "s", read_at: "2026-11-10T11:00:00Z", stack: { key: "k", count: 15, unread_count: 1 } });

describe("notification stacks (ADR-600)", () => {
  it("a single notification counts as one", () => {
    expect(entryCount(row())).toBe(1);
    expect(entryUnread(row())).toBe(1);
    expect(entryUnread(row({ read_at: "2026-11-10T11:00:00Z" }))).toBe(0);
    expect(isStack(row())).toBe(false);
  });

  it("a stack is new while any of it is unread, even if its newest was read", () => {
    expect(isStack(stack)).toBe(true);
    expect(entryCount(stack)).toBe(15);
    expect(entryUnread(stack)).toBe(1);
    expect(isUnreadEntry(stack)).toBe(true);
  });

  it("sums every notification across rows", () => {
    expect(unreadAcross([stack, row()])).toBe(2);
    expect(countAcross([stack, row()])).toBe(16);
  });

  it("the closed eye reads every notification of a stack", () => {
    const read = markEntryRead(stack, "2026-11-10T12:00:00Z");
    expect(read.stack?.unread_count).toBe(0);
    expect(isUnreadEntry(read)).toBe(false);
    expect(markEntryRead(row(), "2026-11-10T12:00:00Z").read_at).toBe("2026-11-10T12:00:00Z");
  });
});
