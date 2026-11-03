import type {
  AgeGroup,
  ClassVisitPerson,
  Division,
  FitnessDomain,
  FitnessDomainName,
  FitnessDisplayMode,
  FitnessReason,
  LeaderboardQuery,
  LeaderboardWindow,
  VisitBadge,
} from "@/api/training-floor";

// Pure rules behind the v3.1 «Training and floor» screens (ADR-356..359,
// ADR-389). The API decides who sees what; these only shape what is shown.

// -- CP-D2: leaderboard chips and «Προχωρημένα» -------------------------------

export type LeaderboardFilters = {
  division: Division | null;
  ageGroup: AgeGroup | null;
  scale: string | null;
  window: LeaderboardWindow;
  /** ADR-394: `palee` ranks a benchmark WOD across every box. */
  scope: "box" | "branch" | "palee";
  buddies: boolean;
};

export const DEFAULT_LEADERBOARD_FILTERS: LeaderboardFilters = {
  division: null,
  ageGroup: null,
  scale: null,
  window: "day",
  scope: "box",
  buddies: false,
};

export const LEADERBOARD_WINDOWS: readonly LeaderboardWindow[] = ["day", "week", "month", "year", "all"];

/**
 * ADR-356: masters-style group by the age reached during `year`, exactly as
 * `Gamification.Domain.LeaderboardFilters.age_group/2`.
 */
export function ageGroupFor(birthYear: number | null | undefined, year: number): AgeGroup | null {
  if (!birthYear) return null;
  const age = year - birthYear;
  if (age < 18) return "under_18";
  if (age < 35) return "18_34";
  if (age >= 65) return "65_plus";
  const low = Math.floor(age / 5) * 5;
  return `${low}_${low + 4}` as AgeGroup;
}

/** «35–39», «18–34», «<18», «65+». */
export function ageGroupLabel(group: AgeGroup): string {
  if (group === "under_18") return "<18";
  if (group === "65_plus") return "65+";
  return group.replace("_", "–");
}

export type LeaderboardChip =
  | { kind: "all"; on: boolean }
  | { kind: "scope"; value: "box" | "palee"; on: boolean }
  | { kind: "division"; value: Division; on: boolean }
  | { kind: "age"; value: AgeGroup; on: boolean }
  | { kind: "scale"; value: string; label: string; on: boolean };

/**
 * One row of chips (mockup d2 A): «Όλοι», then only the slices that are the
 * viewer's own: their division and age group (when they told the box) and
 * the scale level of their own result.
 *
 * ADR-394: on a WOD the coach tagged as a benchmark, «Όλοι» gives way to
 * two scope chips, «Το box μου» and «Όλο το Palee». Other WODs are unchanged.
 */
export function leaderboardChips(
  filters: LeaderboardFilters,
  own: {
    division: Division | null | undefined;
    birthYear: number | null | undefined;
    year: number;
    scale: { slug: string; label: string } | null;
  },
  options: { benchmark?: boolean } = {},
): LeaderboardChip[] {
  const palee = filters.scope === "palee";
  const chips: LeaderboardChip[] = options.benchmark
    ? [
        { kind: "scope", value: "box", on: !palee },
        { kind: "scope", value: "palee", on: palee },
      ]
    : [{ kind: "all", on: !filters.division && !filters.ageGroup && !filters.scale }];
  if (own.division) chips.push({ kind: "division", value: own.division, on: filters.division === own.division });
  const age = ageGroupFor(own.birthYear, own.year);
  if (age) chips.push({ kind: "age", value: age, on: filters.ageGroup === age });
  if (own.scale) chips.push({ kind: "scale", value: own.scale.slug, label: own.scale.label, on: filters.scale === own.scale.slug });
  return chips;
}

/**
 * The window a scope starts from: the box compares today's class, the
 * Palee-wide board every result of the benchmark (ADR-394).
 */
export function defaultWindow(scope: LeaderboardFilters["scope"]): LeaderboardWindow {
  return scope === "palee" ? "all" : "day";
}

/**
 * Tapping a chip: «Όλοι» clears the slices, a scope chip switches between the
 * box and all of Palee (with that scope's own window), any other toggles its
 * own slice.
 */
export function toggleChip(filters: LeaderboardFilters, chip: LeaderboardChip): LeaderboardFilters {
  switch (chip.kind) {
    case "all":
      return { ...filters, division: null, ageGroup: null, scale: null };
    case "scope":
      if (chip.on) return filters;
      return chip.value === "palee"
        ? { ...filters, scope: "palee", window: defaultWindow("palee"), buddies: false }
        : { ...filters, scope: "box", window: defaultWindow("box") };
    case "division":
      return { ...filters, division: chip.on ? null : chip.value };
    case "age":
      return { ...filters, ageGroup: chip.on ? null : chip.value };
    case "scale":
      return { ...filters, scale: chip.on ? null : chip.value };
  }
}

