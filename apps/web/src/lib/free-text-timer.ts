import type { TimerSegment } from "@/api/executions";
import { readSegmentClock, segmentLimitMs, type SegmentClock } from "@/lib/timer-engine";

/**
 * Timer for free-text workouts. A free-text workout has no structured
 * sections, so the athlete (or the coach, ahead of time) picks a timer preset;
 * the preset becomes the same segment list the API builds for structured
 * workouts and runs on the shared timer engine. The whole run is described by
 * one elapsed total, so it survives reloads and background tabs.
 */

export const FREE_TEXT_TIMER_FORMATS = ["untimed", "for_time", "amrap", "emom", "tabata", "custom_hiit", "death_by"] as const;
export type FreeTextTimerFormat = (typeof FREE_TEXT_TIMER_FORMATS)[number];

export type FreeTextTimerPreset = {
  format: FreeTextTimerFormat;
  /** AMRAP length or For Time cap. */
  duration_seconds?: number | null;
  rounds?: number | null;
  work_seconds?: number | null;
  rest_seconds?: number | null;
  interval_seconds?: number | null;
};

/** Key under `workout_metadata` where a coach attaches a preset to a free-text workout. */
export const FREE_TEXT_TIMER_METADATA_KEY = "free_text_timer";

export const QUICK_PRESETS: { id: string; preset: FreeTextTimerPreset }[] = [
  { id: "tabata", preset: { format: "tabata", work_seconds: 20, rest_seconds: 10, rounds: 8 } },
  { id: "emom10", preset: { format: "emom", interval_seconds: 60, rounds: 10 } },
  { id: "e2mom20", preset: { format: "emom", interval_seconds: 120, rounds: 10 } },
  { id: "amrap12", preset: { format: "amrap", duration_seconds: 720 } },
  { id: "forTime12", preset: { format: "for_time", duration_seconds: 720 } },
  { id: "deathBy", preset: { format: "death_by", interval_seconds: 60 } },
  { id: "stopwatch", preset: { format: "untimed" } },
];

/** ADR-571: «Χωρίς χρόνο», the default timer of a text section. */
export const NO_TIME_PRESET: FreeTextTimerPreset = { format: "untimed" };

/**
 * A preset reduced to the fields its format runs on, with the timer
 * engine's values for missing ones. Mirrors the API's
 * `FrequentTimerPresets.canonical/1`, so a chip and the section's own
 * timer compare equal however each was written.
 */
export function canonicalTimerPreset(value: unknown): FreeTextTimerPreset | null {
  const preset = parseFreeTextTimerPreset(value);
  if (!preset) return null;
  switch (preset.format) {
    case "amrap":
      return { format: "amrap", duration_seconds: preset.duration_seconds ?? 720 };
    case "for_time":
      return preset.duration_seconds ? { format: "for_time", duration_seconds: preset.duration_seconds } : { format: "for_time" };
    case "emom":
      return { format: "emom", interval_seconds: preset.interval_seconds ?? 60, rounds: preset.rounds ?? 10 };
    case "death_by":
      return preset.rounds
        ? { format: "death_by", interval_seconds: preset.interval_seconds ?? 60, rounds: preset.rounds }
        : { format: "death_by", interval_seconds: preset.interval_seconds ?? 60 };
    case "tabata":
    case "custom_hiit": {
      const rest = preset.rest_seconds ?? (preset.format === "tabata" ? 10 : null);
      return {
        format: preset.format,
        work_seconds: preset.work_seconds ?? 20,
        ...(rest ? { rest_seconds: rest } : {}),
        rounds: preset.rounds ?? 8,
      };
    }
    default:
      return NO_TIME_PRESET;
  }
}

/** Whether two presets run the same timer. */
export function sameTimerPreset(a: unknown, b: unknown) {
  const left = canonicalTimerPreset(a);
  const right = canonicalTimerPreset(b);
  if (!left || !right) return false;
  const keys = new Set([...Object.keys(left), ...Object.keys(right)]) as Set<keyof FreeTextTimerPreset>;
  return [...keys].every((key) => left[key] === right[key]);
}

