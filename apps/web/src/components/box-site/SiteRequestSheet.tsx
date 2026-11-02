"use client";

import Link from "next/link";
import { useId, useState } from "react";
import { useLocale, useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import { sendSiteForm } from "@/api/box-site";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { attribution, contactFields } from "@/lib/public-site";

import { trackLead, useSiteConsent } from "./SiteConsent";

type Kind = "trial" | "contact";
type Field = "name" | "contact" | "message" | "privacy_ack";

const nowMs = () => Date.now();

/** The form's field errors from the API's 422 (`email`/`phone` both belong to «Κινητό ή email»). */
export function formErrors(error: unknown): Partial<Record<Field, string>> | null {
  if (!(error instanceof ApiError) || error.status !== 422) return null;
  const errors = (error.payload.errors ?? {}) as Record<string, string[] | string>;
  const first = (key: string) => {
    const value = errors[key];
    return Array.isArray(value) ? value[0] : value;
  };
  const result: Partial<Record<Field, string>> = {};
  if (first("name")) result.name = "required";
  const contact = first("email") ?? first("phone");
  if (contact) result.contact = contact === "email_or_phone" ? "required" : "invalid";
  if (first("message")) result.message = "required";
  if (first("privacy_ack")) result.privacy_ack = "required";
  return result;
}

/**
 * The website's request form (ANR s5 B): a sheet from «Κλείσε δοκιμαστικό»
 * (or «Ρώτησε κάτι»). A request never books a seat: it becomes a lead
 * (ADR-353) and the box answers. Few fields; marketing only with its own,
 * unticked box; a honeypot and the time spent keep bots out.
 */
export function SiteRequestSheet({ slug, kind, privacyHref, onClose }: { slug: string; kind: Kind; privacyHref: string; onClose: () => void }) {
  const t = useTranslations("BoxSite");
  const locale = useLocale();
  const consent = useSiteConsent();
  const ids = useId();
  const [openedAt] = useState(nowMs);
  const [form, setForm] = useState({ name: "", contact: "", preferred: "", message: "", marketing: false, privacy: false, website: "" });
  const [errors, setErrors] = useState<Partial<Record<Field, string>>>({});
  const [failed, setFailed] = useState(false);
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);
  const set = <K extends keyof typeof form>(key: K, value: (typeof form)[K]) => setForm((current) => ({ ...current, [key]: value }));

  async function submit() {
    const local: Partial<Record<Field, string>> = {};
    if (!form.name.trim()) local.name = "required";
    if (!form.contact.trim()) local.contact = "required";
    if (kind === "contact" && !form.message.trim()) local.message = "required";
    if (!form.privacy) local.privacy_ack = "required";
    setErrors(local);
    setFailed(false);
    if (Object.keys(local).length > 0) return;
    setSending(true);
    try {
      await sendSiteForm(slug, kind, {
        name: form.name.trim(),
        ...contactFields(form.contact),
        message: form.message.trim() || undefined,
        preferred_time: form.preferred.trim() || undefined,
        locale,
        marketing_opt_in: form.marketing,
        privacy_ack: true,
        visitor_id: consent.visitorId() ?? undefined,
        attribution: attribution(window.location, document.referrer),
        website: form.website,
        elapsed_ms: nowMs() - openedAt,
      });
      if (consent.marketing()) trackLead();
      setSent(true);
    } catch (error) {
      const fields = formErrors(error);
      if (fields && Object.keys(fields).length > 0) setErrors(fields);
      else setFailed(true);
    } finally {
      setSending(false);
    }
  }

  const field = (name: Field) => ({
    "aria-invalid": errors[name] ? true : undefined,
    "aria-describedby": errors[name] ? `${ids}-${name}-error` : undefined,
  });
  const inputStyle = (name: Field) => ({ background: "var(--bg)", border: `1px solid ${errors[name] ? "var(--danger)" : "var(--border)"}`, color: "var(--text)" });
  const inputClass = "min-h-11 w-full rounded-2xl px-3.5 text-sm";

  if (sent)
    return (
      <Dialog onClose={onClose} title={t(`form.${kind}.sentTitle`)} size="md" testId="site-request-sent">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t(`form.${kind}.sentText`)}</p>
      </Dialog>
    );

  return (
    <Dialog
      onClose={onClose}
      title={t(`form.${kind}.title`)}
      description={t(`form.${kind}.subtitle`)}
      size="md"
      variant="sheet"
      dismissible={!sending}
      testId="site-request-sheet"
      onSubmit={() => void submit()}
      footer={
        <>
          <button type="button" onClick={onClose} className="min-h-11 px-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("form.cancel")}
          </button>
          <button type="submit" disabled={sending} className="min-h-11 rounded-2xl px-5 text-sm font-bold disabled:opacity-60" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {sending ? t("form.sending") : t(`form.${kind}.send`)}
          </button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        {failed ? <ErrorNotice>{t("form.failed")}</ErrorNotice> : null}
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("form.name")}</span>
          <input value={form.name} onChange={(event) => set("name", event.target.value)} autoComplete="name" maxLength={80} className={inputClass} style={inputStyle("name")} {...field("name")} />
          {errors.name ? <FieldError id={`${ids}-name-error`}>{t("form.errors.nameRequired")}</FieldError> : null}
        </label>
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("form.contact")}</span>
          <input value={form.contact} onChange={(event) => set("contact", event.target.value)} autoComplete="email" maxLength={160} className={inputClass} style={inputStyle("contact")} {...field("contact")} />
          {errors.contact ? <FieldError id={`${ids}-contact-error`}>{t(errors.contact === "invalid" ? "form.errors.contactInvalid" : "form.errors.contactRequired")}</FieldError> : null}
        </label>
        {kind === "trial" ? (
          <label className="flex flex-col gap-1.5">
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("form.preferred")}</span>
            <input value={form.preferred} onChange={(event) => set("preferred", event.target.value)} maxLength={120} placeholder={t("form.preferredPlaceholder")} className={inputClass} style={{ background: "var(--bg)", border: "1px solid var(--border)", color: "var(--text)" }} />
          </label>
        ) : (
          <label className="flex flex-col gap-1.5">
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("form.message")}</span>
            <textarea value={form.message} onChange={(event) => set("message", event.target.value)} rows={4} maxLength={2000} className="w-full rounded-2xl px-3.5 py-2.5 text-sm" style={inputStyle("message")} {...field("message")} />
            {errors.message ? <FieldError id={`${ids}-message-error`}>{t("form.errors.messageRequired")}</FieldError> : null}
          </label>
        )}
        {/* Honeypot: people never see it; a bot that fills it is dropped (ADR-353). */}
        <input type="text" name="website" tabIndex={-1} autoComplete="off" aria-hidden="true" value={form.website} onChange={(event) => set("website", event.target.value)} className="absolute -left-[9999px] h-0 w-0 opacity-0" />
        <label className="flex items-start gap-3 text-sm" style={{ color: "var(--text)" }}>
          <input type="checkbox" checked={form.marketing} onChange={(event) => set("marketing", event.target.checked)} className="mt-0.5 h-5 w-5 shrink-0" />
          <span>{t("form.marketing")}</span>
        </label>
        <div className="flex flex-col gap-1.5">
          <label className="flex items-start gap-3 text-sm" style={{ color: "var(--text)" }}>
            <input type="checkbox" checked={form.privacy} onChange={(event) => set("privacy", event.target.checked)} className="mt-0.5 h-5 w-5 shrink-0" {...field("privacy_ack")} />
            <span>
              {t.rich("form.privacy", {
                link: (chunks) => (
                  <Link href={privacyHref} target="_blank" className="font-semibold underline" style={{ color: "var(--primary-strong)" }}>
                    {chunks}
                  </Link>
                ),
              })}
            </span>
          </label>
          {errors.privacy_ack ? <FieldError id={`${ids}-privacy_ack-error`}>{t("form.errors.privacyRequired")}</FieldError> : null}
        </div>
      </div>
    </Dialog>
  );
}
