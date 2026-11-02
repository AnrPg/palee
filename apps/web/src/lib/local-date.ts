export function formatLocalDate(date: Date) {
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");

  return `${year}-${month}-${day}`;
}

export function addLocalDays(date: Date, amount: number) {
  const next = new Date(date);
  next.setDate(next.getDate() + amount);
  return next;
}

export function startOfLocalWeek(date: Date) {
  const next = new Date(date);
  const day = next.getDay();
  const diff = day === 0 ? -6 : 1 - day;

  next.setDate(next.getDate() + diff);
  next.setHours(0, 0, 0, 0);
  return next;
}

const DATE_KEY = /^(\d{4})-(\d{2})-(\d{2})/;

/**
 * A calendar day the API sends as `YYYY-MM-DD` (a due date, an expiry), in the
 * reader's language: «28 Νοε 2026», "Nov 28, 2026". It is a day, not an
 * instant, so it never shifts with the device's time zone. Anything that is
 * not a day reads as null, so a caller can leave the date out.
 */
export function formatDateKey(locale: string, value: unknown): string | null {
  if (typeof value !== "string") return null;
  const match = DATE_KEY.exec(value);
  if (!match) return null;
  const [, year, month, day] = match;
  const date = new Date(Date.UTC(Number(year), Number(month) - 1, Number(day)));
  if (Number.isNaN(date.getTime()) || date.getUTCDate() !== Number(day)) return null;
  return new Intl.DateTimeFormat(locale, { day: "numeric", month: "short", year: "numeric", timeZone: "UTC" }).format(date);
}

/** The earliest `YYYY-MM-DD` among `values` (keys sort as text), or null. */
export function earliestDateKey(values: unknown[]): string | null {
  const keys = values.filter((value): value is string => typeof value === "string" && DATE_KEY.test(value));
  return keys.length ? keys.map((key) => key.slice(0, 10)).sort()[0] : null;
}
