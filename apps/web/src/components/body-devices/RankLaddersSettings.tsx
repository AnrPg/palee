"use client";

import { useEffect, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import {
  createRankLadder,
  deleteRankLadder,
  fetchRankLadders,
  rankLaddersKey,
  updateRankLadder,
  type RankColor,
  type RankCriterion,
  type RankLadder,
} from "@/api/body-devices";
import { listAdminClassTypes } from "@/api/schedule";
import { listScaleLevels } from "@/api/workouts";
import { Belt } from "@/components/body-devices/Belt";
import { RankTemplatePicker } from "@/components/body-devices/RankTemplatePicker";
import { ConfirmButton } from "@/components/check-in/ConfirmButton";
import { IntegerInput } from "@/components/integer-input";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { SaveBar } from "@/components/ui/SaveBar";
import { Select } from "@/components/ui/Select";
import { useWorkoutTypeLabels } from "@/components/workouts/WorkoutTypeSelect";
import { rankSkills } from "@/lib/body-devices";

const BELT_SHADES: RankColor[] = ["white", "grey", "yellow", "orange", "green", "blue", "purple", "brown", "red", "black", "pink"];
const CRITERIA: RankCriterion[] = ["days", "classes", "skills"];
const MAX_SKILLS = 20;
const MAX_RANKS = 30;

let nextKey = 0;
const newKey = () => `k${(nextKey += 1)}`;

export type DraftSkill = { key: string; id: string | null; name: string; note: string; video: string };

export type DraftRank = {
  key: string;
  id?: string;
  name: string;
  color: RankColor | null;
  max_stripes: number;
  min_days: number | null;
  min_classes: number | null;
  skills: DraftSkill[];
  scale_level_slug: string | null;
};

export type Draft = { name: string; discipline: string; style: string; class_type_ids: string[]; ready_criteria: RankCriterion[]; ranks: DraftRank[] };

export function draftOf(ladder: RankLadder): Draft {
  return {
    name: ladder.name,
    discipline: ladder.discipline,
    style: ladder.style,
    class_type_ids: Array.isArray(ladder.class_type_ids) ? ladder.class_type_ids : [],
    ready_criteria: Array.isArray(ladder.ready_criteria) && ladder.ready_criteria.length > 0 ? ladder.ready_criteria : ["classes", "days"],
    ranks: (Array.isArray(ladder.ranks) ? ladder.ranks : []).map((rank) => ({
      key: rank.id,
      id: rank.id,
      name: rank.name,
      color: rank.color ?? null,
      max_stripes: rank.max_stripes,
      min_days: rank.requirements?.min_days ?? null,
      min_classes: rank.requirements?.min_classes ?? null,
      skills: rankSkills(rank).map((skill) => ({ key: skill.id ?? newKey(), id: skill.id, name: skill.name, note: skill.note ?? "", video: skill.video ?? "" })),
      scale_level_slug: rank.scale_level_slug ?? null,
    })),
  };
}

/**
 * The request body of a draft; empty requirements are left out. Each skill
 * keeps its id (a new one sends null), so a rename or a new order keeps the
 * ticks people already have (ADR-400 follow-up).
 */
export function ladderBody(draft: Draft) {
  return {
    name: draft.name.trim(),
    discipline: draft.discipline,
    class_type_ids: draft.class_type_ids,
    ready_criteria: CRITERIA.filter((criterion) => draft.ready_criteria.includes(criterion)),
    ranks: draft.ranks.map((rank) => {
      const skills = rank.skills.map((skill) => ({ ...skill, name: skill.name.trim() })).filter((skill) => skill.name);
      const notes = skills.map((skill) => skill.note.trim() || null);
      const videos = skills.map((skill) => skill.video.trim() || null);
      return {
        ...(rank.id ? { id: rank.id } : {}),
        name: rank.name.trim(),
        color: rank.color,
        max_stripes: rank.max_stripes,
        scale_level_slug: rank.scale_level_slug,
        requirements: {
          ...(rank.min_days ? { min_days: rank.min_days } : {}),
          ...(rank.min_classes ? { min_classes: rank.min_classes } : {}),
          ...(skills.length
            ? {
                skills: skills.map((skill) => skill.name),
                skill_ids: skills.map((skill) => skill.id),
                ...(notes.some(Boolean) ? { skill_notes: notes } : {}),
                ...(videos.some(Boolean) ? { skill_videos: videos } : {}),
              }
            : {}),
        },
      };
    }),
  };
}

/** How many parts of the ladder differ from what is saved (the save bar's count). */
export function draftChanges(saved: Draft, draft: Draft): number {
  const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);
  let changes = 0;
  if (draft.name !== saved.name) changes += 1;
  if (!same([...draft.ready_criteria].sort(), [...saved.ready_criteria].sort())) changes += 1;
  if (!same(draft.class_type_ids, saved.class_type_ids)) changes += 1;
  const strip = (rank: DraftRank) => ({ ...rank, key: undefined, skills: rank.skills.map((skill) => ({ ...skill, key: undefined })) });
  const length = Math.max(draft.ranks.length, saved.ranks.length);
  for (let index = 0; index < length; index += 1) {
    const before = saved.ranks[index];
    const after = draft.ranks[index];
    if (!before || !after || !same(strip(before), strip(after))) changes += 1;
  }
  return changes;
}

