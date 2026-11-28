"use client";

import { useEffect, useMemo, useState } from "react";
import { useLocale } from "next-intl";

import {
  fetchAdminUserSchedule,
  programAdminUserWorkout,
  programWorkoutForUsers,
  type AdminUserProgramming,
  type AdminUserSchedule,
  type MemberProgrammingMode,
} from "@/api/admin-users";
import { fetchSchedule, type ScheduleSlot } from "@/api/schedule";
import {
  duplicateWorkout,
  listAdminWorkouts,
  listWorkoutFolders,
  type WorkoutFolder,
  type WorkoutRecord,
} from "@/api/workouts";
import { ContextualWorkoutCreator } from "@/components/workouts/creation/ContextualWorkoutCreator";
import { compareFolders, folderDisplayName } from "@/components/workouts/library/library-folders";
import { localizeAdminAssignmentError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import {
  MEMBER_PROGRAMMING_MODES,
  canProgramMorePeople,
  modeRequiresBookedClass,
  modeRequiresProgrammingEntitlement,
  dayFormatter,
  offerableClasses,
  programmingBlocker,
  programmingSources,
  programmingSuccessKey,
  sourceOpensEditor,
  type ProgrammingSource,
} from "@/lib/member-programming";
import { useOrganizationTimeZone } from "@/lib/organization-slug";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { AdditionalPeoplePicker, type PickedPerson } from "@/components/admin/users/AdditionalPeoplePicker";
import { GroupOutcomeList } from "@/components/workouts/GroupOutcomeList";
import { groupOutcomeRows, memberClassWorkoutId, type GroupOutcomeRow } from "@/lib/group-variations";
import { clockFormat } from "@/lib/clock";

type Props = {
  token: string;
  userId: string;
  role: "member" | "athlete" | "admin";
  /** The person's nickname, shown in the outcome when more people are programmed (ADR-201). */
  nickname?: string;
  /** When set, opens the assignment dialog for this day (used by the profile's quick action). */
  assignRequestDate?: string | null;
  onAssignRequestHandled?: () => void;
  /**
   * ADR-225: whether a WOD may be assigned to the person (their subscription
   * package includes online programming or personal training). When it is
   * `allowed: false`, assigning is closed up front with the reason; for a
   * member, changing the WOD of a booked class stays open.
   */
  programming?: AdminUserProgramming | null;
};

// Outcome-first labels: each says who gets the change; the full explanation sits under it.
const MODE_LABEL_KEYS: Record<MemberProgrammingMode, string> = {
  class_variant: "programmingModeVariant",
  personal: "programmingModePersonal",
  class_workout: "programmingModeClass",
};

const MODE_HINT_KEYS: Record<MemberProgrammingMode, string> = {
  class_variant: "memberProgrammingModeClassVariantHint",
  personal: "memberProgrammingModePersonalHint",
  class_workout: "memberProgrammingModeClassWorkoutHint",
};

const SOURCE_LABEL_KEYS: Record<ProgrammingSource, string> = {
  adapt_class: "programmingSourceAdapt",
  class_as_is: "programmingSourceAsIs",
  library: "programmingSourceLibrary",
  new: "programmingSourceNew",
};

const FIELD_STYLE = { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" };

/** A chip-like radio: the selected one carries the primary outline. */
function choiceStyle(selected: boolean) {
  return {
    background: selected ? "color-mix(in srgb, var(--primary) 12%, var(--panel))" : "var(--panel)",
    border: selected ? "1px solid var(--primary)" : "1px solid var(--border)",
    color: "var(--text)",
  };
}

function isoDate(date: Date) {
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 10);
}

function itemDate(item: Record<string, unknown>) {
  const value = item.scheduled_for ?? item.scheduled_at;
  return typeof value === "string" ? value.slice(0, 10) : "";
}

function itemId(item: Record<string, unknown>) {
  return typeof item.id === "string" ? item.id : "";
}

function itemTitle(item: Record<string, unknown>, fallback: string) {
  const workout = item.workout;
  if (workout && typeof workout === "object" && "title" in workout) return String(workout.title);
  if (typeof item.name === "string" && item.name) return item.name;
  return fallback;
}

function isClassItem(item: Record<string, unknown>) {
  return item.kind === "class";
}

function isClassVariantItem(item: Record<string, unknown>) {
  return item.kind === "assignment" && item.assignment_kind === "class_variant";
}

export function UserProgrammingSchedule({ token, userId, role, nickname, assignRequestDate, onAssignRequestHandled, programming }: Props) {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const zone = useOrganizationTimeZone();
  const isMember = role === "member";
  const notInPackage = programming?.allowed === false;
  const [startDate, setStartDate] = useState(() => isoDate(new Date()));
  const [schedule, setSchedule] = useState<AdminUserSchedule | null>(null);
  const [workouts, setWorkouts] = useState<WorkoutRecord[]>([]);
  const [folders, setFolders] = useState<WorkoutFolder[]>([]);
  const [selectedDate, setSelectedDate] = useState(() => isoDate(new Date()));
  const [selectedWorkoutId, setSelectedWorkoutId] = useState("");
  const [selectedFolderId, setSelectedFolderId] = useState("");
  const [selectedSlotId, setSelectedSlotId] = useState("");
  // ADR-785 (ζ): a member's variant of a class is always the default; it
  // needs no programming grant, and nothing ever switches to «for everyone».
  const [memberMode, setMemberMode] = useState<MemberProgrammingMode>("class_variant");
  const [source, setSource] = useState<ProgrammingSource>(() => programmingSources(role, "class_variant")[0]);
  // ADR-785 (1A): the day's classes, for a variant in a class they have not booked.
  const [daySlots, setDaySlots] = useState<ScheduleSlot[]>([]);
  // When the day's classes were read: «still open» is judged against it.
  const [daySlotsAt, setDaySlotsAt] = useState(0);
  const [moreOpen, setMoreOpen] = useState(false);
  const [assignmentModalOpen, setAssignmentModalOpen] = useState(false);
  const [creating, setCreating] = useState(false);
  const [editingDraftId, setEditingDraftId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  // ADR-201: more people who get the same programming, each as if alone.
  const [extraPeople, setExtraPeople] = useState<PickedPerson[]>([]);
  const [outcomeRows, setOutcomeRows] = useState<GroupOutcomeRow[]>([]);

  const needsClass = isMember && modeRequiresBookedClass(memberMode);
  const canAddPeople = canProgramMorePeople(role, memberMode);
  const groupPeople = canAddPeople ? extraPeople : [];
  const sources = programmingSources(role, memberMode);
  const automaticFolderLabel = !isMember
    ? i18n("featureAutoAthleteFolder")
    : memberMode === "class_workout"
      ? i18n("featureAutoClassFolder")
      : i18n("featureAutoMemberVariationFolder");
  const folderLabels = {
    athletes: i18n("featureAthletesFolder"),
    classes: i18n("featureClassesFolder"),
    memberVariations: i18n("featureMemberVariationsFolder"),
  };

  const endDate = useMemo(() => {
    const date = new Date(`${startDate}T12:00:00`);
    date.setDate(date.getDate() + 6);
    return isoDate(date);
  }, [startDate]);

  const days = useMemo(() => Array.from({ length: 7 }, (_, index) => {
    const date = new Date(`${startDate}T12:00:00`);
    date.setDate(date.getDate() + index);
    return isoDate(date);
  }), [startDate]);

  async function reload() {
    const [nextSchedule, nextWorkouts, nextFolders] = await Promise.all([
      fetchAdminUserSchedule(token, userId, startDate, endDate),
      listAdminWorkouts(token),
      listWorkoutFolders(token),
    ]);
    setSchedule(nextSchedule);
    setWorkouts(nextWorkouts.filter((workout) => workout.status === "published"));
    setFolders(nextFolders);
  }

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => {
      void reload().catch((reason) => setError(reason instanceof Error ? reason.message : i18n("featureCouldNotLoadSchedule")));
    });
    return () => window.cancelAnimationFrame(frame);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token, userId, startDate, endDate, i18n]);

  // Every opening starts from the recommended path with extras folded away.
  function openDay(day: string) {
    setSelectedDate(day);
    setSelectedSlotId("");
    setSelectedWorkoutId("");
    setSource(programmingSources(role, memberMode)[0]);
    setMoreOpen(extraPeople.length > 0);
    setError(null);
    setAssignmentModalOpen(true);
  }

  useEffect(() => {
    if (!assignRequestDate) return;
    const frame = window.requestAnimationFrame(() => {
      openDay(assignRequestDate);
      onAssignRequestHandled?.();
    });
    return () => window.cancelAnimationFrame(frame);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [assignRequestDate, onAssignRequestHandled]);

  function chooseMode(mode: MemberProgrammingMode) {
    setMemberMode(mode);
    setSource(programmingSources(role, mode)[0]);
    setError(null);
  }

  useEffect(() => {
    if (!assignmentModalOpen || !isMember) return;
    let active = true;
    // The day as the profile's calendar reads it (a bare ISO date parses as UTC), with a margin.
    const start = new Date(selectedDate);
    start.setUTCDate(start.getUTCDate() - 1);
    const end = new Date(selectedDate);
    end.setUTCDate(end.getUTCDate() + 2);
    fetchSchedule(token, { startAt: start.toISOString(), endAt: end.toISOString(), days: 3, classTypeIds: [] })
      .then((window) => {
        if (!active) return;
        setDaySlots((window.slots ?? []).filter((slot) => slot.scheduled_at.slice(0, 10) === selectedDate));
        setDaySlotsAt(Date.now());
      })
      .catch(() => {
        if (active) setDaySlots([]);
      });
    return () => {
      active = false;
    };
  }, [assignmentModalOpen, isMember, selectedDate, token]);

  const dayItems = (schedule?.items ?? []).filter((item) => itemDate(item) === selectedDate);
  const selectedDaySlots = isMember ? dayItems.filter(isClassItem) : [];
  const bookedSlotIds = new Set(selectedDaySlots.map(itemId));
  // ADR-785 (1A): a variant may also go to a class of that day they have not booked.
  const otherDaySlots =
    isMember && memberMode === "class_variant" ? offerableClasses(daySlots, bookedSlotIds, daySlotsAt) : [];
  const classChoices = selectedDaySlots.length + otherDaySlots.length;
  // One class that day is the only possible answer: pick it for staff.
  const slotId =
    selectedSlotId ||
    (classChoices === 1 ? (selectedDaySlots[0] ? itemId(selectedDaySlots[0]) : otherDaySlots[0].id) : "");
  const selectedSlot = selectedDaySlots.find((item) => itemId(item) === slotId);
  const offeredSlot = selectedSlot ? undefined : otherDaySlots.find((slot) => slot.id === slotId);
  const fullSlot = daySlots.find((slot) => slot.id === slotId);
  const classHasWorkout = typeof selectedSlot?.master_workout_id === "string" || Boolean(offeredSlot?.workout?.id);
  const personalModeClosed = notInPackage && (!isMember || modeRequiresProgrammingEntitlement(memberMode));
  const blocker = personalModeClosed ? "programmingNotInPackageBlocker" : programmingBlocker({
    needsClass,
    hasBookedClasses: classChoices > 0,
    slotId,
    source,
    workoutId: selectedWorkoutId,
    classHasWorkout,
  });

  const longDate = dayFormatter(locale, { weekday: "long", day: "numeric", month: "long" });
  const shortDate = dayFormatter(locale, { day: "numeric", month: "short" });
  const dayCardDate = dayFormatter(locale, { weekday: "short", day: "numeric" });
  const classTime = clockFormat(locale, { hour: "numeric", minute: "2-digit", ...(zone ? { timeZone: zone } : {}) });

  function classLabel(item: Record<string, unknown>) {
    const title = itemTitle(item, i18n("featureScheduledClass"));
    const at = typeof item.scheduled_at === "string" && item.scheduled_at.includes("T") ? new Date(item.scheduled_at) : null;
    return at && !Number.isNaN(at.getTime()) ? `${classTime.format(at)} · ${title}` : title;
  }

  const folderName = selectedFolderId
    ? folders.find((folder) => folder.id === selectedFolderId)
    : null;
  const moreSummary = i18n("programmingMoreSummary", {
    folder: folderName ? folderDisplayName(folderName, folderLabels, locale) : i18n("programmingFolderAuto"),
    count: groupPeople.length,
  });

  function submit() {
    if (blocker || busy) return;
    if (source === "adapt_class") void editClassWorkoutForMember();
    else if (source === "class_as_is") void program(null, true);
    else if (source === "library") void program(selectedWorkoutId, true);
    else openCreator();
  }

  const primaryLabel = sourceOpensEditor(source)
    ? i18n("programmingSubmitEditor")
    : isMember && memberMode === "class_workout"
      ? i18n("programmingSubmitReplaceClass")
      : i18n("programmingSubmitAssign", { count: groupPeople.length + 1 });

  function validateTarget() {
    if (needsClass && !slotId) {
      setError(i18n("featureChooseBookedClass"));
      return false;
    }
    return true;
  }

  async function program(masterWorkoutId: string | null, copySource: boolean) {
    if (!validateTarget()) return;

    setBusy(true);
    setError(null);
    setOutcomeRows([]);
    const body = {
      ...(masterWorkoutId ? { master_workout_id: masterWorkoutId } : {}),
      // Empty = file automatically in the athlete's, class-day or member variations folder.
      folder_id: selectedFolderId || null,
      scheduled_for: selectedDate,
      slot_id: needsClass ? slotId : undefined,
      copy_source: copySource,
      ...(isMember ? { mode: memberMode } : {}),
      // ADR-746/785: a class they have not booked gets the variant and a notice, not a booking.
      ...(isMember && memberMode === "class_variant" && offeredSlot ? { offer_booking: true } : {}),
    };
    try {
      if (groupPeople.length) {
        await programGroup(body);
        return;
      }
      await programAdminUserWorkout(token, userId, body);
      setMessage(i18n(programmingSuccessKey(role, memberMode)));
      setSelectedWorkoutId("");
      setAssignmentModalOpen(false);
      await reload();
    } catch (reason) {
      setError(reason instanceof Error ? localizeAdminAssignmentError(reason, i18n) : i18n("featureProgrammingSaveFailed"));
    } finally {
      setBusy(false);
    }
  }

  // ADR-201: everyone is programmed as if alone. A WOD made just now is
  // filed for this person (as today) and copied for each of the others.
  async function programGroup(body: Parameters<typeof programAdminUserWorkout>[2]) {
    const names = new Map<string, string>([
      [userId, nickname ?? userId],
      ...groupPeople.map((person): [string, string] => [person.id, person.nickname]),
    ]);
    const others = groupPeople.map((person) => person.id);
    let rows: GroupOutcomeRow[];
    if (body.copy_source) {
      const response = await programWorkoutForUsers(token, { ...body, user_ids: [userId, ...others] });
      rows = groupOutcomeRows(response.results, names);
    } else {
      await programAdminUserWorkout(token, userId, body);
      const response = await programWorkoutForUsers(token, { ...body, copy_source: true, user_ids: others });
      rows = [{ userId, nickname: names.get(userId) ?? userId, ok: true }, ...groupOutcomeRows(response.results, names)];
    }
    setOutcomeRows(rows);
    setMessage(null);
    setSelectedWorkoutId("");
    setExtraPeople([]);
    setAssignmentModalOpen(false);
    await reload();
  }

  function openCreator() {
    useWorkoutCreationStore.getState().resetDraft();
    setEditingDraftId(null);
    setCreating(true);
  }

  // ADR-125: duplicate the class's workout into a draft and edit it in the
  // embedded canvas; publishing assigns it as this member's version.
  async function editClassWorkoutForMember() {
    if (!validateTarget()) return;
    // ADR-785 (3A): from the WOD they do in that class (their pick, else «Τώρα»).
    const sourceWorkoutId =
      (fullSlot ? memberClassWorkoutId(fullSlot, userId) : null) ??
      (typeof selectedSlot?.master_workout_id === "string" ? selectedSlot.master_workout_id : null) ??
      offeredSlot?.workout?.id ??
      null;
    if (!sourceWorkoutId) {
      setError(i18n("memberProgrammingClassHasNoWorkout"));
      return;
    }

    setBusy(true);
    setError(null);
    try {
      const draft = await duplicateWorkout(token, sourceWorkoutId, { slot_id: slotId });
      useWorkoutCreationStore.getState().resetDraft();
      setEditingDraftId(draft.id);
      setCreating(true);
    } catch (reason) {
      setError(reason instanceof Error ? localizeAdminAssignmentError(reason, i18n) : i18n("featureProgrammingSaveFailed"));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap gap-2">
          <button type="button" className="rounded-full px-3 py-2 text-sm" style={{ background: "var(--panel-muted)" }} onClick={() => {
            const date = new Date(`${startDate}T12:00:00`); date.setDate(date.getDate() - 7); setStartDate(isoDate(date));
          }}><span aria-hidden="true" className="inline-block rtl:-scale-x-100">←</span> {i18n("featurePreviousWeek")}</button>
          <button type="button" className="rounded-full px-3 py-2 text-sm" style={{ background: "var(--panel-muted)" }} onClick={() => setStartDate(isoDate(new Date()))}>{i18n("featureToday")}</button>
          <button type="button" className="rounded-full px-3 py-2 text-sm" style={{ background: "var(--panel-muted)" }} onClick={() => {
            const date = new Date(`${startDate}T12:00:00`); date.setDate(date.getDate() + 7); setStartDate(isoDate(date));
          }}>{i18n("featureNextWeek")} <span aria-hidden="true" className="inline-block rtl:-scale-x-100">→</span></button>
        </div>
        <p className="text-xs" style={{ color: "var(--muted)" }}>{shortDate.formatRange(startDate, endDate)}</p>
      </div>

      <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-7">
        {days.map((day) => {
          const items = (schedule?.items ?? []).filter((item) => itemDate(item) === day);
          return <button key={day} type="button" data-testid={`programming-day-${day}`} className="min-h-28 rounded-2xl p-3 text-start" style={{ background: selectedDate === day ? "color-mix(in srgb, var(--primary) 14%, var(--panel-muted))" : "var(--panel-muted)", border: selectedDate === day ? "1px solid var(--primary)" : "1px solid var(--border)" }} onClick={() => openDay(day)}>
            <span className="block text-xs font-semibold">{dayCardDate.format(day)}</span>
            <span className="mt-2 block text-xs" style={{ color: "var(--muted)" }}>{items.length ? i18n("featureScheduledCount", { count: items.length }) : i18n("featureOpenDay")}</span>
            {items.slice(0, 2).map((item) => <span key={itemId(item)} className="mt-1 block truncate text-xs">
              {isClassVariantItem(item) ? <span style={{ color: "var(--primary)" }}>{i18n("memberProgrammingClassVersionBadge")} · </span> : null}
              {itemTitle(item, i18n("featureScheduledClass"))}
            </span>)}
          </button>;
        })}
      </div>

      {notInPackage ? <p data-testid="programming-not-in-package" className="rounded-2xl px-4 py-3 text-sm leading-5" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}>
        {i18n("programmingNotInPackageNotice", { name: nickname ?? "" })}
        {isMember ? <> {i18n("programmingNotInPackageMemberHint")}</> : null}
      </p> : null}
      {message ? <p className="text-sm" style={{ color: "var(--success)" }}>{message}</p> : null}
      {/* ADR-214: while the dialog is open, its errors show only inside it. */}
      {error && !assignmentModalOpen ? <ErrorNotice>{error}</ErrorNotice> : null}
      <GroupOutcomeList rows={outcomeRows} />

      {assignmentModalOpen ? <Dialog
        onClose={() => setAssignmentModalOpen(false)}
        dismissible={!busy}
        eyebrow={nickname ? i18n("programmingDialogEyebrowFor", { name: nickname }) : i18n("featureScheduleProgramming")}
        title={<span className="first-letter:uppercase">{longDate.format(selectedDate)}</span>}
        size="lg"
        variant="sheet"
        testId="programming-dialog"
        error={error}
        onSubmit={(event) => {
          event.preventDefault();
          submit();
        }}
        footerStart={blocker && blocker !== "programmingDialogNoClass" ? <p className="text-xs" data-testid="programming-blocker" style={{ color: "var(--muted)" }}>{i18n(blocker)}</p> : sourceOpensEditor(source) ? <p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("programmingEditorHint")}</p> : null}
        footer={<div className="ms-auto flex gap-2">
          <button type="button" className="whitespace-nowrap rounded-full px-4 py-2 text-sm font-semibold" style={{ background: "var(--border)", color: "var(--text-soft)" }} onClick={() => setAssignmentModalOpen(false)}>
            {i18n("cancel77dfd21")}
          </button>
          <button type="submit" data-testid="programming-submit" disabled={busy || Boolean(blocker)} className="whitespace-nowrap rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {primaryLabel}
          </button>
        </div>}
      >
        <div className="space-y-5">
          {isMember ? <fieldset>
            <legend className="mb-2 text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("programmingDialogWhat")}</legend>
            <div className="space-y-2">
              {MEMBER_PROGRAMMING_MODES.map((mode) => <label key={mode} className={`flex items-start gap-3 rounded-xl px-3 py-2.5 ${notInPackage && modeRequiresProgrammingEntitlement(mode) ? "cursor-not-allowed opacity-50" : "cursor-pointer"}`} style={choiceStyle(memberMode === mode)}>
                <input type="radio" className="mt-1" name="member-programming-mode" value={mode} checked={memberMode === mode} disabled={notInPackage && modeRequiresProgrammingEntitlement(mode)} onChange={() => chooseMode(mode)} />
                <span className="min-w-0">
                  <span className="block text-sm font-semibold">{i18n(MODE_LABEL_KEYS[mode])}</span>
                  <span className="block text-xs" style={{ color: "var(--muted)" }}>{i18n(MODE_HINT_KEYS[mode])}</span>
                </span>
              </label>)}
            </div>
          </fieldset> : null}

          {needsClass ? classChoices ? <label className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("programmingDialogClass")}
            <Select className="mt-2 w-full rounded-xl px-3 py-2 text-sm" style={FIELD_STYLE} value={slotId} onValueChange={(value) => { setSelectedSlotId(value); setError(null); }} data-testid="programming-class">
              <option value="">{i18n("programmingDialogChooseClass")}</option>
              {otherDaySlots.length && selectedDaySlots.length ? <optgroup label={i18n("programmingDialogBookedClasses")}>
                {selectedDaySlots.map((item) => <option key={itemId(item)} value={itemId(item)}>{classLabel(item)}</option>)}
              </optgroup> : selectedDaySlots.map((item) => <option key={itemId(item)} value={itemId(item)}>{classLabel(item)}</option>)}
              {otherDaySlots.length ? <optgroup label={i18n("programmingDialogOtherClasses")}>
                {otherDaySlots.map((slot) => <option key={slot.id} value={slot.id}>{classLabel({ ...slot, name: slot.name || slot.class_type?.name })}</option>)}
              </optgroup> : null}
            </Select>
            {offeredSlot ? <span className="mt-1.5 block text-xs font-normal" style={{ color: "var(--muted)" }} data-testid="programming-offered-hint">{i18n("programmingDialogOfferedHint")}</span> : null}
          </label> : <p className="rounded-xl px-3 py-2.5 text-sm" data-testid="programming-no-class" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}>{i18n(memberMode === "class_variant" ? "programmingDialogNoOpenClass" : "programmingDialogNoClass")}</p> : null}

          {!(needsClass && !classChoices) ? <fieldset>
            <legend className="mb-2 text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("programmingDialogWorkout")}</legend>
            <div className="flex flex-wrap gap-2">
              {sources.map((option) => <label key={option} className="cursor-pointer whitespace-nowrap rounded-full px-3 py-1.5 text-sm font-semibold has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2" style={choiceStyle(source === option)}>
                <input type="radio" className="sr-only" name="programming-source" value={option} checked={source === option} onChange={() => { setSource(option); setError(null); }} />
                {i18n(SOURCE_LABEL_KEYS[option])}
              </label>)}
            </div>
            {source === "library" ? <Select aria-label={i18n("featureExistingWod")} className="mt-3 w-full rounded-xl px-3 py-2 text-sm" style={FIELD_STYLE} value={selectedWorkoutId} onValueChange={(value) => { setSelectedWorkoutId(value); setError(null); }}>
              <option value="">{i18n("programmingDialogChooseWod")}</option>
              {workouts.map((workout) => <option key={workout.id} value={workout.id}>{workout.title}</option>)}
            </Select> : null}
          </fieldset> : null}

          <div className="border-t pt-3" style={{ borderColor: "var(--border)" }}>
            <button type="button" className="flex w-full items-center justify-between gap-3 text-start" aria-expanded={moreOpen} aria-controls="programming-more" onClick={() => setMoreOpen((open) => !open)}>
              <span className="min-w-0">
                <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("programmingMoreOptions")}</span>
                {!moreOpen ? <span className="block truncate text-xs" style={{ color: "var(--muted)" }}>{moreSummary}</span> : null}
              </span>
              <span aria-hidden="true" style={{ color: "var(--muted)" }}>{moreOpen ? "▴" : "▾"}</span>
            </button>
            {moreOpen ? <div id="programming-more" className="mt-3 space-y-3">
              <label className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{i18n("programmingFolder")}
                <Select className="mt-2 w-full rounded-xl px-3 py-2 text-sm" style={FIELD_STYLE} value={selectedFolderId} onValueChange={(value) => setSelectedFolderId(value)}>
                  <option value="">{automaticFolderLabel}</option>
                  {[...folders].sort(compareFolders).map((folder) => (
                    <option key={folder.id} value={folder.id}>
                      {folderDisplayName(folder, folderLabels, locale)}
                    </option>
                  ))}
                </Select>
              </label>
              {canAddPeople ? <AdditionalPeoplePicker token={token} excludeUserId={userId} picked={extraPeople} onChange={setExtraPeople} needsBooking={needsClass} collapsible={false} /> : null}
            </div> : null}
          </div>
        </div>
      </Dialog> : null}

      {creating ? <ContextualWorkoutCreator target={[nickname, selectedDate].filter(Boolean).join(" · ") || null} draftId={editingDraftId} onClose={() => { setCreating(false); setEditingDraftId(null); }} onPublished={(workoutId) => program(workoutId, false)} /> : null}
    </div>
  );
}
