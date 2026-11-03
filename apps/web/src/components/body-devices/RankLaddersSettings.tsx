"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import {
  createRankLadder,
  deleteRankLadder,
  fetchRankLadders,
  rankLaddersKey,
  updateRankLadder,
  type RankColor,
  type RankLadder,
} from "@/api/body-devices";
import { listAdminClassTypes } from "@/api/schedule";
import { listScaleLevels } from "@/api/workouts";
import { Belt } from "@/components/body-devices/Belt";
import { ConfirmButton } from "@/components/check-in/ConfirmButton";
import { IntegerInput } from "@/components/integer-input";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useWorkoutTypeLabels, WorkoutTypeSelect } from "@/components/workouts/WorkoutTypeSelect";
import type { WorkoutType } from "@/lib/workout-types";

const BELT_SHADES: RankColor[] = ["white", "grey", "yellow", "orange", "green", "blue", "purple", "brown", "red", "black", "pink"];
const TEMPLATE_KEYS = ["bjj_adult", "karate_kyu", "gymnastics_levels"] as const;

type DraftRank = {
  id?: string;
  name: string;
  color: RankColor | null;
  max_stripes: number;
  min_days: number | null;
  min_classes: number | null;
  skills: string;
  scale_level_slug: string | null;
};

type Draft = { name: string; discipline: string; class_type_ids: string[]; ranks: DraftRank[] };

function draftOf(ladder: RankLadder): Draft {
  return {
    name: ladder.name,
    discipline: ladder.discipline,
    class_type_ids: ladder.class_type_ids,
    ranks: ladder.ranks.map((rank) => ({
      id: rank.id,
      name: rank.name,
      color: rank.color ?? null,
      max_stripes: rank.max_stripes,
      min_days: rank.requirements.min_days ?? null,
      min_classes: rank.requirements.min_classes ?? null,
      skills: (rank.requirements.skills ?? []).join(", "),
      scale_level_slug: rank.scale_level_slug ?? null,
    })),
  };
}

/** The request body of a draft; empty requirements are left out. */
export function ladderBody(draft: Draft) {
  return {
    name: draft.name.trim(),
    discipline: draft.discipline,
    class_type_ids: draft.class_type_ids,
    ranks: draft.ranks.map((rank) => {
      const skills = rank.skills
        .split(",")
        .map((skill) => skill.trim())
        .filter(Boolean);
      return {
        ...(rank.id ? { id: rank.id } : {}),
        name: rank.name.trim(),
        color: rank.color,
        max_stripes: rank.max_stripes,
        scale_level_slug: rank.scale_level_slug,
        requirements: {
          ...(rank.min_days ? { min_days: rank.min_days } : {}),
          ...(rank.min_classes ? { min_classes: rank.min_classes } : {}),
          ...(skills.length ? { skills } : {}),
        },
      };
    }),
  };
}

/**
 * Ρυθμίσεις › Προχωρημένα › Βαθμοί (ADR-377, mockup e2setup A): one ladder
 * per discipline, started from a template and corrected in a table (name,
 * belt, stripes, requirements). Scale level and skills per rank sit under
 * «Προχωρημένα».
 */