/** Moves `list[from]` to `to` (clamped); the same list when nothing moves. */
export function moveItem<T>(list: T[], from: number, to: number): T[] {
  const target = Math.max(0, Math.min(list.length - 1, to));
  if (from === target || from < 0 || from >= list.length) return list;
  const next = [...list];
  const [item] = next.splice(from, 1);
  next.splice(target, 0, item);
  return next;
}

const TEMPLATE_LOCALES = ["en", "el", "ar", "ru", "de", "es", "pt-PT", "he", "it", "bg", "nl", "fr"] as const;
type TemplateLocale = (typeof TEMPLATE_LOCALES)[number];

/** The web locale as a template language the API knows; Greek otherwise (ADR-400). */
function templateLocale(locale: string): TemplateLocale {
  return (TEMPLATE_LOCALES as readonly string[]).includes(locale) ? (locale as TemplateLocale) : "el";
}

/**
 * Ρυθμίσεις › Προχωρημένα › Βαθμοί (ADR-377, ADR-400): one ladder per
 * discipline, started from the template picker (option Β) and kept in the
 * curriculum editor (option Α). Owner, admins and head coaches only.
 */
export function RankLaddersSettings({ token, slug }: { token: string; slug: string }) {
  const t = useTranslations("BodyDevices");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const ladders = useQuery({
    queryKey: rankLaddersKey(slug, locale),
    enabled: Boolean(token && slug),
    queryFn: () => fetchRankLadders(token, slug, locale),
  });
  const [creating, setCreating] = useState(false);
  const [opened, setOpened] = useState<string | null>(null);
  const create = useMutation({
    mutationFn: (body: Parameters<typeof createRankLadder>[2]) => createRankLadder(token, slug, body),
    onSuccess: (ladder) => {
      setCreating(false);
      setOpened(ladder?.id ?? null);
      void queryClient.invalidateQueries({ queryKey: rankLaddersKey(slug) });
    },
  });

  if (ladders.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (ladders.isError) return <ErrorNotice>{t("errorGeneric")}</ErrorNotice>;
  const list = ladders.data.ladders.filter((ladder) => ladder && typeof ladder.id === "string");

  return (
    <div className="flex flex-col gap-4" data-testid="rank-ladders">
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("ranks.settingsHint")}</p>
      {list.map((ladder) => (
        <LadderEditor key={ladder.id} token={token} slug={slug} ladder={ladder} justCreated={ladder.id === opened} />
      ))}
      {creating || list.length === 0 ? (
        <RankTemplatePicker
          templates={ladders.data.templates}
          boxDisciplines={ladders.data.box_disciplines.filter((value): value is string => typeof value === "string")}
          pending={create.isPending}
          failed={create.isError}
          onClose={list.length > 0 ? () => setCreating(false) : undefined}
          onTemplate={(template) => create.mutate({ template: template.key, name: template.name || template.key, locale: templateLocale(locale) })}
          onScratch={(discipline) =>
            create.mutate({ name: t("ranks.newLadderName"), discipline, style: "level", ready_criteria: ["skills"], ranks: [{ name: t("ranks.firstRank") }] })
          }
        />
      ) : (
        <button
          type="button"
          onClick={() => setCreating(true)}
          className="min-h-11 self-start rounded-2xl px-4 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("ranks.newLadder")}
        </button>
      )}
    </div>
  );
}

const field = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

