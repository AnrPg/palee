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
  QUIET_HOURS,
  budgetCents,
  budgetInput,
  budgetState,
  currencySymbol,
  formatCents,
  inputStyle,
  isSmsVendor,
  ownVendors,
  providerFor,
  quietHoursReady,
  senderError,
  SENDER_EXAMPLE,
  SMS_VENDOR_NAMES,
  smsErrorCode,
  smsSwitchedOn,
  suggestSender,
  VENDOR_FIELDS,
  VENDOR_GUIDE_STEPS,
  vendorFieldError,
  type SmsVendor,
  type VendorFieldKey,
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
 * with the box's name and the monthly cost limit the box types itself
 * before they go on (ADR-390: no invented default). «Δοκιμή σύνδεσης» and
 * this month's cost sit beside it. Quiet hours (off until the box picks its
 * own times), the box's own SMS vendor (ADR-396) and its own email provider
 * (SMTP) wait under «Προχωρημένα». A box in demo mode is told plainly that no SMS
 * leave.
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
  const [askingCap, setAskingCap] = useState(false);

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
  const hasCap = connection?.monthly_budget_cents != null;

  const turnOn = (monthly_budget_cents?: number) => {
    const suggested = suggestSender(boxName);
    save.mutate(
      {
        channels: ["sms"],
        ...(monthly_budget_cents != null ? { monthly_budget_cents } : {}),
        ...(connection ? {} : { account_mode: "palee" as const, ...(suggested && !senderError(suggested) ? { sms_sender: suggested } : {}) }),
      },
      { onSuccess: () => setAskingCap(false) },
    );
  };

  const switchOn = (value: boolean) => {
    if (!value) {
      setAskingCap(false);
      save.mutate({ channels: [] });
      return;
    }
    // ADR-390: the box types its own cap before the first SMS can go.
    if (hasCap) turnOn();
    else setAskingCap(true);
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
          <Toggle label={t("title")} checked={on || askingCap} disabled={save.isPending} onChange={switchOn} />
        </div>
        {askingCap && !on ? (
          <BudgetField
            saved={null}
            currency={connection?.currency ?? "EUR"}
            pending={save.isPending}
            serverError={fieldErrors(save.error).monthly_budget_cents}
            intro={t("capFirst")}
            action={t("turnOn")}
            onSave={turnOn}
          />
        ) : null}
        {save.isError && !Object.keys(fieldErrors(save.error)).length ? <ErrorNotice variant="field">{smsError(save.error)}</ErrorNotice> : null}
      </Card>

      {on && connection ? (
        <>
          <Card>
            <SenderRow key={connection.sms_sender ?? ""} saved={connection.sms_sender ?? ""} pending={save.isPending} error={fieldErrors(save.error).sms_sender} onSave={(sms_sender) => save.mutate({ sms_sender: sms_sender || null })} />
            <BudgetField
              key={connection.monthly_budget_cents ?? "none"}
              saved={connection.monthly_budget_cents ?? null}
              currency={connection.currency ?? "EUR"}
              pending={save.isPending}
              serverError={fieldErrors(save.error).monthly_budget_cents}
              action={t("budgetSave")}
              onSave={(monthly_budget_cents) => save.mutate({ monthly_budget_cents })}
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
                {connection.account_mode === "own" ? t("accountOwn", { vendor: SMS_VENDOR_NAMES[isSmsVendor(connection.provider) ? connection.provider : "brevo"] }) : t("accountPalee")}
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
            <MonthSummary messages={usage.messages} spent={usage.spent_cents} cap={connection.monthly_budget_cents ?? null} currency={usage.currency} />
          </Card>

          <EventTexts token={token} />
        </>
      ) : null}

      <Advanced>
        {on && connection ? (
          <QuietHoursRow
            key={`${connection.quiet_start ?? ""}-${connection.quiet_end ?? ""}`}
            start={connection.quiet_start ?? null}
            end={connection.quiet_end ?? null}
            pending={save.isPending}
            onSave={(quiet_start, quiet_end) => save.mutate({ quiet_start, quiet_end })}
          />
        ) : null}
        <OwnAccount token={token} settings={settingsQuery.data} />
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

/**
 * «Ώρες ησυχίας» under «Προχωρημένα» (ADR-390): off until the box opens them
 * and picks both times itself; only offers wait, updates always go.
 */
function QuietHoursRow({ start, end, pending, onSave }: { start: string | null; end: string | null; pending: boolean; onSave: (start: string | null, end: string | null) => void }) {
  const t = useTranslations("Sms");
  const saved = quietHoursReady(start, end);
  const [open, setOpen] = useState(saved);
  const [from, setFrom] = useState(start ?? "");
  const [to, setTo] = useState(end ?? "");
  const hours = (current: string) => (current && !QUIET_HOURS.includes(current) ? [...QUIET_HOURS, current].sort() : QUIET_HOURS);
  const ready = quietHoursReady(from || null, to || null);
  const dirty = from !== (start ?? "") || to !== (end ?? "");
  const toggle = (value: boolean) => {
    setOpen(value);
    if (!value) {
      setFrom("");
      setTo("");
      if (saved) onSave(null, null);
    }
  };
  return (
    <section className="space-y-2" data-testid="sms-quiet-hours">
      <SettingRow title={t("quiet")} hint={t("quietHint")}>
        <Toggle label={t("quiet")} checked={open} disabled={pending} onChange={toggle} />
      </SettingRow>
      {open ? (
        <div className="flex flex-wrap items-center gap-2">
          <Select aria-label={t("quietFrom")} value={from} placeholder={t("quietChoose")} disabled={pending} onValueChange={(value: string) => setFrom(value)} className="min-w-[7rem]">
            {hours(from).map((hour) => <option key={hour} value={hour}>{hour}</option>)}
          </Select>
          <span aria-hidden="true" style={{ color: "var(--dim)" }}>–</span>
          <Select aria-label={t("quietTo")} value={to} placeholder={t("quietChoose")} disabled={pending} onValueChange={(value: string) => setTo(value)} className="min-w-[7rem]">
            {hours(to).map((hour) => <option key={hour} value={hour}>{hour}</option>)}
          </Select>
          {dirty ? (
            <button
              type="button"
              className="rounded-full px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              disabled={pending || !ready}
              onClick={() => onSave(from, to)}
            >
              {t("quietSave")}
            </button>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}

/**
 * «Μηνιαίο όριο κόστους» typed by the box (ADR-390): required before SMS go
 * on, no suggested amount. The reason sits under the field (ADR-214).
 */
function BudgetField({
  saved,
  currency,
  pending,
  serverError,
  intro,
  action,
  onSave,
}: {
  saved: number | null;
  currency: string;
  pending: boolean;
  serverError?: string;
  intro?: string;
  action: string;
  onSave: (cents: number) => void;
}) {
  const t = useTranslations("Sms");
  const locale = useUiLocale();
  const initial = budgetInput(saved, locale);
  const [value, setValue] = useState(initial);
  // The value last sent: a reason (ours or the API's) shows until the field changes.
  const [sent, setSent] = useState<string | null>(null);
  const parsed = budgetCents(value);
  const reason = sent !== value ? null : "error" in parsed ? parsed.error : serverError ? (serverError === "required" ? "required" : "invalid") : null;
  const message = reason === "required" ? t("budgetRequired") : reason === "invalid" ? t("budgetInvalid") : null;
  const dirty = saved == null || value.trim() !== initial;
  const submit = () => {
    setSent(value);
    if ("cents" in parsed) onSave(parsed.cents);
  };
  return (
    <div className="border-b py-3 last:border-b-0" style={{ borderColor: "var(--border)" }} data-testid="sms-budget">
      <label className="block text-sm font-semibold" style={{ color: "var(--text)" }} htmlFor="sms-budget">{t("budget")}</label>
      <p className="text-xs leading-5" style={{ color: "var(--dim)" }}>{intro ?? t("budgetHint")}</p>
      <div className="mt-2 flex flex-wrap items-start gap-2">
        <div className="min-w-[8rem] flex-1">
          <div className="flex items-center gap-2">
            <input
              id="sms-budget"
              inputMode="decimal"
              autoComplete="off"
              required
              value={value}
              aria-invalid={Boolean(message)}
              aria-describedby={message ? "sms-budget-error" : undefined}
              onChange={(event) => setValue(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") submit();
              }}
              className={`${inputClass} max-w-[9rem]`}
              style={inputStyle(Boolean(message))}
            />
            <span className="text-sm" style={{ color: "var(--text-soft)" }}>{t("budgetUnit", { currency: currencySymbol(currency, locale) })}</span>
          </div>
          {message ? (
            <p id="sms-budget-error" className="mt-1 text-xs" style={{ color: "var(--danger-strong)" }}>{message}</p>
          ) : null}
        </div>
        {dirty ? (
          <button
            type="button"
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            disabled={pending}
            onClick={submit}
          >
            {action}
          </button>
        ) : null}
      </div>
    </div>
  );
}

/** «Αυτόν τον μήνα»: messages and cost against the limit, with a bar. */
export function MonthSummary({ messages, spent, cap, currency }: { messages: number; spent: number; cap: number | null; currency: string }) {
  const t = useTranslations("Sms");
  const locale = useUiLocale();
  const state = budgetState(spent, cap);
  const percent = cap == null ? 0 : cap > 0 ? Math.min(100, Math.round((spent / cap) * 100)) : 100;
  const color = state === "full" ? "var(--danger)" : state === "near" ? "var(--warning)" : "var(--primary)";
  return (
    <div className="space-y-2 border-t pt-3" style={{ borderColor: "var(--border)" }} data-testid="sms-month">
      <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("thisMonth")}</p>
      <div className="flex flex-wrap justify-between gap-2 text-sm" style={{ color: "var(--text-soft)" }}>
        <span>{t("messagesCount", { count: messages })}</span>
        <span className="font-mono tabular-nums">
          {cap == null ? formatCents(spent, currency, locale) : t("spentOfCap", { spent: formatCents(spent, currency, locale), cap: formatCents(cap, currency, locale) })}
        </span>
      </div>
      <div className="h-2 overflow-hidden rounded-full" style={{ background: "var(--border)" }} role="meter" aria-valuemin={0} aria-valuemax={100} aria-valuenow={percent} aria-label={t("thisMonth")}>
        <div className="h-full rounded-full" style={{ width: `${percent}%`, background: color }} />
      </div>
      {cap == null ? (
        <p className="text-xs" style={{ color: "var(--text-soft)" }}>{t("budgetRequired")}</p>
      ) : state !== "ok" ? (
        <p className="text-xs" style={{ color: "var(--text-soft)" }}>{state === "full" ? t("capReached") : t("capNear")}</p>
      ) : null}
    </div>
  );
}

/**
 * Λογαριασμός Palee (default) or the box's own SMS vendor (ADR-348/396):
 * Brevo, Twilio, Vonage, Infobip, Yuboto or Apifon, picked with ui/Select,
 * each with its own fields and step-by-step guide. Secrets are written once
 * and never read back; a refused key or a wrong field shows under that field.
 */
function OwnAccount({ token, settings }: { token: string; settings: ChannelSettings }) {
  const t = useTranslations("Sms");
  const smsError = useSmsError();
  const queryClient = useQueryClient();
  const connection = settings.connection;
  const own = connection?.account_mode === "own";
  const vendors = ownVendors(settings.providers);
  const current = own && isSmsVendor(connection?.provider) ? connection.provider : null;
  const [choosing, setChoosing] = useState(false);
  const [vendor, setVendor] = useState<SmsVendor>(current ?? vendors[0] ?? "brevo");
  const prefill = (next: SmsVendor): Partial<Record<VendorFieldKey, string>> =>
    next === current ? { account_id: connection?.account_id ?? "", base_url: connection?.base_url ?? "" } : {};
  const [values, setValues] = useState<Partial<Record<VendorFieldKey, string>>>(() => prefill(vendor));
  const [submitted, setSubmitted] = useState(false);
  const [rejected, setRejected] = useState(false);

  const save = useMutation({
    mutationFn: (update: ChannelSettingsUpdate) => saveChannelSettings(token, update),
    onSuccess: ({ connection: saved, check }) => {
      queryClient.setQueryData<ChannelSettings>(CHANNEL_SETTINGS_KEY, (previous) => (previous ? { ...previous, connection: saved } : previous));
      // ADR-396: refused credentials keep the form open, with the reason under the key.
      if (check.error_code === "credentials_rejected") {
        setRejected(true);
        return;
      }
      setChoosing(false);
      setSubmitted(false);
      setValues({});
    },
  });

  const serverErrors = fieldErrors(save.error);
  const fields = VENDOR_FIELDS[vendor];
  const kept = (key: VendorFieldKey) => key !== "account_id" && key !== "base_url" && vendor === current && (key === "secret" ? Boolean(connection?.has_secret) : Boolean(connection?.has_webhook_secret));
  const localError = (key: VendorFieldKey) => vendorFieldError(vendor, key, values[key] ?? "", kept(key));
  const errorOf = (key: VendorFieldKey): string | null => {
    const reason = (submitted ? localError(key) : null) ?? serverErrors[key] ?? null;
    if (reason === "required") return t("vendorFieldRequired");
    if (reason) {
      if (vendor === "twilio" && key === "account_id") return t("twilioSidInvalid");
      if (key === "base_url") return t("infobipBaseUrlInvalid");
      return t("vendorFieldInvalid", { vendor: SMS_VENDOR_NAMES[vendor] });
    }
    if (rejected && key === "secret") return t("vendorRejected", { vendor: SMS_VENDOR_NAMES[vendor] });
    return null;
  };
  const otherError = save.isError && !Object.keys(serverErrors).length ? smsError(save.error) : null;

  const pick = (next: string) => {
    if (!isSmsVendor(next)) return;
    setVendor(next);
    setValues(prefill(next));
    setSubmitted(false);
    setRejected(false);
    save.reset();
  };

  const submit = () => {
    setSubmitted(true);
    setRejected(false);
    if (fields.some((entry) => localError(entry.key))) return;
    const update: ChannelSettingsUpdate = { provider: vendor, account_mode: "own" };
    for (const entry of fields) {
      const value = (values[entry.key] ?? "").trim();
      if (value !== "") update[entry.key] = value;
    }
    // ADR-390: the keys alone; SMS go on with the switch, once the box typed its cap.
    save.mutate(update);
  };

  const cancel = () => {
    setChoosing(false);
    setSubmitted(false);
    setRejected(false);
    setValues(prefill(vendor));
    save.reset();
  };

  const name = SMS_VENDOR_NAMES[current ?? vendor];

  return (
    <section className="space-y-3" data-testid="sms-own-account">
      <div>
        <p className="font-semibold" style={{ color: "var(--text)" }}>{t("accountTitle")}</p>
        <p className="text-sm" style={{ color: "var(--dim)" }}>{own ? t("accountOwnHint", { vendor: name }) : t("accountPaleeHint")}</p>
      </div>
      {own && !choosing ? (
        <div className="flex flex-wrap gap-2">
          <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => setChoosing(true)}>{t("ownReplaceKey")}</button>
          <button
            type="button"
            className="text-sm font-semibold"
            style={{ color: "var(--primary)" }}
            disabled={save.isPending}
            onClick={() => save.mutate({ provider: providerFor(null, settings.providers, "palee"), account_mode: "palee" })}
          >
            {t("backToPalee")}
          </button>
        </div>
      ) : !choosing ? (
        <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => setChoosing(true)}>{t("useOwnVendor")}</button>
      ) : (
        <div className="space-y-3">
          <div>
            <label className="block text-sm font-semibold" style={{ color: "var(--text)" }} htmlFor="sms-vendor">{t("vendor")}</label>
            <Select id="sms-vendor" value={vendor} disabled={save.isPending} onValueChange={pick} className="mt-1 min-w-[10rem]" data-testid="sms-vendor">
              {vendors.map((entry) => <option key={entry} value={entry}>{SMS_VENDOR_NAMES[entry]}</option>)}
            </Select>
          </div>
          <ol className="list-decimal space-y-1 ps-5 text-sm" style={{ color: "var(--text-soft)" }} data-testid={`${vendor}-guide`}>
            {Array.from({ length: VENDOR_GUIDE_STEPS[vendor] }, (_, index) => (
              <li key={index}>{vendor === "brevo" ? t(`brevoStep${index + 1}`) : t(`guide_${vendor}_${index + 1}`)}</li>
            ))}
          </ol>
          {fields.map((entry) => {
            const id = `sms-vendor-${entry.key}`;
            const message = errorOf(entry.key);
            return (
              <div key={`${vendor}-${entry.key}`}>
                <label className="block text-sm font-semibold" style={{ color: "var(--text)" }} htmlFor={id}>
                  {vendor === "brevo" && entry.key === "secret" ? t("brevoKey") : t(`vendorField_${vendor}_${entry.key}`)}
                </label>
                <input
                  id={id}
                  type={entry.secret ? "password" : "text"}
                  autoComplete="off"
                  spellCheck={false}
                  value={values[entry.key] ?? ""}
                  placeholder={kept(entry.key) ? t("vendorSecretKept") : entry.key === "base_url" ? "https://xxxxx.api.infobip.com" : undefined}
                  onChange={(event) => setValues((previous) => ({ ...previous, [entry.key]: event.target.value }))}
                  aria-invalid={Boolean(message)}
                  aria-describedby={message ? `${id}-error` : undefined}
                  className={`${inputClass} mt-1`}
                  style={inputStyle(Boolean(message))}
                />
                {message ? (
                  <p id={`${id}-error`} className="mt-1 text-xs" style={{ color: "var(--danger-strong)" }}>{message}</p>
                ) : entry.key === "webhook_secret" ? (
                  <p className="mt-1 text-xs" style={{ color: "var(--dim)" }}>{t("vonageSignatureHint")}</p>
                ) : null}
              </div>
            );
          })}
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("brevoKeyHint")}</p>
          {otherError ? <ErrorNotice variant="field">{otherError}</ErrorNotice> : null}
          <div className="flex gap-2">
            <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ color: "var(--text)" }} onClick={cancel}>{t("cancel")}</button>
            <button
              type="button"
              className="rounded-full px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              disabled={save.isPending}
              onClick={submit}
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
