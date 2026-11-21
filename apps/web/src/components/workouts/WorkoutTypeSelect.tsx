"use client";

import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useCallback, useMemo, type CSSProperties } from "react";

import { apiRequest } from "@/api/client";
import { fetchWorkoutAuthoringSettings, WOD_ASSISTANT_AVAILABILITY_KEY, type WodAssistantAvailability } from "@/api/workouts";
import { useOptionalSession, useSession } from "@/components/session-provider";
import { Select } from "@/components/ui/Select";
import { semanticLabel } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import {
  boxKindId,
  workoutKindRefs,
  isBoxKindRef,
  mergeCatalogues,
  resolveMergedKind,
  sortKindRefs,
  unnamedKindRefs,
  type WorkoutKindCatalogue,
} from "@/lib/workout-kinds";
import { isWorkoutType, offeredWorkoutTypeGroups, workoutTypeFamily, type WorkoutType } from "@/lib/workout-types";

/** ADR-690: names for kinds the Palee team added and for box types, from any box. */
export function fetchWorkoutKindNames(token: string, refs: readonly string[]) {
  const query = refs.length > 0 ? `?refs=${encodeURIComponent(refs.join(","))}` : "";
  return apiRequest<WorkoutKindCatalogue>(`/me/workout-kinds${query}`, { token });
}

export const WORKOUT_KIND_NAMES_KEY = ["me", "workout-kinds"] as const;

/**
 * ADR-690: the catalogue a screen needs to name and colour `refs`: the box's
 * own catalogue when the editor already loaded it, plus a lookup of the
 * references it does not hold (a member's journal spans boxes).
 */
export function useWorkoutKindCatalogue(refs: readonly string[] = []): WorkoutKindCatalogue {
  const tokens = useOptionalSession()?.tokens;
  // Subscribes to the editor's settings when a screen already loaded them; never fetches them.
  const authoring = useQuery<WodAssistantAvailability>({
    queryKey: WOD_ASSISTANT_AVAILABILITY_KEY,
    queryFn: () => fetchWorkoutAuthoringSettings(tokens!.access_token),
    enabled: false,
  }).data?.workout_kinds;
  const missing = unnamedKindRefs(refs).filter((ref) => {
    const id = boxKindId(ref);
    return id ? !authoring?.box.some((kind) => kind.id === id) : true;
  });
  const lookup = useQuery({
    queryKey: [...WORKOUT_KIND_NAMES_KEY, missing.filter(isBoxKindRef).join(",")],
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchWorkoutKindNames(tokens!.access_token, missing.filter(isBoxKindRef)),
    staleTime: 5 * 60_000,
  });
  return useMemo(() => mergeCatalogues(lookup.data, authoring), [lookup.data, authoring]);
}

/**
 * The translated name of a workout type or family (ADR-275/680): built-in
 * kinds through the catalogue, Palee additions in the reader's language,
 * box types exactly as the box typed them. Unknown values read as words,
 * never raw keys. Pass the references a screen shows so box types get named.
 */
export function useWorkoutTypeLabels(refs: readonly string[] = []) {
  const t = useTranslations("WorkoutTypes");
  const i18n = useUiTranslations();
  const locale = useLocale().replace("-", "_");
  const catalogue = useWorkoutKindCatalogue(refs);
  const type = useCallback(
    (value: string | null | undefined) => {
      if (!value) return "";
      if (isWorkoutType(value)) return semanticLabel(value, i18n);
      const resolved = resolveMergedKind(value, catalogue);
      const id = boxKindId(resolved);
      if (id) return catalogue.box.find((kind) => kind.id === id)?.label ?? t("boxType");
      const addition = catalogue.additions.find((entry) => entry.key === resolved);
      if (addition) return addition.labels[locale] ?? addition.labels[locale.split("_")[0]] ?? addition.labels.en ?? semanticLabel(resolved, i18n);
      return semanticLabel(resolved, i18n);
    },
    [catalogue, i18n, locale, t],
  );
  const family = useCallback(
    (value: string | null | undefined) => {
      const known = workoutTypeFamily(value) ?? value;
      return known ? t(`family.${known}`) : "";
    },
    [t],
  );
  /** Every type of a WOD, joined (there is no main type). */
  const list = useCallback(
    (values: readonly string[] | null | undefined) =>
      sortKindRefs(values ?? [], catalogue, type)
        .map(type)
        .filter(Boolean)
        .join(" · "),
    [catalogue, type],
  );
  return { type, family, list, catalogue };
}

type Props = {
  value: WorkoutType | "";
  onChange: (value: WorkoutType) => void;
  /** Shown while nothing is chosen. */
  placeholder: string;
  invalid?: boolean;
  className?: string;
  style?: CSSProperties;
};

/**
 * The «Τύπος προπόνησης» picker (ADR-275): the gym's kinds from its
 * settings, grouped by family. A workout's own kind stays listed even when
 * the gym hides it, so opening an old workout never blanks its kind.
 */
export function WorkoutTypeSelect({ value, onChange, placeholder, invalid = false, className, style }: Props) {
  const labels = useWorkoutTypeLabels();
  const { tokens } = useSession();
  const settings = useQuery({
    queryKey: WOD_ASSISTANT_AVAILABILITY_KEY,
    enabled: Boolean(tokens?.access_token),
    queryFn: () => fetchWorkoutAuthoringSettings(tokens!.access_token),
    staleTime: 60_000,
  });
  const groups = offeredWorkoutTypeGroups(settings.data?.workout_types, value || null);

  return (
    <Select
      className={className}
      style={style}
      value={value}
      onValueChange={(next) => {
        if (isWorkoutType(next)) onChange(next);
      }}
      aria-invalid={invalid}
      data-testid="workout-type-select"
    >
      <option value="" disabled>
        {placeholder}
      </option>
      {workoutTypeOptionGroups(groups, labels)}
    </Select>
  );
}

/** `<optgroup>`s of workout kinds by family, for any `Select` (filters included). */
export function workoutTypeOptionGroups(
  groups: ReturnType<typeof offeredWorkoutTypeGroups>,
  labels: ReturnType<typeof useWorkoutTypeLabels>,
) {
  return groups.map((group) => (
    <optgroup key={group.family} label={labels.family(group.family)}>
      {group.types.map((type) => (
        <option key={type} value={type}>
          {labels.type(type)}
        </option>
      ))}
    </optgroup>
  ));
}

/**
 * ADR-690: every type of a WOD in words («CrossFit · Δύναμη»); box types
 * read as the box wrote them. There is no main type.
 */
export function WorkoutTypesText({ workout }: { workout: { type?: string | null; types?: readonly string[] | null } | null | undefined }) {
  const refs = workoutKindRefs(workout);
  const labels = useWorkoutTypeLabels(refs);
  return <>{labels.list(refs)}</>;
}