/** The curriculum editor (mockup «Πρόγραμμα κλίμακας», option Α). */
function LadderEditor({ token, slug, ladder, justCreated }: { token: string; slug: string; ladder: RankLadder; justCreated: boolean }) {
  const t = useTranslations("BodyDevices");
  const labels = useWorkoutTypeLabels();
  const queryClient = useQueryClient();
  const [saved, setSaved] = useState<Draft>(() => draftOf(ladder));
  const [draft, setDraftState] = useState<Draft>(saved);
  const [past, setPast] = useState<Draft[]>([]);
  const [future, setFuture] = useState<Draft[]>([]);
  const [open, setOpen] = useState<string | null>(justCreated ? (saved.ranks[0]?.key ?? null) : null);
  const [advanced, setAdvanced] = useState(false);
  const [errors, setErrors] = useState<{ ladder?: boolean; criteria?: boolean; ranks: Set<string> }>({ ranks: new Set() });
  const [justSaved, setJustSaved] = useState(false);
  const sectionRef = useRef<HTMLElement>(null);
  useEffect(() => {
    if (justCreated) sectionRef.current?.scrollIntoView?.({ block: "start", behavior: "smooth" });
  }, [justCreated]);

  const classTypes = useQuery({ queryKey: ["body-devices", "class-types"], enabled: advanced, queryFn: () => listAdminClassTypes(token) });
  const scaleLevels = useQuery({ queryKey: ["body-devices", "scale-levels"], enabled: advanced, queryFn: () => listScaleLevels(token) });
  const save = useMutation({
    mutationFn: () => updateRankLadder(token, slug, ladder.id, ladderBody(draft)),
    onSuccess: (answer) => {
      const next = answer && typeof answer === "object" && Array.isArray(answer.ranks) ? draftOf(answer) : draft;
      setSaved(next);
      setDraftState(next);
      setPast([]);
      setFuture([]);
      setJustSaved(true);
      void queryClient.invalidateQueries({ queryKey: rankLaddersKey(slug) });
    },
  });
  const remove = useMutation({
    mutationFn: () => deleteRankLadder(token, slug, ladder.id),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: rankLaddersKey(slug) }),
  });

  const setDraft = (change: (current: Draft) => Draft) => {
    setPast((list) => [...list.slice(-49), draft]);
    setFuture([]);
    setJustSaved(false);
    setDraftState(change);
  };
  const setRank = (key: string, change: (rank: DraftRank) => DraftRank) =>
    setDraft((current) => ({ ...current, ranks: current.ranks.map((rank) => (rank.key === key ? change(rank) : rank)) }));
  const belt = draft.style === "belt";

  function submit() {
    const ranks = new Set(draft.ranks.filter((rank) => !rank.name.trim()).map((rank) => rank.key));
    const next = { ladder: !draft.name.trim(), criteria: draft.ready_criteria.length === 0, ranks };
    setErrors(next);
    if (ranks.size > 0) setOpen([...ranks][0]);
    if (!next.ladder && !next.criteria && ranks.size === 0) save.mutate();
  }

  return (
    <section
      ref={sectionRef}
      data-testid={`rank-ladder-${ladder.id}`}
      className="flex flex-col gap-3 rounded-2xl p-4"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex flex-wrap items-center gap-2">
        <input
          aria-label={t("ranks.ladderName")}
          value={draft.name}
          maxLength={60}
          aria-invalid={errors.ladder}
          onChange={(event) => {
            const name = event.target.value;
            setDraft((current) => ({ ...current, name }));
          }}
          className="min-h-11 grow rounded-2xl px-4 text-base font-bold"
          style={{ ...field, border: `1px solid ${errors.ladder ? "var(--danger)" : "var(--border)"}` }}
        />
        <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}>
          {t("ranks.discipline", { discipline: labels.type(draft.discipline) })}
        </span>
      </div>
      {errors.ladder ? <span className="-mt-2 text-xs" style={{ color: "var(--danger)" }}>{t("ranks.nameRequired")}</span> : null}

      <div className="flex flex-col gap-1">
        <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("ranks.criteria.title")}</span>
        <div className="flex flex-wrap gap-2" role="group" aria-label={t("ranks.criteria.title")}>
          {CRITERIA.map((criterion) => {
            const on = draft.ready_criteria.includes(criterion);
            return (
              <button
                key={criterion}
                type="button"
                aria-pressed={on}
                onClick={() =>
                  setDraft((current) => ({
                    ...current,
                    ready_criteria: on ? current.ready_criteria.filter((entry) => entry !== criterion) : [...current.ready_criteria, criterion],
                  }))
                }
                className="min-h-9 rounded-full px-3 text-sm font-semibold"
                style={{
                  background: on ? "var(--primary)" : "var(--panel-muted)",
                  color: on ? "var(--primary-contrast)" : "var(--text)",
                  border: "1px solid var(--border)",
                }}
              >
                {t(`ranks.criteria.${criterion}`)}
              </button>
            );
          })}
        </div>
        {errors.criteria && draft.ready_criteria.length === 0 ? (
          <span className="text-xs" style={{ color: "var(--danger)" }}>{t("ranks.criteria.required")}</span>
        ) : null}
      </div>

      <ol className="flex flex-col gap-2">
        {draft.ranks.map((rank, index) => (
          <RankSection
            key={rank.key}
            rank={rank}
            belt={belt}
            open={open === rank.key}
            invalid={errors.ranks.has(rank.key)}
            removable={draft.ranks.length > 1}
            onToggle={() => setOpen(open === rank.key ? null : rank.key)}
            onChange={(change) => setRank(rank.key, change)}
            onRemove={() => setDraft((current) => ({ ...current, ranks: current.ranks.filter((_, at) => at !== index) }))}
          />
        ))}
      </ol>
      {draft.ranks.length < MAX_RANKS ? (
        <button
          type="button"
          onClick={() => {
            const key = newKey();
            setDraft((current) => ({
              ...current,
              ranks: [...current.ranks, { key, name: "", color: null, max_stripes: 0, min_days: null, min_classes: null, skills: [], scale_level_slug: null }],
            }));
            setOpen(key);
          }}
          className="min-h-11 self-start rounded-2xl px-4 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("ranks.addRank")}
        </button>
      ) : null}

      <button type="button" aria-expanded={advanced} onClick={() => setAdvanced(!advanced)} className="self-start text-sm font-semibold" style={{ color: "var(--dim)" }}>
        {t("advanced")}
      </button>
      {advanced ? (
        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1">
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("ranks.countsClasses")}</span>
            <span className="text-xs" style={{ color: "var(--dim)" }}>{t("ranks.countsClassesHint")}</span>
            <div className="flex flex-wrap gap-2">
              {(classTypes.data ?? [])
                .filter((type) => !type.archived_at)
                .map((type) => {
                  const on = draft.class_type_ids.includes(type.id);
                  return (
                    <button
                      key={type.id}
                      type="button"
                      aria-pressed={on}
                      onClick={() =>
                        setDraft((current) => ({
                          ...current,
                          class_type_ids: on ? current.class_type_ids.filter((id) => id !== type.id) : [...current.class_type_ids, type.id],
                        }))
                      }
                      className="min-h-9 rounded-full px-3 text-sm font-semibold"
                      style={{
                        background: on ? "var(--primary)" : "var(--panel-muted)",
                        color: on ? "var(--primary-contrast)" : "var(--text)",
                        border: "1px solid var(--border)",
                      }}
                    >
                      {type.name}
                    </button>
                  );
                })}
            </div>
          </div>
          {draft.ranks.map((rank) => (
            <div key={`adv-${rank.key}`} className="flex flex-wrap items-center gap-2">
              <span className="w-28 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{rank.name}</span>
              <Select
                aria-label={t("ranks.scaleLevel")}
                value={rank.scale_level_slug ?? ""}
                onValueChange={(value) => setRank(rank.key, (current) => ({ ...current, scale_level_slug: value || null }))}
                className="min-h-10 min-w-36"
              >
                <option value="">{t("ranks.noScaleLevel")}</option>
                {(scaleLevels.data ?? []).map((level) => (
                  <option key={level.slug} value={level.slug}>
                    {level.label}
                  </option>
                ))}
              </Select>
            </div>
          ))}
          <ConfirmButton
            label={t("ranks.deleteLadder")}
            question={t("ranks.deleteLadderConfirm", { name: ladder.name })}
            confirmLabel={t("ranks.deleteLadderAction")}
            pending={remove.isPending}
            onConfirm={() => remove.mutate()}
          />
        </div>
      ) : null}
      {remove.isError ? <ErrorNotice variant="field">{t("ranks.deleteFailed")}</ErrorNotice> : null}
      <SaveBar
        changes={draftChanges(saved, draft)}
        canUndo={past.length > 0}
        canRedo={future.length > 0}
        onUndo={() => {
          const previous = past[past.length - 1];
          if (!previous) return;
          setPast(past.slice(0, -1));
          setFuture([draft, ...future]);
          setDraftState(previous);
        }}
        onRedo={() => {
          const [next, ...rest] = future;
          if (!next) return;
          setFuture(rest);
          setPast([...past, draft]);
          setDraftState(next);
        }}
        onCancel={() => {
          setDraftState(saved);
          setPast([]);
          setFuture([]);
          setErrors({ ranks: new Set() });
        }}
        onSave={submit}
        saving={save.isPending}
        saved={justSaved}
        error={save.isError ? t("ranks.saveFailed") : undefined}
        testId={`rank-ladder-save-${ladder.id}`}
      />
    </section>
  );
}

