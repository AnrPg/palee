"use client";

import Placeholder from "@tiptap/extension-placeholder";
import { EditorContent, useEditor, type JSONContent } from "@tiptap/react";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from "react";

import { ApiError } from "@/api/client";
import { decideExerciseMatches, fetchExerciseMatches, type ExerciseMatch } from "@/api/exercise-matches";
import {
  createDraftWorkout,
  fetchAdminWorkout,
  FREQUENT_TIMERS_KEY,
  publishWorkoutDraft,
  type WorkoutRecord,
} from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { useDraftSaver } from "@/hooks/useDraftSaver";
import { groupExerciseMatches, linkFor, matchDecisions, type ExerciseMatchAnswers } from "@/lib/exercise-match-answers";
import { DraftConflictError, type DraftSaveStatus } from "@/lib/draft-saver";
import { WodGoalsEditorPanel } from "@/components/wod-goals/WodGoalsEditorPanel";
import { useUiTranslations } from "@/i18n/ui";
import {
  FREE_TEXT_TIMER_METADATA_KEY,
  type FreeTextTimerPreset,
  freeTextLimitMs,
  buildFreeTextSegments,
  parseFreeTextTimerPreset,
} from "@/lib/free-text-timer";
import { findTextTimers } from "@/lib/wod-formats/parse";
import { FOLLOW_TEXT } from "@/lib/wod-formats/text-timer";
import {
  describePreset,
  emptySection,
  withSectionTimer,
  SECTIONED_TEXT_MODE,
  sectionProblems,
  type EditorTextSection,
  type SectionProblem,
  editorSectionsFrom,
  sectionsPayload,
} from "@/lib/text-sections";
import { FREE_TEXT_EDITOR_CLASS, sanitizeWorkoutDslPaste } from "@/lib/workout-dsl-editor-data";
import { getFormatLabels, type SectionFormat, type WorkoutType } from "@/types/workout";

import { AssistantSwitch } from "./AssistantSwitch";
import { DraftConflictNotice } from "./DraftConflictNotice";
import { EditorTabs } from "./EditorTabs";
import { WodFormatsHelpButton } from "./WodFormatsHelp";
import { useEditorExerciseSuggestions, useExerciseSuggestKeys } from "./EditorExerciseSuggestions";
import { ExerciseCheckFailedNotice } from "./ExerciseCheckFailedNotice";
import { ExerciseMatchesDialog } from "./ExerciseMatchesDialog";
import { ExerciseSuggestKeys, type LinkSpan } from "./exercise-link";
import { linkSectionDocument, sectionContentExtensions } from "./section-text-schema";
import { SectionScoringField } from "./SectionScoringField";
import { TextTimerNote } from "./TextTimerNote";
import { TimerChips } from "./TimerChips";
import { useFrequentTimers } from "./useFrequentTimers";
import { WorkoutTypeSelect } from "@/components/workouts/WorkoutTypeSelect";
import { isWorkoutType } from "@/lib/workout-types";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

type Props = {
  draftId: string | null;
  folderId?: string | null;
  onDraftReady: (id: string) => void;
  /** The workout was published: the host decides where the coach goes next. */
  onPublished: (workoutId: string) => void;
  /** Whether the gym lets coaches use the assistant (ADR-180). */
  assistantAvailable: boolean;
  /** Switch this workout to the assistant's free-text editor (the draft is saved first). */
  onUseAssistant: () => void;
  /** ADR-270: filled with "save the sections now", so the host can switch editors without losing them. */
  saveHandleRef?: MutableRefObject<(() => Promise<void>) | null>;
};

/**
 * ADR-180: a workout written without the assistant. The coach adds sections
 * («+ Προσθήκη ενότητας»), writes each one's text and picks its own timer;
 * athletes run those timers one section at a time. The assistant parses
 * nothing here, but the exercises are still checked before publishing
 * (ADR-570 / ADR-671): the same «Αναγνωρίσαμε ασκήσεις» dialog as the
 * free-text editor, answered section by section, so every exercise counts
 * for the muscles and qualities.
 */
