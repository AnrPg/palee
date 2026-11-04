import type { components } from "@/api/generated/schema";

/**
 * The programme page (board 2κ/2μ A): the facts under the title, the free
 * preview days and the weeks as accordions. Pure, and tolerant of a payload
 * with fields missing or of the wrong shape (e2e stubs answer `{}`).
 */
export type EquipmentKey = components["schemas"]["EquipmentKey"];

export const EQUIPMENT_KEYS: readonly EquipmentKey[] = [
  "none",
  "barbell",
  "dumbbell",
  "kettlebell",
  "bench",
  "box",
  "pull_up_bar",
  "rings",
  "dip_bars",
  "climbing_rope",
  "ghd",
  "jump_rope",
  "wall_ball",
  "sled",
  "rower",
  "bike",
  "air_bike",
  "ski_erg",
  "pool",
  "band",
  "foam_roller",
];

/** The fields of a programme card or page this model reads; every one may be missing. */
export type ProgrammeShape = {
  weeks?: unknown;
  sessions_per_week?: unknown;
  minutes_per_session?: unknown;
  main_equipment?: unknown;
  preview?: unknown;
  week_outline?: unknown;
  refund_policy?: unknown;
  cover_url?: unknown;
};

export function positiveInt(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? Math.round(value) : null;
}

/** The equipment keys the app knows, in the API's order, without repeats. */
export function knownEquipment(value: unknown): EquipmentKey[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.filter((key): key is EquipmentKey => (EQUIPMENT_KEYS as readonly unknown[]).includes(key)))];
}

export type ProgrammeFacts = {
  weeks: number | null;
  perWeek: number | null;
  /** «Περίπου ανά προπόνηση»: only when the API knows it (ADR-542). */
  minutes: number | null;
  /** «Κύριος εξοπλισμός»: the first two keys; empty hides the fact. */
  equipment: EquipmentKey[];
};

export function programmeFacts(programme: ProgrammeShape | null | undefined): ProgrammeFacts {
  return {
    weeks: positiveInt(programme?.weeks),
    perWeek: positiveInt(programme?.sessions_per_week),
    minutes: positiveInt(programme?.minutes_per_session),
    equipment: knownEquipment(programme?.main_equipment).slice(0, 2),
  };
}

/** The cover photo's address, or null for the theme colour strip (ADR-541). */
export function coverUrl(programme: ProgrammeShape | null | undefined): string | null {
  const value = programme?.cover_url;
  return typeof value === "string" && /^(https?:\/\/|\/)/.test(value) ? value : null;
}

export const REFUND_POLICIES = ["before_start", "withdrawal_only", "pro_rata"] as const;
export type RefundPolicy = (typeof REFUND_POLICIES)[number];

/** The refund rule the buy bar names; an unknown one names nothing. */
export function refundPolicy(programme: ProgrammeShape | null | undefined): RefundPolicy | null {
  const value = programme?.refund_policy;
  return (REFUND_POLICIES as readonly unknown[]).includes(value) ? (value as RefundPolicy) : null;
}

export type OutlineDay = {
  /** 0-based day of the programme. */
  day: number;
  week: number;
  /** 1-based day within its week («Ημ. 3»). */
  dayOfWeek: number;
  titles: string[];
};

export type OutlineWeek = {
  /** First and last week (1-based) the accordion covers; equal for a single week. */
  from: number;
  to: number;
  open: OutlineDay[];
  /** WODs behind the lock in these weeks. */
  locked: number;
  /**
   * A single week's seven days from the API's outline (free days with their
   * WODs, locked days with type and length, rest); null when the payload has
   * no day outline (older API) or the accordion covers several weeks.
   */
  days: OutlineRow[] | null;
};

export type OutlineRow = {
  day: number;
  /** 1-based day within its week («Ημ. 3»); day 1 is the start date's weekday. */
  dayOfWeek: number;
  kind: "free" | "locked" | "rest";
  /** A free day's WOD titles. */
  titles: string[];
  /** A locked day's workout type (ADR-275 key) and approximate minutes, when known. */
  workoutType: string | null;
  minutes: number | null;
};

type PreviewRow = { day: number; title: string | null };

function previewRows(value: unknown): PreviewRow[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((row) => {
    if (!row || typeof row !== "object") return [];
    const { day, title } = row as { day?: unknown; title?: unknown };
    if (typeof day !== "number" || !Number.isInteger(day) || day < 0) return [];
    return [{ day, title: typeof title === "string" && title.trim() ? title.trim() : null }];
  });
}

