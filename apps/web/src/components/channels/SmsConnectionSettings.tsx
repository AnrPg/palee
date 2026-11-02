"use client";

import { useState, type ReactNode } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  checkChannelSettings,
  fetchChannelSettings,
  fetchChannelTemplates,
  resetChannelTemplate,
  saveChannelSettings,
  saveChannelTemplate,
  type ChannelSettings,
  type ChannelSettingsUpdate,
  type ChannelTemplate,
} from "@/api/channels";
import { Toggle } from "@/components/admin/finance/packages/package-ui";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { SPARK_ACTIVE_STYLE } from "@/lib/spark";

import { OwnEmailSettings } from "./OwnEmailSettings";
import {
  DEFAULT_QUIET_END,
  DEFAULT_QUIET_START,
  QUIET_HOURS,
  budgetChoices,
  budgetState,
  formatCents,
  inputStyle,
  providerFor,
  senderError,
  SENDER_EXAMPLE,
  smsErrorCode,
  smsSwitchedOn,
  suggestSender,
} from "./sms";

export const CHANNEL_SETTINGS_KEY = ["admin", "channels", "settings"] as const;
const TEMPLATES_KEY = ["admin", "channels", "templates"] as const;
const EVENT_TEMPLATES = ["event_reminder", "event_changed"] as const;

/** The API's code in words: SMS codes have their own sentence, field errors theirs. */
export function useSmsError() {
  const t = useTranslations("Sms");
  return (error: unknown): string | null => {
    if (!error) return null;
    if (error instanceof ApiError) {
      const code = smsErrorCode(error.payload.code);
      if (code) return t(`errors.${code}`);
    }
    return t("errors.generic");
  };
}

function fieldErrors(error: unknown): Record<string, string> {
  if (!(error instanceof ApiError) || !error.payload.errors) return {};
  return Object.fromEntries(Object.entries(error.payload.errors).map(([field, value]) => [field, String(Array.isArray(value) ? value[0] : value)]));
}

/**
 * Ρυθμίσεις › Συνδέσεις › Μηνύματα SMS (W3 screen 1, option A; ADR-348/349).
 * One card with the switch: once on, SMS leave from Palee's Brevo account
 * with the box's name, a monthly cost limit and quiet hours. «Δοκιμή
 * σύνδεσης» and this month's cost sit beside it. The box's own Brevo key
 * and its own email provider (SMTP) wait under «Προχωρημένα», each with a
 * step-by-step guide. A box in demo mode is told plainly that no SMS leave.
 */
