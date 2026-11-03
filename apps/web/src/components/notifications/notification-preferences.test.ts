import { describe, expect, it } from "vitest";

import type { NotificationPreference } from "@/api/notifications";
import { applyChange, emailSwitch } from "@/components/notifications/notification-preferences";

const row = (channels: NotificationPreference["channels"], extra: Partial<NotificationPreference> = {}): NotificationPreference =>
  ({ category: "bookings", audience: "everyone", locked: false, channels, ...extra }) as NotificationPreference;

describe("applyChange (ADR-199)", () => {
  it("turns push off with the bell, and keeps the booking email", () => {
    expect(applyChange({ in_app: true, push: true, email: true }, { in_app: false })).toEqual({
      in_app: false,
      push: false,
      email: true,
    });
    expect(applyChange({ in_app: true, push: true, email: true }, { email: false })).toEqual({
      in_app: true,
      push: true,
      email: false,
    });
  });
});

describe("emailSwitch (ADR-392)", () => {
  it("shows the booking email only where the API offers email", () => {
    expect(emailSwitch(row({ in_app: true, push: true, email: true }))).toEqual({ on: true });
    expect(emailSwitch(row({ in_app: false, push: false, email: false }))).toEqual({ on: false });
    expect(emailSwitch(row({ in_app: true, push: true }, { category: "community" }))).toBeNull();
    expect(emailSwitch(row({ in_app: true, push: true, email: true }, { locked: true }))).toBeNull();
  });
});
