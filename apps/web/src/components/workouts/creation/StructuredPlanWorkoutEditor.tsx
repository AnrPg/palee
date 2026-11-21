"use client";

import { useNewWorkoutForAssignment } from "./NewWorkoutPurpose";
import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from "react";

import { ApiError } from "@/api/client";
import { createDraftWorkout, fetchAdminWorkout, listScaleLevels, publishWorkoutDraft, type WorkoutRecord } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { WorkoutTypesField } from "@/components/workouts/WorkoutTypesField";
import { workoutKindRefs } from "@/lib/workout-kinds";
import { WodGoalsEditorPanel } from "@/components/wod-goals/WodGoalsEditorPanel";
import { PlanEditor, type PlanLevel } from "@/components/workouts/plan-editor";
import { useDraftSaver } from "@/hooks/useDraftSaver";
import { useUiTranslations } from "@/i18n/ui";
import { DraftConflictError, type DraftSaveStatus } from "@/lib/draft-saver";
import { timeline } from "@/lib/structured-plan";
import { usePlanEditorStore } from "@/stores/structured-plan";

import { DraftConflictNotice } from "./DraftConflictNotice";
import { EditorTabs } from "./EditorTabs";
import {
  freeTextPayload,
  planDocumentFrom,
  planHasContent,
  planIsEmpty,
  planPayload,
  planProblems,
  planTimeDomain,
  planToText,
  type PlanDraftPayload,
} from "./structured-plan-authoring";

/** What the authoring modes host asks of the open plan editor before switching away from it. */
export type PlanEditorHandle = {
  /** Whether switching to free text would drop something written (asks the coach first). */
  hasContent: () => boolean;
  /** Writes the plan out as free text and saves the draft that way. */
  switchToText: () => Promise<void>;
};

type Props = {
  draftId: string | null;
  folderId?: string | null;
  onDraftReady: (id: string) => void;
  /** The workout was published: the host decides where the coach goes next. */
  onPublished: (workoutId: string) => void;
  /** Filled while this editor is open (the host's «Ελεύθερο κείμενο / Δομημένο» toggle). */
  handleRef?: MutableRefObject<PlanEditorHandle | null>;
};

/**
 * ADR-270: a workout written in the structured WOD editor. The plan editor
 * (`plan-editor/`) holds the WOD in `usePlanEditorStore`; this host loads the
 * draft into it, autosaves every change as `authoring_mode: "structured_plan"`
 * (each section with its `plan`; the API derives the exercises), resolves
 * draft conflicts and publishes.
 */
