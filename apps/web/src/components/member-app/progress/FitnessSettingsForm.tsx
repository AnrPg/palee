"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState, type FormEvent } from "react";

import {
  fitnessProfileKeys,
  putFitnessSettings,
  type FitnessDisplayMode,
  type FitnessProfile,
  type FitnessSettingsRequest,
} from "@/api/training-floor";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { fieldBorder, formErrorsFrom, invalidFieldProps, NO_FORM_ERRORS, type FormErrors } from "@/lib/form-errors";
import { looserDisplay } from "@/lib/training-floor";

const DISPLAY_MODES: readonly FitnessDisplayMode[] = ["all", "progress_only", "none"];
const MIN_WEIGHT = 25;
const MAX_WEIGHT = 300;
const MIN_YEAR = 1900;

type Field = "body_weight_kg" | "birth_year" | "display";

const controlClass = "w-full max-w-[9rem] rounded-xl px-3 py-2.5 text-sm outline-none";

type Inputs = { weight: string; year: string; display: FitnessDisplayMode };

const numberText = (value: number | null) => (value === null ? "" : String(value));

/** "72,5" or "72.5" as a number; "" as null; anything else as NaN. */
function parseNumber(text: string): number | null {
  const trimmed = text.trim().replace(",", ".");
  if (!trimmed) return null;
  return /^\d+(\.\d+)?$/.test(trimmed) ? Number(trimmed) : Number.NaN;
}

/**
 * The card's «Προχωρημένα» (ADR-395, ANR fitness v2 sections 1, 2, 4 A): body
 * weight, birth year (only once the age bands count) and «Τι να δείχνει».
 * Private to the person and their coach. When the coach chose something
 * stricter, the person's own choice stays theirs but cannot loosen it.
 */