export function SectionedWorkoutEditor({ draftId, folderId = null, onDraftReady, onPublished, assistantAvailable, onUseAssistant, saveHandleRef }: Props) {
  const i18n = useUiTranslations();
  const assistantT = useTranslations("WorkoutAssistant");
  const goalsT = useTranslations("WodGoals");
  const conflictT = useTranslations("DraftConflict");
  const { tokens } = useSession();
  const accessToken = tokens?.access_token;
  const formatLabels = useMemo(() => getFormatLabels(i18n), [i18n]);
  const queryClient = useQueryClient();
  // ADR-571: the coach's three most used timers, as chips on every section.
  const frequentTimers = useFrequentTimers();

  const [title, setTitle] = useState("");
  const [type, setType] = useState<WorkoutType | "">("");
  const [sections, setSections] = useState<EditorTextSection[]>(() => [emptySection()]);
  const [loaded, setLoaded] = useState(false);
  /** The draft could not be created or loaded. */
  const [loadFailed, setLoadFailed] = useState(false);
  const [draftSaves, setDraftSaves] = useState(0);
  const { saver, status: draftSaveStatus, loadDraft } = useDraftSaver<SectionedDraftPayload>({
    accessToken,
    draftId,
    onSaved: () => setDraftSaves((count) => count + 1),
  });
  const saveStatus: DraftSaveStatus = loadFailed ? "error" : draftSaveStatus;
  const [publishing, setPublishing] = useState(false);
  const [showProblems, setShowProblems] = useState(false);
  const [serverProblems, setServerProblems] = useState<SectionProblem[] | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const matchesT = useTranslations("ExerciseMatches");
  /** ADR-671: the exercises found before publishing, waiting for the coach's answers. */
  const [matchCheck, setMatchCheck] = useState<{ matches: ExerciseMatch[]; busy: boolean; error: string | null } | null>(null);
  /** ADR-671: the exercise check could not run; the coach retries or publishes without it. */
  const [checkFailed, setCheckFailed] = useState(false);
  /** The settings tab open above the sections (none: all the room for writing). */
  const [openTab, setOpenTab] = useState<"details" | "goals" | null>("details");
  const [focusKey, setFocusKey] = useState<string | null>(null);
  const metadataRef = useRef<Record<string, unknown>>({});
  const loadedDraftRef = useRef<string | null>(null);

  useEffect(() => {
    if (!accessToken || draftId || loadedDraftRef.current === "creating") return;
    loadedDraftRef.current = "creating";
    createDraftWorkout(accessToken, folderId)
      .then((draft) => onDraftReady(draft.id))
      .catch(() => {
        loadedDraftRef.current = null;
        setLoadFailed(true);
      });
  }, [accessToken, draftId, folderId, onDraftReady]);

  /** Puts a stored draft into the editor and arms autosave at its revision. */
  const applyWorkout = useCallback(
    (workout: WorkoutRecord) => {
      setTitle(workout.title ?? "");
      setType(isWorkoutType(workout.type) ? workout.type : "");
      metadataRef.current = workout.workout_metadata ?? {};
      // A free-text draft switched to sections keeps its text as section 1
      // and its whole-workout timer as that section's timer.
      setSections(
        editorSectionsFrom(workout, parseFreeTextTimerPreset(metadataRef.current[FREE_TEXT_TIMER_METADATA_KEY])),
      );
      // A save based on an older revision is refused, so autosave starts here.
      saver.start(workout.dsl_source_revision ?? 0);
      setLoaded(true);
    },
    [saver],
  );

  useEffect(() => {
    if (!accessToken || !draftId || loadedDraftRef.current === draftId) return;
    loadedDraftRef.current = draftId;
    // Changes this browser still holds for the draft are saved first.
    loadDraft(() => fetchAdminWorkout(accessToken, draftId), (workout) => workout.dsl_source_revision)
      .then(applyWorkout)
      .catch(() => {
        loadedDraftRef.current = null;
        setLoadFailed(true);
      });
  }, [accessToken, applyWorkout, draftId, loadDraft]);

  const buildPayload = useCallback(() => sectionedPayload(title, type, sections, metadataRef.current), [sections, title, type]);

  // Autosave: one request at a time, a second after the last change.
  useEffect(() => {
    if (!loaded) return;
    saver.schedule(buildPayload());
  }, [buildPayload, loaded, saver]);

  useEffect(() => {
    if (!saveHandleRef) return;
    saveHandleRef.current = async () => {
      if (saver.started) await saver.saveNow(buildPayload());
    };
    return () => {
      saveHandleRef.current = null;
    };
  }, [buildPayload, saveHandleRef, saver]);

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

  const problems = useMemo(() => sectionProblems(sections), [sections]);
  const visibleProblems = serverProblems ?? (showProblems ? problems : []);
  const titleMissing = title.trim().length < 3;
  const timeDomainSeconds = useMemo(() => {
    let total = 0;
    for (const section of sections) {
      if (!section.preset) continue;
      const limit = freeTextLimitMs(buildFreeTextSegments(section.preset));
      if (limit === null) return null;
      total += limit / 1000;
    }
    return total > 0 ? Math.round(total) : null;
  }, [sections]);

  function updateSection(key: string, patch: Partial<EditorTextSection>) {
    setServerProblems(null);
    // ADR-650: a section whose timer follows its text gets the text's timer after every change.
    setSections((current) => current.map((section) => (section.key === key ? withSectionTimer({ ...section, ...patch }) : section)));
  }

  function addSection() {
    const section = emptySection();
    setSections((current) => [...current, section]);
    setFocusKey(section.key);
  }

  function moveSection(index: number, offset: -1 | 1) {
    setServerProblems(null);
    setSections((current) => {
      const target = index + offset;
      if (target < 0 || target >= current.length) return current;
      const next = [...current];
      [next[index], next[target]] = [next[target]!, next[index]!];
      return next;
    });
  }

  function removeSection(key: string) {
    setServerProblems(null);
    setSections((current) => (current.length > 1 ? current.filter((section) => section.key !== key) : [emptySection()]));
  }

  async function switchToAssistant() {
    if (!saver.started) return;
    try {
      await saver.saveNow(buildPayload());
    } catch {
      // Not saved: stay here so nothing is lost (the status or notice says why).
      return;
    }
    onUseAssistant();
  }

  /**
   * Publishes the sections. ADR-671: the exercises the matcher finds in the
   * saved sections are confirmed first (`ExerciseMatchesDialog`); nothing
   * found publishes at once. A check that could not run says so
   * (`ExerciseCheckFailedNotice`) instead of publishing silently.
   * `sections` are the ones to publish when the state has not caught up yet
   * (right after the answers were linked).
   */
  async function publish(options: { matchesChecked?: boolean; sections?: EditorTextSection[] } = {}) {
    if (!accessToken || !draftId) return;
    setNotice(null);
    setServerProblems(null);
    setCheckFailed(false);
    if (problems.length > 0 || titleMissing || !type) {
      setShowProblems(true);
      return;
    }

    setPublishing(true);
    const payload = options.sections ? sectionedPayload(title, type, options.sections, metadataRef.current) : buildPayload();

    if (!options.matchesChecked) {
      let matches: ExerciseMatch[];
      try {
        await saver.saveNow(payload);
        matches = await fetchExerciseMatches(accessToken, draftId);
      } catch (error) {
        setPublishing(false);
        // A conflict is explained by the notice above the sections.
        if (!(error instanceof DraftConflictError)) setCheckFailed(true);
        return;
      }
      if (matches.length > 0) {
        setMatchCheck({ matches, busy: false, error: null });
        setPublishing(false);
        return;
      }
    }

    try {
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
      // This workout's timers now count among the coach's most used.
      void queryClient.invalidateQueries({ queryKey: FREQUENT_TIMERS_KEY });
      onPublished(draftId);
    } catch (error) {
      const details = error instanceof ApiError ? (error.payload?.details as { sections?: SectionProblem[] } | undefined) : undefined;
      if (details?.sections?.length) {
        setServerProblems(details.sections);
      } else if (!(error instanceof DraftConflictError)) {
        setNotice(assistantT("publishFailed"));
      }
    } finally {
      setPublishing(false);
    }
  }

  /** ADR-671: the coach answered every found exercise: link the words in their sections, save, remember, publish. */
  async function confirmExerciseMatches(answers: ExerciseMatchAnswers) {
    if (!accessToken || !draftId || !matchCheck) return;
    setMatchCheck({ ...matchCheck, busy: true, error: null });
    const groups = groupExerciseMatches(matchCheck.matches);
    const linked = linkSections(
      sections,
      groups.flatMap((group) => group.matches.map((match) => ({ match, ...linkFor(match, answers[group.key]!) }))),
    );
    setSections(linked);
    try {
      await saver.saveNow(sectionedPayload(title, type, linked, metadataRef.current));
      if (groups.length > 0) await decideExerciseMatches(accessToken, draftId, matchDecisions(groups, answers));
    } catch (error) {
      setMatchCheck({ ...matchCheck, busy: false, error: error instanceof DraftConflictError ? null : matchesT("failed") });
      return;
    }
    setMatchCheck(null);
    await publish({ matchesChecked: true, sections: linked });
  }

  return (
    <div className="mx-auto flex min-h-[calc(100dvh-6.5rem)] w-full max-w-3xl min-w-0 flex-col gap-4 px-4 pb-5 sm:px-6">
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
              badge:
                showProblems && (titleMissing || !type) ? (
                  <span aria-hidden="true" style={{ color: "var(--danger)" }}>●</span>
                ) : undefined,
            },
            { key: "goals", icon: "🎯", label: goalsT("title") },
          ]}
          active={openTab}
          onSelect={setOpenTab}
          trailing={
            <>
              <span className="hidden text-xs font-semibold sm:inline" role="status" style={{ color: "var(--muted)" }}>
                {saveStatus === "conflict" ? conflictT("status") : saveStatusText(saveStatus, i18n)}
              </span>
              <AssistantSwitch enabled={false} available={assistantAvailable} onChange={() => void switchToAssistant()} />
            </>
          }
        >
          {openTab === "details" ? (
            <div className="grid gap-3 p-4 md:grid-cols-[minmax(0,1fr)_12rem]">
              <label className="block">
                <span className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                  {i18n("title768e0c1")}
                </span>
                <input
                  className="mt-1 w-full rounded-xl border px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--card)", borderColor: showProblems && titleMissing ? "var(--danger)" : "var(--dim)", color: "var(--text)" }}
                  value={title}
                  onChange={(event) => setTitle(event.target.value)}
                  maxLength={160}
                  placeholder={assistantT("titlePlaceholder")}
                  aria-invalid={showProblems && titleMissing}
                />
              </label>
              <label className="block">
                <span className="text-xs font-bold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                  {i18n("workoutType34a530c")}
                </span>
                <WorkoutTypeSelect
                  className="mt-1 w-full rounded-xl border px-3 py-2 text-sm outline-none"
                  style={{ background: "var(--card)", borderColor: showProblems && !type ? "var(--danger)" : "var(--dim)", color: "var(--text)" }}
                  value={type}
                  onChange={setType}
                  placeholder={assistantT("chooseType")}
                  invalid={showProblems && !type}
                />
              </label>
            </div>
          ) : null}
          {openTab === "goals" ? (
            <div className="max-h-[55vh] overflow-y-auto">
              <WodGoalsEditorPanel workoutId={draftId} refreshKey={draftSaves} timeDomainSeconds={timeDomainSeconds} />
            </div>
          ) : null}
        </EditorTabs>
      </div>

      <ol className="space-y-3" aria-label={i18n("textSectionsLabel")}>
        {sections.map((section, index) => (
          <SectionCard
            key={section.key}
            section={section}
            index={index}
            count={sections.length}
            ready={loaded}
            autoFocus={focusKey === section.key}
            problems={visibleProblems.filter((problem) => problem.section === index + 1).map((problem) => problem.problem)}
            formatLabels={formatLabels}
            frequentTimers={frequentTimers}
            onChange={(patch) => updateSection(section.key, patch)}
            onMove={(offset) => moveSection(index, offset)}
            onRemove={() => removeSection(section.key)}
          />
        ))}
      </ol>

      <button
        type="button"
        onClick={addSection}
        disabled={sections.length >= 30}
        className="min-h-12 w-full rounded-2xl border border-dashed text-sm font-black disabled:opacity-40"
        style={{ borderColor: "var(--primary)", color: "var(--primary)", background: "transparent" }}
      >
        + {i18n("addTextSection")}
      </button>

      <footer className="sticky bottom-(--bottom-nav-space) flex flex-wrap items-center justify-between gap-3 border-t py-3" style={{ borderColor: "var(--dim)", background: "var(--bg)" }}>
        {checkFailed ? (
          <ExerciseCheckFailedNotice
            busy={publishing}
            onRetry={() => void publish()}
            onPublishAnyway={() => void publish({ matchesChecked: true })}
          />
        ) : notice ? (
          <ErrorNotice variant="text">{notice}</ErrorNotice>
        ) : (
          <span className="text-xs" style={{ color: "var(--muted)" }}>
            {showProblems && (titleMissing || !type)
              ? i18n("sectionedEditorNeedsTitleAndType")
              : visibleProblems.length > 0
                ? i18n("sectionedEditorFixSections")
                : i18n("textSectionCount", { count: sections.length })}
          </span>
        )}
        <button
          type="button"
          disabled={!accessToken || !draftId || !loaded || publishing}
          onClick={() => void publish()}
          className="rounded-xl px-5 py-2 text-sm font-black disabled:opacity-40"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {publishing ? i18n("quickTextPublishing") : i18n("quickTextPublish")}
        </button>
      </footer>
      {matchCheck ? (
        <ExerciseMatchesDialog
          matches={matchCheck.matches}
          busy={matchCheck.busy}
          error={matchCheck.error}
          onBack={() => setMatchCheck(null)}
          onConfirm={(answers) => void confirmExerciseMatches(answers)}
        />
      ) : null}
    </div>
  );
}