/** Whether anything under «Προχωρημένα» differs from the calm default. */
export function advancedActive(filters: LeaderboardFilters): boolean {
  return filters.window !== defaultWindow(filters.scope) || filters.scope === "branch" || filters.buddies;
}

/** The API query; the branch is always the person's home branch. */
export function leaderboardQuery(
  filters: LeaderboardFilters,
  context: { date: string; homeLocationId: string | null },
): LeaderboardQuery {
  if (filters.scope === "palee") {
    return {
      date: context.date,
      window: filters.window,
      ...(filters.division ? { division: filters.division } : {}),
      ...(filters.ageGroup ? { age_group: filters.ageGroup } : {}),
      ...(filters.scale ? { scale: filters.scale } : {}),
      scope: "palee" as const,
    };
  }
  const branch = filters.scope === "branch" && context.homeLocationId;
  return {
    date: context.date,
    window: filters.window,
    ...(filters.division ? { division: filters.division } : {}),
    ...(filters.ageGroup ? { age_group: filters.ageGroup } : {}),
    ...(filters.scale ? { scale: filters.scale } : {}),
    ...(branch ? { scope: "branch" as const, location_id: context.homeLocationId! } : { scope: "box" as const }),
    ...(filters.buddies ? { buddies: true } : {}),
  };
}

/** Birth years the profile form offers: 14 to 90 years old this year, newest first. */
export function birthYearOptions(year: number): number[] {
  const years: number[] = [];
  for (let value = year - 14; value >= year - 90; value -= 1) years.push(value);
  return years;
}

// -- CP-D3: the day's tag in programming --------------------------------------

export type DayTag = { date: string; tag: "none" | "not_assigned" | "mixed" | "all_assigned"; classes: number; with_wod: number };

export type DayTagView = { key: "dayTagNone" | "dayTagNotAssigned" | "dayTagMixed" | "dayTagAllAssigned"; tone: "muted" | "danger" | "warning" | "success" };

/** ANR 2026-11-02: words, not colour only; the mixed tag carries «1/3». */
export function dayTagView(tag: DayTag["tag"]): DayTagView {
  switch (tag) {
    case "all_assigned":
      return { key: "dayTagAllAssigned", tone: "success" };
    case "mixed":
      return { key: "dayTagMixed", tone: "warning" };
    case "not_assigned":
      return { key: "dayTagNotAssigned", tone: "danger" };
    default:
      return { key: "dayTagNone", tone: "muted" };
  }
}

export function dayTagsByDate(days: DayTag[] | null | undefined): Map<string, DayTag> {
  return new Map((days ?? []).map((day) => [day.date, day]));
}

/** What a WOD snapshot's content says, as short lines (title aside). */
export function snapshotLines(content: Record<string, unknown>): string[] {
  const lines: string[] = [];
  const text = (value: unknown) => (typeof value === "string" ? value.trim() : "");
  const body = text(content.content) || text(content.description);
  if (body) lines.push(...body.split(/\r?\n/).map((line) => line.trim()).filter(Boolean));
  const sections = Array.isArray(content.sections) ? (content.sections as Array<Record<string, unknown>>) : [];
  for (const section of sections) {
    const exercises = Array.isArray(section.exercises) ? (section.exercises as Array<Record<string, unknown>>) : [];
    const names = exercises.map((exercise) => text(exercise.name)).filter(Boolean);
    const name = text(section.name);
    const line = [name, names.join(" · ")].filter(Boolean).join(": ");
    if (line) lines.push(line);
  }
  return lines;
}

// -- CP-D6: fitness profile ---------------------------------------------------

export const FITNESS_DOMAINS: readonly FitnessDomainName[] = ["strength", "power", "gymnastics", "monostructural", "metcon"];

/** The five domains in a fixed order, untested ones included. */
export function orderedDomains(domains: FitnessDomain[] | undefined): FitnessDomain[] {
  const known = Array.isArray(domains) ? domains : [];
  return FITNESS_DOMAINS.map(
    (name) => known.find((domain) => domain.domain === name) ?? { domain: name, score: null, confidence: null, reasons: [], stale: false },
  );
}

// -- ADR-395: fitness card version 2 ------------------------------------------

/** An age band as the API names it (`40_44`, `60_plus`) the way people write it: «40–44», «60+». */
export function ageBandLabel(band: string | null | undefined): string | null {
  if (!band) return null;
  const plus = /^(\d+)_plus$/.exec(band);
  if (plus) return `${plus[1]}+`;
  const range = /^(\d+)_(\d+)$/.exec(band);
  return range ? `${range[1]}–${range[2]}` : null;
}

/**
 * What separates a reading from the next level, in the PR's own unit: kg more
 * on the 1RM, reps more, or seconds faster. Null at the top of the scale.
 */
export function nextGap(reading: Pick<FitnessReason, "unit" | "value" | "next">): number | null {
  const next = reading.next;
  if (!next) return null;
  const gap = reading.unit === "mins_secs" ? reading.value - next.value : next.value - reading.value;
  if (gap <= 0) return null;
  return reading.unit === "kg" ? Math.round(gap * 2) / 2 : Math.round(gap);
}