export function SmsConnectionSettings({ token }: { token: string }) {
  const t = useTranslations("Sms");
  const smsError = useSmsError();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const { membership } = useSelectedMembershipRole();
  const demo = membership?.organization.activation === "demo";
  const boxName = membership?.settings?.brand_name?.trim() || membership?.organization.name || "";

  const settingsQuery = useQuery({ queryKey: CHANNEL_SETTINGS_KEY, queryFn: () => fetchChannelSettings(token) });

  const save = useMutation({
    mutationFn: (update: Omit<ChannelSettingsUpdate, "provider"> & { provider?: string }) => {
      const data = settingsQuery.data;
      return saveChannelSettings(token, {
        ...update,
        provider: update.provider ?? providerFor(data?.connection, data?.providers ?? [], update.account_mode ?? data?.connection?.account_mode ?? "palee"),
      });
    },
    onSuccess: ({ connection }) => {
      queryClient.setQueryData<ChannelSettings>(CHANNEL_SETTINGS_KEY, (previous) => (previous ? { ...previous, connection } : previous));
    },
  });

  const check = useMutation({
    mutationFn: () => checkChannelSettings(token),
    onSuccess: ({ connection }) => {
      queryClient.setQueryData<ChannelSettings>(CHANNEL_SETTINGS_KEY, (previous) => (previous ? { ...previous, connection } : previous));
    },
  });

  if (settingsQuery.isLoading) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (settingsQuery.isError || !settingsQuery.data) return <ErrorNotice>{smsError(settingsQuery.error)}</ErrorNotice>;

  const { connection, usage } = settingsQuery.data;
  const on = smsSwitchedOn(connection);

  const switchOn = (value: boolean) => {
    if (!value) {
      save.mutate({ channels: [] });
      return;
    }
    const suggested = suggestSender(boxName);
    save.mutate({
      channels: ["sms"],
      ...(connection ? {} : { account_mode: "palee" as const, ...(suggested && !senderError(suggested) ? { sms_sender: suggested } : {}) }),
    });
  };

  return (
    <div className="space-y-4" data-testid="sms-settings">
      {demo ? (
        <p role="status" className="rounded-2xl px-4 py-3 text-sm" style={{ background: "color-mix(in srgb, var(--warning) 14%, transparent)", border: "1px solid var(--warning)", color: "var(--text)" }} data-testid="sms-demo-notice">
          {t("demoNotice")}
        </p>
      ) : null}

      <Card>
        <div className="flex items-start gap-3">
          <div className="min-w-0 flex-1">
            <p className="font-semibold" style={{ color: "var(--text)" }}>{t("title")}</p>
            <p className="mt-1 text-sm" style={{ color: "var(--dim)" }}>{t("intro")}</p>
          </div>
          <Toggle label={t("title")} checked={on} disabled={save.isPending} onChange={switchOn} />
        </div>
        {save.isError && !Object.keys(fieldErrors(save.error)).length ? <ErrorNotice variant="field">{smsError(save.error)}</ErrorNotice> : null}
      </Card>

      {on && connection ? (
        <>
          <Card>
            <SenderRow key={connection.sms_sender ?? ""} saved={connection.sms_sender ?? ""} pending={save.isPending} error={fieldErrors(save.error).sms_sender} onSave={(sms_sender) => save.mutate({ sms_sender: sms_sender || null })} />
            <SettingRow title={t("budget")} hint={t("budgetHint")}>
              <Select
                aria-label={t("budget")}
                value={String(Math.round(connection.monthly_budget_cents / 100))}
                disabled={save.isPending}
                onValueChange={(value: string) => save.mutate({ monthly_budget_cents: Number(value) * 100 })}
                className="min-w-[8rem]"
              >
                {budgetChoices(connection.monthly_budget_cents).map((euros) => (
                  <option key={euros} value={String(euros)}>
                    {t("budgetPerMonth", { amount: formatCents(euros * 100, connection.currency ?? "EUR", locale) })}
                  </option>
                ))}
              </Select>
            </SettingRow>
            <QuietHoursRow
              start={connection.quiet_start ?? null}
              end={connection.quiet_end ?? null}
              pending={save.isPending}
              onSave={(quiet_start, quiet_end) => save.mutate({ quiet_start, quiet_end })}
            />
          </Card>

          <Card>
            <div className="flex flex-wrap items-center gap-3">
              <span
                className="rounded-full px-3 py-1 text-xs font-semibold"
                style={connection.status === "active" ? SPARK_ACTIVE_STYLE : { background: "var(--danger-surface)", color: "var(--danger-strong)", border: "1px solid var(--danger-border)" }}
                data-testid="sms-status"
              >
                {connection.status === "active" ? t("statusActive") : t("statusInvalid")}
              </span>
              <span className="min-w-0 flex-1 text-sm" style={{ color: "var(--dim)" }}>
                {connection.account_mode === "own" ? t("accountOwn") : t("accountPalee")}
                {connection.checked_at ? ` · ${t("checkedAt", { when: new Date(connection.checked_at).toLocaleString(locale, { dateStyle: "short", timeStyle: "short", hourCycle: "h23" }) })}` : ""}
              </span>
              <button type="button" className="rounded-full px-4 py-1.5 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }} disabled={check.isPending} onClick={() => check.mutate()}>
                {t("check")}
              </button>
            </div>
            {check.data ? (
              check.data.check.ok ? (
                <p role="status" className="text-sm" style={{ color: "var(--success)" }}>{t("checkOk")}</p>
              ) : (
                <ErrorNotice variant="field">{t("checkFailed")}</ErrorNotice>
              )
            ) : null}
            {check.isError ? <ErrorNotice variant="field">{smsError(check.error)}</ErrorNotice> : null}
            <MonthSummary messages={usage.messages} spent={usage.spent_cents} cap={connection.monthly_budget_cents} currency={usage.currency} />
          </Card>

          <EventTexts token={token} />
        </>
      ) : null}

      <Advanced>
        <OwnAccount
          settings={settingsQuery.data}
          pending={save.isPending}
          error={save.isError ? fieldErrors(save.error).secret ?? null : null}
          onSave={(update) => save.mutate(update)}
        />
        <OwnEmailSettings token={token} />
      </Advanced>
    </div>
  );
}