function SectionCard({
  section,
  index,
  count,
  ready,
  autoFocus,
  problems,
  formatLabels,
  frequentTimers,
  onChange,
  onMove,
  onRemove,
}: {
  section: EditorTextSection;
  index: number;
  count: number;
  ready: boolean;
  autoFocus: boolean;
  problems: string[];
  formatLabels: Record<SectionFormat, string>;
  frequentTimers: FreeTextTimerPreset[];
  onChange: (patch: Partial<EditorTextSection>) => void;
  onMove: (offset: -1 | 1) => void;
  onRemove: () => void;
}) {
  const i18n = useUiTranslations();
  const textTimerT = useTranslations("TextTimer");
  const [timerOpen, setTimerOpen] = useState(false);
  const [scoringOpen, setScoringOpen] = useState(section.metrics.length > 0);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const titleRef = useRef<HTMLInputElement>(null);
  const number = index + 1;
  const textMissing = problems.includes("text_required") || problems.includes("text_too_long");
  const timerMissing = problems.includes("timer_required");
  const scoringInvalid = problems.includes("scoring_invalid");
  // ADR-650: the timers the section's text asks for.
  const textTimers = useMemo(() => findTextTimers(section.body), [section.body]);
  const timerFrom = section.timerFrom ?? FOLLOW_TEXT;
  const timerFromText = timerFrom.from === "text" && textTimers.timers.length > 0;

  useEffect(() => {
    if (autoFocus) titleRef.current?.focus();
  }, [autoFocus]);

  return (
    <li
      className="rounded-2xl border p-4"
      style={{ borderColor: problems.length > 0 ? "var(--danger)" : "var(--dim)", background: "var(--card)" }}
      data-testid="text-section"
    >
      <div className="flex flex-wrap items-center gap-2">
        <span className="shrink-0 text-xs font-black tabular-nums" style={{ color: "var(--dim)" }}>
          {number}
        </span>
        <input
          ref={titleRef}
          className="min-w-0 flex-1 rounded-lg border-0 bg-transparent px-1 py-1 text-base font-black outline-none"
          style={{ color: "var(--text)" }}
          value={section.title}
          maxLength={120}
          placeholder={i18n("textSectionNumber", { number })}
          aria-label={i18n("textSectionTitleLabel", { number })}
          onChange={(event) => onChange({ title: event.target.value })}
        />
        <IconButton label={i18n("moveSectionUp")} disabled={index === 0} onClick={() => onMove(-1)}>↑</IconButton>
        <IconButton label={i18n("moveSectionDown")} disabled={index === count - 1} onClick={() => onMove(1)}>↓</IconButton>
        {confirmRemove ? (
          <button
            type="button"
            className="min-h-8 rounded-lg px-2 text-xs font-bold"
            style={{ background: "var(--danger)", color: "var(--bg)" }}
            onClick={() => {
              setConfirmRemove(false);
              onRemove();
            }}
            onBlur={() => setConfirmRemove(false)}
          >
            {i18n("removeSectionConfirm")}
          </button>
        ) : (
          <IconButton
            label={i18n("removeSection")}
            onClick={() => (section.body.trim() ? setConfirmRemove(true) : onRemove())}
          >
            ×
          </IconButton>
        )}
      </div>

      <div
        className="mt-2 rounded-xl border"
        style={{ borderColor: textMissing ? "var(--danger)" : "var(--border)", background: "var(--bg)" }}
      >
        {ready ? (
          <SectionTextEditor
            document={section.document}
            label={i18n("textSectionTextLabel", { number })}
            frequentTimers={frequentTimers}
            contentVersion={section.contentVersion ?? 0}
            onChange={(body, document) => onChange({ body, document })}
          />
        ) : null}
      </div>
      {textMissing ? (
        <ErrorNotice variant="field" className="mt-1">
          {problems.includes("text_too_long") ? i18n("textSectionTooLong") : i18n("textSectionTextRequired")}
        </ErrorNotice>
      ) : null}

      <div className="mt-3">
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            aria-expanded={timerOpen}
            onClick={() => setTimerOpen((open) => !open)}
            className="inline-flex min-h-10 items-center gap-2 rounded-full px-3 text-sm font-bold"
            style={
              timerFromText && !timerMissing
                ? {
                    background: "color-mix(in srgb, var(--success) 14%, var(--panel))",
                    color: "var(--success)",
                    border: "1px solid var(--success)",
                  }
                : {
                    background: "var(--panel)",
                    color: "var(--text)",
                    border: `1px solid ${timerMissing ? "var(--danger)" : "var(--border)"}`,
                  }
            }
            data-testid="section-timer-button"
          >
            <span aria-hidden="true">⏱</span>
            {section.preset.format === "untimed"
              ? i18n("timerNoTime")
              : describePreset(section.preset, formatLabels[section.preset.format])}
            {timerFromText ? <span className="text-xs font-semibold opacity-80">· {textTimerT("fromText")}</span> : null}
            <svg aria-hidden="true" viewBox="0 0 20 20" className="h-4 w-4 shrink-0" style={{ color: "var(--muted)", transform: timerOpen ? "rotate(180deg)" : undefined, transition: "transform 120ms" }}>
              <path d="M5 7.5 10 12.5 15 7.5" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>
          <button
            type="button"
            aria-expanded={scoringOpen}
            onClick={() => setScoringOpen((open) => !open)}
            className="inline-flex min-h-10 min-w-0 items-center gap-2 rounded-full px-3 text-sm font-bold"
            style={
              section.metrics.length > 0
                ? { background: "var(--panel)", color: "var(--text)", border: `1px solid ${scoringInvalid ? "var(--danger)" : "var(--border)"}` }
                : { color: "var(--muted)", border: "1px dashed var(--border)" }
            }
          >
            <span aria-hidden="true">🏅</span>
            <span className="truncate">
              {section.metrics.length > 0
                ? section.metrics.map((metric) => metric.label).join(" · ")
                : i18n("addSectionScoring")}
            </span>
          </button>
        </div>
        <div className="mt-2 empty:hidden">
          <TextTimerNote
            preset={section.preset}
            source={timerFrom}
            found={textTimers}
            formatLabels={formatLabels}
            oneTimer={false}
            showChip={false}
            help={timerOpen ? null : <WodFormatsHelpButton />}
            onRestore={() => onChange({ timerFrom: FOLLOW_TEXT })}
            onNext={() => onChange({ timerFrom: { from: "text", pick: timerFrom.pick + 1 } })}
          />
        </div>
        {timerMissing ? (
          <ErrorNotice variant="field" className="mt-1">
            {i18n("textSectionTimerRequired")}
          </ErrorNotice>
        ) : null}
        {timerOpen ? (
          <div className="mt-3 rounded-xl border p-3" style={{ borderColor: "var(--border)", background: "var(--panel)" }}>
            <TimerChips
              preset={section.preset}
              frequent={frequentTimers}
              formatLabels={formatLabels}
              onChange={(preset) => onChange({ preset, timerFrom: { from: "hand", pick: 0 } })}
            />
            <div className="mt-2">
              <WodFormatsHelpButton />
            </div>
          </div>
        ) : null}
        {scoringOpen || scoringInvalid ? (
          <SectionScoringField
            metrics={section.metrics}
            invalid={scoringInvalid}
            onChange={(metrics) => onChange({ metrics })}
          />
        ) : null}
      </div>
    </li>
  );
}

