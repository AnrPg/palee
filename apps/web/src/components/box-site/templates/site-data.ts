import type { PublicSiteV2, SiteProgramme, SiteSection, SiteStats } from "@/api/box-site";
import type { PublicPackage } from "@/api/my-payments";
import type { PublicBoxPage } from "@/api/social";

import { isPaletteKey, isTemplateKey } from "./palettes";

/**
 * ADR-530: the pure data side of the box's website. Everything here is
 * computed from what the public API returns and tolerates missing fields
 * (an older API, a stubbed one): a switched-on section without data is
 * hidden, and a page left without sections leaves the menu.
 */

/** The site with every field present (older APIs answer without the ADR-530 fields). */
export function normalizeSite(raw: Partial<PublicSiteV2> | null | undefined): PublicSiteV2 {
  const site = (raw ?? {}) as Partial<PublicSiteV2>;
  const reviews = (site.reviews ?? {}) as Partial<PublicSiteV2["reviews"]>;
  const forms = (site.forms ?? {}) as Partial<PublicSiteV2["forms"]>;
  const tracking = (site.tracking ?? {}) as Partial<PublicSiteV2["tracking"]>;
  const photos = (site.photos ?? {}) as Partial<PublicSiteV2["photos"]>;
  const list = <T,>(value: T[] | null | undefined): T[] => (Array.isArray(value) ? value : []);
  return {
    ...(site as PublicSiteV2),
    slug: site.slug ?? "",
    language: site.language ?? "el",
    languages: list(site.languages),
    canonical_url: site.canonical_url ?? "",
    time_zone: site.time_zone || "Europe/Athens",
    translation: site.translation ?? null,
    about: site.about ?? null,
    texts: site.texts ?? {},
    class_type_names: site.class_type_names ?? {},
    sections: list(site.sections),
    faq: list(site.faq).filter((entry) => entry && entry.question && entry.answer),
    forms: { trial: Boolean(forms.trial), contact: Boolean(forms.contact), kinds: list(forms.kinds) },
    reviews: { palee: reviews.palee ?? null, google: reviews.google ?? null, google_reviews_url: reviews.google_reviews_url ?? null },
    events: list(site.events),
    timetable: list(site.timetable).filter((entry) => entry && entry.scheduled_at && !Number.isNaN(Date.parse(entry.scheduled_at))),
    wod: list(site.wod),
    tracking: {
      banner_version: tracking.banner_version ?? 1,
      categories: list(tracking.categories),
      consent_required: Boolean(tracking.consent_required),
      tags: tracking.tags ?? { ga4_measurement_id: null, gtm_container_id: null, meta_pixel_id: null },
      validity_days: tracking.validity_days ?? 180,
    },
    // Sites from before ADR-530 moved to «Αρένα» with the Palee palette.
    template: isTemplateKey(site.template) ? site.template : "arena",
    palette: isPaletteKey(site.palette) ? site.palette : "palee",
    appearance: site.appearance === "light" || site.appearance === "dark" ? site.appearance : "auto",
    calm_motion: Boolean(site.calm_motion),
    photos: { items: list(photos.items).filter((photo) => photo && photo.url), video: photos.video?.url ? photos.video : null },
    stats: site.stats ?? null,
    programmes: list(site.programmes),
    phone: site.phone?.trim() || null,
  };
}

/** The packages answer, tolerant of an empty or malformed one. */
export function packageList(data: unknown): PublicPackage[] {
  const packages = (data as { packages?: unknown } | null | undefined)?.packages;
  return Array.isArray(packages) ? (packages as PublicPackage[]).filter((pkg) => pkg && pkg.id && pkg.name) : [];
}

export type GalleryPhoto = { id: string; url: string; caption: string | null };

/** «Φωτογραφίες»: what the API chose, or the box page's photos and its rooms' public photos. */
export function galleryPhotos(site: PublicSiteV2, page: PublicBoxPage): GalleryPhoto[] {
  if (site.photos.items.length > 0) return site.photos.items.map((photo) => ({ id: photo.id, url: photo.url, caption: photo.caption ?? null }));
  const profile = page.profile ?? ({} as PublicBoxPage["profile"]);
  const own = (profile.photos ?? []).map((photo) => ({ id: photo.id, url: photo.url, caption: null }));
  const rooms = (page.rooms ?? []).flatMap((room) =>
    (room.photos ?? []).filter((photo) => photo.url).map((photo) => ({ id: photo.id, url: photo.url!, caption: photo.caption || room.name || null })),
  );
  return [...own, ...rooms];
}