function Card({ children }: { children: ReactNode }) {
  return (
    <div className="space-y-3 rounded-[1.5rem] p-5" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      {children}
    </div>
  );
}

export function SettingRow({ title, hint, children }: { title: string; hint?: string; children?: ReactNode }) {
  return (
    <div className="flex flex-wrap items-center gap-3 border-b py-3 last:border-b-0" style={{ borderColor: "var(--border)" }}>
      <div className="min-w-0 flex-1">
        <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{title}</p>
        {hint ? <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{hint}</p> : null}
      </div>
      {children}
    </div>
  );
}

function Advanced({ children }: { children: ReactNode }) {
  const t = useTranslations("Sms");
  const [open, setOpen] = useState(false);
  return (
    <div className="rounded-[1.5rem]" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <button type="button" aria-expanded={open} className="flex w-full items-center justify-between gap-3 p-5 text-start" onClick={() => setOpen((value) => !value)}>
        <span>
          <span className="block font-semibold" style={{ color: "var(--text)" }}>{t("advanced")}</span>
          <span className="block text-sm" style={{ color: "var(--dim)" }}>{t("advancedHint")}</span>
        </span>
        <span aria-hidden="true" className="text-sm" style={{ color: "var(--dim)" }}>{open ? "▴" : "▾"}</span>
      </button>
      {open ? <div className="space-y-6 border-t px-5 pb-5 pt-4" style={{ borderColor: "var(--border)" }}>{children}</div> : null}
    </div>
  );
}

const inputClass = "w-full rounded-xl px-3 py-2 text-sm";

function SenderRow({ saved, pending, error, onSave }: { saved: string; pending: boolean; error?: string; onSave: (value: string) => void }) {
  const t = useTranslations("Sms");
  const [value, setValue] = useState(saved);
  const local = senderError(value);
  const message = local ? t(`sender_${local}`) : error ? t("sender_latinOnly") : null;
  const dirty = value.trim() !== saved;
  return (
    <div className="border-b py-3" style={{ borderColor: "var(--border)" }}>
      <label className="block text-sm font-semibold" style={{ color: "var(--text)" }} htmlFor="sms-sender">{t("sender")}</label>
      <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{t("senderHint")}</p>
      <div className="mt-2 flex flex-wrap items-start gap-2">
        <div className="min-w-[10rem] flex-1">
          <input
            id="sms-sender"
            value={value}
            maxLength={16}
            placeholder={SENDER_EXAMPLE}
            aria-invalid={Boolean(message)}
            aria-describedby={message ? "sms-sender-error" : undefined}
            onChange={(event) => setValue(event.target.value)}
            className={inputClass}
            style={inputStyle(Boolean(message))}
          />
          {message ? (
            <p id="sms-sender-error" className="mt-1 text-xs" style={{ color: "var(--danger-strong)" }}>{message}</p>
          ) : null}
        </div>
        {dirty ? (
          <button
            type="button"
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            disabled={pending || Boolean(local)}
            onClick={() => onSave(value.trim())}
          >
            {t("saveSender")}
          </button>
        ) : null}
      </div>
    </div>
  );
}

function QuietHoursRow({ start, end, pending, onSave }: { start: string | null; end: string | null; pending: boolean; onSave: (start: string | null, end: string | null) => void }) {
  const t = useTranslations("Sms");
  const on = Boolean(start && end);
  const hours = (current: string | null) => (current && !QUIET_HOURS.includes(current) ? [...QUIET_HOURS, current].sort() : QUIET_HOURS);
  return (
    <SettingRow title={t("quiet")} hint={t("quietHint")}>
      <div className="flex flex-wrap items-center gap-2">
        {on ? (
          <>
            <Select aria-label={t("quietFrom")} value={start!} disabled={pending} onValueChange={(value: string) => onSave(value, end)} className="min-w-[6rem]">
              {hours(start).map((hour) => <option key={hour} value={hour}>{hour}</option>)}
            </Select>
            <span aria-hidden="true" style={{ color: "var(--dim)" }}>–</span>
            <Select aria-label={t("quietTo")} value={end!} disabled={pending} onValueChange={(value: string) => onSave(start, value)} className="min-w-[6rem]">
              {hours(end).map((hour) => <option key={hour} value={hour}>{hour}</option>)}
            </Select>
          </>
        ) : null}
        <Toggle label={t("quiet")} checked={on} disabled={pending} onChange={(value) => (value ? onSave(DEFAULT_QUIET_START, DEFAULT_QUIET_END) : onSave(null, null))} />
      </div>
    </SettingRow>
  );
}