export function RankLaddersSettings({ token, slug }: { token: string; slug: string }) {
  const t = useTranslations("BodyDevices");
  const queryClient = useQueryClient();
  const ladders = useQuery({ queryKey: rankLaddersKey(slug), enabled: Boolean(token && slug), queryFn: () => fetchRankLadders(token, slug) });
  const [creating, setCreating] = useState(false);
  const [scratchType, setScratchType] = useState<WorkoutType | "">("");
  const create = useMutation({
    mutationFn: (body: Parameters<typeof createRankLadder>[2]) => createRankLadder(token, slug, body),
    onSuccess: () => {
      setCreating(false);
      setScratchType("");
      void queryClient.invalidateQueries({ queryKey: rankLaddersKey(slug) });
    },
  });

  if (ladders.isPending) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (ladders.isError) return <ErrorNotice>{t("errorGeneric")}</ErrorNotice>;

  return (
    <div className="flex flex-col gap-4" data-testid="rank-ladders">
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("ranks.settingsHint")}</p>
      {ladders.data.ladders.map((ladder) => (
        <LadderEditor key={ladder.id} token={token} slug={slug} ladder={ladder} />
      ))}
      {creating || ladders.data.ladders.length === 0 ? (
        <section className="flex flex-col gap-3 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <b className="text-sm" style={{ color: "var(--text)" }}>{t("ranks.newLadder")}</b>
          <div className="flex flex-wrap gap-2">
            {TEMPLATE_KEYS.map((key) => (
              <button
                key={key}
                type="button"
                disabled={create.isPending}
                onClick={() => create.mutate({ template: key, name: t(`ranks.template.${key}`) })}
                className="min-h-9 rounded-full px-3 text-sm font-semibold"
                style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
              >
                {t(`ranks.template.${key}`)}
              </button>
            ))}
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <WorkoutTypeSelect value={scratchType} onChange={setScratchType} placeholder={t("ranks.fromScratch")} className="min-h-11 min-w-56" />
            {scratchType ? (
              <button
                type="button"
                disabled={create.isPending}
                onClick={() =>
                  create.mutate({
                    name: t("ranks.newLadderName"),
                    discipline: scratchType,
                    style: "level",
                    ranks: [{ name: t("ranks.firstRank") }],
                  })
                }
                className="min-h-11 rounded-2xl px-4 text-sm font-semibold"
                style={{ border: "1px solid var(--border)", color: "var(--text)" }}
              >
                {t("ranks.create")}
              </button>
            ) : null}
          </div>
          {create.isError ? <ErrorNotice>{t("errorGeneric")}</ErrorNotice> : null}
        </section>
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

function LadderEditor({ token, slug, ladder }: { token: string; slug: string; ladder: RankLadder }) {
  const t = useTranslations("BodyDevices");
  const labels = useWorkoutTypeLabels();
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState<Draft>(() => draftOf(ladder));
  const [advanced, setAdvanced] = useState(false);
  const [nameErrors, setNameErrors] = useState<Set<number>>(new Set());
  const classTypes = useQuery({ queryKey: ["body-devices", "class-types"], enabled: advanced, queryFn: () => listAdminClassTypes(token) });
  const scaleLevels = useQuery({ queryKey: ["body-devices", "scale-levels"], enabled: advanced, queryFn: () => listScaleLevels(token) });
  const save = useMutation({
    mutationFn: () => updateRankLadder(token, slug, ladder.id, ladderBody(draft)),
    onSuccess: (saved) => {
      setDraft(draftOf(saved));
      void queryClient.invalidateQueries({ queryKey: rankLaddersKey(slug) });
    },
  });
  const remove = useMutation({
    mutationFn: () => deleteRankLadder(token, slug, ladder.id),
    onSuccess: () => void queryClient.invalidateQueries({ queryKey: rankLaddersKey(slug) }),
  });

  const setRank = (index: number, change: Partial<DraftRank>) =>
    setDraft((current) => ({ ...current, ranks: current.ranks.map((rank, at) => (at === index ? { ...rank, ...change } : rank)) }));
  const field = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

  function submit() {
    const missing = new Set(draft.ranks.flatMap((rank, index) => (rank.name.trim() ? [] : [index])));
    setNameErrors(missing);
    if (missing.size === 0 && draft.name.trim()) save.mutate();
  }

  return (
    <section
      data-testid={`rank-ladder-${ladder.id}`}
      className="flex flex-col gap-3 rounded-2xl p-4"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex flex-wrap items-center gap-2">
        <input
          aria-label={t("ranks.ladderName")}
          value={draft.name}
          maxLength={60}
          aria-invalid={!draft.name.trim()}
          onChange={(event) => setDraft({ ...draft, name: event.target.value })}
          className="min-h-11 grow rounded-2xl px-4 text-base font-bold"
          style={{ ...field, border: `1px solid ${draft.name.trim() ? "var(--border)" : "var(--danger)"}` }}
        />
        <span className="rounded-full px-3 py-1 text-xs font-semibold" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }}>
          {t("ranks.discipline", { discipline: labels.type(draft.discipline) })}
        </span>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[34rem] text-sm" style={{ color: "var(--text)" }}>
          <thead>
            <tr className="text-left text-xs" style={{ color: "var(--text-soft)" }}>
              <th className="py-1 pr-2 font-semibold">{t("ranks.rank")}</th>
              <th className="py-1 pr-2 font-semibold">{t("ranks.belt")}</th>
              <th className="py-1 pr-2 font-semibold">{t("ranks.stripes")}</th>
              <th className="py-1 pr-2 font-semibold">{t("ranks.minDays")}</th>
              <th className="py-1 pr-2 font-semibold">{t("ranks.minClasses")}</th>
              <th className="py-1" />
            </tr>
          </thead>
          <tbody>
            {draft.ranks.map((rank, index) => (
              <tr key={rank.id ?? `new-${index}`} className="align-top">
                <td className="py-1 pr-2">
                  <input
                    aria-label={t("ranks.rank")}
                    value={rank.name}
                    maxLength={60}
                    aria-invalid={nameErrors.has(index)}
                    onChange={(event) => setRank(index, { name: event.target.value })}
                    className="min-h-10 w-full rounded-xl px-3"
                    style={{ ...field, border: `1px solid ${nameErrors.has(index) ? "var(--danger)" : "var(--border)"}` }}
                  />
                  {nameErrors.has(index) ? <span className="text-xs" style={{ color: "var(--danger)" }}>{t("ranks.nameRequired")}</span> : null}
                </td>
                <td className="py-1 pr-2">
                  <div className="flex items-center gap-2">
                    <Belt color={rank.color} stripes={rank.max_stripes} className="h-3 w-16" />
                    <Select
                      aria-label={t("ranks.belt")}
                      value={rank.color ?? ""}
                      onValueChange={(value) => setRank(index, { color: (value || null) as RankColor | null })}
                      className="min-h-10 min-w-28"
                    >
                      <option value="">{t("ranks.noColor")}</option>
                      {BELT_SHADES.map((color) => (
                        <option key={color} value={color}>
                          {t(`ranks.color.${color}`)}
                        </option>
                      ))}
                    </Select>
                  </div>
                </td>
                <td className="py-1 pr-2">
                  <IntegerInput
                    aria-label={t("ranks.stripes")}
                    value={rank.max_stripes}
                    min={0}
                    max={10}
                    emptyValue={0}
                    onValueChange={(value) => setRank(index, { max_stripes: value ?? 0 })}
                    className="min-h-10 w-16 rounded-xl px-3"
                    style={field}
                  />
                </td>
                <td className="py-1 pr-2">
                  <IntegerInput
                    aria-label={t("ranks.minDays")}
                    value={rank.min_days}
                    min={0}
                    max={3650}
                    onValueChange={(value) => setRank(index, { min_days: value })}
                    className="min-h-10 w-20 rounded-xl px-3"
                    style={field}
                  />
                </td>
                <td className="py-1 pr-2">
                  <IntegerInput
                    aria-label={t("ranks.minClasses")}
                    value={rank.min_classes}
                    min={0}
                    max={2000}
                    onValueChange={(value) => setRank(index, { min_classes: value })}
                    className="min-h-10 w-20 rounded-xl px-3"
                    style={field}
                  />
                </td>
                <td className="py-1">
                  {draft.ranks.length > 1 ? (
                    <button
                      type="button"
                      aria-label={t("ranks.removeRank", { name: rank.name })}
                      onClick={() => setDraft({ ...draft, ranks: draft.ranks.filter((_, at) => at !== index) })}
                      className="min-h-10 px-2"
                      style={{ color: "var(--dim)" }}
                    >
                      ×
                    </button>
                  ) : null}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <button
        type="button"
        aria-expanded={advanced}
        onClick={() => setAdvanced(!advanced)}
        className="self-start text-sm font-semibold"
        style={{ color: "var(--dim)" }}
      >
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
                        setDraft({
                          ...draft,
                          class_type_ids: on ? draft.class_type_ids.filter((id) => id !== type.id) : [...draft.class_type_ids, type.id],
                        })
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
          {draft.ranks.map((rank, index) => (
            <div key={rank.id ?? `adv-${index}`} className="flex flex-wrap items-center gap-2">
              <span className="w-28 truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{rank.name}</span>
              <Select
                aria-label={t("ranks.scaleLevel")}
                value={rank.scale_level_slug ?? ""}
                onValueChange={(value) => setRank(index, { scale_level_slug: value || null })}
                className="min-h-10 min-w-36"
              >
                <option value="">{t("ranks.noScaleLevel")}</option>
                {(scaleLevels.data ?? []).map((level) => (
                  <option key={level.slug} value={level.slug}>
                    {level.label}
                  </option>
                ))}
              </Select>
              <input
                aria-label={t("ranks.skills")}
                placeholder={t("ranks.skillsPlaceholder")}
                value={rank.skills}
                onChange={(event) => setRank(index, { skills: event.target.value })}
                className="min-h-10 grow rounded-xl px-3"
                style={field}
              />
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
      {save.isError ? <ErrorNotice>{t("ranks.saveFailed")}</ErrorNotice> : null}
      {remove.isError ? <ErrorNotice>{t("ranks.deleteFailed")}</ErrorNotice> : null}
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={() =>
            setDraft({
              ...draft,
              ranks: [...draft.ranks, { name: "", color: null, max_stripes: 0, min_days: null, min_classes: null, skills: "", scale_level_slug: null }],
            })
          }
          className="min-h-11 rounded-2xl px-4 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("ranks.addRank")}
        </button>
        <span className="grow" />
        <button
          type="button"
          disabled={save.isPending}
          onClick={submit}
          className="min-h-11 rounded-2xl px-5 text-sm font-bold"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {save.isPending ? t("saving") : t("save")}
        </button>
      </div>
    </section>
  );
}