/** The numbers «Αριθμοί κοινότητας» shows: aggregates only, a zero or a null is left out. */
export function statEntries(stats: SiteStats | null): { key: "classes_per_week" | "prs_this_year" | "years_open"; value: number }[] {
  if (!stats) return [];
  return (["classes_per_week", "prs_this_year", "years_open"] as const)
    .map((key) => ({ key, value: Number(stats[key] ?? 0) }))
    .filter((entry) => Number.isFinite(entry.value) && entry.value > 0);
}

export type OpeningSpan = { weekday: number; opens: string; closes: string };

/** The opening hours of the first location that has any (ISO weekday, Monday = 1). */
export function openingSpans(page: PublicBoxPage): OpeningSpan[] {
  for (const location of page.locations ?? []) {
    const spans = (location.opening_hours ?? []).filter(
      (span): span is OpeningSpan =>
        typeof span?.weekday === "number" && typeof span?.opens === "string" && typeof span?.closes === "string",
    );
    if (spans.length > 0) return spans;
  }
  return [];
}

/** The first location people can find: an address or a pin. */
export function mainLocation(page: PublicBoxPage) {
  return (page.locations ?? []).find((location) => location.address || (location.latitude != null && location.longitude != null)) ?? null;
}

/** «Σχετικά» in the page's language (ADR-520): the translation, else the box's own text. */
export function aboutText(site: PublicSiteV2, page: PublicBoxPage) {
  const translated = site.translation ? site.about?.trim() : "";
  return translated || page.profile?.about?.trim() || "";
}

export type SectionData ={ site: PublicSiteV2; page: PublicBoxPage; packages: number; gallery: number };

/** Whether a switched-on section has anything to show. */
export function sectionHasData(key: SiteSection | string, data: SectionData): boolean {
  const { site, page } = data;
  switch (key) {
    case "hero":
      return true;
    case "about":
      return Boolean(aboutText(site, page));
    case "photos":
      return data.gallery > 0 || Boolean(site.photos.video);
    case "stats":
      return statEntries(site.stats).length > 0;
    case "schedule":
      return site.timetable.length > 0;
    case "wod":
      return site.wod.length > 0;
    case "events":
      return site.events.length > 0;
    case "programmes":
      return site.programmes.length > 0;
    case "packages":
      return data.packages > 0;
    case "coaches":
      return (page.profile?.coaches ?? []).length > 0;
    case "location":
      return mainLocation(page) !== null;
    case "reviews":
      return Boolean((site.reviews.palee && site.reviews.palee.count > 0) || site.reviews.google?.rating);
    case "faq":
      return site.faq.length > 0;
    case "trial_form":
      return site.forms.trial;
    case "contact_form":
      return site.forms.contact;
    default:
      return false;
  }
}

/** The sections the website shows: switched on by the owner and with data. */
export function visibleSections(data: SectionData): SiteSection[] {
  return data.site.sections.filter((key) => sectionHasData(key, data));
}

// ── Time, in the box's time zone ────────────────────────────────────────────

function safeZone(timeZone: string) {
  try {
    new Intl.DateTimeFormat("en", { timeZone }).format(0);
    return timeZone;
  } catch {
    return "UTC";
  }
}

const WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

/** The day (YYYY-MM-DD), ISO weekday and seconds since midnight of an instant in a zone. */
export function zoned(ms: number, timeZone: string): { day: string; weekday: number; seconds: number } {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: safeZone(timeZone),
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    weekday: "short",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(ms));
  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? "0";
  return {
    day: `${get("year")}-${get("month")}-${get("day")}`,
    weekday: WEEKDAYS.indexOf(get("weekday")) + 1,
    seconds: Number(get("hour")) * 3600 + Number(get("minute")) * 60 + Number(get("second")),
  };
}

function dayNumber(day: string) {
  const [year, month, date] = day.split("-").map(Number);
  return Date.UTC(year!, month! - 1, date!) / 86_400_000;
}

function dayAfter(day: string, offset: number) {
  return new Date((dayNumber(day) + offset) * 86_400_000).toISOString().slice(0, 10);
}