/** «Αυτόν τον μήνα»: messages and cost against the limit, with a bar. */
export function MonthSummary({ messages, spent, cap, currency }: { messages: number; spent: number; cap: number; currency: string }) {
  const t = useTranslations("Sms");
  const locale = useUiLocale();
  const state = budgetState(spent, cap);
  const percent = cap > 0 ? Math.min(100, Math.round((spent / cap) * 100)) : 100;
  const color = state === "full" ? "var(--danger)" : state === "near" ? "var(--warning)" : "var(--primary)";
  return (
    <div className="space-y-2 border-t pt-3" style={{ borderColor: "var(--border)" }} data-testid="sms-month">
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("thisMonth")}</p>
      <div className="flex flex-wrap justify-between gap-2 text-sm" style={{ color: "var(--text-soft)" }}>
        <span>{t("messagesCount", { count: messages })}</span>
        <span className="font-mono tabular-nums">{t("spentOfCap", { spent: formatCents(spent, currency, locale), cap: formatCents(cap, currency, locale) })}</span>
      </div>
      <div className="h-2 overflow-hidden rounded-full" style={{ background: "var(--border)" }} role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={percent} aria-label={t("thisMonth")}>
        <div className="h-full rounded-full" style={{ width: `${percent}%`, background: color }} />
      </div>
      {state !== "ok" ? <p className="text-xs" style={{ color: "var(--text-soft)" }}>{state === "full" ? t("capReached") : t("capNear")}</p> : null}
    </div>
  );
}

/** Λογαριασμός Palee (default) or the box's own Brevo key, with the steps to get one. */
function OwnAccount({ settings, pending, error, onSave }: { settings: ChannelSettings; pending: boolean; error: string | null; onSave: (update: ChannelSettingsUpdate) => void }) {
  const t = useTranslations("Sms");
  const connection = settings.connection;
  const own = connection?.account_mode === "own";
  const [choosing, setChoosing] = useState(false);
  const [key, setKey] = useState("");
  const provider = providerFor(connection, settings.providers, "own");
  return (
    <section className="space-y-3" data-testid="sms-own-account">
      <div>
        <p className="font-semibold" style={{ color: "var(--text)" }}>{t("accountTitle")}</p>
        <p className="text-sm" style={{ color: "var(--dim)" }}>{own ? t("accountOwnHint") : t("accountPaleeHint")}</p>
      </div>
      {own && !choosing ? (
        <div className="flex flex-wrap gap-2">
          <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => setChoosing(true)}>{t("ownReplaceKey")}</button>
          <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} disabled={pending} onClick={() => onSave({ provider, account_mode: "palee" })}>
            {t("backToPalee")}
          </button>
        </div>
      ) : !choosing ? (
        <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => setChoosing(true)}>{t("useOwnBrevo")}</button>
      ) : (
        <div className="space-y-3">
          <ol className="list-decimal space-y-1 ps-5 text-sm" style={{ color: "var(--text-soft)" }} data-testid="brevo-guide">
            <li>{t("brevoStep1")}</li>
            <li>{t("brevoStep2")}</li>
            <li>{t("brevoStep3")}</li>
            <li>{t("brevoStep4")}</li>
          </ol>
          <label className="block text-sm font-semibold" style={{ color: "var(--text)" }} htmlFor="brevo-key">{t("brevoKey")}</label>
          <input id="brevo-key" type="password" autoComplete="off" value={key} onChange={(event) => setKey(event.target.value)} aria-invalid={Boolean(error)} className={inputClass} style={inputStyle(Boolean(error))} />
          {error ? <p className="text-xs" style={{ color: "var(--danger-strong)" }}>{t("brevoKeyInvalid")}</p> : null}
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("brevoKeyHint")}</p>
          <div className="flex gap-2">
            <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ color: "var(--text)" }} onClick={() => setChoosing(false)}>{t("cancel")}</button>
            <button
              type="button"
              className="rounded-full px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              disabled={pending || key.trim() === ""}
              onClick={() => {
                onSave({ provider, account_mode: "own", secret: key.trim(), ...(connection ? {} : { channels: ["sms"] }) });
                setKey("");
                setChoosing(false);
              }}
            >
              {t("saveKey")}
            </button>
          </div>
        </div>
      )}
      {own && connection?.webhook_url ? (
        <p className="break-all text-xs" style={{ color: "var(--dim)" }}>
          {t("webhook")} <code>{connection.webhook_url}</code>
        </p>
      ) : null}
    </section>
  );
}

