"use client";

import { Fragment, useMemo, type CSSProperties, type InputHTMLAttributes, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import { Combobox, type ComboboxOption } from "@/components/ui/Combobox";
import { rankExerciseSuggestions, useExerciseSuggestions, type RankedExerciseSuggestion } from "@/hooks/useExerciseSuggestions";
import type { FuzzyMatch } from "@/lib/structured-plan/fuzzy";

const KEEP_ID = "keep-as-typed";
const CATEGORIES = ["strength", "bodyweight", "cardio", "mobility", "skill"] as const;

/** The name with its matched parts marked (`<mark>`). */
export function HighlightedName({ text, marks }: { text: string; marks: FuzzyMatch["marks"] }) {
  const parts: ReactNode[] = [];
  let at = 0;
  for (const [a, b] of [...marks].sort((x, y) => x[0] - y[0])) {
    if (a < at) continue;
    parts.push(text.slice(at, a), <mark key={a}>{text.slice(a, b)}</mark>);
    at = b;
  }
  parts.push(text.slice(at));
  return (
    <>
      {parts.map((part, i) => (
        <Fragment key={i}>{part}</Fragment>
      ))}
    </>
  );
}

type Props = Omit<InputHTMLAttributes<HTMLInputElement>, "value" | "onChange" | "onSelect" | "role" | "style"> & {
  value: string;
  /** Every change: what is typed now, and the catalog slug when a Palee suggestion was picked (else `null`). */
  onValueChange: (name: string, catalogSlug: string | null) => void;
  /** The box whose names to suggest; the selected box when left out. */
  organizationId?: string | null;
  inputStyle?: CSSProperties;
};

/**
 * ADR-461: an exercise name is free text with suggestions. Typing asks the
 * server (debounced), the list shows «Έχεις γράψει», «Του box σου» and
 * «Palee», a name once, best match first, and ends with «Κράτα «…» όπως το
 * έγραψα». ↑/↓ move, Enter or Tab pick, Esc keeps the typed text. Whatever
 * is picked, the field holds a name; a Palee pick also links its slug.
 */
export function ExerciseNameInput({ value, onValueChange, organizationId, inputStyle, ...inputProps }: Props) {
  const t = useTranslations("ExerciseNameInput");
  const { groups } = useExerciseSuggestions(value, { organizationId });

  const ranked = useMemo(() => rankExerciseSuggestions(value, groups), [value, groups]);
  const options = useMemo<ComboboxOption[]>(() => {
    if (!value.trim() || ranked.length === 0) return [];
    const list: ComboboxOption[] = ranked.map((item, index) => ({
      id: `${item.source}-${index}`,
      label: item.name,
      display: <HighlightedName text={item.name} marks={item.marks} />,
      group: t(`group.${item.source}`),
      hint: hintFor(item, t),
    }));
    list.push({ id: KEEP_ID, label: t("keep", { text: value.trim() }), hint: t("keepKey") });
    return list;
  }, [ranked, t, value]);

  function pick(option: ComboboxOption) {
    if (option.id === KEEP_ID) {
      onValueChange(value, null);
      return;
    }
    const item = ranked[options.indexOf(option)];
    if (item) onValueChange(item.name, item.catalog_slug ?? null);
  }

  return (
    <Combobox
      {...inputProps}
      value={value}
      onValueChange={(text) => onValueChange(text, null)}
      options={options}
      onPick={pick}
      listLabel={t("listLabel")}
      inputStyle={inputStyle}
      data-exercise-name-input=""
    />
  );
}

function hintFor(item: RankedExerciseSuggestion, t: ReturnType<typeof useTranslations>): string | undefined {
  if (item.source === "palee") {
    return item.hint && (CATEGORIES as readonly string[]).includes(item.hint) ? t(`category.${item.hint}`) : undefined;
  }
  if (item.uses_count > 0) return t(item.source === "mine" ? "usesMine" : "usesBox", { count: item.uses_count });
  return undefined;
}