const DISPLAY_RANK: Record<FitnessDisplayMode, number> = { all: 0, progress_only: 1, none: 2 };

/** Whether a display choice shows more than another (a member's own choice never loosens the coach's). */
export function looserDisplay(choice: FitnessDisplayMode, than: FitnessDisplayMode): boolean {
  return DISPLAY_RANK[choice] < DISPLAY_RANK[than];
}

/** The change chip's direction: up, down or the same; null when there is nothing to compare. */
export function changeDirection(change: number | null | undefined): "up" | "down" | "same" | null {
  if (typeof change !== "number") return null;
  return change > 0 ? "up" : change < 0 ? "down" : "same";
}

/** A PR value as the reason line shows it: kg, reps, or m:ss. */
export function reasonValue(value: number, unit: "kg" | "reps" | "mins_secs", locale: string): string {
  if (unit === "mins_secs") {
    const total = Math.round(value);
    const minutes = Math.floor(total / 60);
    const seconds = total % 60;
    return `${minutes}:${String(seconds).padStart(2, "0")}`;
  }
  const number = new Intl.NumberFormat(locale, { maximumFractionDigits: 1 }).format(value);
  return unit === "kg" ? `${number} kg` : number;
}

// -- CP-E1: who is new in a class ---------------------------------------------

/** «Νέοι σήμερα» (mockup e1 B): a first visit or a trial seat. */
export function newcomers(people: ClassVisitPerson[] | null | undefined): ClassVisitPerson[] {
  return (people ?? []).filter((person) => person.badges.includes("first_visit") || person.badges.includes("trial"));
}

export function visitFor(people: ClassVisitPerson[] | null | undefined, bookingId: string): ClassVisitPerson | null {
  return (people ?? []).find((person) => person.booking_id === bookingId) ?? null;
}

/**
 * Badges a row shows as chips: how they came is one «Ήρθε μέσω …» chip of its
 * own, and the roster already tags a trial seat («Δοκιμαστικό»).
 */
export function rowBadges(badges: readonly VisitBadge[] | null | undefined, options: { skipTrial?: boolean } = {}): VisitBadge[] {
  return (badges ?? []).filter(
    (badge) => !(options.skipTrial && badge === "trial") && badge !== "came_via_event" && badge !== "came_via_referral",
  );
}

// -- CP-E4: the calendar offer at the first booking ---------------------------

const CALENDAR_OFFER_KEY = "palee:calendar-offer";

/** Asked once per person on this device (mockup e4 A); a «no» is final too. */
export function calendarOfferPending(userId: string | null | undefined): boolean {
  if (!userId || typeof window === "undefined") return false;
  try {
    return window.localStorage.getItem(`${CALENDAR_OFFER_KEY}:${userId}`) === null;
  } catch {
    return false;
  }
}

export function rememberCalendarOffer(userId: string, answer: "apple" | "google" | "no") {
  try {
    window.localStorage.setItem(`${CALENDAR_OFFER_KEY}:${userId}`, answer);
  } catch {
    // Storage blocked: the offer may come back once, which is harmless.
  }
}

/** Google Calendar's «add by URL» for the private feed. */
export function googleCalendarUrl(webcalUrl: string): string {
  return `https://calendar.google.com/calendar/render?cid=${encodeURIComponent(webcalUrl)}`;
}

// -- CP-E5: who reads a note ---------------------------------------------------

export type NoteAudience = "private" | "staff";

/** The coach starts from «Μόνο εγώ»; everyone else writes for the staff (mockup e5 A). */
export function defaultNoteAudience(roles: string[], canWritePrivate: boolean): NoteAudience {
  if (!canWritePrivate) return "staff";
  return roles.includes("coach") ? "private" : "staff";
}

// -- ADR-393: the WOD changed after you logged it ------------------------------

/**
 * The bell's title and body of `logged_workout_changed`: the WOD's name when
 * it has one. Null for any other notification type.
 */
export function loggedWodChangedText(
  type: string,
  payload: Record<string, unknown>,
  part: "title" | "body",
  t: (key: string, values?: Record<string, string>) => string,
): string | null {
  if (type !== "logged_workout_changed") return null;
  if (part === "title") return t("notifWodChangedTitle");
  const title = typeof payload.workout_title === "string" ? payload.workout_title.trim() : "";
  return title ? t("notifWodChangedBody", { title }) : t("notifWodChangedBodyUntitled");
}

/**
 * Whether the Journal was opened on this run or score (`/journal?entry=<id>`,
 * the link of `logged_workout_changed`), so its «Το WOD άλλαξε από τότε» line
 * is brought into view.
 */
export function journalEntryFocused(search: string | null | undefined, id: string): boolean {
  if (!search || !id) return false;
  return new URLSearchParams(search).get("entry") === id;
}