const NO_FREQUENT_TIMERS: FreeTextTimerPreset[] = [];

export function SectionTextEditor({
  document,
  label,
  frequentTimers = NO_FREQUENT_TIMERS,
  contentVersion = 0,
  onChange,
}: {
  document: JSONContent;
  label: string;
  frequentTimers?: FreeTextTimerPreset[];
  /** ADR-671: a new value puts `document` into the editor (it was replaced from outside). */
  contentVersion?: number;
  onChange: (body: string, document: JSONContent) => void;
}) {
  const i18n = useUiTranslations();
  /** ADR-570: the keys the open exercise suggestion list takes (Tab, ↑/↓, Enter, Esc). */
  const suggestKeys = useExerciseSuggestKeys();
  const editor = useEditor({
    extensions: [
      // ADR-671: with `exerciseLink`, a name picked from the suggestions is
      // linked to its exercise, as in the free-text editor.
      ...sectionContentExtensions(),
      Placeholder.configure({ placeholder: i18n("textSectionPlaceholder") }),
      ExerciseSuggestKeys.configure({ onKeyDown: suggestKeys.onKeyDown }),
    ],
    content: document,
    immediatelyRender: false,
    editorProps: {
      attributes: {
        class: `${FREE_TEXT_EDITOR_CLASS} min-h-24`,
        spellcheck: "true",
        role: "textbox",
        "aria-multiline": "true",
        "aria-label": label,
      },
      transformPastedHTML: sanitizeWorkoutDslPaste,
    },
    onUpdate: ({ editor: current }) => onChange(current.getText({ blockSeparator: "\n" }), current.getJSON()),
  });

  // ADR-671: answers linked outside the editor are shown in it, without an update round trip.
  const shownVersion = useRef(contentVersion);
  useEffect(() => {
    if (!editor || shownVersion.current === contentVersion) return;
    shownVersion.current = contentVersion;
    editor.commands.setContent(document, { emitUpdate: false });
  }, [contentVersion, document, editor]);

  // ADR-650: WOD formats too, the coach's most used timers first.
  const suggestionOptions = useMemo(() => ({ formats: { frequent: frequentTimers } }), [frequentTimers]);
  const { menu } = useEditorExerciseSuggestions(editor, suggestKeys.handlerRef, suggestionOptions);

  return (
    <>
      <EditorContent editor={editor} />
      {menu}
    </>
  );
}