export function StructuredPlanWorkoutEditor({ draftId, folderId = null, onDraftReady, onPublished, handleRef }: Props) {
  const awaitingFiling = useNewWorkoutForAssignment();
  const i18n = useUiTranslations();
  const assistantT = useTranslations("WorkoutAssistant");
  const goalsT = useTranslations("WodGoals");
  const conflictT = useTranslations("DraftConflict");
  const viewT = useTranslations("PlanView");
  const { tokens } = useSession();
  const accessToken = tokens?.access_token;

  const [types, setTypes] = useState<string[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [loadFailed, setLoadFailed] = useState(false);
  const [draftSaves, setDraftSaves] = useState(0);
  const { saver, status: draftSaveStatus, loadDraft } = useDraftSaver<PlanDraftPayload | ReturnType<typeof freeTextPayload>>({
    accessToken,
    draftId,
    onSaved: () => setDraftSaves((count) => count + 1),
  });
  const saveStatus: DraftSaveStatus = loadFailed ? "error" : draftSaveStatus;
  const [publishing, setPublishing] = useState(false);
  const [showProblems, setShowProblems] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);
  const [openTab, setOpenTab] = useState<"details" | "goals" | null>(null);
  const metadataRef = useRef<Record<string, unknown>>({});
  const typesRef = useRef<string[]>([]);
  const loadedDraftRef = useRef<string | null>(null);

  const title = usePlanEditorStore((state) => state.title);
  const sections = usePlanEditorStore((state) => state.sections);

  const levels = useQuery({
    queryKey: ["admin", "scale-levels"],
    enabled: Boolean(accessToken),
    queryFn: () => listScaleLevels(accessToken!),
    staleTime: 60_000,
  });
  const planLevels: PlanLevel[] = useMemo(
    () => (levels.data ?? []).filter((level) => level.is_active).map((level) => ({ key: level.slug, label: level.label })),
    [levels.data],
  );

  useEffect(() => {
    if (!accessToken || draftId || loadedDraftRef.current === "creating") return;
    loadedDraftRef.current = "creating";
    createDraftWorkout(accessToken, folderId, { awaitingFiling })
      .then((draft) => onDraftReady(draft.id))
      .catch(() => {
        loadedDraftRef.current = null;
        setLoadFailed(true);
      });
  }, [accessToken, awaitingFiling, draftId, folderId, onDraftReady]);

  const buildPayload = useCallback(() => planPayload(usePlanEditorStore.getState().serialize(), typesRef.current, metadataRef.current), []);

  /** Puts a stored draft into the plan editor and arms autosave at its revision. */
  const applyWorkout = useCallback(
    (workout: WorkoutRecord) => {
      const nextTypes = workoutKindRefs(workout);
      typesRef.current = nextTypes;
      setTypes(nextTypes);
      metadataRef.current = workout.workout_metadata ?? {};
      usePlanEditorStore.getState().load(planDocumentFrom(workout));
      // A new plan opens its first section on step Ροή.
      if (usePlanEditorStore.getState().sections.length === 0) usePlanEditorStore.getState().addSection();
      setOpenTab(workout.title?.trim() && nextTypes.length > 0 ? null : "details");
      saver.start(workout.dsl_source_revision ?? 0);
      setLoaded(true);
      // A text workout switched to structured is saved as a plan right away.
      if (workout.authoring_mode !== "structured_plan") saver.schedule(buildPayload());
    },
    [buildPayload, saver],
  );

  useEffect(() => {
    if (!accessToken || !draftId || loadedDraftRef.current === draftId) return;
    loadedDraftRef.current = draftId;
    setLoaded(false);
    // Changes this browser still holds for the draft are saved first.
    loadDraft(() => fetchAdminWorkout(accessToken, draftId), (workout) => workout.dsl_source_revision)
      .then(applyWorkout)
      .catch(() => {
        loadedDraftRef.current = null;
        setLoadFailed(true);
      });
  }, [accessToken, applyWorkout, draftId, loadDraft]);

  // Autosave: every change to the plan (and the workout type), one request at a time.
  useEffect(() => {
    if (!loaded) return;
    return usePlanEditorStore.subscribe((state, previous) => {
      if (state.sections !== previous.sections || state.title !== previous.title || state.note !== previous.note) {
        saver.schedule(buildPayload());
      }
    });
  }, [buildPayload, loaded, saver]);

  function changeTypes(next: string[]) {
    typesRef.current = next;
    setTypes(next);
    if (loaded) saver.schedule(buildPayload());
  }

  const levelLabels = useMemo(() => Object.fromEntries(planLevels.map((level) => [level.key, level.label])), [planLevels]);

  useEffect(() => {
    if (!handleRef) return;
    handleRef.current = {
      hasContent: () => planHasContent(usePlanEditorStore.getState().serialize()),
      switchToText: async () => {
        const doc = usePlanEditorStore.getState().serialize();
        const body = planToText(doc, (key, values) => viewT(key, values), levelLabels);
        await saver.saveNow(freeTextPayload(doc.title, typesRef.current, body, metadataRef.current));
      },
    };
    return () => {
      handleRef.current = null;
    };
  }, [handleRef, levelLabels, saver, viewT]);

  async function keepMyVersion() {
    if (!accessToken || !draftId) return;
    const latest = await fetchAdminWorkout(accessToken, draftId);
    saver.schedule(buildPayload());
    await saver.overwrite(latest.dsl_source_revision ?? 0);
  }

  async function loadSavedVersion() {
    if (!accessToken || !draftId) return;
    applyWorkout(await fetchAdminWorkout(accessToken, draftId));
  }

  const problems = useMemo(() => planProblems(sections), [sections]);
  const empty = useMemo(() => planIsEmpty(sections), [sections]);
  const titleMissing = title.trim().length < 3;
  const timeDomainSeconds = useMemo(() => planTimeDomain(sections, (plan) => timeline(plan).total ?? 0), [sections]);

  async function publish() {
    if (!accessToken || !draftId) return;
    setNotice(null);
    if (titleMissing || types.length === 0 || empty || problems.length > 0) {
      setShowProblems(true);
      if (titleMissing || types.length === 0) setOpenTab("details");
      return;
    }
    setPublishing(true);
    try {
      const payload = buildPayload();
      // The final save and the publish run back to back in the save queue.
      await saver.saveNow(payload, async (revision) => {
        saver.close();
        try {
          await publishWorkoutDraft(accessToken, draftId, { ...payload, expected_source_revision: revision });
        } catch (error) {
          saver.reopen();
          throw error;
        }
      });
      onPublished(draftId);
    } catch (error) {
      if (error instanceof ApiError && error.payload?.code === "invalid_plan_sections") {
        setNotice(viewT("editor.fixProblems"));
      } else if (!(error instanceof DraftConflictError)) {
        setNotice(assistantT("publishFailed"));
      }
    } finally {
      setPublishing(false);
    }
  }

  const footerProblem = showProblems && (titleMissing || types.length === 0 || empty || problems.length > 0);
  const footerText =
    showProblems && (titleMissing || types.length === 0)
      ? i18n("sectionedEditorNeedsTitleAndType")
      : showProblems && empty
        ? viewT("editor.planEmpty")
        : showProblems && problems.length > 0
          ? viewT("editor.fixProblems")
          : viewT("editor.sectionCount", { count: sections.length });

  return (
    <div className="mx-auto flex min-h-[calc(100dvh-6.5rem)] w-full max-w-4xl min-w-0 flex-col gap-4 px-4 pb-5 sm:px-6" data-testid="structured-plan-workout-editor">
      {saveStatus === "conflict" ? (
        <div className="-mx-4 sm:-mx-6">
          <DraftConflictNotice onKeepMine={keepMyVersion} onLoadSaved={loadSavedVersion} />
        </div>
      ) : null}
      <div className="-mx-4 sm:-mx-6">
        <EditorTabs
          label={i18n("workoutEditorTabsLabel")}
          tabs={[
            {
              key: "details",
              icon: "📝",
              label: i18n("workoutDetails9366821"),
              badge: showProblems && types.length === 0 ? <span aria-hidden="true" style={{ color: "var(--danger)" }}>●</span> : undefined,
            },
            { key: "goals", icon: "🎯", label: goalsT("title") },
          ]}
          active={openTab}
          onSelect={setOpenTab}
          trailing={
            <span className="hidden text-xs font-semibold sm:inline" role="status" style={{ color: "var(--muted)" }}>
              {saveStatus === "conflict" ? conflictT("status") : saveStatusText(saveStatus, i18n)}
            </span>
          }
        >
          {openTab === "details" ? (
            <div className="grid gap-3 p-4 sm:max-w-md">
              <div className="block">
                <span className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                  {i18n("workoutType34a530c")}
                </span>
                <div className="mt-1">
                  <WorkoutTypesField
                    value={types}
                    onChange={changeTypes}
                    placeholder={assistantT("chooseType")}
                    invalid={showProblems && types.length === 0}
                  />
                </div>
              </div>
            </div>
          ) : null}
          {openTab === "goals" ? (
            <div className="max-h-[55vh] overflow-y-auto">
              <WodGoalsEditorPanel workoutId={draftId} refreshKey={draftSaves} timeDomainSeconds={timeDomainSeconds} />
            </div>
          ) : null}
        </EditorTabs>
      </div>

      {loaded ? <PlanEditor levels={planLevels} /> : <div className="min-h-40" aria-busy="true" />}

      <footer
        className="sticky bottom-(--bottom-nav-space) flex flex-wrap items-center justify-between gap-3 border-t py-3"
        style={{ borderColor: "var(--dim)", background: "var(--bg)" }}
      >
        {notice ? (
          <ErrorNotice variant="text">{notice}</ErrorNotice>
        ) : (
          <span className="text-xs" style={{ color: footerProblem ? "var(--danger)" : "var(--muted)" }}>
            {footerText}
          </span>
        )}
        <button
          type="button"
          disabled={!accessToken || !draftId || !loaded || publishing}
          onClick={() => void publish()}
          className="rounded-xl px-5 py-2 text-sm font-black disabled:opacity-40"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          data-testid="plan-publish"
        >
          {publishing ? i18n("quickTextPublishing") : i18n("quickTextPublish")}
        </button>
      </footer>
    </div>
  );
}

function saveStatusText(status: Exclude<DraftSaveStatus, "conflict">, i18n: ReturnType<typeof useUiTranslations>) {
  switch (status) {
    case "saving":
      return i18n("quickTextSaving");
    case "saved":
      return i18n("quickTextSaved");
    case "error":
      return i18n("quickTextSaveError");
    case "idle":
      return "";
  }
}
