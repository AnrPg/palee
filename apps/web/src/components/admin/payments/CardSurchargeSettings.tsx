"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState, type ReactNode } from "react";

import { fetchSurcharge, saveSurcharge, SURCHARGE_KEY, type SurchargeChannel, type SurchargeStatus } from "@/api/card-surcharge";
import { ApiError } from "@/api/client";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { fieldBorder, invalidFieldProps } from "@/lib/form-errors";
import { formatMinorUnits } from "@/lib/finance-accounting";
import { FRESHNESS } from "@/lib/query-policy";

import {
  CHANNELS,
  capBps,
  countryName,
  enableBody,
  fieldForSurchargeError,
  initialDraft,
  lawSentence,
  parseFixedCents,
  parsePercentBps,
  percentText,
  stepErrors,
  surchargeOn,
  type GuideDraft,
  type GuideErrors,
  type GuideField,
  type GuideStep,
} from "./card-surcharge";

/** The package price the example in step 2 works on (60,00). */
const EXAMPLE_CENTS = 6000;

/**
 * Ρυθμίσεις › Πληρωμές › «Επιβάρυνση κάρτας» (ADR-340; mockup W1 s1, option
 * B). Calm by default: one line says whether it applies. «Ρύθμιση» opens a
 * guide in three steps (Κανόνες › Ποσό › Πού μπαίνει): the law of the box's
 * country comes first, the amount is refused above its cap, and «Κάρτα στο
 * POS» starts off. The fixed amount is rare, so it waits under «Προχωρημένα».
 */
export function CardSurchargeSettings({ token }: { token: string }) {
  const t = useTranslations("CardSurcharge");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const [guide, setGuide] = useState<{ step: GuideStep; draft: GuideDraft } | null>(null);
  const [saved, setSaved] = useState(false);

  const query = useQuery({ queryKey: SURCHARGE_KEY, queryFn: () => fetchSurcharge(token), staleTime: FRESHNESS.reference });
  const save = useMutation({
    mutationFn: (update: Parameters<typeof saveSurcharge>[1]) => saveSurcharge(token, update),
    onSuccess: (next) => queryClient.setQueryData(SURCHARGE_KEY, next),
  });

  if (query.isLoading) return <p className="text-sm" style={{ color: "var(--dim)" }}>{ui("loading33ce417")}</p>;
  if (query.isError || !query.data) return <ErrorNotice>{localizeError(query.error, ui)}</ErrorNotice>;
  const status = query.data;
  const on = status.settings.enabled && status.allowed;

  const open = () => {
    setSaved(false);
    save.reset();
    setGuide({ step: 0, draft: initialDraft(status, locale) });
  };

  if (guide) {
    return (
      <Guide
        status={status}
        step={guide.step}
        draft={guide.draft}
        saving={save.isPending}
        saveError={save.error}
        onDraft={(draft) => setGuide({ ...guide, draft })}
        onStep={(step) => {
          save.reset();
          setGuide({ ...guide, step });
        }}
        onRegion={(region) => save.mutate({ region_code: region })}
        onCancel={() => setGuide(null)}
        onEnable={() =>
          save.mutate(enableBody(guide.draft), {
            onSuccess: () => {
              setGuide(null);
              setSaved(true);
            },
          })
        }
      />
    );
  }

  return (
    <Card testId="card-surcharge">
      <div className="flex flex-wrap items-start gap-3">
        <div className="min-w-0 flex-1">
          <p className="font-semibold" style={{ color: "var(--text)" }}>{t("title")}</p>
          <p className="mt-1 text-sm" style={{ color: "var(--dim)" }} data-testid="card-surcharge-summary">
            {on ? t("summaryOn", { amount: amountText(status, locale), channels: channelList(status.settings.channels, t, locale) }) : status.allowed || status.law.region_required ? t("summaryOff") : t("summaryNotAllowed")}
          </p>
        </div>
        {status.allowed || status.law.region_required || on ? (
          <button
            type="button"
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
            onClick={open}
          >
            {on ? t("change") : t("setUp")}
          </button>
        ) : null}
      </div>
      {saved ? (
        <p role="status" className="text-sm font-medium" style={{ color: "var(--success)" }}>
          {t("saved")}
        </p>
      ) : null}
      {on ? (
        <div className="flex justify-end">
          <button
            type="button"
            className="text-sm font-semibold"
            style={{ color: "var(--danger)" }}
            disabled={save.isPending}
            onClick={() => save.mutate({ enabled: false }, { onSuccess: () => setSaved(true) })}
          >
            {t("turnOff")}
          </button>
        </div>
      ) : null}
      {!status.allowed && !status.law.region_required ? <LawBox status={status} /> : null}
      {save.isError ? <ErrorNotice variant="field">{localizeError(save.error, ui)}</ErrorNotice> : null}
    </Card>
  );
}