/** One rank as a collapsible section: swatch, name and what it takes; inside, its fields and skills. */
function RankSection({
  rank,
  belt,
  open,
  invalid,
  removable,
  onToggle,
  onChange,
  onRemove,
}: {
  rank: DraftRank;
  belt: boolean;
  open: boolean;
  invalid: boolean;
  removable: boolean;
  onToggle: () => void;
  onChange: (change: (rank: DraftRank) => DraftRank) => void;
  onRemove: () => void;
}) {
  const t = useTranslations("BodyDevices");
  const [dragged, setDragged] = useState<number | null>(null);
  const [details, setDetails] = useState<string | null>(null);
  const handles = useRef(new Map<string, HTMLButtonElement>());
  const summary = [
    rank.min_days ? t("ranks.section.days", { count: rank.min_days }) : null,
    rank.min_classes ? t("ranks.section.classes", { count: rank.min_classes }) : null,
    rank.skills.length ? t("ranks.picker.skillsCount", { count: rank.skills.length }) : null,
    belt && rank.max_stripes ? t("ranks.section.stripes", { count: rank.max_stripes }) : null,
  ].filter(Boolean);
  const setSkills = (change: (skills: DraftSkill[]) => DraftSkill[]) => onChange((current) => ({ ...current, skills: change(current.skills) }));
  const move = (from: number, to: number, focusKey?: string) => {
    setSkills((skills) => moveItem(skills, from, to));
    if (focusKey) requestAnimationFrame(() => handles.current.get(focusKey)?.focus());
  };
  const editing = rank.skills.find((skill) => skill.key === details) ?? null;
  const editingIndex = editing ? rank.skills.indexOf(editing) : -1;

  return (
    <li className="rounded-2xl" style={{ background: "var(--panel-muted)", border: `1px solid ${invalid ? "var(--danger)" : "var(--border)"}` }} data-testid="rank-section">
      <button type="button" aria-expanded={open} onClick={onToggle} className="flex min-h-12 w-full items-center gap-3 px-3 py-2 text-start">
        {belt ? <Belt color={rank.color} stripes={0} className="h-3 w-10" /> : null}
        <span className="flex min-w-0 flex-1 flex-col">
          <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{rank.name || t("ranks.unnamedRank")}</span>
          <span className="truncate text-xs" style={{ color: "var(--text-soft)" }}>{summary.length ? summary.join(" · ") : t("ranks.section.none")}</span>
        </span>
        <span aria-hidden="true" style={{ color: "var(--dim)" }}>{open ? "⌄" : "›"}</span>
      </button>
      {open ? (
        <div className="flex flex-col gap-3 px-3 pb-3">
          <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("ranks.rank")}
            <input
              value={rank.name}
              maxLength={60}
              aria-invalid={invalid}
              onChange={(event) => {
                const name = event.target.value;
                onChange((current) => ({ ...current, name }));
              }}
              className="min-h-10 rounded-xl px-3 text-sm font-normal"
              style={{ ...field, background: "var(--panel)", border: `1px solid ${invalid ? "var(--danger)" : "var(--border)"}` }}
            />
            {invalid ? <span className="font-normal" style={{ color: "var(--danger)" }}>{t("ranks.nameRequired")}</span> : null}
          </label>
          <div className="flex flex-wrap gap-3">
            {belt ? (
              <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
                {t("ranks.belt")}
                <Select
                  value={rank.color ?? ""}
                  onValueChange={(value) => onChange((current) => ({ ...current, color: (value || null) as RankColor | null }))}
                  className="min-h-10 min-w-28"
                >
                  <option value="">{t("ranks.noColor")}</option>
                  {BELT_SHADES.map((color) => (
                    <option key={color} value={color}>
                      {t(`ranks.color.${color}`)}
                    </option>
                  ))}
                </Select>
              </label>
            ) : null}
            {belt ? (
              <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
                {t("ranks.stripes")}
                <IntegerInput
                  value={rank.max_stripes}
                  min={0}
                  max={10}
                  emptyValue={0}
                  onValueChange={(value) => onChange((current) => ({ ...current, max_stripes: value ?? 0 }))}
                  className="min-h-10 w-20 rounded-xl px-3 text-sm font-normal"
                  style={{ ...field, background: "var(--panel)" }}
                />
              </label>
            ) : null}
            <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
              {t("ranks.minDays")}
              <IntegerInput
                value={rank.min_days}
                min={0}
                max={3650}
                onValueChange={(value) => onChange((current) => ({ ...current, min_days: value }))}
                className="min-h-10 w-24 rounded-xl px-3 text-sm font-normal"
                style={{ ...field, background: "var(--panel)" }}
              />
            </label>
            <label className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
              {t("ranks.minClasses")}
              <IntegerInput
                value={rank.min_classes}
                min={0}
                max={2000}
                onValueChange={(value) => onChange((current) => ({ ...current, min_classes: value }))}
                className="min-h-10 w-24 rounded-xl px-3 text-sm font-normal"
                style={{ ...field, background: "var(--panel)" }}
              />
            </label>
          </div>

          <div className="flex flex-col gap-1">
            <span className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("ranks.skills")}</span>
            <ul className="flex flex-col gap-1" data-testid="rank-skills">
              {rank.skills.map((skill, index) => (
                <li
                  key={skill.key}
                  className="flex items-center gap-1 rounded-xl pe-1"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", opacity: dragged === index ? 0.5 : 1 }}
                  onDragOver={(event) => {
                    if (dragged === null) return;
                    event.preventDefault();
                    if (dragged !== index) {
                      move(dragged, index);
                      setDragged(index);
                    }
                  }}
                  onDrop={(event) => {
                    event.preventDefault();
                    setDragged(null);
                  }}
                >
                  <button
                    type="button"
                    ref={(element) => {
                      if (element) handles.current.set(skill.key, element);
                      else handles.current.delete(skill.key);
                    }}
                    draggable
                    onDragStart={(event) => {
                      setDragged(index);
                      event.dataTransfer.effectAllowed = "move";
                    }}
                    onDragEnd={() => setDragged(null)}
                    onKeyDown={(event) => {
                      if (event.key === "ArrowUp" || event.key === "ArrowDown") {
                        event.preventDefault();
                        move(index, index + (event.key === "ArrowUp" ? -1 : 1), skill.key);
                      }
                    }}
                    aria-label={t("ranks.skillRow.handle", { name: skill.name || t("ranks.skillRow.unnamed") })}
                    className="min-h-10 cursor-grab px-2 text-sm"
                    style={{ color: "var(--dim)" }}
                  >
                    ⋮⋮
                  </button>
                  <input
                    aria-label={t("ranks.skillRow.name")}
                    value={skill.name}
                    maxLength={120}
                    onChange={(event) => {
                      const name = event.target.value;
                      setSkills((skills) => skills.map((entry) => (entry.key === skill.key ? { ...entry, name } : entry)));
                    }}
                    className="min-h-10 min-w-0 flex-1 bg-transparent px-1 text-sm outline-none"
                    style={{ color: "var(--text)" }}
                  />
                  {skill.note.trim() || skill.video.trim() ? <span aria-hidden="true" className="h-1.5 w-1.5 rounded-full" style={{ background: "var(--primary)" }} /> : null}
                  <button
                    type="button"
                    onClick={() => setDetails(skill.key)}
                    aria-label={t("ranks.skillRow.more", { name: skill.name || t("ranks.skillRow.unnamed") })}
                    className="min-h-10 px-2 text-sm"
                    style={{ color: "var(--dim)" }}
                  >
                    ⋯
                  </button>
                  <button
                    type="button"
                    onClick={() => setSkills((skills) => skills.filter((entry) => entry.key !== skill.key))}
                    aria-label={t("ranks.skillRow.remove", { name: skill.name || t("ranks.skillRow.unnamed") })}
                    className="min-h-10 px-2 text-sm"
                    style={{ color: "var(--dim)" }}
                  >
                    ✕
                  </button>
                </li>
              ))}
            </ul>
            {rank.skills.length < MAX_SKILLS ? (
              <button
                type="button"
                onClick={() => setSkills((skills) => [...skills, { key: newKey(), id: null, name: "", note: "", video: "" }])}
                className="min-h-10 self-start text-sm font-semibold"
                style={{ color: "var(--text-soft)" }}
              >
                {t("ranks.addSkill")}
              </button>
            ) : null}
          </div>
          {removable ? (
            <button type="button" onClick={onRemove} className="self-start text-sm font-semibold" style={{ color: "var(--dim)" }}>
              {t("ranks.removeRank", { name: rank.name || t("ranks.unnamedRank") })}
            </button>
          ) : null}
        </div>
      ) : null}
      {editing ? (
        <SkillDetailsSheet
          skill={editing}
          first={editingIndex === 0}
          last={editingIndex === rank.skills.length - 1}
          onMove={(step) => move(editingIndex, editingIndex + step)}
          onClose={() => setDetails(null)}
          onSave={(note, video) => setSkills((skills) => skills.map((entry) => (entry.key === editing.key ? { ...entry, note, video } : entry)))}
        />
      ) : null}
    </li>
  );
}

