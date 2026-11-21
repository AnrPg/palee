"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useMemo, useState } from "react";

import { createWorkoutKind, fetchWorkoutAuthoringSettings, WOD_ASSISTANT_AVAILABILITY_KEY, WORKOUT_KINDS_KEY } from "@/api/workouts";
import { useSession } from "@/components/session-provider";
import { Combobox, type ComboboxOption } from "@/components/ui/Combobox";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useWorkoutTypeLabels } from "@/components/workouts/WorkoutTypeSelect";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { workoutFamilyColor } from "@/lib/theme";
import { WORKOUT_FAMILY_KEYS, foldKindLabel, kindFamily, sortKindRefs } from "@/lib/workout-kinds";
import { offeredWorkoutTypeGroups, type WorkoutTypeFamily } from "@/lib/workout-types";

const NEW_TYPE = "__new_type__";
const MAX_LABEL = 40;

type Props = {
  value: readonly string[];
  onChange: (value: string[]) => void;
  /** Shown in the search field while nothing is chosen. */
  placeholder: string;
  invalid?: boolean;
  /** A sectioned WOD's own field: its types are the sections' union, shown only. */
  readOnly?: boolean;
  /** Smaller, for a section's types (ADR-690 2C). */
  compact?: boolean;
  testId?: string;
};

/**
 * ADR-690 «Τύποι προπόνησης» (2A): one search field; once a type is chosen,
 * its chip and «+ Κι άλλος τύπος». Every type counts the same (there is no
 * main one). A name the box does not have yet becomes a box type from the
 * same field, after «Μήπως εννοείς…» and a family.
 */
export function WorkoutTypesField({ value, onChange, placeholder, invalid = false, readOnly = false, compact = false, testId = "workout-types-field" }: Props) {
  const t = useTranslations("WorkoutTypes");
  const { tokens } = useSession();
  const settings = useQuery({
    queryKey: WOD_ASSISTANT_AVAILABILITY_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchWorkoutAuthoringSettings(tokens!.access_token),
    staleTime: 60_000,
  });
  const labels = useWorkoutTypeLabels(value);
  const [adding, setAdding] = useState(false);
  const [query, setQuery] = useState("");
  const [creating, setCreating] = useState<string | null>(null);

  const chosen = sortKindRefs(value, labels.catalogue, labels.type);
  const options = useKindOptions(settings.data?.workout_types, chosen, labels);
  const folded = foldKindLabel(query);
  const matches = folded ? options.filter((option) => option.folded.includes(folded)) : options;
  const exact = options.some((option) => option.folded === folded) || chosen.some((ref) => foldKindLabel(labels.type(ref)) === folded);
  const comboOptions: ComboboxOption[] = [
    ...matches.map((option) => ({ id: option.ref, label: option.label, group: labels.family(option.family) })),
    ...(folded.length >= 2 && !exact
      ? [{ id: NEW_TYPE, label: t("field.newType", { name: query.trim().slice(0, MAX_LABEL) }), group: t("field.newGroup") }]
      : []),
  ];

  function add(ref: string) {
    onChange(sortKindRefs([...value, ref], labels.catalogue, labels.type));
    setQuery("");
    setAdding(false);
  }

  const showSearch = !readOnly && (chosen.length === 0 || adding);

  return (
    <div className={`flex flex-wrap items-center gap-2 ${compact ? "text-xs" : "text-sm"}`} data-testid={testId} aria-invalid={invalid || undefined}>
      {chosen.map((ref) => {
        const family = kindFamily(ref, labels.catalogue);
        return (
          <span
            key={ref}
            className={`inline-flex items-center gap-1.5 rounded-full border font-semibold ${compact ? "min-h-7 px-2" : "min-h-9 px-3"}`}
            style={{ borderColor: workoutFamilyColor(family), background: `color-mix(in srgb, ${workoutFamilyColor(family)} 12%, var(--card))`, color: "var(--text)" }}
            data-testid="workout-type-chip"
          >
            <i aria-hidden="true" className="inline-block h-2 w-2 rounded-full" style={{ background: workoutFamilyColor(family) }} />
            {labels.type(ref)}
            {readOnly ? null : (
              <button
                type="button"
                className="-mr-1 grid h-6 w-6 place-items-center rounded-full"
                style={{ color: "var(--muted)" }}
                aria-label={t("field.remove", { name: labels.type(ref) })}
                onClick={() => onChange(value.filter((item) => item !== ref))}
              >
                ×
              </button>
            )}
          </span>
        );
      })}
      {showSearch ? (
        <Combobox
          value={query}
          onValueChange={setQuery}
          options={comboOptions}
          onPick={(option) => (option.id === NEW_TYPE ? setCreating(query.trim().slice(0, MAX_LABEL)) : add(option.id))}
          openOnFocus
          autoFocus={adding}
          listLabel={t("field.listLabel")}
          placeholder={chosen.length === 0 ? placeholder : t("field.searchMore")}
          aria-invalid={invalid}
          className={`${compact ? "min-h-8" : "min-h-11"} min-w-48 flex-1 rounded-xl border px-3`}
          inputStyle={{ borderColor: invalid ? "var(--danger)" : "var(--border)", background: "var(--card)", color: "var(--text)" }}
          emptyText={t("field.nothing")}
          onBlur={() => {
            if (chosen.length > 0 && !query) setAdding(false);
          }}
          data-testid="workout-types-search"
        />
      ) : null}
      {!readOnly && chosen.length > 0 && !adding ? (
        <button
          type="button"
          className={`${compact ? "min-h-7 px-2" : "min-h-9 px-3"} rounded-full border border-dashed font-semibold`}
          style={{ borderColor: "var(--border)", color: "var(--primary)" }}
          onClick={() => setAdding(true)}
          data-testid="workout-type-add-more"
        >
          {t("field.addMore")}
        </button>
      ) : null}
      {creating !== null ? (
        <NewWorkoutTypeDialog
          name={creating}
          options={options}
          onPick={(ref) => {
            setCreating(null);
            add(ref);
          }}
          onClose={() => setCreating(null)}
        />
      ) : null}
    </div>
  );
}