function amountText(status: SurchargeStatus, locale: string) {
  const { percent_bps: bps, fixed_cents: fixed } = status.settings;
  const parts = [bps > 0 ? percentText(bps, locale) : null, fixed > 0 ? formatMinorUnits(locale, fixed, "EUR") : null].filter(Boolean);
  return parts.join(" + ");
}

function channelList(channels: SurchargeChannel[], t: (key: string) => string, locale: string) {
  const names = CHANNELS.filter((channel) => channels.includes(channel)).map((channel) => t(`channel_${channel}`));
  try {
    return new Intl.ListFormat(locale, { type: "conjunction" }).format(names);
  } catch {
    return names.join(", ");
  }
}

function Card({ children, testId }: { children: ReactNode; testId?: string }) {
  return (
    <div className="space-y-3 rounded-[1.5rem] p-5" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }} data-testid={testId}>
      {children}
    </div>
  );
}

/** «Κανόνες επιβάρυνσης της χώρας · Ελλάδα» and what the law says, in plain words. */
function LawBox({ status }: { status: SurchargeStatus }) {
  const t = useTranslations("CardSurcharge");
  const locale = useUiLocale();
  const sentence = lawSentence(status.law, locale);
  const ok = status.allowed;
  return (
    <div
      className="rounded-2xl px-4 py-3"
      data-testid="card-surcharge-law"
      style={{
        background: `color-mix(in srgb, var(${ok ? "--success" : "--danger"}) 10%, transparent)`,
        border: `1px solid var(${ok ? "--success" : "--danger"})`,
      }}
    >
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
        {status.country_code ? t("lawTitle", { country: countryName(status.country_code, locale) }) : t("lawTitleNoCountry")}
      </p>
      <p className="mt-1 text-sm" style={{ color: "var(--text-soft)" }}>{t(sentence.key, sentence.values)}</p>
      {!ok && !status.law.region_required ? <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{t("lawNoneHint")}</p> : null}
    </div>
  );
}

function Steps({ step }: { step: GuideStep }) {
  const t = useTranslations("CardSurcharge");
  const labels = [t("stepRules"), t("stepAmount"), t("stepWhere")];
  return (
    <ol className="flex flex-wrap gap-2" aria-label={t("title")}>
      {labels.map((label, index) => {
        const current = index === step;
        const done = index < step;
        return (
          <li
            key={label}
            aria-current={current ? "step" : undefined}
            className="inline-flex items-center gap-2 rounded-full px-3 py-1 text-xs font-semibold"
            style={{
              background: current ? "var(--primary)" : "var(--panel)",
              color: current ? "var(--primary-contrast)" : done ? "var(--text)" : "var(--dim)",
              border: `1px solid ${current ? "var(--primary)" : "var(--border)"}`,
            }}
          >
            <span aria-hidden="true">{done ? "✓" : index + 1}</span>
            {label}
          </li>
        );
      })}
    </ol>
  );
}

