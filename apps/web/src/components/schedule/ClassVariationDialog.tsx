"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useEffect, useMemo, useState } from "react";

import { fetchAdminUsers, programWorkoutForUsers, type ProgramForUsersResult } from "@/api/admin-users";
import { classWorkouts, type ScheduleSlot } from "@/api/schedule";
import { duplicateWorkout, listAdminWorkouts, type WorkoutRecord } from "@/api/workouts";
import { ContextualWorkoutCreator } from "@/components/workouts/creation/ContextualWorkoutCreator";
import { useWorkoutCreationStore } from "@/stores/workout-creation";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { GroupOutcomeList } from "@/components/workouts/GroupOutcomeList";
import { localizeAdminAssignmentError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useDebounced } from "@/hooks/useDebounced";
import {
  GROUP_PROGRAMMING_LIMIT,
  classDay,
  groupOutcomeRows,
  memberClassWorkoutId,
  toggleSelection,
  variationCandidates,
  variationSections,
  type GroupOutcomeRow,
  type VariationPerson,
} from "@/lib/group-variations";

/**
 * ADR-201: «Variation for…» from the class popup. Staff pick several of the
 * class's attendees and a WOD; each one gets their own class version
 * (`class_variant`), exactly as if programmed alone from their profile.
 *
 * ADR-746 (ANR, 2026-11-23): the search finds every member of the box, in
 * two sections that update as you type: those who booked («Έκλεισαν θέση»)
 * first, then «Άλλα μέλη». Someone who has not booked is not booked by it:
 * the WOD is in their programme that day and their notice opens the class.
 *
 * ADR-785 (ANR picks 1A, 3A, 2026-11-28): the roster's «Παραλλαγή μόνο για …»
 * opens it for one person (`initialPeople`). «Ξεκίνα από» defaults to the WOD
 * each person does in the class (their pick, else «Τώρα»); the class's other
 * WODs and the library follow. For one person «Αλλαγές πριν την αποθήκευση»
 * opens the copy in the editor and saves it as their variant on publish. The
 * optional «Γιατί» is shown to the member. No online programming is needed.
 */