/** The outline's days of one week, or null when it has none (an older API or stub). */
function outlineDays(value: unknown, week: number, open: OutlineDay[]): OutlineRow[] | null {
  if (!Array.isArray(value)) return null;
  const entry = value.find((row) => row && typeof row === "object" && (row as { week?: unknown }).week === week) as { days?: unknown } | undefined;
  if (!entry || !Array.isArray(entry.days)) return null;
  const titles = new Map(open.map((day) => [day.day, day.titles]));
  const rows = entry.days.flatMap((raw): OutlineRow[] => {
    if (!raw || typeof raw !== "object") return [];
    const row = raw as { day?: unknown; weekday?: unknown; rest?: unknown; preview?: unknown; workout_type?: unknown; minutes?: unknown };
    if (typeof row.day !== "number" || !Number.isInteger(row.day) || row.day < 0) return [];
    const weekday = typeof row.weekday === "number" && row.weekday >= 0 && row.weekday < 7 ? row.weekday : row.day % 7;
    const free = row.preview === true || titles.has(row.day);
    const kind = row.rest === true ? "rest" : free ? "free" : "locked";
    return [
      {
        day: row.day,
        dayOfWeek: weekday + 1,
        kind,
        titles: kind === "free" ? (titles.get(row.day) ?? []) : [],
        workoutType: kind === "locked" && typeof row.workout_type === "string" && row.workout_type ? row.workout_type : null,
        minutes: kind === "locked" ? positiveInt(row.minutes) : null,
      },
    ];
  });
  return rows.length ? rows.sort((a, b) => a.day - b.day) : null;
}

function outlineCounts(value: unknown): Map<number, number> {
  const counts = new Map<number, number>();
  if (!Array.isArray(value)) return counts;
  for (const row of value) {
    if (!row || typeof row !== "object") continue;
    const { week, sessions } = row as { week?: unknown; sessions?: unknown };
    if (typeof week === "number" && week >= 1 && typeof sessions === "number" && sessions >= 0) counts.set(week, sessions);
  }
  return counts;
}

/** The free preview days, one entry per day with its WODs' titles. */
export function previewDays(programme: ProgrammeShape | null | undefined): OutlineDay[] {
  const byDay = new Map<number, OutlineDay>();
  for (const row of previewRows(programme?.preview)) {
    const entry = byDay.get(row.day) ?? { day: row.day, week: Math.floor(row.day / 7) + 1, dayOfWeek: (row.day % 7) + 1, titles: [] };
    if (row.title) entry.titles.push(row.title);
    byDay.set(row.day, entry);
  }
  return [...byDay.values()].sort((a, b) => a.day - b.day);
}

/**
 * The weeks as accordions: each week with free days on its own, then one
 * more week as a taste of a normal week, then the rest together
 * («Εβδομάδες 3–6»). Locked WODs are counted, never named.
 */
export function weekOutline(programme: ProgrammeShape | null | undefined): OutlineWeek[] {
  const open = previewDays(programme);
  const counts = outlineCounts(programme?.week_outline);
  const lastPreview = open.reduce((max, day) => Math.max(max, day.week), 0);
  const weeks = positiveInt(programme?.weeks) ?? Math.max(lastPreview, ...counts.keys(), 0);
  if (weeks === 0) return [];
  const rowsPerWeek = new Map<number, number>();
  for (const row of previewRows(programme?.preview)) {
    const week = Math.floor(row.day / 7) + 1;
    rowsPerWeek.set(week, (rowsPerWeek.get(week) ?? 0) + 1);
  }
  const lockedIn = (week: number) => {
    const fallback = positiveInt(programme?.sessions_per_week) ?? 0;
    return Math.max(0, (counts.get(week) ?? fallback) - (rowsPerWeek.get(week) ?? 0));
  };
  const single = Math.min(weeks, Math.max(lastPreview, 1) + 1);
  const result: OutlineWeek[] = [];
  for (let week = 1; week <= single; week += 1) {
    const weekOpen = open.filter((day) => day.week === week);
    result.push({ from: week, to: week, open: weekOpen, locked: lockedIn(week), days: outlineDays(programme?.week_outline, week, weekOpen) });
  }
  if (single < weeks) {
    let locked = 0;
    for (let week = single + 1; week <= weeks; week += 1) locked += lockedIn(week);
    result.push({ from: single + 1, to: weeks, open: [], locked, days: null });
  }
  return result;
}