function clockTime(ms: number, timeZone: string) {
  return new Intl.DateTimeFormat("en-GB", { timeZone: safeZone(timeZone), hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(ms));
}

export type SiteClass = PublicSiteV2["timetable"][number];

export type NextClass = { id: string; name: string; time: string; startsAt: number; inSeconds: number; dayOffset: number; weekday: number };

/**
 * «Επόμενο τμήμα»: the first class that has not started. `now` is null
 * while the page is rendered on the server: the first class of the
 * timetable then stands in, without a countdown.
 */
export function nextClass(timetable: SiteClass[], timeZone: string, now: number | null): NextClass | null {
  const sorted = [...timetable].sort((a, b) => Date.parse(a.scheduled_at) - Date.parse(b.scheduled_at));
  const next = now === null ? sorted[0] : sorted.find((entry) => Date.parse(entry.scheduled_at) > now);
  if (!next) return null;
  const startsAt = Date.parse(next.scheduled_at);
  const reference = now ?? startsAt;
  const start = zoned(startsAt, timeZone);
  return {
    id: next.id,
    name: next.name,
    time: clockTime(startsAt, timeZone),
    startsAt,
    inSeconds: Math.max(0, Math.floor((startsAt - reference) / 1000)),
    dayOffset: dayNumber(start.day) - dayNumber(zoned(reference, timeZone).day),
    weekday: start.weekday,
  };
}

/** The countdown: «02:43:39» under a day, whole days above. */
export function countdown(seconds: number): { kind: "clock"; text: string } | { kind: "days"; days: number } {
  const total = Math.max(0, Math.floor(seconds));
  if (total >= 86_400) return { kind: "days", days: Math.floor(total / 86_400) };
  const pad = (value: number) => String(value).padStart(2, "0");
  return { kind: "clock", text: `${pad(Math.floor(total / 3600))}:${pad(Math.floor((total % 3600) / 60))}:${pad(total % 60)}` };
}

const seconds = (time: string) => {
  const [hours, minutes] = time.split(":").map(Number);
  return (hours ?? 0) * 3600 + (minutes ?? 0) * 60;
};

export type OpenState = { state: "open"; until: string } | { state: "opens"; at: string } | { state: "closed" } | { state: "closedToday" };

/** «Ανοιχτά · κλείνει 22:00», «Ανοίγει 07:00», «Κλειστά τώρα», «Κλειστά σήμερα». */
export function openState(spans: OpeningSpan[], timeZone: string, now: number): OpenState | null {
  if (spans.length === 0) return null;
  const here = zoned(now, timeZone);
  const today = spans.filter((span) => span.weekday === here.weekday).sort((a, b) => seconds(a.opens) - seconds(b.opens));
  if (today.length === 0) return { state: "closedToday" };
  for (const span of today) {
    const closes = seconds(span.closes) || 86_400;
    if (here.seconds >= seconds(span.opens) && here.seconds < closes) return { state: "open", until: span.closes };
    if (here.seconds < seconds(span.opens)) return { state: "opens", at: span.opens };
  }
  return { state: "closed" };
}

/** «Δευ–Πέμ 07:00–22:00 · Παρ 07:00–21:00»: days with the same hours in one run. */
export function hoursSummary(spans: OpeningSpan[], locale: string): string {
  if (spans.length === 0) return "";
  const name = (weekday: number) => new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: "UTC" }).format(new Date(Date.UTC(2024, 0, weekday)));
  const hours = (weekday: number) =>
    spans
      .filter((span) => span.weekday === weekday)
      .sort((a, b) => seconds(a.opens) - seconds(b.opens))
      .map((span) => `${span.opens}–${span.closes}`)
      .join(", ");
  const runs: { from: number; to: number; hours: string }[] = [];
  for (let weekday = 1; weekday <= 7; weekday++) {
    const value = hours(weekday);
    if (!value) continue;
    const last = runs[runs.length - 1];
    if (last && last.to === weekday - 1 && last.hours === value) last.to = weekday;
    else runs.push({ from: weekday, to: weekday, hours: value });
  }
  return runs.map((run) => `${name(run.from)}${run.to > run.from ? `–${name(run.to)}` : ""} ${run.hours}`).join(" · ");
}

export type ScheduleEntry = { id: string; time: string; startsAt: number; name: string; type: string; minutes: number };
export type ScheduleDay = { day: string; weekday: string; date: string; entries: ScheduleEntry[] };

/**
 * The week the timetable widget shows: seven days from today (from the
 * first class while the server renders), each with its classes in the
 * page's language.
 */
