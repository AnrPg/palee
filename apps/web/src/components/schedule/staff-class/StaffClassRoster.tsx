"use client";

import { useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import { adminRecordAttendance } from "@/api/admin";
import type { ScheduleBooking, ScheduleSlot } from "@/api/schedule";
import type { ClassVisitPerson } from "@/api/training-floor";
import { splitRoster } from "@/components/schedule/admin-roster";
import { NewTodayCard, VisitBadgeChips } from "@/components/schedule/VisitBadges";
import { SemanticLabel } from "@/components/semantic-label";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { SPARK_ACTIVE_STYLE } from "@/lib/spark";
import { newcomers, visitFor } from "@/lib/training-floor";

/** «Σ» for Σοφία Λ., «ΝΚ» for Νίκος Κ.: the row's avatar, never its only label. */
export function initials(name: string) {
  const words = name.trim().split(/\s+/).filter(Boolean);
  return words
    .slice(0, 2)
    .map((word) => Array.from(word)[0] ?? "")
    .join("")
    .toLocaleUpperCase();
}

/** The person a booking is for: the guest with their host, else the member. */
export function useBookingLabel() {
  const i18n = useUiTranslations();
  return (booking: ScheduleBooking) => {
    const member = booking.user_nickname ?? booking.user_id;
    return booking.guest_name ? i18n("admRosterGuest", { name: booking.guest_name, member }) : member;
  };
}

/**
 * «Συμμετέχοντες» on the staff class page: who is coming, then the waitlist
 * in offer order and members' own versions of the class (ADR-125). Pending
 * requests are not here: they wait at the top of the page with their buttons.
 *
 * From the moment the box's check-in window opens (`checkInOpen`), each
 * booked member gets «Ήρθε;». Whatever records attendance (this button, the
 * member's own check-in, a QR scan at the door) refreshes the page over the
 * schedule topic, so the row turns to «Ήρθε» by itself.
 */
export function StaffClassRoster({
  slot,
  accessToken,
  checkInOpen,
  badgeFor,
  visits,
  onChanged,
}: {
  slot: ScheduleSlot;
  accessToken: string;
  checkInOpen: boolean;
  badgeFor?: (booking: ScheduleBooking) => ReactNode;
  visits?: ClassVisitPerson[];
  onChanged?: () => void;
}) {
  const i18n = useUiTranslations();
  const t = useTranslations("StaffClass");
  const tTrials = useTranslations("Trials");
  const personLabel = useBookingLabel();
  const { booked, waitlist } = splitRoster(slot.bookings);
  const coming = booked.filter((booking) => booking.status !== "pending");
  const approved = coming.filter((booking) => booking.status === "approved");
  // Marked here before the refresh lands, so the tap answers at once.
  const [marked, setMarked] = useState<Record<string, boolean>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const attendanceOf = (booking: ScheduleBooking) =>
    booking.attendance_status ?? (marked[booking.id] ? "attended" : null);
  const arrived = approved.filter((booking) => attendanceOf(booking) === "attended").length;

  async function markArrived(booking: ScheduleBooking) {
    setBusy(booking.id);
    setError(null);
    try {
      await adminRecordAttendance(accessToken, slot.id, booking.user_id, { status: "attended" });
      setMarked((current) => ({ ...current, [booking.id]: true }));
      onChanged?.();
    } catch (reason) {
      setError(localizeError(reason, i18n));
    } finally {
      setBusy(null);
    }
  }

  return (
    <section aria-labelledby={`class-people-${slot.id}`} data-testid="class-roster">
      <div className="flex items-baseline justify-between gap-3">
        <h3 id={`class-people-${slot.id}`} className="text-lg font-semibold" style={{ color: "var(--text)" }}>
          {t("people")}
        </h3>
        <p className="text-xs font-semibold" style={{ color: "var(--muted)" }} data-testid="class-roster-count">
          {checkInOpen && approved.length
            ? t("arrivedCount", { arrived, booked: approved.length })
            : t("bookedCount", { booked: slot.approved_booking_count, capacity: slot.capacity })}
        </p>
      </div>

      <div className="mt-3 space-y-3">
        <NewTodayCard
          people={newcomers(visits).filter((person) => coming.some((booking) => booking.id === person.booking_id))}
          nameFor={(person) => {
            const booking = coming.find((entry) => entry.id === person.booking_id);
            return booking ? personLabel(booking) : (person.guest_name ?? "?");
          }}
        />
        {error ? <ErrorNotice variant="field">{error}</ErrorNotice> : null}
        {coming.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>
            {i18n("noBookingsYetdb81e7a")}
          </p>
        ) : (
          <ul className="divide-y" style={{ borderColor: "var(--border)" }}>
            {coming.map((booking) => {
              const label = personLabel(booking);
              const visit = visitFor(visits, booking.id);
              const attendance = attendanceOf(booking);
              // A guest seat has no attendance of its own.
              const canMark = checkInOpen && booking.status === "approved" && !booking.guest_name;
              return (
                <li key={booking.id} className="flex items-center gap-3 py-2.5" style={{ borderColor: "var(--border)" }}>
                  <span
                    aria-hidden="true"
                    className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full text-xs font-bold"
                    style={{ background: "color-mix(in srgb, var(--primary) 14%, var(--panel))", color: "var(--primary)" }}
                  >
                    {initials(label)}
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="flex flex-wrap items-center gap-1.5 text-sm font-semibold" style={{ color: "var(--text)" }}>
                      <span className="truncate">{label}</span>
                      {booking.kind === "trial" ? (
                        <span className="rounded-full px-2 py-0.5 text-[11px] font-bold" style={SPARK_ACTIVE_STYLE}>
                          {tTrials("tag")}
                        </span>
                      ) : null}
                      {visit ? <VisitBadgeChips badges={visit.badges} via={visit.via} skipTrial={booking.kind === "trial"} /> : null}
                      {badgeFor?.(booking)}
                    </p>
                    {booking.status !== "approved" ? (
                      <p className="mt-0.5 text-xs" style={{ color: "var(--dim)" }}>
                        <SemanticLabel value={booking.status} />
                      </p>
                    ) : null}
                    {booking.admin_message ? (
                      <p className="mt-0.5 text-xs" style={{ color: "var(--muted)" }}>
                        {booking.admin_message}
                      </p>
                    ) : null}
                  </div>
                  {attendance === "attended" ? (
                    <span
                      className="shrink-0 rounded-full px-3 py-1.5 text-xs font-bold"
                      style={SPARK_ACTIVE_STYLE}
                      data-testid="class-arrived"
                    >
                      ✓ {t("arrived")}
                    </span>
                  ) : attendance ? (
                    <span className="shrink-0 text-xs font-semibold" style={{ color: "var(--muted)" }}>
                      <SemanticLabel value={attendance} />
                    </span>
                  ) : canMark ? (
                    <button
                      type="button"
                      disabled={busy === booking.id}
                      aria-label={t("markArrived", { name: label })}
                      className="min-h-10 shrink-0 rounded-full px-3.5 text-xs font-bold disabled:opacity-60"
                      style={{ border: "1px solid var(--border-strong)", color: "var(--text)", background: "var(--panel)" }}
                      onClick={() => void markArrived(booking)}
                    >
                      {t("arrivedQuestion")}
                    </button>
                  ) : null}
                </li>
              );
            })}
          </ul>
        )}
      </div>

      {waitlist.length > 0 ? (
        <div className="mt-5">
          <h4 className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {i18n("admRosterWaitlist", { count: waitlist.length })}
          </h4>
          <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>
            {i18n("admRosterWaitlistHint")}
          </p>
          <ol className="mt-2 space-y-2">
            {waitlist.map((booking, index) => (
              <li
                className="flex items-center gap-3 rounded-2xl px-4 py-2.5 text-sm"
                key={booking.id}
                style={{ background: "var(--panel-muted)" }}
              >
                <span className="w-5 text-center font-semibold tabular-nums" style={{ color: "var(--dim)" }}>
                  {index + 1}
                </span>
                <span className="min-w-0 flex-1 truncate font-semibold" style={{ color: "var(--text)" }}>
                  {personLabel(booking)}
                </span>
                {badgeFor?.(booking)}
                {(booking.waitlist_priority ?? 0) > 0 ? (
                  <span
                    className="rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wider"
                    style={{ background: "color-mix(in srgb, var(--primary) 12%, transparent)", color: "var(--primary)" }}
                  >
                    {i18n("admRosterPriority")}
                  </span>
                ) : null}
              </li>
            ))}
          </ol>
        </div>
      ) : null}

      {(slot.member_versions ?? []).length > 0 ? (
        <div className="mt-5">
          <p className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
            {i18n("memberProgrammingMemberVersions")}
          </p>
          <ul className="mt-2 space-y-2">
            {(slot.member_versions ?? []).map((version) => (
              <li
                key={version.assignment_id}
                className="flex flex-wrap items-center justify-between gap-2 rounded-2xl px-4 py-2 text-sm"
                style={{ background: "var(--panel-muted)" }}
              >
                <span className="font-semibold" style={{ color: "var(--text)" }}>
                  {version.user_nickname ?? version.user_id}
                </span>
                <span style={{ color: "var(--muted)" }}>{version.workout_title}</span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </section>
  );
}