/** Whole minutes as a number, anything else as m:ss. */
function minutes(seconds: number) {
  if (seconds % 60 === 0) return String(seconds / 60);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

/**
 * The short name of a timer chip, the way coaches say it: «AMRAP 10»,
 * «EMOM 4», «E2MOM 20», «For Time 12′», «Tabata 20/10 × 8». The format
 * names come from the locale; the numbers are minutes (or m:ss).
 */
export function timerChipLabel(preset: FreeTextTimerPreset, formatLabel: string): string {
  const timer = canonicalTimerPreset(preset) ?? NO_TIME_PRESET;
  switch (timer.format) {
    case "amrap":
      return `${formatLabel} ${minutes(timer.duration_seconds!)}`;
    case "for_time":
      return timer.duration_seconds ? `${formatLabel} ${minutes(timer.duration_seconds)}′` : formatLabel;
    case "emom": {
      const interval = timer.interval_seconds!;
      const rounds = timer.rounds!;
      if (interval === 60) return `${formatLabel} ${rounds}`;
      // «E2MOM 20»: every 2 minutes, 20 minutes in all (only where the name is EMOM itself).
      if (interval % 60 === 0 && formatLabel === "EMOM") return `E${interval / 60}MOM ${(interval / 60) * rounds}`;
      return `${formatLabel} ${rounds} × ${minutes(interval)}`;
    }
    case "death_by":
      return timer.interval_seconds === 60 ? formatLabel : `${formatLabel} ${minutes(timer.interval_seconds!)}`;
    case "tabata":
    case "custom_hiit":
      return `${formatLabel} ${timer.work_seconds}${timer.rest_seconds ? `/${timer.rest_seconds}` : ""} × ${timer.rounds}`;
    default:
      return formatLabel;
  }
}

const positive = (value: unknown, fallback: number | null = null) =>
  typeof value === "number" && Number.isFinite(value) && value > 0 ? Math.round(value) : fallback;

/** Reads a preset from untrusted data (workout metadata, local storage). */
export function parseFreeTextTimerPreset(value: unknown): FreeTextTimerPreset | null {
  if (!value || typeof value !== "object") return null;
  const raw = value as Record<string, unknown>;
  if (!FREE_TEXT_TIMER_FORMATS.includes(raw.format as FreeTextTimerFormat)) return null;
  return {
    format: raw.format as FreeTextTimerFormat,
    duration_seconds: positive(raw.duration_seconds),
    rounds: positive(raw.rounds),
    work_seconds: positive(raw.work_seconds),
    rest_seconds: positive(raw.rest_seconds),
    interval_seconds: positive(raw.interval_seconds),
  };
}

function base(index: number, extra: Partial<TimerSegment>): TimerSegment {
  return {
    segment_key: `free-text:${index}`,
    section_id: "free-text",
    section_name: "",
    format: "untimed",
    kind: "countup",
    phase: "work",
    duration_seconds: null,
    round: null,
    total_rounds: null,
    label: "",
    label_key: null,
    label_params: {},
    scoreable: false,
    score_config: null,
    timer_config: {},
    exercises: [],
    ...extra,
  };
}

export function buildFreeTextSegments(preset: FreeTextTimerPreset): TimerSegment[] {
  switch (preset.format) {
    case "for_time":
      return [base(0, { format: "for_time", kind: "countup", duration_seconds: positive(preset.duration_seconds) })];
    case "amrap":
      return [base(0, { format: "amrap", kind: "countdown", duration_seconds: positive(preset.duration_seconds, 720) })];
    case "emom":
      return [
        base(0, {
          format: "emom",
          kind: "interval_cycle",
          duration_seconds: positive(preset.interval_seconds, 60),
          total_rounds: positive(preset.rounds, 10),
          label: "EMOM",
          label_key: "emom",
        }),
      ];
    case "death_by":
      return [
        base(0, {
          format: "death_by",
          kind: "interval_cycle",
          duration_seconds: positive(preset.interval_seconds, 60),
          total_rounds: positive(preset.rounds),
          label: "Death By",
          label_key: "death_by",
        }),
      ];
    case "tabata":
    case "custom_hiit": {
      const rounds = positive(preset.rounds, 8)!;
      const work = positive(preset.work_seconds, 20);
      const rest = positive(preset.rest_seconds, preset.format === "tabata" ? 10 : null);
      const segments: TimerSegment[] = [];
      for (let round = 1; round <= rounds; round += 1) {
        segments.push(
          base(segments.length, {
            format: preset.format,
            kind: "countdown",
            duration_seconds: work,
            round,
            total_rounds: rounds,
            label: `Work ${round}/${rounds}`,
            label_key: "work",
            label_params: { round, total: rounds },
          }),
        );
        if (rest && round < rounds) {
          segments.push(
            base(segments.length, {
              format: preset.format,
              kind: "countdown",
              phase: "rest",
              duration_seconds: rest,
              round,
              total_rounds: rounds,
              label: `Rest ${round}/${rounds}`,
              label_key: "rest_round",
              label_params: { round, total: rounds },
            }),
          );
        }
      }
      return segments;
    }
    default:
      return [base(0, { format: "untimed", kind: "countup" })];
  }
}

export type FreeTextPosition = {
  index: number;
  segment: TimerSegment;
  clock: SegmentClock;
  /** The whole timer ran out (its last segment expired). */
  finished: boolean;
  /** Total time of the run, capped at the timer's total length. */
  totalElapsedMs: number;
};

/** Total length of a timer that ends on its own; null when it runs until stopped. */
export function freeTextLimitMs(segments: TimerSegment[]): number | null {
  let total = 0;
  for (const segment of segments) {
    const limit = segmentLimitMs(segment);
    if (limit === null) return null;
    total += limit;
  }
  return total;
}

/** Where a run is after `elapsedMs` of running time, across all segments. */
export function freeTextPosition(segments: TimerSegment[], elapsedMs: number): FreeTextPosition {
  let offset = Math.max(0, elapsedMs);
  let total = 0;

  for (let index = 0; index < segments.length; index += 1) {
    const segment = segments[index]!;
    const limit = segmentLimitMs(segment);
    const last = index === segments.length - 1;

    if (limit === null || offset < limit || last) {
      const clock = readSegmentClock(segment, last && limit !== null ? Math.min(offset, limit) : offset);
      return {
        index,
        segment,
        clock,
        finished: last && limit !== null && offset >= limit,
        totalElapsedMs: total + clock.elapsedMs,
      };
    }

    offset -= limit;
    total += limit;
  }

  throw new Error("A free-text timer needs at least one segment");
}

export type FreeTextRun = {
  preset: FreeTextTimerPreset;
  /** Wall-clock time the current running stretch began; null while paused. */
  startedAt: number | null;
  /** Running time banked by earlier pauses. */
  carriedMs: number;
};

export function runElapsedMs(run: Pick<FreeTextRun, "startedAt" | "carriedMs">, now: number) {
  return run.carriedMs + (run.startedAt === null ? 0 : Math.max(0, now - run.startedAt));
}

const RUN_KEY = "palee:free-text-timer:";
const LAST_PRESET_KEY = "palee:free-text-timer:last-preset";

/** Persisted per execution so a reload resumes the same clock. */
export function readFreeTextRun(executionId: string): FreeTextRun | null {
  try {
    const raw = window.localStorage.getItem(RUN_KEY + executionId);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<FreeTextRun>;
    const preset = parseFreeTextTimerPreset(parsed.preset);
    if (!preset) return null;
    return {
      preset,
      startedAt: typeof parsed.startedAt === "number" ? parsed.startedAt : null,
      carriedMs: typeof parsed.carriedMs === "number" ? Math.max(0, parsed.carriedMs) : 0,
    };
  } catch {
    return null;
  }
}

export function storeFreeTextRun(executionId: string, run: FreeTextRun | null) {
  try {
    if (run) window.localStorage.setItem(RUN_KEY + executionId, JSON.stringify(run));
    else window.localStorage.removeItem(RUN_KEY + executionId);
  } catch {
    // Storage unavailable (private mode); the run still works for this visit.
  }
}

export function readLastPreset(): FreeTextTimerPreset | null {
  try {
    return parseFreeTextTimerPreset(JSON.parse(window.localStorage.getItem(LAST_PRESET_KEY) ?? "null"));
  } catch {
    return null;
  }
}

export function storeLastPreset(preset: FreeTextTimerPreset) {
  try {
    window.localStorage.setItem(LAST_PRESET_KEY, JSON.stringify(preset));
  } catch {
    // ignore
  }
}

export type FreeTextKpi = {
  pauses: number;
  paused_ms: number;
  finish_wizard_opens: number;
  /** Timer restarts from zero (the free-text counterpart of skipping). */
  skips: number;
  first_started_at_ms?: number;
  /** While paused: when the pause began, for `paused_ms`. */
  paused_at?: number | null;
};

const KPI_KEY = "palee:free-text-kpi:";

export function emptyFreeTextKpi(): FreeTextKpi {
  return { pauses: 0, paused_ms: 0, finish_wizard_opens: 0, skips: 0, paused_at: null };
}

/** Counters survive resets and reloads, so they live apart from the run. */
export function readFreeTextKpi(executionId: string): FreeTextKpi {
  try {
    const raw = JSON.parse(window.localStorage.getItem(KPI_KEY + executionId) ?? "null") as Partial<FreeTextKpi> | null;
    if (!raw || typeof raw !== "object") return emptyFreeTextKpi();
    const count = (value: unknown) => (typeof value === "number" && value >= 0 ? Math.round(value) : 0);
    return {
      pauses: count(raw.pauses),
      paused_ms: count(raw.paused_ms),
      finish_wizard_opens: count(raw.finish_wizard_opens),
      skips: count(raw.skips),
      first_started_at_ms: typeof raw.first_started_at_ms === "number" ? raw.first_started_at_ms : undefined,
      paused_at: typeof raw.paused_at === "number" ? raw.paused_at : null,
    };
  } catch {
    return emptyFreeTextKpi();
  }
}

export function storeFreeTextKpi(executionId: string, kpi: FreeTextKpi | null) {
  try {
    if (kpi) window.localStorage.setItem(KPI_KEY + executionId, JSON.stringify(kpi));
    else window.localStorage.removeItem(KPI_KEY + executionId);
  } catch {
    // ignore
  }
}

/** The counters the API accepts (drops local bookkeeping). */
export function kpiPayload(kpi: FreeTextKpi) {
  const { paused_at: _pausedAt, ...counters } = kpi;
  void _pausedAt;
  return counters;
}
