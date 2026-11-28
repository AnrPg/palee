import type { ActivityLogEntry } from "@/api/activity-log";

/** A staff-view row for tests, with every required field. */
export function entry(overrides: Partial<ActivityLogEntry> = {}): ActivityLogEntry {
  return {
    id: "e1",
    occurred_at: "2026-11-23T11:20:00Z",
    action: "package.freeze",
    area: "packages",
    actor: { id: "s1", name: "Eleni S.", roles: ["front_desk"] },
    person: { id: "p1", name: "Maria K." },
    subject: {},
    subject_label: null,
    details: {},
    reason: null,
    reason_shared: false,
    sensitive: false,
    source: "request",
    redacted: false,
    ...overrides,
  };
}