/** ⋯ on a skill: move it up or down, and the coach's note and video for the member. */
function SkillDetailsSheet({
  skill,
  first,
  last,
  onMove,
  onClose,
  onSave,
}: {
  skill: DraftSkill;
  first: boolean;
  last: boolean;
  onMove: (step: -1 | 1) => void;
  onClose: () => void;
  onSave: (note: string, video: string) => void;
}) {
  const t = useTranslations("BodyDevices");
  const [note, setNote] = useState(skill.note);
  const [video, setVideo] = useState(skill.video);
  const [videoError, setVideoError] = useState(false);
  const secondary = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };
  return (
    <Dialog
      onClose={onClose}
      title={skill.name || t("ranks.skillRow.unnamed")}
      titleId={`skill-details-${skill.key}`}
      variant="sheet"
      size="sm"
      testId="skill-details"
      footer={
        <div className="flex w-full items-center justify-end gap-3">
          <button type="button" onClick={onClose} className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("cancel")}
          </button>
          <button
            type="button"
            onClick={() => {
              const link = video.trim();
              if (link && !/^https:\/\/[^\s/]+\.[^\s]+$/i.test(link)) {
                setVideoError(true);
                return;
              }
              onSave(note.trim(), link);
              onClose();
            }}
            className="min-h-11 rounded-2xl px-5 text-sm font-bold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          >
            {t("ranks.skillRow.done")}
          </button>
        </div>
      }
    >
      <div className="flex flex-col gap-3">
        <div className="flex gap-2">
          <button type="button" disabled={first} onClick={() => onMove(-1)} className="min-h-10 rounded-xl px-3 text-sm font-semibold disabled:opacity-40" style={secondary}>
            {t("ranks.skillRow.up")}
          </button>
          <button type="button" disabled={last} onClick={() => onMove(1)} className="min-h-10 rounded-xl px-3 text-sm font-semibold disabled:opacity-40" style={secondary}>
            {t("ranks.skillRow.down")}
          </button>
        </div>
        <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("ranks.skillRow.note")}
          <textarea
            value={note}
            maxLength={500}
            rows={3}
            onChange={(event) => setNote(event.target.value)}
            className="rounded-2xl px-4 py-2 text-sm font-normal"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
          <span className="text-xs font-normal" style={{ color: "var(--dim)" }}>{t("ranks.skillRow.noteHint")}</span>
        </label>
        <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
          {t("ranks.skillRow.video")}
          <input
            type="url"
            inputMode="url"
            value={video}
            maxLength={500}
            placeholder="https://"
            aria-invalid={videoError}
            onChange={(event) => {
              setVideo(event.target.value);
              setVideoError(false);
            }}
            className="min-h-11 rounded-2xl px-4 text-sm font-normal"
            style={{ background: "var(--panel-muted)", border: `1px solid ${videoError ? "var(--danger)" : "var(--border)"}`, color: "var(--text)" }}
          />
          {videoError ? <span className="text-xs font-normal" style={{ color: "var(--danger)" }}>{t("ranks.skillRow.videoInvalid")}</span> : null}
        </label>
      </div>
    </Dialog>
  );
}
