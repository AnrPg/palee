"use client";

import { useEffect, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import Link from "next/link";

import { CHECK_IN_RULES_KEY, fetchCheckInRules } from "@/api/check-in";
import type { DayWorkout } from "@/api/day-workouts";
import { classWorkouts, type ClassAction, type ScheduleBooking, type ScheduleCoach, type ScheduleSlot } from "@/api/schedule";
import { fetchClassVisitBadges, visitBadgesKey } from "@/api/training-floor";
import { ClassNoticeDialog } from "@/components/channels/ClassNoticeDialog";
import { ClassStateNotice, classActionsFor } from "@/components/schedule/ClassState";
import { ClassVariationDialog } from "@/components/schedule/ClassVariationDialog";
import type { VariationPerson } from "@/lib/group-variations";
import { slotCoachName } from "@/components/schedule/member-booking";
import { ClassRoomDialog } from "@/components/spaces/ClassRoomDialog";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { MoreMenu, type MoreMenuItem } from "@/components/ui/MoreMenu";
import { InjuryWarningBadge, RosterInjuryWarningsPanel, useSlotInjuryWarnings } from "@/components/wellbeing/InjuryWarnings";
import { useSession } from "@/components/session-provider";
import { FeltSummaryCard } from "@/components/wod-goals/FeltSummaryCard";
import { WorkoutEditModal } from "@/components/workouts/WorkoutEditModal";
import { YourTime } from "@/components/zoned-time";
import { useUiTranslations } from "@/i18n/ui";
import { formatMinutes } from "@/lib/duration-parts";
import { downloadIcsEvent } from "@/lib/ics";
import { warningLevelFor, warningLevelsByUser } from "@/lib/injury-warnings";
import { selectedMembership } from "@/lib/membership-role";
import { adminHref, useOrganizationMemberships, useOrganizationSlug } from "@/lib/organization-slug";
import { SPARK_ACTIVE_STYLE, SPARK_GO_STYLE } from "@/lib/spark";
import { workoutTypeColor } from "@/lib/workout-colors";
import { zonedText } from "@/lib/zoned-time";
import { mayAddToClass } from "./add-to-class";
import { classPhase, minutesUntilStart, nextPhaseChange, staffCheckInOpen, type ClassPhase } from "./class-phase";
import { StaffClassRoster, initials, useBookingLabel } from "./StaffClassRoster";
import { StaffClassWod } from "./StaffClassWod";
import { useClassWodLink } from "./use-class-wod-link";
import { useLiveWodSwitch } from "./use-live-wod-switch";

export type StaffClassPageProps = {
  slot: ScheduleSlot;
  /** ADR-179: the gym's zone; the class shows on its clock. */
  timeZone: string | null;
  accessToken: string;
  onClose: () => void;
  onEdit: () => void;
  onDuplicate?: () => void;
  onDelete?: () => void;
  /** ADR-200: pause, resume, cancel, restore or delete (upcoming classes). */
  onClassAction?: (action: ClassAction) => void;
  onApproveBooking: (booking: ScheduleBooking) => void;
  onRejectBooking: (booking: ScheduleBooking) => void;
  /** Reloads the class after a change made here (a WOD linked, attendance). */
  onSlotChanged?: () => void;
  coaches?: ScheduleCoach[];
  /** ADR-201: staff who manage coaching can give attendees a variation. */
  canProgramVariations: boolean;
  /** ADR-230: the day WOD that covers this class, if any. */
  dayWorkout: DayWorkout | null;
};

const BAR_BUTTON = "flex min-h-12 items-center justify-center whitespace-nowrap rounded-full px-4 text-sm font-bold";

/** Re-renders at the next moment the class's phase or check-in window changes, and each minute while it is close. */
function usePhaseClock(slot: ScheduleSlot, windowBefore: number | null | undefined) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const next = nextPhaseChange(slot, now, windowBefore);
    if (next === null) return;
    // «Σε 20′» counts down by the minute; otherwise wait for the next boundary.
    const phase = classPhase(slot, now);
    const wait = phase === "soon" ? Math.min(60_000, next - now) : next - now;
    // setTimeout holds at most ~24.8 days; a class further out re-checks then.
    const timer = window.setTimeout(() => setNow(Date.now()), Math.min(Math.max(wait, 1_000), 2_000_000_000));
    return () => window.clearTimeout(timer);
  }, [slot, now, windowBefore]);
  return now;
}

