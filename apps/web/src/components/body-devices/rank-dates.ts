/** «3/2025»: the month an award was given (a calendar date, no time zone). */
export function formatRankDate(isoDate: string, locale: string): string {
  const [year, month] = isoDate.split("-").map(Number);
  if (!year || !month) return isoDate;
  return new Intl.DateTimeFormat(locale, { month: "numeric", year: "numeric", timeZone: "UTC" }).format(Date.UTC(year, month - 1, 1));
}

/** Today as YYYY-MM-DD on this device's calendar. */
export function todayIso(now: Date = new Date()): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}