type KindOption = { ref: string; label: string; folded: string; family: WorkoutTypeFamily };

/** Every type the box offers, by family: its kinds, the Palee additions and its own active types. */
function useKindOptions(offered: readonly string[] | undefined, chosen: readonly string[], labels: ReturnType<typeof useWorkoutTypeLabels>) {
  return useMemo(() => {
    const taken = new Set(chosen);
    const options: KindOption[] = [];
    for (const group of offeredWorkoutTypeGroups(offered)) {
      for (const type of group.types) options.push({ ref: type, label: labels.type(type), folded: "", family: group.family });
    }
    for (const addition of labels.catalogue.additions) options.push({ ref: addition.key, label: labels.type(addition.key), folded: "", family: addition.family });
    for (const kind of labels.catalogue.box) {
      if (kind.status === "active") options.push({ ref: kind.ref, label: kind.label, folded: "", family: kind.family });
    }
    return options
      .filter((option) => !taken.has(option.ref))
      .map((option) => ({ ...option, folded: foldKindLabel(option.label) }))
      .sort((a, b) => WORKOUT_FAMILY_KEYS.indexOf(a.family) - WORKOUT_FAMILY_KEYS.indexOf(b.family));
  }, [offered, chosen, labels]);
}

/** Close names: one contains the other, or few letters differ. */
export function closeWorkoutKinds<T extends { folded: string }>(name: string, options: readonly T[], limit = 3): T[] {
  const folded = foldKindLabel(name);
  if (folded.length < 2) return [];
  return options
    .map((option) => ({ option, distance: kindDistance(folded, option.folded) }))
    .filter(({ distance }) => distance <= Math.max(1, Math.round(folded.length / 3)))
    .sort((a, b) => a.distance - b.distance)
    .slice(0, limit)
    .map(({ option }) => option);
}

function kindDistance(a: string, b: string) {
  if (b.includes(a) || a.includes(b)) return 0;
  const row = Array.from({ length: b.length + 1 }, (_, index) => index);
  for (let i = 1; i <= a.length; i += 1) {
    let previous = row[0];
    row[0] = i;
    for (let j = 1; j <= b.length; j += 1) {
      const current = row[j];
      row[j] = Math.min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] === b[j - 1] ? 0 : 1));
      previous = current;
    }
  }
  return row[b.length];
}