/**
 * The class page for staff and coaches (ANR pick A, 2026-11-21), one column
 * on every screen (on a wide one, a side drawer about as wide as a phone),
 * the most important things first:
 *
 * 1. the class itself: name, when (with «Σε 20′» / «Τώρα»), room, coach, and
 *    its settings in one tappable line; editing sits on ✎ and ⋯ at the top;
 * 2. what waits for a decision: booking requests (with their buttons) and
 *    injury warnings;
 * 3. the WOD, the screen's one Deep hero card, with its own ⋯;
 * 4. «Συμμετέχοντες», with «Ήρθε;» once the box's check-in window opens;
 * 5. a bar at the bottom whose actions follow the time: editing the class or
 *    its WOD beforehand, «Έναρξη τμήματος» from 30′ before, «Διάλεξε WOD»
 *    whenever the WOD is missing.
 */
export function StaffClassPage({
  slot,
  timeZone,
  accessToken,
  onClose,
  onEdit,
  onDuplicate,
  onDelete,
  onClassAction,
  onApproveBooking,
  onRejectBooking,
  onSlotChanged,
  coaches,
  canProgramVariations,
  dayWorkout,
}: StaffClassPageProps) {
  const i18n = useUiTranslations();
  const t = useTranslations("StaffClass");
  const tSchedule = useTranslations("Schedule");
  const tSpaces = useTranslations("Spaces");
  const tSms = useTranslations("Sms");
  const rulesT = useTranslations("BookingRules");
  const locale = useLocale();
  const organizationSlug = useOrganizationSlug();
  const memberships = useOrganizationMemberships();
  const { currentUser } = useSession();
  const membership = selectedMembership(Array.isArray(memberships.data) ? memberships.data : [], organizationSlug);
  const personLabel = useBookingLabel();

  const [settingsOpen, setSettingsOpen] = useState(false);
  const [noticeOpen, setNoticeOpen] = useState(false);
  const [editWorkoutOpen, setEditWorkoutOpen] = useState(false);
  // ADR-785: null = closed; [] = «Παραλλαγή για άτομα»; one person from their roster row.
  const [variationPeople, setVariationPeople] = useState<VariationPerson[] | null>(null);
  const [roomOpen, setRoomOpen] = useState(false);

  // The box's «Ρυθμίσεις › Check-in» window; its default when the role can't read it.
  const rules = useQuery({
    queryKey: CHECK_IN_RULES_KEY,
    queryFn: () => fetchCheckInRules(accessToken),
    enabled: Boolean(accessToken),
    retry: false,
    staleTime: 5 * 60_000,
  });
  const windowBefore = rules.data?.window_before_minutes;
  const now = usePhaseClock(slot, windowBefore);
  const phase = classPhase(slot, now);
  // ADR-785 (α): variations from now until the class ends, never for a cancelled one.
  const variationsOpen = canProgramVariations && phase !== "ended" && !slot.cancelled_at;
  const isPast = Date.parse(slot.scheduled_at) <= now;
  const checkInOpen = !slot.cancelled_at && staffCheckInOpen(slot, now, windowBefore);

  const pending = slot.bookings.filter((booking) => booking.status === "pending");
  const hasBookedMembers = slot.bookings.some((booking) => booking.status === "approved" || booking.status === "pending");
  const slotInjuryWarnings = useSlotInjuryWarnings(accessToken, slot.id, Boolean(slot.workout) && hasBookedMembers);
  const injuryLevels = warningLevelsByUser(slotInjuryWarnings.data?.athletes ?? []);
  // ADR-359: who is new in this class; a role without the right (403) sees no badges.
  const visitBadges = useQuery({
    queryKey: visitBadgesKey(slot.id),
    queryFn: () => fetchClassVisitBadges(accessToken, slot.id),
    enabled: hasBookedMembers && Boolean(accessToken),
    retry: false,
    staleTime: 60_000,
  });
  const bookingNames = new Map(slot.bookings.map((booking) => [booking.user_id, personLabel(booking)]));

  const wod = useClassWodLink({ slot, accessToken, timeZone, onLinked: onSlotChanged });
  // ADR-746: the class's WODs; the hero shows one, «Τώρα» first.
  const tWods = useTranslations("ClassWods");
  const liveSwitch = useLiveWodSwitch({ slot, accessToken, onChanged: onSlotChanged });
  const workouts = classWorkouts(slot);
  const liveId =
    slot.live_workout_id && workouts.some((item) => item.id === slot.live_workout_id)
      ? slot.live_workout_id
      : (workouts[0]?.id ?? null);
  const [viewedId, setViewedId] = useState<string | null>(null);
  const viewed = workouts.find((item) => item.id === viewedId) ?? workouts.find((item) => item.id === liveId) ?? null;
  const viewedIndex = viewed ? workouts.indexOf(viewed) : 0;
  const coachName = slotCoachName(slot, coaches);
  const typeColor = workoutTypeColor(slot.class_type.slug);
  // ADR-200: pause/resume, cancel/restore and delete apply to upcoming classes only.
  const stateActions = onClassAction && !isPast ? classActionsFor(slot) : [];

  function addToCalendar() {
    downloadIcsEvent({
      title: slot.name || slot.class_type.name,
      date: slot.scheduled_at.slice(0, 10),
      datetime: slot.scheduled_at,
      durationMinutes: slot.duration_minutes,
    });
  }

  // One menu for the class, opened from ⋯ at the top or from the bottom bar.
  const classMenu: MoreMenuItem[] = [
    { label: i18n("editSlot4754d1f"), onSelect: onEdit, testId: "class-menu-edit" },
    ...(onDuplicate ? [{ label: tSchedule("duplicateClass"), onSelect: onDuplicate }] : []),
    ...(slot.cancelled_at ? [] : [{ label: i18n("addToCalendar4f05cd6"), onSelect: addToCalendar }]),
    ...(hasBookedMembers && !isPast ? [{ label: tSms("noticeTitle"), onSelect: () => setNoticeOpen(true) }] : []),
    ...stateActions
      .filter((action) => action !== "restore" && action !== "resume" && action !== "delete")
      .map((action) => ({
        label: tSchedule(`classAction_${action}`),
        onSelect: () => onClassAction?.(action),
        tone: action === "cancel" ? ("danger" as const) : undefined,
      })),
    ...(onDelete || onClassAction
      ? [
          {
            label: i18n("deletef6fdbe4"),
            onSelect: () => (onClassAction ? onClassAction("delete") : onDelete?.()),
            tone: "danger" as const,
          },
        ]
      : []),
  ];

  // One menu for the WOD, opened from its card's ⋯ or from the bottom bar.
  const several = workouts.length > 1;
  const wodMenu: MoreMenuItem[] = [
    ...(viewed && several && viewed.id !== liveId
      ? [{ label: tWods("makeLive"), onSelect: () => void liveSwitch.request(viewed.id), testId: "class-wod-make-live" }]
      : []),
    ...(viewed ? [{ label: t("editWod"), onSelect: () => setEditWorkoutOpen(true) }] : []),
    { label: viewed ? t("changeWod") : tSchedule("wodPickerChoose"), onSelect: () => wod.openPicker(viewedIndex) },
    ...(viewed && several && viewedIndex > 0
      ? [{ label: tWods("moveEarlier"), onSelect: () => void wod.move(viewed.id, -1) }]
      : []),
    ...(viewed && several && viewedIndex < workouts.length - 1
      ? [{ label: tWods("moveLater"), onSelect: () => void wod.move(viewed.id, 1) }]
      : []),
    // ADR-201: without a class WOD, the dialog asks which WOD to start from.
    ...(variationsOpen ? [{ label: i18n("groupVariationAction"), onSelect: () => setVariationPeople([]) }] : []),
    ...(viewed && several
      ? [
          {
            label: tWods("removeWod"),
            tone: "danger" as const,
            testId: "class-wod-remove",
            onSelect: () => {
              setViewedId(null);
              void wod.remove(viewed.id);
            },
          },
        ]
      : []),
  ];

  const approvalValue = slot.auto_approve ? i18n("autoc614ba7") : i18n("manual4e836fd");
  // ADR-226: how long a booking request waits for staff, in words.
  const approvalWaitValue = slot.auto_approve
    ? rulesT("answerInstant")
    : slot.booking_timeout_minutes === null
      ? rulesT("untilStart")
      : formatMinutes(slot.booking_timeout_minutes, locale);

  const phasePill = slot.cancelled_at ? null : phase === "soon" ? (
    <span className="rounded-full px-2.5 py-0.5 text-xs font-bold" style={SPARK_ACTIVE_STYLE} data-testid="class-phase">
      {t("phaseSoon", { minutes: minutesUntilStart(slot, now) })}
    </span>
  ) : phase === "live" ? (
    <span className="rounded-full px-2.5 py-0.5 text-xs font-bold" style={SPARK_ACTIVE_STYLE} data-testid="class-phase">
      {t("phaseLive")}
    </span>
  ) : phase === "ended" ? (
    <span
      className="rounded-full px-2.5 py-0.5 text-xs font-bold"
      style={{ background: "var(--panel-muted)", color: "var(--muted)" }}
      data-testid="class-phase"
    >
      {t("phaseEnded")}
    </span>
  ) : null;

  const injuryPanel = slotInjuryWarnings.data ? (
    <RosterInjuryWarningsPanel
      accessToken={accessToken}
      slotId={slot.id}
      workoutId={slotInjuryWarnings.data.workout_id}
      athletes={slotInjuryWarnings.data.athletes}
      level={slotInjuryWarnings.data.level}
      nameFor={(userId) => bookingNames.get(userId) ?? i18n("injuryWarningUnknownPerson")}
    />
  ) : slotInjuryWarnings.isError ? (
    <ErrorNotice variant="field">{i18n("injuryWarningLoadFailed")}</ErrorNotice>
  ) : null;

  return (
    <>
      <Dialog onClose={onClose} bare variant="drawer" size="lg" ariaLabel={slot.class_type.name}>
        <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain">
          {/* Top bar: what this is, ✎ and ⋯ away from the thumb, and close. */}
          <div
            className="sticky top-0 z-10 flex items-center justify-between gap-3 px-4 py-3 sm:px-6"
            style={{ background: "var(--panel)", borderBottom: "1px solid var(--border)" }}
          >
            <p className="min-w-0 truncate text-xs font-bold uppercase tracking-[0.24em]" style={{ color: typeColor }}>
              {slot.class_type.name}
            </p>
            <div className="flex shrink-0 items-center gap-1.5">
              <div className="flex items-center gap-1.5" data-testid="class-actions">
                <button
                  type="button"
                  aria-label={i18n("editSlot4754d1f")}
                  title={i18n("editSlot4754d1f")}
                  className="flex h-10 w-10 items-center justify-center rounded-full text-base"
                  style={{ background: "var(--card)", color: "var(--text-soft)" }}
                  onClick={onEdit}
                >
                  <span aria-hidden="true">✎</span>
                </button>
                <MoreMenu variant="pill" label={tSchedule("classMoreActions")} testId="class-more-actions" items={classMenu} />
              </div>
              <button
                className="shrink-0 rounded-full px-3 py-2 text-sm font-semibold"
                style={{ background: "var(--card)", color: "var(--text-soft)" }}
                onClick={onClose}
                type="button"
              >
                {i18n("closefeb3e25")}
              </button>
            </div>
          </div>

          <div className="space-y-5 px-4 pb-6 pt-4 sm:px-6">
            {/* 1 · The class. */}
            <header className="space-y-3">
              <div>
                <h2 className="text-3xl font-semibold leading-tight" style={{ color: "var(--text)" }}>
                  {slot.name || slot.class_type.name}
                </h2>
                <p className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-sm" style={{ color: "var(--muted)" }}>
                  {phasePill}
                  <span>
                    {zonedText(slot.scheduled_at, timeZone, locale, {
                      weekday: "long",
                      month: "short",
                      day: "numeric",
                      hour: "numeric",
                      minute: "2-digit",
                    })}
                  </span>
                  <YourTime at={slot.scheduled_at} zone={timeZone} format="day-time" />
                  {slot.space ? (
                    // A decorative separator, kept out of the label.
                    <span aria-hidden="true">·</span>
                  ) : null}
                  {slot.space?.viewable ? (
                    // ADR-290: the room on the floor plan.
                    <button
                      type="button"
                      data-testid="slot-space"
                      className="font-semibold underline-offset-2 hover:underline"
                      style={{ color: "var(--primary)" }}
                      onClick={() => setRoomOpen(true)}
                    >
                      {tSpaces("classSpaceAt", { space: slot.space.name })}
                    </button>
                  ) : slot.space ? (
                    <span data-testid="slot-space">{tSpaces("classSpaceAt", { space: slot.space.name })}</span>
                  ) : null}
                </p>
              </div>
              {coachName ? (
                <p className="flex items-center gap-2 text-sm" style={{ color: "var(--text)" }}>
                  <span
                    aria-hidden="true"
                    className="flex h-8 w-8 items-center justify-center rounded-full text-xs font-bold"
                    style={{ background: "color-mix(in srgb, var(--primary) 14%, var(--panel))", color: "var(--primary)" }}
                  >
                    {initials(coachName)}
                  </span>
                  <span data-testid="slot-coach">{tSchedule("classCoachChip", { coach: coachName })}</span>
                </p>
              ) : null}

              {/* The settings, one line; the details and «Επεξεργασία» one tap away. */}
              <button
                type="button"
                data-testid="class-settings"
                aria-haspopup="dialog"
                aria-label={t("settingsOpen", {
                  booked: slot.approved_booking_count,
                  capacity: slot.capacity,
                  approval: approvalValue,
                  answer: approvalWaitValue,
                })}
                className="grid w-full grid-cols-[1fr_1fr_1fr_auto] items-stretch overflow-hidden rounded-2xl text-start"
                style={{ border: "1px solid var(--border)", background: "var(--panel)" }}
                onClick={() => setSettingsOpen(true)}
              >
                <StripCell value={`${slot.approved_booking_count}/${slot.capacity}`} label={t("stripBookings")} big />
                <StripCell value={approvalValue} label={t("stripApproval")} />
                <StripCell value={approvalWaitValue} label={t("stripAnswer")} testId="slot-approval-wait" />
                <span aria-hidden="true" className="flex items-center px-3 text-lg" style={{ color: "var(--muted)" }}>
                  ›
                </span>
              </button>
            </header>

            <ClassStateNotice
              slot={slot}
              onAction={stateActions.some((action) => action === "restore" || action === "resume") ? onClassAction : undefined}
            />

            {/* 2 · What waits for a decision. */}
            {pending.length || injuryPanel || slot.space_unavailable || slot.space_overlap ? (
              <div className="space-y-3" data-testid="class-attention">
                {pending.length ? (
                  <section
                    aria-labelledby={`class-pending-${slot.id}`}
                    className="rounded-2xl p-4"
                    style={{
                      background: "color-mix(in srgb, var(--primary) 9%, var(--panel))",
                      border: "1px solid color-mix(in srgb, var(--primary) 35%, var(--border))",
                    }}
                    data-testid="class-pending"
                  >
                    <h3 id={`class-pending-${slot.id}`} className="text-sm font-bold" style={{ color: "var(--text)" }}>
                      {t("pendingTitle", { count: pending.length })}
                    </h3>
                    <ul className="mt-2 space-y-2">
                      {pending.map((booking) => (
                        <li key={booking.id} className="flex flex-wrap items-center gap-2">
                          <span className="min-w-0 flex-1 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>
                            {personLabel(booking)}
                          </span>
                          <button
                            type="button"
                            className="min-h-10 rounded-full px-4 text-xs font-bold"
                            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                            onClick={() => onApproveBooking(booking)}
                          >
                            {i18n("approve7b2c7f1")}
                          </button>
                          <button
                            type="button"
                            className="min-h-10 rounded-full px-4 text-xs font-bold"
                            style={{ background: "var(--panel)", border: "1px solid var(--border-strong)", color: "var(--danger)" }}
                            onClick={() => onRejectBooking(booking)}
                          >
                            {i18n("reject2b03b59")}
                          </button>
                        </li>
                      ))}
                    </ul>
                  </section>
                ) : null}
                {injuryPanel}
                {slot.space_unavailable ? (
                  <p data-testid="slot-space-unavailable" className="rounded-2xl px-4 py-3 text-sm font-semibold" style={{ border: "1px solid var(--danger)", color: "var(--danger)" }}>
                    {tSpaces("classSpaceUnavailable")}
                  </p>
                ) : null}
                {slot.space_overlap ? (
                  <p data-testid="slot-space-overlap" className="rounded-2xl px-4 py-3 text-sm font-semibold" style={{ border: "1px solid var(--danger)", color: "var(--danger)" }}>
                    {tSpaces("classSpaceOverlap")}
                  </p>
                ) : null}
              </div>
            ) : null}

            {/* 3 · The WOD and 4 · the people. One column on every screen: on a
                wide one this is a side drawer about as wide as a phone (ANR, 2026-11-21). */}
            <div className="space-y-6">
              <StaffClassWod
                slot={slot}
                accessToken={accessToken}
                isPast={isPast}
                dayWorkout={dayWorkout}
                wod={wod}
                menuItems={wodMenu}
                onChanged={onSlotChanged}
                workout={viewed}
                workouts={workouts}
                liveId={liveId}
                onView={setViewedId}
              />
              {liveSwitch.error ? <ErrorNotice>{liveSwitch.error}</ErrorNotice> : null}
              <div className="space-y-5">
                <StaffClassRoster
                  onVariation={variationsOpen ? (person) => setVariationPeople([person]) : undefined}
                  slot={slot}
                  accessToken={accessToken}
                  checkInOpen={checkInOpen}
                  badgeFor={(booking) => <InjuryWarningBadge level={warningLevelFor(injuryLevels, booking.user_id)} />}
                  visits={visitBadges.data?.people}
                  onChanged={onSlotChanged}
                  workouts={workouts}
                  canAdd={
                    (phase === "upcoming" || phase === "soon") &&
                    !slot.cancelled_at &&
                    !slot.paused_at &&
                    mayAddToClass(membership, slot, currentUser?.id)
                  }
                />
                {/* What members felt in this class (WOD goals, ADR-163). */}
                {slot.workout && phase === "ended" ? <FeltSummaryCard source={{ kind: "slot", id: slot.id }} /> : null}
              </div>
            </div>
          </div>
        </div>

        <ClassBar
          slot={slot}
          phase={phase}
          organizationSlug={organizationSlug}
          classMenu={classMenu}
          wodMenu={wodMenu}
          onChooseWod={() => wod.openPicker(0)}
          onNewWod={wod.openCreator}
        />
      </Dialog>

      {settingsOpen ? (
        <Dialog
          onClose={() => setSettingsOpen(false)}
          title={t("settingsTitle")}
          size="md"
          variant="sheet"
          footer={
            <button
              type="button"
              className="w-full rounded-full px-5 py-3 text-sm font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              onClick={() => {
                setSettingsOpen(false);
                onEdit();
              }}
            >
              {i18n("editSlot4754d1f")}
            </button>
          }
        >
          <dl className="divide-y text-sm" style={{ borderColor: "var(--border)" }}>
            <SettingRow label={i18n("capacity45bd908")} value={t("bookedCount", { booked: slot.approved_booking_count, capacity: slot.capacity })} />
            <SettingRow label={t("waitlist")} value={String(slot.waitlist_count ?? 0)} />
            <SettingRow label={i18n("approval8cc047a")} value={approvalValue} />
            <SettingRow
              label={rulesT("answerTime")}
              value={approvalWaitValue}
              hint={slot.auto_approve ? undefined : rulesT("answerTimeHelp")}
            />
            <SettingRow label={t("duration")} value={formatMinutes(slot.duration_minutes, locale)} />
            {slot.space ? <SettingRow label={t("space")} value={slot.space.name} /> : null}
          </dl>
        </Dialog>
      ) : null}

      {wod.overlays}
      {liveSwitch.overlay}
      {noticeOpen ? (
        <ClassNoticeDialog slotId={slot.id} cancelled={Boolean(slot.cancelled_at)} onClose={() => setNoticeOpen(false)} />
      ) : null}
      {editWorkoutOpen && viewed ? (
        <WorkoutEditModal
          workoutId={viewed.id}
          workoutTitle={viewed.title}
          accessToken={accessToken}
          context={{ kind: "slot", sourceId: slot.id, sourceLabel: i18n("classOnDate", { date: slot.scheduled_at }) }}
          onClose={() => setEditWorkoutOpen(false)}
        />
      ) : null}
      {variationPeople && canProgramVariations ? (
        <ClassVariationDialog
          key={variationPeople.map((person) => person.userId).join(",") || "many"}
          slot={slot}
          accessToken={accessToken}
          initialPeople={variationPeople}
          onClose={() => setVariationPeople(null)}
          onProgrammed={onSlotChanged}
        />
      ) : null}
      {roomOpen && slot.space ? (
        <ClassRoomDialog slotId={slot.id} spaceName={slot.space.name} onClose={() => setRoomOpen(false)} />
      ) : null}
    </>
  );
}

