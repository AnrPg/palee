import type { AccessEvent, DoorOpenResult, DoorPeriod, DoorRules, DoorWho } from "@/api/doors";
import { ApiError } from "@/api/client";

/*
 * Pure rules of the door screens (W10 screens 4–6, ADR-381): the entry rules
 * form, the access log's filters and rows, and the member's one answer after
 * the door scan.
 */

export const DOOR_WHO: DoorWho[] = ["booked_or_covered", "members", "staff_only"];

export const DEFAULT_RULES: DoorRules = {
  who: "booked_or_covered",
  staff_always: true,
  window_before_minutes: 30,
  window_after_minutes: 15,
  unlock_seconds: 5,
  hours: [],
};

/** The door's saved rules over the defaults (the API stores them filled, but old rows may not be). */
export function rulesOf(raw: unknown): DoorRules {
  const value = (raw && typeof raw === "object" ? raw : {}) as Partial<DoorRules>;
  return {
    who: DOOR_WHO.includes(value.who as DoorWho) ? (value.who as DoorWho) : DEFAULT_RULES.who,
    staff_always: typeof value.staff_always === "boolean" ? value.staff_always : DEFAULT_RULES.staff_always,
    window_before_minutes: numberOr(value.window_before_minutes, DEFAULT_RULES.window_before_minutes),
    window_after_minutes: numberOr(value.window_after_minutes, DEFAULT_RULES.window_after_minutes),
    unlock_seconds: numberOr(value.unlock_seconds, DEFAULT_RULES.unlock_seconds),
    hours: Array.isArray(value.hours) ? value.hours.filter(isPeriod) : [],
  };
}

function numberOr(value: unknown, fallback: number) {
  return typeof value === "number" && Number.isInteger(value) ? value : fallback;
}

function isPeriod(value: unknown): value is DoorPeriod {
  const period = value as DoorPeriod;
  return Boolean(period) && Array.isArray(period.days) && typeof period.from === "string" && typeof period.to === "string";
}

/** The «Προχωρημένα» numbers, with the API's ranges. */
export const RULE_RANGES = {
  window_before_minutes: [0, 180],
  window_after_minutes: [0, 180],
  unlock_seconds: [1, 30],
} as const;

export function rangeError(key: keyof typeof RULE_RANGES, value: number) {
  const [min, max] = RULE_RANGES[key];
  return Number.isInteger(value) && value >= min && value <= max ? null : { min, max };
}

/** «06:30» ↔ minutes; "24:00" closes a day. */
export function periodError(period: DoorPeriod): "days" | "order" | null {
  if (period.days.length === 0) return "days";
  return toMinutes(period.to) > toMinutes(period.from) ? null : "order";
}

function toMinutes(clock: string) {
  const [hour, minute] = clock.split(":").map(Number);
  return (hour ?? 0) * 60 + (minute ?? 0);
}

/** Every half hour of a day, then 24:00, for the hours pickers. */
export const HALF_HOURS = [
  ...Array.from({ length: 48 }, (_, index) => `${String(Math.floor(index / 2)).padStart(2, "0")}:${index % 2 ? "30" : "00"}`),
  "24:00",
];

/** ISO weekdays, Monday first. */
export const WEEKDAYS = [1, 2, 3, 4, 5, 6, 7] as const;

// Access log (W10 screen 6 A) ------------------------------------------------------

export const LOG_FILTERS = ["all", "problems", "staff"] as const;
export type LogFilter = (typeof LOG_FILTERS)[number];

/** «Αρνήσεις και βλάβες»: refusals, failed openings and the controller's own events; «Προσωπικό»: desk openings. */
export function matchesLogFilter(event: Pick<AccessEvent, "kind" | "method">, filter: LogFilter) {
  if (filter === "problems") return event.kind === "denied" || event.kind === "unlock_failed" || event.kind === "door_event";
  if (filter === "staff") return event.kind === "staff_unlock" || (event.kind === "granted" && event.method === "staff");
  return true;
}

export type LogTone = "ok" | "warn" | "bad" | "manual";

export function logTone(kind: AccessEvent["kind"]): LogTone {
  switch (kind) {
    case "granted":
      return "ok";
    case "denied":
    case "door_event":
      return "warn";
    case "unlock_failed":
      return "bad";
    case "staff_unlock":
      return "manual";
  }
}

// The member's door answer (W10 screen 5 A) ----------------------------------------

export type DoorAnswer =
  | { kind: "opened"; door: string; seconds: number }
  | { kind: "denied"; reason: string; door: string | null }
  | { kind: "offline" }
  | { kind: "choose"; doors: { id: string; name: string }[] }
  | { kind: "none" }
  | { kind: "error" };

const DENIAL_REASONS = ["not_a_member", "outside_hours", "no_booking_in_window", "staff_only"];

/** The door's part of the one answer after a scan. A branch without doors says nothing. */
export function doorAnswer(result: DoorOpenResult | null, error: unknown): DoorAnswer {
  if (result) return result.opened ? { kind: "opened", door: result.door.name, seconds: result.seconds } : { kind: "error" };
  if (!(error instanceof ApiError)) return error ? { kind: "error" } : { kind: "none" };
  const params = (error.payload.params ?? {}) as { reason?: string; door?: { name?: string }; doors?: { id: string; name: string }[] };
  switch (error.payload.code) {
    case "no_door_here":
    case "door_disabled":
      return { kind: "none" };
    case "entry_denied":
      return { kind: "denied", reason: DENIAL_REASONS.includes(params.reason ?? "") ? params.reason! : "generic", door: params.door?.name ?? null };
    case "door_offline":
    case "door_unauthorized":
    case "door_refused":
      return { kind: "offline" };
    case "choose_door":
      return Array.isArray(params.doors) && params.doors.length > 0 ? { kind: "choose", doors: params.doors } : { kind: "error" };
    default:
      return { kind: "error" };
  }
}
