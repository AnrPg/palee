"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  checkEmailSettings,
  deleteEmailSettings,
  fetchEmailSettings,
  saveEmailSettings,
  type EmailSettings,
  type EmailSettingsUpdate,
} from "@/api/channels";
import { Toggle } from "@/components/admin/finance/packages/package-ui";
import { Select } from "@/components/ui/Select";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

import { inputStyle } from "./sms";

const EMAIL_KEY = ["admin", "channels", "email"] as const;
const PORTS = [587, 465, 2525, 25] as const;
type Port = (typeof PORTS)[number];

type Draft = { host: string; port: Port; tls_mode: "starttls" | "tls"; username: string; secret: string; from_address: string; from_name: string };

function errorsOf(error: unknown): Record<string, string> {
  if (!(error instanceof ApiError) || !error.payload.errors) return {};
  return Object.fromEntries(Object.entries(error.payload.errors).map(([field, value]) => [field, String(Array.isArray(value) ? value[0] : value)]));
}

/**
 * «Προχωρημένα» › Δικός μου πάροχος email (ADR-368): Palee sends the box's
 * email by default, free. A box that wants its own address fills in its
 * SMTP details after a short guide, checks them, and sees the DNS records
 * (SPF, DKIM, DMARC) to add at its domain. The password is never shown.
 */