export function ClassVariationDialog({
  slot,
  accessToken,
  onClose,
  onProgrammed,
  initialPeople = [],
}: {
  slot: ScheduleSlot;
  accessToken: string;
  onClose: () => void;
  /** ADR-785: start with these people picked (the roster's one-person entry). */
  initialPeople?: readonly VariationPerson[];
  /** Called after at least one person got their version. */
  onProgrammed?: () => void;
}) {
  const i18n = useUiTranslations();
  const candidates = useMemo(
    () => variationCandidates(slot.bookings, slot.member_versions ?? []),
    [slot.bookings, slot.member_versions],
  );
  const tWods = useTranslations("ClassWods");
  const [selected, setSelected] = useState<string[]>(() => initialPeople.map((person) => person.userId));
  const [search, setSearch] = useState("");
  const typed = useDebounced(search.trim(), 250);
  const directory = useQuery({
    queryKey: ["class-variation", "members", typed],
    enabled: typed.length > 0,
    staleTime: 30_000,
    queryFn: () => fetchAdminUsers(accessToken, { q: typed, role: "member", limit: 30 }),
  });
  const sections = useMemo(
    () => variationSections(candidates, typed ? (directory.data?.users ?? []) : [], search),
    [candidates, directory.data, typed, search],
  );
  // Names of everyone picked, so a pick keeps its name after the search changes.
  const [known, setKnown] = useState<ReadonlyMap<string, string>>(
    () => new Map(initialPeople.map((person) => [person.userId, person.nickname] as const)),
  );
  const single = initialPeople.length === 1 ? initialPeople[0] : null;
  const classWods = classWorkouts(slot);
  const [instructions, setInstructions] = useState("");
  const [creating, setCreating] = useState(false);
  const [draftId, setDraftId] = useState<string | null>(null);
  function toggle(person: VariationPerson) {
    setKnown((current) => (current.has(person.userId) ? current : new Map(current).set(person.userId, person.nickname)));
    setSelected((current) => toggleSelection(current, person.userId));
  }
  const [workouts, setWorkouts] = useState<WorkoutRecord[]>([]);
  // Empty = start from the class's own WOD.
  const [workoutId, setWorkoutId] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [rows, setRows] = useState<GroupOutcomeRow[]>([]);

  useEffect(() => {
    let active = true;
    listAdminWorkouts(accessToken)
      .then((list) => {
        if (active) setWorkouts(list.filter((workout) => workout.status === "published"));
      })
      .catch(() => {
        if (active) setWorkouts([]);
      });
    return () => {
      active = false;
    };
  }, [accessToken]);

  const classHasWorkout = Boolean(slot.master_workout_id ?? slot.workout?.id);
  const needsWorkout = !classHasWorkout && !workoutId;
  const classWodIds = new Set(classWods.map((workout) => workout.id));
  const ownWodId = single ? memberClassWorkoutId(slot, single.userId) : null;
  const ownWodTitle = classWods.find((workout) => workout.id === ownWodId)?.title ?? null;
  const defaultSourceLabel = !classHasWorkout
    ? i18n("featureChooseWod")
    : single && ownWodTitle
      ? tWods("variationStartTheirWod", { title: ownWodTitle })
      : classWods.length > 1
        ? tWods("variationStartEachOwn")
        : i18n("groupVariationClassWod");
  // The source an «Αλλαγές πριν την αποθήκευση» copy starts from.
  const adaptSourceId = workoutId || ownWodId;
  const allSelected = candidates.length > 0 && candidates.slice(0, GROUP_PROGRAMMING_LIMIT).every((c) => selected.includes(c.userId));

  async function adapt() {
    if (!single || !adaptSourceId) return;
    setBusy(true);
    setError(null);
    try {
      const draft = await duplicateWorkout(accessToken, adaptSourceId, { slot_id: slot.id });
      useWorkoutCreationStore.getState().resetDraft();
      setDraftId(draft.id);
      setCreating(true);
    } catch (reason) {
      setError(localizeAdminAssignmentError(reason, i18n));
    } finally {
      setBusy(false);
    }
  }

  // The edited copy is the person's variant as it is (no second copy).
  async function saveAdapted(publishedId: string) {
    await submit({ masterWorkoutId: publishedId, copySource: false });
    setCreating(false);
    setDraftId(null);
  }

  async function submit(source?: { masterWorkoutId: string; copySource: boolean }) {
    if (!selected.length || (needsWorkout && !source)) return;
    const chosenId = source?.masterWorkoutId ?? workoutId;
    setBusy(true);
    setError(null);
    try {
      const bookedIds = new Set(candidates.map((candidate) => candidate.userId));
      const groups = [selected.filter((id) => bookedIds.has(id)), selected.filter((id) => !bookedIds.has(id))];
      const results: ProgramForUsersResult[] = [];
      for (const [index, userIds] of groups.entries()) {
        if (!userIds.length) continue;
        const response = await programWorkoutForUsers(accessToken, {
          user_ids: userIds,
          ...(chosenId ? { master_workout_id: chosenId } : {}),
          folder_id: null,
          scheduled_for: classDay(slot.scheduled_at),
          slot_id: slot.id,
          copy_source: source?.copySource ?? true,
          mode: "class_variant",
          ...(instructions.trim() ? { instructions: instructions.trim() } : {}),
          // ADR-746: people who have not booked get the WOD and a notice, not a booking.
          ...(index === 1 ? { offer_booking: true } : {}),
        });
        results.push(...response.results);
      }
      const names = new Map([...candidates.map((candidate) => [candidate.userId, candidate.nickname] as const), ...known]);
      const outcome = groupOutcomeRows(results, names);
      setRows(outcome);
      setSelected([]);
      if (outcome.some((row) => row.ok)) onProgrammed?.();
    } catch (reason) {
      setError(localizeAdminAssignmentError(reason, i18n));
    } finally {
      setBusy(false);
    }
  }

  return (
    <Dialog
      onClose={onClose}
      dismissible={!busy}
      eyebrow={slot.class_type.name}
      title={single ? tWods("variationForPerson", { name: single.nickname }) : i18n("groupVariationTitle")}
      description={single ? tWods("variationForPersonIntro") : i18n("groupVariationIntro")}
      size="lg"
      variant="center"
      testId="class-variation-dialog"
      footer={
        <>
          <DialogButton tone="ghost" onClick={onClose} disabled={busy}>
            {i18n("closefeb3e25")}
          </DialogButton>
          {single ? (
            <DialogButton tone="ghost" onClick={() => void adapt()} disabled={busy || !adaptSourceId}>
              {tWods("variationAdaptFirst")}
            </DialogButton>
          ) : null}
          <DialogButton
            tone="primary"
            onClick={() => void submit()}
            disabled={busy || !selected.length || needsWorkout}
          >
            {i18n("groupVariationSubmit", { count: selected.length })}
          </DialogButton>
        </>
      }
    >
      <div className="space-y-4">
        <label className="block text-xs font-semibold" style={{ color: "var(--text)" }}>
          {i18n("groupVariationWorkoutLabel")}
          <Select
            className="mt-2 w-full rounded-xl px-3 py-2"
            style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
            value={workoutId}
            onValueChange={(value) => setWorkoutId(value)}
          >
            <option value="">{defaultSourceLabel}</option>
            {classWods.length > 1
              ? classWods
                  .filter((workout) => workout.id !== ownWodId)
                  .map((workout) => (
                    <option key={`class-${workout.id}`} value={workout.id}>
                      {tWods("variationStartClassWod", { title: workout.title })}
                    </option>
                  ))
              : null}
            {workouts
              .filter((workout) => !classWodIds.has(workout.id))
              .map((workout) => (
                <option key={workout.id} value={workout.id}>
                  {workout.title}
                </option>
              ))}
          </Select>
        </label>
        <label className="block text-xs font-semibold" style={{ color: "var(--text)" }}>
          {tWods("variationWhy")}
          <input
            type="text"
            value={instructions}
            maxLength={500}
            onChange={(event) => setInstructions(event.target.value)}
            placeholder={tWods("variationWhyPlaceholder")}
            data-testid="class-variation-why"
            className="mt-2 w-full rounded-xl px-3 py-2 text-base sm:text-sm"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
        </label>
        <p className="text-xs" style={{ color: "var(--muted)" }}>
          {tWods("variationNoCharge")}
        </p>
        {needsWorkout ? (
          <p className="text-xs" style={{ color: "var(--muted)" }}>
            {i18n("groupVariationClassHasNoWod")}
          </p>
        ) : null}

        <fieldset className="rounded-2xl p-4" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
          <legend className="px-1 text-xs font-semibold" style={{ color: "var(--text)" }}>
            {i18n("groupVariationPeople")}
          </legend>
          <input
            type="search"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder={tWods("variationSearch")}
            aria-label={tWods("variationSearch")}
            data-testid="class-variation-search"
            className="mb-3 w-full rounded-xl px-3 py-2 text-sm"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
          {!search.trim() && candidates.length ? (
            <div className="mb-2 flex items-center justify-between gap-2">
              <p className="text-xs" style={{ color: "var(--muted)" }}>
                {i18n("groupVariationLimit", { limit: GROUP_PROGRAMMING_LIMIT })}
              </p>
              <button
                type="button"
                className="rounded-full px-3 py-1 text-xs font-semibold"
                style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}
                onClick={() =>
                  setSelected(
                    allSelected ? [] : candidates.slice(0, GROUP_PROGRAMMING_LIMIT).map((candidate) => candidate.userId),
                  )
                }
              >
                {allSelected ? i18n("groupVariationClearSelection") : i18n("groupVariationSelectAll")}
              </button>
            </div>
          ) : null}
          <div className="max-h-80 space-y-3 overflow-y-auto" aria-live="polite" aria-busy={directory.isFetching}>
            <PeopleSection
              title={search.trim() ? tWods("variationBooked") : null}
              people={sections.booked}
              selected={selected}
              onToggle={toggle}
              versionLabel={i18n("groupVariationHasVersion")}
              testId="class-variation-booked"
            />
            {search.trim() ? (
              <PeopleSection
                title={tWods("variationOthers")}
                people={sections.others}
                selected={selected}
                onToggle={toggle}
                versionLabel={i18n("groupVariationHasVersion")}
                hint={tWods("variationOthersHint")}
                testId="class-variation-others"
              />
            ) : null}
            {!search.trim() && candidates.length === 0 ? (
              <p className="text-sm" style={{ color: "var(--muted)" }}>
                {i18n("groupVariationNoAttendees")}
              </p>
            ) : null}
            {search.trim() && typed && !directory.isFetching && sections.booked.length + sections.others.length === 0 ? (
              <p className="text-sm" style={{ color: "var(--muted)" }}>
                {tWods("variationNoMatch")}
              </p>
            ) : null}
          </div>
        </fieldset>

        {error ? <ErrorNotice>{error}</ErrorNotice> : null}
        <GroupOutcomeList rows={rows} />
      </div>
      {creating ? (
        <ContextualWorkoutCreator
          target={[single?.nickname, slot.class_type.name].filter(Boolean).join(" · ") || null}
          draftId={draftId}
          onClose={() => {
            setCreating(false);
            setDraftId(null);
          }}
          onPublished={saveAdapted}
        />
      ) : null}
    </Dialog>
  );
}