function StripCell({ value, label, big = false, testId }: { value: string; label: string; big?: boolean; testId?: string }) {
  return (
    <span className="min-w-0 px-3 py-2.5" style={{ borderInlineEnd: "1px solid var(--border)" }}>
      <span
        className={`block truncate font-semibold ${big ? "text-lg" : "text-sm"}`}
        style={{ color: "var(--text)" }}
        data-testid={testId}
      >
        {value}
      </span>
      <span className="block truncate text-[11px]" style={{ color: "var(--muted)" }}>
        {label}
      </span>
    </span>
  );
}

function SettingRow({ label, value, hint }: { label: string; value: string; hint?: string }) {
  return (
    <div className="flex items-start justify-between gap-4 py-3" style={{ borderColor: "var(--border)" }}>
      <dt style={{ color: "var(--text-soft)" }}>
        {label}
        {hint ? (
          <span className="mt-0.5 block text-xs" style={{ color: "var(--muted)" }}>
            {hint}
          </span>
        ) : null}
      </dt>
      <dd className="text-end font-semibold" style={{ color: "var(--text)" }}>
        {value}
      </dd>
    </div>
  );
}

/**
 * The thumb's bar (ANR pick A): the one action that matters at this moment.
 * Without a WOD, «Διάλεξε WOD» (Spark) and «+ Νέο WOD». Before the class,
 * «Επεξεργασία τμήματος» and «Επεξεργασία WOD», which open the same menus
 * as their ⋯. From 30′ before until the end, «Έναρξη τμήματος» (Spark) and
 * the wall screen; afterwards both timer links, quietly. Nothing on a
 * cancelled class.
 */