export function OwnEmailSettings({ token }: { token: string }) {
  const t = useTranslations("Sms");
  const queryClient = useQueryClient();
  const query = useQuery({ queryKey: EMAIL_KEY, queryFn: () => fetchEmailSettings(token) });
  const [editing, setEditing] = useState(false);
  const connection = query.data?.connection ?? null;
  const [draft, setDraft] = useState<Draft>({ host: "", port: 587, tls_mode: "starttls", username: "", secret: "", from_address: "", from_name: "" });

  const save = useMutation({
    mutationFn: (update: EmailSettingsUpdate) => saveEmailSettings(token, update),
    onSuccess: (data) => {
      queryClient.setQueryData(EMAIL_KEY, data);
      setEditing(false);
    },
  });
  const check = useMutation({
    mutationFn: () => checkEmailSettings(token),
    onSuccess: ({ connection: next }) => queryClient.setQueryData<EmailSettings>(EMAIL_KEY, (previous) => (previous ? { ...previous, connection: next } : previous)),
  });
  const remove = useMutation({
    mutationFn: () => deleteEmailSettings(token),
    onSuccess: () => queryClient.setQueryData<EmailSettings>(EMAIL_KEY, (previous) => (previous ? { ...previous, connection: null } : previous)),
  });

  if (query.isLoading || query.isError) return null;
  const errors = errorsOf(save.error);
  const field = (name: keyof Draft, label: string, type = "text") => (
    <div>
      <label className="block text-xs font-semibold" style={{ color: "var(--text)" }} htmlFor={`smtp-${name}`}>{label}</label>
      <input
        id={`smtp-${name}`}
        type={type}
        autoComplete="off"
        value={String(draft[name])}
        aria-invalid={Boolean(errors[name])}
        onChange={(event) => setDraft((previous) => ({ ...previous, [name]: event.target.value }))}
        className="mt-1 w-full rounded-xl px-3 py-2 text-sm"
        style={inputStyle(Boolean(errors[name]))}
      />
      {errors[name] ? <p className="mt-1 text-xs" style={{ color: "var(--danger-strong)" }}>{t("smtpFieldInvalid")}</p> : null}
    </div>
  );

  return (
    <section className="space-y-3" data-testid="own-email">
      <div>
        <p className="font-semibold" style={{ color: "var(--text)" }}>{t("emailTitle")}</p>
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("emailHint")}</p>
      </div>

      {connection && !editing ? (
        <div className="space-y-2">
          <div className="flex flex-wrap items-center gap-3">
            <span className="min-w-0 flex-1 text-sm" style={{ color: "var(--text)" }}>
              {connection.from_address} · {connection.host}:{connection.port}
            </span>
            <Toggle label={t("emailUse")} checked={connection.enabled} disabled={save.isPending} onChange={(enabled) => save.mutate({ enabled })} />
          </div>
          <p className="text-xs" style={{ color: connection.status === "invalid" ? "var(--danger-strong)" : "var(--dim)" }}>
            {connection.status === "active" ? t("emailActive") : connection.status === "invalid" ? t("emailInvalid") : t("emailUnchecked")}
          </p>
          <div className="flex flex-wrap gap-3">
            <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} disabled={check.isPending} onClick={() => check.mutate()}>{t("check")}</button>
            <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => setEditing(true)}>{t("emailEdit")}</button>
            <button type="button" className="text-sm font-semibold" style={{ color: "var(--danger-strong)" }} disabled={remove.isPending} onClick={() => remove.mutate()}>{t("emailRemove")}</button>
          </div>
          {check.data && !check.data.check.ok ? <ErrorNotice variant="field">{t("emailCheckFailed")}</ErrorNotice> : null}
          {query.data?.dns_guidance?.steps.length ? (
            <div className="space-y-1" data-testid="email-dns">
              <p className="text-xs font-semibold" style={{ color: "var(--text)" }}>{t("emailDns", { domain: query.data.dns_guidance.domain ?? "" })}</p>
              <ul className="space-y-1">
                {query.data.dns_guidance.steps.map((step) => (
                  <li key={step.key} className="break-all rounded-xl px-3 py-2 font-mono text-xs" style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text-soft)" }}>
                    {step.key.toUpperCase()} · {step.host ?? "@"} · {step.record ?? "—"}
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
        </div>
      ) : !editing ? (
        <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => setEditing(true)}>{t("emailSetUp")}</button>
      ) : (
        <div className="space-y-3">
          <ol className="list-decimal space-y-1 ps-5 text-sm" style={{ color: "var(--text-soft)" }} data-testid="smtp-guide">
            <li>{t("smtpStep1")}</li>
            <li>{t("smtpStep2")}</li>
            <li>{t("smtpStep3")}</li>
            <li>{t("smtpStep4")}</li>
          </ol>
          <div className="grid gap-3 sm:grid-cols-2">
            {field("host", t("smtpHost"))}
            <div>
              <span className="block text-xs font-semibold" style={{ color: "var(--text)" }}>{t("smtpPort")}</span>
              <Select aria-label={t("smtpPort")} value={String(draft.port)} onValueChange={(value: string) => setDraft((previous) => ({ ...previous, port: Number(value) as Port, tls_mode: value === "465" ? "tls" : "starttls" }))} className="mt-1 w-full">
                {PORTS.map((port) => <option key={port} value={String(port)}>{port}</option>)}
              </Select>
            </div>
            {field("username", t("smtpUser"))}
            {field("secret", t("smtpPassword"), "password")}
            {field("from_address", t("smtpFrom"), "email")}
            {field("from_name", t("smtpFromName"))}
          </div>
          {save.isError && Object.keys(errors).length === 0 ? <ErrorNotice variant="field">{t("errors.generic")}</ErrorNotice> : null}
          <div className="flex flex-wrap gap-2">
            <button type="button" className="rounded-full px-4 py-2 text-sm font-semibold" style={{ color: "var(--text)" }} onClick={() => setEditing(false)}>{t("cancel")}</button>
            <button
              type="button"
              className="rounded-full px-4 py-2 text-sm font-semibold"
              style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
              disabled={save.isPending}
              onClick={() =>
                save.mutate({
                  enabled: true,
                  host: draft.host.trim(),
                  port: draft.port,
                  tls_mode: draft.tls_mode,
                  username: draft.username.trim(),
                  from_address: draft.from_address.trim(),
                  from_name: draft.from_name.trim() || null,
                  ...(draft.secret ? { secret: draft.secret } : {}),
                })
              }
            >
              {t("emailSave")}
            </button>
          </div>
        </div>
      )}
    </section>
  );
}
