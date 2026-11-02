"use client";

import { useRef, useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  addStatusIncidentUpdate,
  fetchStatusConsole,
  publishStatusIncident,
  translateStatusText,
  type StatusConsole,
  type StatusIncident,
} from "@/api/service-status";
import { useSession } from "@/components/session-provider";
import { BackLink } from "@/components/ui/BackLink";
import { DateTimeInput } from "@/components/ui/DateInput";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { STATUS_COMPONENTS, componentTone, incidentText, toneColor, type StatusComponentKey } from "@/lib/service-status";
import {
  EMPTY_DRAFT,
  draftErrors,
  historyCounts,
  incidentPayload,
  needsTranslation,
  nextStatuses,
  type IncidentStep,
  translationKey,
  updatePayload,
  type IncidentDraft,
  type IncidentKind,
  type Severity,
} from "@/lib/status-console";
import { formatInZone } from "@/lib/zoned-time";

/**
 * ADR-364 / ADR-366, W7 screen 2: «Κατάσταση υπηρεσίας» in the platform
 * console, in the style of «Ειδοποιήσεις συσκευών». «Τώρα» says what the
 * automatic checks see and which incidents are open; one primary button
 * opens «Νέο πρόβλημα ή συντήρηση». The team writes in any language and
 * corrects the automatic English translation before publishing; when the
 * translation fails the incident is published in its own language. Every
 * incident shows who published it.
 */