/**
 * «Νέος τύπος»: «Μήπως εννοείς…» first, then a family (stats, badges,
 * colour and icon read it). The type joins the box at once; the Palee team
 * sees the name in its queue.
 */
function NewWorkoutTypeDialog({
  name,
  options,
  onPick,
  onClose,
}: {
  name: string;
  options: readonly KindOption[];
  onPick: (ref: string) => void;
  onClose: () => void;
}) {
  const t = useTranslations("WorkoutTypes");
  const i18n = useUiTranslations();
  const labels = useWorkoutTypeLabels();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const [label, setLabel] = useState(name);
  const close = closeWorkoutKinds(label, options);
  // The likeliest family is the closest name's; with none, the author picks.
  const [family, setFamily] = useState<WorkoutTypeFamily | null>(close[0]?.family ?? null);
  const create = useMutation({
    mutationFn: () => createWorkoutKind(tokens!.access_token, { label: label.trim(), family: family! }),
    onSuccess: async (data) => {
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: WOD_ASSISTANT_AVAILABILITY_KEY }),
        queryClient.invalidateQueries({ queryKey: WORKOUT_KINDS_KEY }),
      ]);
      onPick(data.workout_kind.ref);
    },
  });
  const tooShort = foldKindLabel(label).length < 2;

  return (
    <Dialog
      onClose={onClose}
      title={t("create.title")}
      description={t("create.hint")}
      size="md"
      onSubmit={() => {
        if (!tooShort && family && !create.isPending) create.mutate();
      }}
      testId="new-workout-type-dialog"
      footer={
        <>
          <button type="button" className="min-h-11 rounded-full px-4 font-semibold" style={{ color: "var(--muted)" }} onClick={onClose}>
            {t("create.cancel")}
          </button>
          <button
            type="submit"
            disabled={tooShort || !family || create.isPending}
            className="min-h-11 rounded-full px-5 font-bold disabled:opacity-60"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            data-testid="new-workout-type-create"
          >
            {t("create.submit")}
          </button>
        </>
      }
    >
      <div className="space-y-5">
        <label className="block space-y-1.5">
          <span className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--muted)" }}>
            {t("create.name")}
          </span>
          <input
            value={label}
            maxLength={MAX_LABEL}
            onChange={(event) => setLabel(event.target.value)}
            className="min-h-11 w-full rounded-xl border px-3"
            style={{ borderColor: "var(--border)", background: "var(--card)", color: "var(--text)" }}
            data-testid="new-workout-type-name"
          />
        </label>

        {close.length > 0 ? (
          <div className="space-y-2" data-testid="new-workout-type-close">
            <p className="text-sm font-semibold">{t("create.didYouMean")}</p>
            <div className="flex flex-wrap gap-2">
              {close.map((option) => (
                <button
                  key={option.ref}
                  type="button"
                  className="min-h-9 rounded-full border px-3 text-sm font-semibold"
                  style={{ borderColor: workoutFamilyColor(option.family), color: "var(--text)", background: "var(--card)" }}
                  onClick={() => onPick(option.ref)}
                >
                  {option.label} <span style={{ color: "var(--dim)" }}>· {labels.family(option.family)}</span>
                </button>
              ))}
            </div>
          </div>
        ) : null}

        <fieldset className="space-y-2">
          <legend className="text-sm font-semibold">{t("create.family")}</legend>
          <p className="text-xs" style={{ color: "var(--dim)" }}>
            {t("create.familyHint")}
          </p>
          <div className="flex flex-wrap gap-2" role="radiogroup" aria-label={t("create.family")}>
            {WORKOUT_FAMILY_KEYS.map((key) => {
              const on = key === family;
              return (
                <button
                  key={key}
                  type="button"
                  role="radio"
                  aria-checked={on}
                  onClick={() => setFamily(key)}
                  className="min-h-9 rounded-full border px-3 text-sm font-semibold"
                  style={{
                    borderColor: on ? workoutFamilyColor(key) : "var(--border)",
                    background: on ? `color-mix(in srgb, ${workoutFamilyColor(key)} 14%, var(--card))` : "var(--card)",
                    color: on ? "var(--text)" : "var(--muted)",
                  }}
                >
                  {labels.family(key)}
                </button>
              );
            })}
          </div>
        </fieldset>

        {create.error ? <ErrorNotice>{localizeError(create.error, i18n)}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}