export function FitnessSettingsForm({ profile }: { profile: FitnessProfile }) {
  const t = useTranslations("TrainingFloor");
  const ui = useUiTranslations();
  const token = useSession().tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const ids = useId();
  const settings = profile.settings;
  const ageReady = profile.inputs.age_ready;
  const coachMode = profile.display.set_by === "coach" ? profile.display.mode : null;

  const canonical: Inputs = {
    weight: numberText(settings.body_weight_kg),
    year: numberText(settings.birth_year),
    display: settings.display,
  };
  const [weight, setWeight] = useState(canonical.weight);
  const [year, setYear] = useState(canonical.year);
  const [display, setDisplay] = useState<FitnessDisplayMode>(canonical.display);
  const [errors, setErrors] = useState<FormErrors<Field>>(NO_FORM_ERRORS);
  const [saved, setSaved] = useState(false);
  // The saved settings the inputs last followed, and what the last save sent.
  const [synced, setSynced] = useState<Inputs>(canonical);
  const [sent, setSent] = useState<Inputs | null>(null);

  // When the saved settings change (a save came back, the server normalised
  // "60,5" to 60.5 or rounded a weight), an input still showing the old saved
  // value or what was sent follows the new one; an edit made since stays.
  if (synced.weight !== canonical.weight || synced.year !== canonical.year || synced.display !== canonical.display) {
    const follows = (current: string, key: keyof Inputs) => current === synced[key] || current === sent?.[key];
    if (follows(weight, "weight")) setWeight(canonical.weight);
    if (follows(year, "year")) setYear(canonical.year);
    if (follows(display, "display")) setDisplay(canonical.display);
    setSynced(canonical);
  }

  const save = useMutation({
    mutationFn: (body: FitnessSettingsRequest) => putFitnessSettings(token, body),
    onSuccess: async () => {
      setErrors(NO_FORM_ERRORS);
      setSaved(true);
      await queryClient.invalidateQueries({ queryKey: fitnessProfileKeys });
    },
    onError: (error) => setErrors(formErrorsFrom(error, ui, ["body_weight_kg", "birth_year", "display"] as const)),
  });

  const thisYear = new Date().getFullYear();
  // Compared as numbers, so "60,5" against a saved 60.5 is not a change.
  const dirty =
    parseNumber(weight) !== settings.body_weight_kg ||
    (ageReady && parseNumber(year) !== settings.birth_year) ||
    display !== settings.display;

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const bodyWeight = parseNumber(weight);
    const birthYear = ageReady ? parseNumber(year) : null;
    const fields: Partial<Record<Field, string>> = {};
    if (bodyWeight !== null && !(bodyWeight >= MIN_WEIGHT && bodyWeight <= MAX_WEIGHT)) {
      fields.body_weight_kg = t("fitnessBodyWeightError", { min: MIN_WEIGHT, max: MAX_WEIGHT });
    }
    if (ageReady && birthYear !== null && !(Number.isInteger(birthYear) && birthYear >= MIN_YEAR && birthYear <= thisYear)) {
      fields.birth_year = t("fitnessBirthYearError", { min: String(MIN_YEAR), max: String(thisYear) });
    }
    if (Object.keys(fields).length > 0) {
      setErrors({ fields, message: null });
      return;
    }
    setSaved(false);
    setSent({ weight, year, display });
    const body: FitnessSettingsRequest = { body_weight_kg: bodyWeight, display };
    if (ageReady) body.birth_year = birthYear;
    save.mutate(body);
  };

  const weightError = errors.fields.body_weight_kg;
  const yearError = errors.fields.birth_year;

  return (
    <form className="space-y-4" onSubmit={submit} noValidate data-testid="fitness-settings">
      <div className="space-y-1">
        <label htmlFor={`${ids}-weight`} className="block text-xs font-semibold" style={{ color: "var(--dim)" }}>
          {t("fitnessBodyWeight")}
        </label>
        <div className="flex items-center gap-2">
          <input
            id={`${ids}-weight`}
            inputMode="decimal"
            autoComplete="off"
            className={controlClass}
            style={{ background: "var(--panel)", color: "var(--text)", border: fieldBorder(weightError) }}
            value={weight}
            onChange={(event) => {
              setWeight(event.target.value);
              setSaved(false);
            }}
            {...invalidFieldProps(weightError, `${ids}-weight-error`)}
          />
          <span className="text-sm" style={{ color: "var(--muted)" }}>{t("fitnessKg")}</span>
        </div>
        <FieldError id={`${ids}-weight-error`}>{weightError}</FieldError>
        {!weightError ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("fitnessBodyWeightHint")}</p> : null}
      </div>

      {ageReady ? (
        <div className="space-y-1">
          <label htmlFor={`${ids}-year`} className="block text-xs font-semibold" style={{ color: "var(--dim)" }}>
            {t("fitnessBirthYear")}
          </label>
          <input
            id={`${ids}-year`}
            inputMode="numeric"
            autoComplete="bday-year"
            className={controlClass}
            style={{ background: "var(--panel)", color: "var(--text)", border: fieldBorder(yearError) }}
            value={year}
            onChange={(event) => {
              setYear(event.target.value);
              setSaved(false);
            }}
            {...invalidFieldProps(yearError, `${ids}-year-error`)}
          />
          <FieldError id={`${ids}-year-error`}>{yearError}</FieldError>
          {!yearError ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("fitnessBirthYearHint")}</p> : null}
        </div>
      ) : null}

      <div className="space-y-1">
        <p className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("fitnessDisplay")}</p>
        <SegmentPicker<FitnessDisplayMode>
          ariaLabel={t("fitnessDisplay")}
          semantics="radiogroup"
          value={display}
          onChange={(value) => {
            setDisplay(value);
            setSaved(false);
          }}
          options={DISPLAY_MODES.map((mode) => ({ value: mode, label: t(`fitnessDisplay_${mode}`) }))}
        />
        {coachMode ? (
          <p className="text-xs" style={{ color: "var(--text-soft)" }} data-testid="fitness-coach-limit">
            {t("fitnessCoachLimit", { mode: t(`fitnessDisplay_${coachMode}`) })}
            {looserDisplay(display, coachMode) ? ` ${t("fitnessCoachLimitLooser")}` : ""}
          </p>
        ) : (
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("fitnessDisplayHint")}</p>
        )}
      </div>

      {errors.message ? <ErrorNotice>{errors.message}</ErrorNotice> : null}

      <div className="flex items-center gap-3">
        <button
          type="submit"
          disabled={!dirty || save.isPending}
          className="min-h-10 rounded-xl px-4 text-sm font-semibold disabled:opacity-40"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {t("fitnessSave")}
        </button>
        {saved && !dirty ? (
          <span role="status" className="text-xs" style={{ color: "var(--muted)" }}>
            {t("fitnessSaved")}
          </span>
        ) : null}
      </div>
    </form>
  );
}
