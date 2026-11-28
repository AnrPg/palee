import type { ScheduleBooking } from "@/api/schedule";

/**
 * Splits a class roster into booked members and the waitlist. The waitlist is
 * in the order spots are offered. The server numbers it (`waitlist_position`:
 * staff «Πρώτος στη σειρά» first, ADR-790, then higher package priority, then
 * earliest to join, ADR-097); without numbers the last two rules apply here.
 */
export function splitRoster(bookings: ScheduleBooking[]) {
  const booked = bookings.filter((booking) => booking.status !== "waitlisted");
  const waitlist = bookings
    .filter((booking) => booking.status === "waitlisted")
    .sort(
      (a, b) =>
        (a.waitlist_position ?? Number.MAX_SAFE_INTEGER) - (b.waitlist_position ?? Number.MAX_SAFE_INTEGER) ||
        (b.waitlist_priority ?? 0) - (a.waitlist_priority ?? 0) ||
        Date.parse(a.inserted_at) - Date.parse(b.inserted_at),
    );
  return { booked, waitlist };
}