const QUERY_KEY = ["platform", "status"] as const;
const fieldStyle = { background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" };
const primary = { background: "var(--primary)", color: "var(--primary-contrast)" };

type View = { mode: "overview" } | { mode: "new" } | { mode: "update"; incident: StatusIncident };

export function PlatformStatusPage() {
  const t = useTranslations("PlatformStatus");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  const [view, setView] = useState<View>({ mode: "overview" });

  const status = useQuery({
    queryKey: QUERY_KEY,
    queryFn: () => fetchStatusConsole(token!),
    enabled: Boolean(token),
    refetchInterval: 60_000,
  });

  const forbidden = status.error instanceof ApiError && status.error.status === 403;
  const heading =
    view.mode === "new" ? t("newTitle") : view.mode === "update" ? t("updateTitle") : t("title");
  const subtitle = view.mode === "overview" ? t("subtitle") : t("anyLanguage");

  return (
    <main className="mx-auto w-full max-w-3xl px-4 pb-24 pt-8 sm:px-6">
      <header className="flex flex-col gap-1 border-b border-[var(--border)] pb-5">
        <BackLink href="/platform/organizations" className="text-sm text-[var(--text-soft)]">{t("back")}</BackLink>
        <h1 className="text-3xl font-semibold text-[var(--text)]">{heading}</h1>
        <p className="text-sm text-[var(--text-soft)]">{subtitle}</p>
      </header>

      {forbidden ? <p className="mt-6 text-[var(--text-soft)]">{t("forbidden")}</p> : null}
      {status.isError && !forbidden ? <ErrorNotice className="mt-6">{t("loadError")}</ErrorNotice> : null}
      {status.isPending && token ? <p className="mt-6 text-sm text-[var(--dim)]">{t("loading")}</p> : null}

      {status.data && view.mode === "overview" ? (
        <Overview
          data={status.data}
          onNew={() => setView({ mode: "new" })}
          onUpdate={(incident) => setView({ mode: "update", incident })}
        />
      ) : null}
      {status.data && view.mode !== "overview" && token ? (
        <IncidentForm
          token={token}
          subscribers={status.data.subscribers.confirmed}
          incident={view.mode === "update" ? view.incident : null}
          onDone={() => setView({ mode: "overview" })}
        />
      ) : null}
    </main>
  );
}

// ── Τώρα ────────────────────────────────────────────────────────────────────

function Overview({
  data,
  onNew,
  onUpdate,
}: {
  data: StatusConsole;
  onNew: () => void;
  onUpdate: (incident: StatusIncident) => void;
}) {
  const t = useTranslations("PlatformStatus");
  const tStatus = useTranslations("ServiceStatus");
  const locale = useLocale();
  const open = data.incidents.filter((incident) => !incident.resolved_at);
  const closed = data.incidents.filter((incident) => incident.resolved_at);
  const counts = historyCounts(data.incidents);
  const probes = new Map(data.probes.map((probe) => [probe.key, probe]));
  const failing = data.probes.filter((probe) => probe.status !== "operational");
  const worst = failing.some((probe) => probe.status === "down") ? "down" : failing.length > 0 ? "degraded" : "operational";
  const badgeTone = open.some((incident) => incident.kind === "incident") ? (worst === "operational" ? "warn" : componentTone(worst)) : componentTone(worst);
  const badgeLabel =
    open.length > 0 || worst !== "operational"
      ? worst === "down"
        ? tStatus("overall.major_outage")
        : tStatus("overall.partial_outage")
      : data.probes.length === 0
        ? tStatus("overall.unknown")
        : tStatus("overall.operational");
  const when = (at: string) => formatInZone(at, null, locale, "time");

  return (
    <div className="mt-6 space-y-6">
      <section
        className="space-y-3 rounded-[1.4rem] border p-5"
        style={{ background: "var(--panel)", borderColor: "var(--border)" }}
        data-testid="status-console-now"
      >
        <div className="flex flex-wrap items-center justify-between gap-3">
          <h2 className="text-lg font-semibold text-[var(--text)]">{t("now")}</h2>
          <span
            data-testid="status-console-badge"
            className="inline-flex items-center gap-2 rounded-full px-3 py-1 text-sm font-semibold"
            style={{
              background: `color-mix(in srgb, ${toneColor(badgeTone)} 18%, var(--panel-muted))`,
              color: toneColor(badgeTone),
            }}
          >
            <span aria-hidden className="h-2 w-2 rounded-full" style={{ background: "currentColor" }} />
            {badgeLabel}
          </span>
        </div>
        <div className="grid gap-1.5">
          {STATUS_COMPONENTS.map((key) => {
            const probe = probes.get(key);
            const state = probe?.status ?? "unknown";
            return (
              <div key={key} className="flex justify-between gap-3 text-sm text-[var(--text)]">
                <span>{tStatus(`component.${key}`)}</span>
                <span className="font-semibold" style={{ color: toneColor(componentTone(state)) }}>
                  <span aria-hidden>● </span>
                  {tStatus(`componentStatus.${state}`)}
                </span>
              </div>
            );
          })}
        </div>
        {failing.map((probe) => (
          <p key={probe.key} className="text-xs leading-5 text-[var(--dim)]">
            {t("probeSays", {
              component: tStatus(`component.${probe.key}`),
              status: tStatus(`componentStatus.${probe.status}`),
              since: when(probe.changed_at),
            })}
            {probe.reason ? ` (${probe.reason})` : null}
            {open.some((incident) => (incident.components as string[]).includes(probe.key)) ? null : ` ${t("noIncidentWritten")}`}
          </p>
        ))}
        {open.map((incident) => (
          <OpenIncident key={incident.id} incident={incident} onUpdate={() => onUpdate(incident)} />
        ))}
      </section>

      <div className="flex flex-wrap items-center gap-3">
        <button type="button" onClick={onNew} className="rounded-full px-5 py-2.5 text-sm font-semibold" style={primary}>
          {t("newAction")}
        </button>
      </div>

      <details className="rounded-[1.3rem] p-4" style={{ border: "1px solid var(--border)" }} data-testid="status-console-history">
        <summary className="cursor-pointer text-sm font-semibold text-[var(--muted)]">
          {t("history", { incidents: counts.incidents, maintenance: counts.maintenance })}
        </summary>
        <div className="mt-3 space-y-3">
          {closed.length === 0 ? <p className="text-sm text-[var(--text-soft)]">{t("historyEmpty")}</p> : null}
          {closed.map((incident) => (
            <div key={incident.id} className="text-sm leading-6 text-[var(--text)]">
              <b>
                {formatInZone(incident.started_at, null, locale, { day: "numeric", month: "short" })} · {incident.title}
              </b>
              <span className="text-[var(--muted)]">
                {" · "}
                {tStatus(`incidentStatus.${incident.status}`)}
                {incident.published_by ? ` · ${t("publishedBy", { name: incident.published_by })}` : null}
              </span>
            </div>
          ))}
        </div>
      </details>

      <p className="text-xs text-[var(--dim)]">{t("subscribers", { count: data.subscribers.confirmed })}</p>
    </div>
  );
}

function OpenIncident({ incident, onUpdate }: { incident: StatusIncident; onUpdate: () => void }) {
  const t = useTranslations("PlatformStatus");
  const tStatus = useTranslations("ServiceStatus");
  const locale = useLocale();
  const latest = incident.updates[0];
  return (
    <div
      data-testid="status-console-open"
      className="rounded-2xl p-3 text-sm"
      style={{ background: "var(--panel-muted)", color: "var(--text)" }}
    >
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <b>{incident.title}</b>
          <p className="text-xs text-[var(--muted)]">
            {tStatus(`incidentStatus.${incident.status}`)} · {formatInZone(incident.started_at, null, locale, "time")}
            {incident.published_by ? ` · ${t("publishedBy", { name: incident.published_by })}` : null}
          </p>
          {latest ? <p className="mt-1 text-[var(--text-soft)]">{incidentText(incident, locale).body}</p> : null}
        </div>
        <button
          type="button"
          onClick={onUpdate}
          className="shrink-0 rounded-full border px-3.5 py-1.5 text-sm font-semibold"
          style={{ borderColor: "var(--border)", color: "var(--primary)" }}
        >
          {t("updateAction")}
        </button>
      </div>
    </div>
  );
}

// ── Νέο πρόβλημα / νέα ενημέρωση ────────────────────────────────────────────

function Field({ label, htmlFor, children }: { label: string; htmlFor?: string; children: ReactNode }) {
  return (
    <div className="space-y-2">
      {htmlFor ? (
        <label htmlFor={htmlFor} className="block text-sm font-semibold text-[var(--text)]">
          {label}
        </label>
      ) : (
        <p className="text-sm font-semibold text-[var(--text)]">{label}</p>
      )}
      {children}
    </div>
  );
}

function FieldError({ id, children }: { id: string; children: ReactNode }) {
  return (
    <p id={id} className="text-xs leading-5" style={{ color: "var(--danger)" }}>
      {children}
    </p>
  );
}

function languageName(code: string | null, locale: string) {
  if (!code) return null;
  try {
    return new Intl.DisplayNames([locale], { type: "language" }).of(code) ?? code;
  } catch {
    return code;
  }
}

function IncidentForm({
  token,
  subscribers,
  incident,
  onDone,
}: {
  token: string;
  subscribers: number;
  incident: StatusIncident | null;
  onDone: () => void;
}) {
  const t = useTranslations("PlatformStatus");
  const tStatus = useTranslations("ServiceStatus");
  const locale = useLocale();
  const queryClient = useQueryClient();
  const isUpdate = incident !== null;
  const [draft, setDraft] = useState<IncidentDraft>(EMPTY_DRAFT);
  const [step, setStep] = useState<IncidentStep>(incident ? nextStatuses(incident.kind)[0] : "investigating");
  const [correcting, setCorrecting] = useState(false);
  const [showErrors, setShowErrors] = useState(false);
  const latestKey = useRef<string | null>(null);
  const set = (patch: Partial<IncidentDraft>) => setDraft((current) => ({ ...current, ...patch }));

  const translate = useMutation({
    mutationFn: (text: { title?: string; body: string }) => translateStatusText(token, text),
  });

  // ADR-366: translate once the text is written (on leaving a field), and again
  // when it changes, unless the person already corrected the English.
  function requestTranslation() {
    const withTitle = !isUpdate;
    if (!needsTranslation(draft, withTitle)) return;
    const key = translationKey(withTitle ? draft.title : "", draft.body);
    latestKey.current = key;
    set({ english: { state: "pending", key } });
    translate.mutate(withTitle ? { title: draft.title.trim(), body: draft.body.trim() } : { body: draft.body.trim() }, {
      onSuccess: (answer) => {
        if (latestKey.current !== key) return;
        setCorrecting(false);
        const english = answer.locale?.toLowerCase().startsWith("en");
        set({
          english: english
            ? { state: "same", key, locale: answer.locale ?? "en" }
            : { state: "ready", key, locale: answer.locale, title: answer.title ?? "", body: answer.body, edited: false },
        });
      },
      onError: () => {
        if (latestKey.current === key) set({ english: { state: "failed", key } });
      },
    });
  }

  const publish = useMutation({
    mutationFn: () =>
      incident
        ? addStatusIncidentUpdate(token, incident.id, updatePayload(draft, step))
        : publishStatusIncident(token, incidentPayload(draft)),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: QUERY_KEY });
      await queryClient.invalidateQueries({ queryKey: ["public-status"] });
      onDone();
    },
  });

  const errors = draftErrors(draft, !isUpdate);
  const shown = showErrors ? errors : {};
  const english = draft.english;
  const detected =
    english.state === "ready" || english.state === "same" ? languageName(english.locale, locale) : null;

  return (
    <form
      className="mt-6 space-y-6"
      noValidate
      data-testid="status-incident-form"
      onSubmit={(event) => {
        event.preventDefault();
        setShowErrors(true);
        if (Object.keys(errors).length > 0 || english.state === "pending") return;
        publish.mutate();
      }}
    >
      {isUpdate ? (
        <>
          <p className="text-sm font-semibold text-[var(--text)]">{incident.title}</p>
          <Field label={t("stepLabel")}>
            <SegmentPicker
              ariaLabel={t("stepLabel")}
              semantics="radiogroup"
              value={step}
              onChange={setStep}
              options={nextStatuses(incident.kind).map((value) => ({ value, label: tStatus(`incidentStatus.${value}`) }))}
            />
          </Field>
        </>
      ) : (
        <>
          <Field label={t("kindLabel")}>
            <SegmentPicker<IncidentKind>
              ariaLabel={t("kindLabel")}
              semantics="radiogroup"
              value={draft.kind}
              onChange={(kind) => set({ kind })}
              options={[
                { value: "incident", label: t("kindIncident") },
                { value: "maintenance", label: t("kindMaintenance") },
              ]}
            />
          </Field>
          <Field label={t("componentsLabel")}>
            <div className="flex flex-wrap gap-2" role="group" aria-label={t("componentsLabel")}>
              {STATUS_COMPONENTS.map((key) => (
                <ToggleChip
                  key={key}
                  pressed={draft.components.includes(key)}
                  onToggle={() =>
                    set({
                      components: draft.components.includes(key)
                        ? draft.components.filter((item) => item !== key)
                        : ([...draft.components, key] as StatusComponentKey[]),
                    })
                  }
                >
                  {tStatus(`component.${key}`)}
                </ToggleChip>
              ))}
            </div>
          </Field>
          {draft.kind === "incident" ? (
            <Field label={t("severityLabel")}>
              <SegmentPicker<Severity>
                ariaLabel={t("severityLabel")}
                semantics="radiogroup"
                value={draft.severity}
                onChange={(severity) => set({ severity })}
                options={[
                  { value: "minor", label: t("severityMinor") },
                  { value: "major", label: t("severityMajor") },
                  { value: "critical", label: t("severityCritical") },
                ]}
              />
            </Field>
          ) : (
            <Field label={t("windowLabel")}>
              <div className="grid gap-2 sm:grid-cols-2">
                <DateTimeInput
                  aria-label={t("windowFrom")}
                  className="w-full rounded-2xl border px-4 py-3 text-sm"
                  style={{ ...fieldStyle, ...(shown.window ? { borderColor: "var(--danger)" } : null) }}
                  value={draft.from}
                  onValueChange={(from) => set({ from })}
                  step={900}
                />
                <DateTimeInput
                  aria-label={t("windowUntil")}
                  className="w-full rounded-2xl border px-4 py-3 text-sm"
                  style={{ ...fieldStyle, ...(shown.window ? { borderColor: "var(--danger)" } : null) }}
                  value={draft.until}
                  onValueChange={(until) => set({ until })}
                  min={draft.from ? draft.from.split("T")[0] : undefined}
                  step={900}
                />
              </div>
              {shown.window ? <FieldError id="status-window-error">{t(shown.window)}</FieldError> : null}
            </Field>
          )}
          <Field label={t("titleLabel")} htmlFor="status-title">
            <input
              id="status-title"
              className="w-full rounded-2xl border px-4 py-3 text-sm"
              style={{ ...fieldStyle, ...(shown.title ? { borderColor: "var(--danger)" } : null) }}
              aria-invalid={Boolean(shown.title) || undefined}
              aria-describedby={shown.title ? "status-title-error" : undefined}
              value={draft.title}
              maxLength={140}
              onChange={(event) => set({ title: event.target.value })}
              onBlur={requestTranslation}
            />
            {shown.title ? <FieldError id="status-title-error">{t(shown.title)}</FieldError> : null}
          </Field>
        </>
      )}

      <Field label={t("bodyLabel")} htmlFor="status-body">
        <textarea
          id="status-body"
          rows={3}
          className="w-full rounded-2xl border px-4 py-3 text-sm"
          style={{ ...fieldStyle, ...(shown.body ? { borderColor: "var(--danger)" } : null) }}
          aria-invalid={Boolean(shown.body) || undefined}
          aria-describedby={shown.body ? "status-body-error" : "status-body-language"}
          value={draft.body}
          maxLength={2000}
          onChange={(event) => set({ body: event.target.value })}
          onBlur={requestTranslation}
        />
        {shown.body ? <FieldError id="status-body-error">{t(shown.body)}</FieldError> : null}
        {detected ? (
          <p id="status-body-language" className="text-xs text-[var(--dim)]">
            {t("detected", { language: detected })}
          </p>
        ) : null}
      </Field>

      {english.state === "pending" ? (
        <p className="text-xs text-[var(--dim)]" role="status">{t("translating")}</p>
      ) : null}
      {english.state === "failed" ? (
        <p className="text-xs leading-5" role="status" style={{ color: "var(--warning)" }} data-testid="status-translation-failed">
          {t("translationFailed")}
        </p>
      ) : null}
      {english.state === "ready" ? (
        <div
          className="grid gap-1.5 rounded-2xl border border-dashed px-4 py-3.5"
          style={{ borderColor: "var(--border)" }}
          data-testid="status-english-preview"
        >
          <div className="flex flex-wrap justify-between gap-2 text-xs text-[var(--muted)]">
            <b className="text-[var(--text)]">{t("english")}</b>
            <span>
              {english.edited ? t("corrected") : t("machineTranslation")}
              {correcting ? null : (
                <>
                  {" · "}
                  <button type="button" className="font-semibold" style={{ color: "var(--primary)" }} onClick={() => setCorrecting(true)}>
                    {t("correct")}
                  </button>
                </>
              )}
            </span>
          </div>
          {correcting ? (
            <div className="grid gap-2" lang="en">
              {isUpdate ? null : (
                <>
                  <input
                    aria-label={t("englishTitle")}
                    className="w-full rounded-2xl border px-4 py-2.5 text-sm"
                    style={{ ...fieldStyle, ...(shown.englishTitle ? { borderColor: "var(--danger)" } : null) }}
                    aria-invalid={Boolean(shown.englishTitle) || undefined}
                    value={english.title}
                    maxLength={140}
                    onChange={(event) => set({ english: { ...english, title: event.target.value, edited: true } })}
                  />
                  {shown.englishTitle ? <FieldError id="status-en-title-error">{t(shown.englishTitle)}</FieldError> : null}
                </>
              )}
              <textarea
                aria-label={t("englishBody")}
                rows={3}
                className="w-full rounded-2xl border px-4 py-2.5 text-sm"
                style={{ ...fieldStyle, ...(shown.englishBody ? { borderColor: "var(--danger)" } : null) }}
                aria-invalid={Boolean(shown.englishBody) || undefined}
                value={english.body}
                maxLength={2000}
                onChange={(event) => set({ english: { ...english, body: event.target.value, edited: true } })}
              />
              {shown.englishBody ? <FieldError id="status-en-body-error">{t(shown.englishBody)}</FieldError> : null}
            </div>
          ) : (
            <div className="text-sm text-[var(--text)]" lang="en">
              {isUpdate ? null : <b className="block">{english.title}</b>}
              {english.body}
            </div>
          )}
        </div>
      ) : null}

      <div className="flex flex-wrap items-center gap-4">
        <button
          type="submit"
          disabled={publish.isPending || english.state === "pending"}
          className="rounded-full px-5 py-2.5 text-sm font-semibold disabled:opacity-60"
          style={primary}
        >
          {publish.isPending ? t("publishing") : isUpdate ? t("publishUpdate") : t("publish")}
        </button>
        <button type="button" onClick={onDone} className="text-sm font-semibold text-[var(--muted)]">
          {t("cancel")}
        </button>
      </div>
      {publish.isError ? <ErrorNotice>{t("publishError")}</ErrorNotice> : null}
      <p className="text-xs leading-5 text-[var(--dim)]">{t("publishNote", { count: subscribers })}</p>
    </form>
  );
}

function ToggleChip({ pressed, onToggle, children }: { pressed: boolean; onToggle: () => void; children: ReactNode }) {
  return (
    <button
      type="button"
      aria-pressed={pressed}
      onClick={onToggle}
      className="min-h-10 rounded-full border px-3.5 text-sm font-semibold"
      style={{
        borderColor: pressed ? "var(--primary)" : "var(--border)",
        color: pressed ? "var(--primary)" : "var(--muted)",
        background: "var(--panel)",
      }}
    >
      {children}
    </button>
  );
}