export function scheduleDays(timetable: SiteClass[], timeZone: string, locale: string, names: Record<string, string>, now: number | null): ScheduleDay[] {
  const sorted = [...timetable].sort((a, b) => Date.parse(a.scheduled_at) - Date.parse(b.scheduled_at));
  const first = now ?? (sorted[0] ? Date.parse(sorted[0].scheduled_at) : null);
  if (first === null) return [];
  const start = zoned(first, timeZone).day;
  const weekday = new Intl.DateTimeFormat(locale, { weekday: "short", timeZone: "UTC" });
  const date = new Intl.DateTimeFormat(locale, { day: "numeric", timeZone: "UTC" });
  const days: ScheduleDay[] = Array.from({ length: 7 }, (_, offset) => {
    const day = dayAfter(start, offset);
    const at = new Date(dayNumber(day) * 86_400_000 + 12 * 3_600_000);
    return { day, weekday: weekday.format(at), date: date.format(at), entries: [] };
  });
  for (const entry of sorted) {
    const at = Date.parse(entry.scheduled_at);
    const target = days.find((day) => day.day === zoned(at, timeZone).day);
    target?.entries.push({
      id: entry.id,
      time: clockTime(at, timeZone),
      startsAt: at,
      name: names[entry.name] ?? entry.name,
      type: entry.name,
      minutes: entry.duration_minutes,
    });
  }
  return days;
}

/** The class types of the timetable, the busiest first (the filters, the marquee). */
export function classTypes(timetable: SiteClass[]): string[] {
  const counts = new Map<string, number>();
  for (const entry of timetable) counts.set(entry.name, (counts.get(entry.name) ?? 0) + 1);
  return [...counts.entries()].sort((a, b) => b[1] - a[1]).map(([name]) => name);
}

/** The colour token of a class type: the palette's accents first, then the status colours. */
export function typeColor(index: number) {
  return ["var(--s-accent)", "var(--s-accent2)", "var(--s-ok)", "var(--s-star)", "var(--s-muted)"][index % 5]!;
}

// ── «Πλακίδια» ──────────────────────────────────────────────────────────────

/**
 * No holes on the phone's two-column grid: an odd number of single tiles
 * makes the last single one wide.
 */
export function balanceTiles<T extends { wide: boolean }>(tiles: T[]): T[] {
  const out = tiles.map((tile) => ({ ...tile }));
  const singles = out.filter((tile) => !tile.wide);
  if (singles.length % 2 === 1) singles[singles.length - 1]!.wide = true;
  return out;
}

/** With fewer than three tiles the hero spans the whole width. */
export function heroSpansAll(tileCount: number) {
  return tileCount < 3;
}

// ── «Ιστορίες» ──────────────────────────────────────────────────────────────

export type StoryKind = "wod" | "space" | "coaches" | "events" | "reviews";
const STORY_SECTIONS: [SiteSection | "photos", StoryKind][] = [
  ["wod", "wod"],
  ["photos", "space"],
  ["coaches", "coaches"],
  ["events", "events"],
  ["reviews", "reviews"],
];

/** The story rings, built from the visible sections in a fixed order. */
export function storyKinds(visible: readonly string[]): StoryKind[] {
  return STORY_SECTIONS.filter(([section]) => visible.includes(section)).map(([, kind]) => kind);
}

// ── Packages and programmes ────────────────────────────────────────────────

/** «από 60 €»: the cheapest paid package that is not a trial. */
export function cheapestPackage(packages: PublicPackage[]): PublicPackage | null {
  const paid = packages.filter((pkg) => pkg.package_type !== "trial" && pkg.base_price_cents > 0);
  return paid.sort((a, b) => a.base_price_cents - b.base_price_cents)[0] ?? null;
}

/** The trial package first, then the rest in the box's order. */
export function packagesInOrder(packages: PublicPackage[]): PublicPackage[] {
  return [...packages.filter((pkg) => pkg.package_type === "trial"), ...packages.filter((pkg) => pkg.package_type !== "trial")];
}

export function cheapestProgramme(programmes: SiteProgramme[]) {
  const priced = programmes.filter((programme) => (programme.price_cents ?? 0) > 0);
  return priced.sort((a, b) => (a.price_cents ?? 0) - (b.price_cents ?? 0))[0] ?? null;
}

/** The first sentence of a text (the «Ποιοι είμαστε» tile, a page description). */
export function firstSentence(text: string | null | undefined, max = 160) {
  const clean = (text ?? "").replace(/\s+/g, " ").trim();
  if (!clean) return "";
  const match = clean.match(/^.+?[.!;?·](?=\s|$)/u);
  const sentence = match ? match[0] : clean;
  return sentence.length > max ? `${sentence.slice(0, max - 1).trimEnd()}…` : sentence;
}

/** Up to two initials of a name (the coaches' faces without a photo). */
export function initials(name: string | null | undefined) {
  return (name ?? "")
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word[0]!.toUpperCase())
    .join("");
}