function PeopleSection({
  title,
  people,
  selected,
  onToggle,
  versionLabel,
  hint,
  testId,
}: {
  title: string | null;
  people: VariationPerson[];
  selected: string[];
  onToggle: (person: VariationPerson) => void;
  versionLabel: string;
  hint?: string;
  testId: string;
}) {
  if (!people.length) return null;
  return (
    <section data-testid={testId}>
      {title ? (
        <h3 className="mb-1 text-xs font-semibold" style={{ color: "var(--text)" }}>
          {title}
        </h3>
      ) : null}
      {hint ? (
        <p className="mb-1 text-xs" style={{ color: "var(--muted)" }}>
          {hint}
        </p>
      ) : null}
      <ul className="space-y-1">
        {people.map((person) => (
          <li key={person.userId}>
            <label
              className="flex cursor-pointer items-center gap-3 rounded-xl px-3 py-2 text-sm"
              style={{
                background: selected.includes(person.userId)
                  ? "color-mix(in srgb, var(--primary) 12%, var(--panel))"
                  : "var(--panel)",
                border: "1px solid var(--border)",
                color: "var(--text)",
              }}
            >
              <input type="checkbox" checked={selected.includes(person.userId)} onChange={() => onToggle(person)} />
              <span className="flex-1 font-semibold">{person.nickname}</span>
              {person.hasVersion ? (
                <span className="text-xs" style={{ color: "var(--primary)" }}>
                  {versionLabel}
                </span>
              ) : null}
            </label>
          </li>
        ))}
      </ul>
    </section>
  );
}