function IconButton({
  label,
  disabled = false,
  onClick,
  children,
}: {
  label: string;
  disabled?: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      disabled={disabled}
      onClick={onClick}
      className="grid h-8 w-8 shrink-0 place-items-center rounded-lg text-sm font-bold disabled:opacity-30"
      style={{ color: "var(--text-soft)", border: "1px solid var(--border)" }}
    >
      {children}
    </button>
  );
}

type SectionedDraftPayload = ReturnType<typeof sectionedPayload>;

/**
 * ADR-671: the sections with the coach's answers put into their documents as
 * exercise links. A match names its section by its place in the saved
 * sections, the same order as on screen.
 */
export function linkSections(
  sections: EditorTextSection[],
  answered: { match: ExerciseMatch; ref: string | null; checked: string | null }[],
): EditorTextSection[] {
  const bySection = new Map<number, LinkSpan[]>();
  for (const { match, ref, checked } of answered) {
    const index = typeof match.section === "number" ? match.section : 0;
    const spans = bySection.get(index) ?? [];
    spans.push({ line: match.line, from: match.from, to: match.to, typed: match.typed, ref, checked });
    bySection.set(index, spans);
  }
  return sections.map((section, index) => {
    const spans = bySection.get(index);
    if (!spans) return section;
    const { document, applied } = linkSectionDocument(section.document, spans);
    return applied > 0 ? { ...section, document, contentVersion: (section.contentVersion ?? 0) + 1 } : section;
  });
}

function sectionedPayload(
  title: string,
  type: WorkoutType | "",
  sections: EditorTextSection[],
  storedMetadata: Record<string, unknown>,
) {
  const metadata = { ...storedMetadata };
  delete metadata[FREE_TEXT_TIMER_METADATA_KEY];
  const payloadSections = sectionsPayload(sections);
  const workoutType = type || null;
  return {
    title,
    type: workoutType,
    authoring_mode: SECTIONED_TEXT_MODE,
    workout_metadata: metadata,
    sections: payloadSections,
    draft_data: {
      title,
      type: workoutType,
      authoring_mode: SECTIONED_TEXT_MODE,
      workout_metadata: metadata,
      sections: payloadSections,
    },
  };
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