function Guide({
  status,
  step,
  draft,
  saving,
  saveError,
  onDraft,
  onStep,
  onRegion,
  onCancel,
  onEnable,
}: {
  status: SurchargeStatus;
  step: GuideStep;
  draft: GuideDraft;
  saving: boolean;
  saveError: unknown;
  onDraft: (draft: GuideDraft) => void;
  onStep: (step: GuideStep) => void;
  onRegion: (region: string) => void;
  onCancel: () => void;
  onEnable: () => void;
}) {
  const t = useTranslations("CardSurcharge");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const ids = useId();
  const [checked, setChecked] = useState<GuideStep | null>(null);
  const [region, setRegion] = useState(status.settings.region_code ?? "");
  const [advanced, setAdvanced] = useState(parseFixedCents(draft.fixed) !== 0);
  const law = status.law;
  const cap = capBps(law);

  const local: GuideErrors = checked === step ? stepErrors(step, draft, law) : {};
  const payload = saveError instanceof ApiError ? saveError.payload : undefined;
  const serverField = fieldForSurchargeError(payload);
  const serverText = saveError ? localizeError(saveError, ui) : null;
  // A region was saved but the law still needs one: the code is not one Palee knows.
  const regionUnknown = law.region_required && Boolean(status.settings.region_code) && region === status.settings.region_code;
  const message = (field: GuideField) =>
    local[field]
      ? t(local[field]!, { cap: cap === null ? "" : percentText(cap, locale) })
      : serverField === field
        ? serverText
        : field === "region" && regionUnknown
          ? t("errorRegionUnknown")
          : null;
  const formError = saveError && !serverField ? serverText : null;

  const next = (to: GuideStep) => {
    setChecked(step);
    if (Object.keys(stepErrors(step, draft, law)).length > 0) return;
    onStep(to);
  };

  const percent = parsePercentBps(draft.percent) ?? 0;
  const fixed = parseFixedCents(draft.fixed) ?? 0;
  const fee = surchargeOn(EXAMPLE_CENTS, percent, fixed);
  const money = (cents: number) => formatMinorUnits(locale, cents, "EUR");

  const primary = (label: string, onClick: () => void, disabled = false, testId?: string) => (
    <button
      type="button"
      data-testid={testId}
      disabled={disabled || saving}
      className="rounded-full px-5 py-2.5 text-sm font-semibold disabled:opacity-50"
      style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      onClick={onClick}
    >
      {label}
    </button>
  );
  const textButton = (label: string, onClick: () => void) => (
    <button type="button" className="px-2 py-2 text-sm font-semibold" style={{ color: "var(--text-soft)" }} onClick={onClick}>
      {label}
    </button>
  );

  return (
    <Card testId="card-surcharge-guide">
      <div className="flex items-center justify-between gap-3">
        <p className="font-semibold" style={{ color: "var(--text)" }}>{t("title")}</p>
        {textButton(t("cancel"), onCancel)}
      </div>
      <Steps step={step} />

      {step === 0 ? (
        <div className="space-y-3">
          <LawBox status={status} />
          {law.region_required ? (
            <div className="space-y-1.5">
              <label htmlFor={`${ids}-region`} className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                {t("region")}
              </label>
              <input
                id={`${ids}-region`}
                className="h-11 w-full max-w-[12rem] rounded-xl px-3 text-sm uppercase outline-none"
                style={{ background: "var(--panel)", color: "var(--text)", border: fieldBorder(message("region")) }}
                placeholder={t("regionPlaceholder", { country: status.country_code ?? "US" })}
                maxLength={10}
                value={region}
                onChange={(event) => setRegion(event.target.value.toUpperCase())}
                {...invalidFieldProps(message("region"), `${ids}-region-error`)}
              />
              <FieldError id={`${ids}-region-error`}>{message("region")}</FieldError>
            </div>
          ) : null}
          <div className="flex items-center justify-end gap-2">
            {law.region_required
              ? primary(t("checkRegion"), () => onRegion(region.trim()), region.trim().length < 4, "card-surcharge-region")
              : primary(t("continue"), () => next(1), !status.allowed, "card-surcharge-next")}
          </div>
        </div>
      ) : null}

      {step === 1 ? (
        <div className="space-y-3">
          <div className="space-y-1.5">
            <label htmlFor={`${ids}-percent`} className="text-sm font-semibold" style={{ color: "var(--text)" }}>
              {t("percent")}
            </label>
            <div className="flex items-center gap-2">
              <input
                id={`${ids}-percent`}
                inputMode="decimal"
                className="h-11 w-28 rounded-xl px-3 text-sm outline-none"
                style={{ background: "var(--panel)", color: "var(--text)", border: fieldBorder(message("percent")) }}
                value={draft.percent}
                onChange={(event) => onDraft({ ...draft, percent: event.target.value })}
                {...invalidFieldProps(message("percent"), `${ids}-percent-error`)}
              />
              <span className="text-sm" style={{ color: "var(--dim)" }}>
                %{cap !== null ? ` · ${t("upTo", { cap: percentText(cap, locale) })}` : ""}
              </span>
            </div>
            <FieldError id={`${ids}-percent-error`}>{message("percent")}</FieldError>
          </div>

          <p className="text-sm" style={{ color: "var(--dim)" }} data-testid="card-surcharge-example">
            {t("example", { price: money(EXAMPLE_CENTS), total: money(EXAMPLE_CENTS + fee), fee: money(fee) })}
          </p>

          {law.at_cost ? (
            <div className="space-y-1.5">
              <button
                type="button"
                role="checkbox"
                aria-checked={draft.atCost}
                className="flex w-full items-start gap-3 rounded-2xl p-3 text-start"
                style={{ background: "var(--panel)", border: fieldBorder(message("atCost")) }}
                onClick={() => onDraft({ ...draft, atCost: !draft.atCost })}
                {...invalidFieldProps(message("atCost"), `${ids}-cost-error`)}
              >
                <CheckMark on={draft.atCost} />
                <span>
                  <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("atCost")}</span>
                  <span className="block text-xs" style={{ color: "var(--dim)" }}>{t("atCostHint")}</span>
                </span>
              </button>
              <FieldError id={`${ids}-cost-error`}>{message("atCost")}</FieldError>
            </div>
          ) : null}

          <div className="rounded-2xl" style={{ border: "1px solid var(--border)" }}>
            <button type="button" aria-expanded={advanced} className="flex w-full items-center justify-between px-4 py-3 text-sm font-semibold" style={{ color: "var(--text)" }} onClick={() => setAdvanced((value) => !value)}>
              {t("advanced")}
              <span aria-hidden="true" style={{ color: "var(--dim)" }}>{advanced ? "▴" : "▾"}</span>
            </button>
            {advanced ? (
              <div className="space-y-1.5 px-4 pb-4">
                <label htmlFor={`${ids}-fixed`} className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {t("fixed")}
                </label>
                <input
                  id={`${ids}-fixed`}
                  inputMode="decimal"
                  className="h-11 w-28 rounded-xl px-3 text-sm outline-none"
                  style={{ background: "var(--panel)", color: "var(--text)", border: fieldBorder(message("fixed")) }}
                  value={draft.fixed}
                  onChange={(event) => onDraft({ ...draft, fixed: event.target.value })}
                  {...invalidFieldProps(message("fixed"), `${ids}-fixed-error`)}
                />
                <p className="text-xs" style={{ color: "var(--dim)" }}>{t("fixedHint")}</p>
                <FieldError id={`${ids}-fixed-error`}>{message("fixed")}</FieldError>
              </div>
            ) : null}
          </div>

          <div className="flex items-center justify-between gap-2">
            {textButton(t("back"), () => onStep(0))}
            {primary(t("continue"), () => next(2), false, "card-surcharge-next")}
          </div>
        </div>
      ) : null}

      {step === 2 ? (
        <div className="space-y-3">
          <div role="group" aria-label={t("stepWhere")} className="space-y-2">
            {CHANNELS.map((channel) => {
              const on = draft.channels.includes(channel);
              return (
                <button
                  key={channel}
                  type="button"
                  role="checkbox"
                  aria-checked={on}
                  data-testid={`card-surcharge-channel-${channel}`}
                  className="flex w-full items-start gap-3 rounded-2xl p-3 text-start"
                  style={{ background: "var(--panel)", border: fieldBorder(message("channels")) }}
                  onClick={() => onDraft({ ...draft, channels: on ? draft.channels.filter((value) => value !== channel) : [...draft.channels, channel] })}
                >
                  <CheckMark on={on} />
                  <span>
                    <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`channel_${channel}`)}</span>
                    <span className="block text-xs" style={{ color: "var(--dim)" }}>{t(`channel_${channel}_hint`)}</span>
                  </span>
                </button>
              );
            })}
            <FieldError id={`${ids}-channels-error`}>{message("channels")}</FieldError>
          </div>
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("receiptNote")}</p>
          {formError ? <ErrorNotice variant="field">{formError}</ErrorNotice> : null}
          <div className="flex items-center justify-between gap-2">
            {textButton(t("back"), () => onStep(1))}
            {primary(saving ? t("saving") : t("enable"), () => {
              setChecked(2);
              if (Object.keys(stepErrors(2, draft, law)).length > 0) return;
              onEnable();
            }, false, "card-surcharge-enable")}
          </div>
        </div>
      ) : null}

      {step === 0 && formError ? <ErrorNotice variant="field">{formError}</ErrorNotice> : null}
    </Card>
  );
}

function CheckMark({ on }: { on: boolean }) {
  return (
    <span
      aria-hidden="true"
      className="mt-0.5 inline-flex h-5 w-5 shrink-0 items-center justify-center rounded-md text-xs font-bold"
      style={{ background: on ? "var(--primary)" : "var(--panel)", color: "var(--primary-contrast)", border: `1px solid ${on ? "var(--primary)" : "var(--border-strong)"}` }}
    >
      {on ? "✓" : ""}
    </span>
  );
}