function ClassBar({
  slot,
  phase,
  organizationSlug,
  classMenu,
  wodMenu,
  onChooseWod,
  onNewWod,
}: {
  slot: ScheduleSlot;
  phase: ClassPhase;
  organizationSlug: string | null;
  classMenu: MoreMenuItem[];
  wodMenu: MoreMenuItem[];
  onChooseWod: () => void;
  onNewWod: () => void;
}) {
  const i18n = useUiTranslations();
  const t = useTranslations("StaffClass");
  const tSchedule = useTranslations("Schedule");
  if (slot.cancelled_at) return null;

  const outline = { background: "var(--panel)", border: "1px solid var(--border-strong)", color: "var(--text)" };
  const control = adminHref(`/class-timer/${slot.id}/control`, organizationSlug);
  const display = adminHref(`/class-timer/${slot.id}/display`, organizationSlug);

  let content;
  if (!slot.workout) {
    content = (
      <>
        <button type="button" className={`${BAR_BUTTON} flex-1`} style={SPARK_GO_STYLE} onClick={onChooseWod}>
          {tSchedule("wodPickerChoose")}
        </button>
        <button type="button" className={BAR_BUTTON} style={outline} onClick={onNewWod}>
          + {tSchedule("wodPickerNew")}
        </button>
      </>
    );
  } else if (phase === "upcoming") {
    content = (
      <>
        <div className="flex min-w-0 flex-1 [&>div]:w-full">
          <MoreMenu
            label={i18n("editSlot4754d1f")}
            items={classMenu}
            testId="class-bar-edit-class"
            trigger={{ text: i18n("editSlot4754d1f"), className: `${BAR_BUTTON} w-full`, style: { background: "var(--primary)", color: "var(--primary-contrast)" } }}
          />
        </div>
        <div className="flex min-w-0 flex-1 [&>div]:w-full">
          <MoreMenu
            label={t("editWod")}
            items={wodMenu}
            testId="class-bar-edit-wod"
            trigger={{ text: t("editWod"), className: `${BAR_BUTTON} w-full`, style: outline }}
          />
        </div>
      </>
    );
  } else if (phase === "soon" || phase === "live") {
    content = (
      <>
        <Link href={control} className={`${BAR_BUTTON} flex-1`} style={SPARK_GO_STYLE} data-testid="class-bar-start">
          <span aria-hidden="true" className="me-1.5">
            ▶
          </span>
          {phase === "soon" ? t("startClass") : i18n("classTimerRemoteLink")}
        </Link>
        <Link href={display} target="_blank" className={BAR_BUTTON} style={outline}>
          {t("wallScreen")}
        </Link>
      </>
    );
  } else {
    content = (
      <>
        <Link href={control} className={`${BAR_BUTTON} flex-1`} style={outline}>
          {i18n("classTimerRemoteLink")}
        </Link>
        <Link href={display} target="_blank" className={BAR_BUTTON} style={outline}>
          {t("wallScreen")}
        </Link>
      </>
    );
  }

  return (
    <div
      role="group"
      aria-label={t("barLabel")}
      data-testid="class-bar"
      className="flex shrink-0 items-center gap-2 px-4 pb-[max(0.75rem,env(safe-area-inset-bottom))] pt-3 sm:px-6"
      style={{ background: "var(--panel)", borderTop: "1px solid var(--border)" }}
    >
      {content}
    </div>
  );
}