/** Screen 6 A: the two event texts, each rewritable in the reader's language. */
function EventTexts({ token }: { token: string }) {
  const t = useTranslations("Sms");
  const locale = useUiLocale();
  const smsError = useSmsError();
  const queryClient = useQueryClient();
  const templates = useQuery({ queryKey: TEMPLATES_KEY, queryFn: () => fetchChannelTemplates(token) });
  const [editing, setEditing] = useState<ChannelTemplate | null>(null);
  const [draft, setDraft] = useState("");
  const lang = locale.startsWith("el") ? "el" : locale.split("-")[0] === "pt" ? "pt-PT" : locale.split("-")[0];
  const save = useMutation({
    mutationFn: ({ key, body }: { key: string; body: string | null }) => (body === null ? resetChannelTemplate(token, key, lang) : saveChannelTemplate(token, key, lang, body)),
    onSuccess: () => {
      setEditing(null);
      void queryClient.invalidateQueries({ queryKey: TEMPLATES_KEY });
    },
  });
  const shown = (templates.data?.templates ?? []).filter((template) => (EVENT_TEMPLATES as readonly string[]).includes(template.key));
  if (shown.length === 0) return null;
  const textOf = (template: ChannelTemplate) =>
    template.custom.find((custom) => custom.locale === lang && custom.channel === "any")?.body ?? template.defaults[lang] ?? template.defaults.en ?? "";

  return (
    <Card>
      <p className="font-semibold" style={{ color: "var(--text)" }}>{t("eventTexts")}</p>
      <p className="text-sm" style={{ color: "var(--dim)" }}>{t("eventTextsHint")}</p>
      <ul className="divide-y" style={{ borderColor: "var(--border)" }}>
        {shown.map((template) => (
          <li key={template.key} className="flex flex-wrap items-start gap-3 py-3">
            <div className="min-w-0 flex-1">
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`template_${template.key}`)}</p>
              <p className="text-xs leading-5" style={{ color: "var(--text-soft)" }}>«{textOf(template)}»</p>
            </div>
            <button
              type="button"
              className="text-sm font-semibold"
              style={{ color: "var(--primary)" }}
              onClick={() => {
                setDraft(textOf(template));
                setEditing(template);
              }}
            >
              {t("changeText")}
            </button>
          </li>
        ))}
      </ul>
      {editing ? (
        <Dialog
          variant="center"
          size="sm"
          title={t(`template_${editing.key}`)}
          onClose={() => setEditing(null)}
          dismissible={!save.isPending}
          footer={
            <div className="flex flex-wrap justify-end gap-2">
              {editing.custom.some((custom) => custom.locale === lang) ? (
                <button type="button" className="me-auto text-sm font-semibold" style={{ color: "var(--primary)" }} disabled={save.isPending} onClick={() => save.mutate({ key: editing.key, body: null })}>
                  {t("resetText")}
                </button>
              ) : null}
              <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ color: "var(--text)" }} onClick={() => setEditing(null)}>{t("cancel")}</button>
              <button
                type="button"
                className="rounded-full px-4 py-2 text-sm font-semibold"
                style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                disabled={save.isPending || draft.trim() === ""}
                onClick={() => save.mutate({ key: editing.key, body: draft.trim() })}
              >
                {t("saveText")}
              </button>
            </div>
          }
        >
          <label className="block text-sm font-semibold" style={{ color: "var(--text)" }} htmlFor="sms-template">{t("textLabel")}</label>
          <textarea id="sms-template" rows={4} value={draft} onChange={(event) => setDraft(event.target.value)} aria-invalid={save.isError} className={`${inputClass} mt-2`} style={inputStyle(save.isError)} />
          <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{t("textPlaceholders", { names: editing.variables.map((name) => `{{${name}}}`).join(" ") })}</p>
          {save.isError ? <p className="mt-1 text-xs" style={{ color: "var(--danger-strong)" }}>{smsError(save.error)}</p> : null}
        </Dialog>
      ) : null}
    </Card>
  );
}
