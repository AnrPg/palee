"use client";

import { useMutation } from "@tanstack/react-query";
import Link from "next/link";
import { useLocale, useTranslations } from "next-intl";
import { useRef, useState } from "react";

import { ENQUIRY_CONSENT_VERSION, sendEnquiry } from "@/api/leads";
import { splitContact, validateEnquiry } from "@/components/admin/leads/lead-model";
import { FieldError, FieldLabel, fieldClass, fieldStyle } from "@/components/admin/leads/leads-ui";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

export const ENQUIRY_INTERESTS = ["trial", "prices", "other"] as const;
type Interest = (typeof ENQUIRY_INTERESTS)[number];

/**
 * «Ενδιαφέρομαι» on the box page for visitors without an account (ADR-345,
 * W2 p6 Γ): name, a phone or an email, what they are interested in, a
 * message, the required yes to being contacted about this request, and a
 * separate, unticked yes to news and offers. Spam and real requests get the
 * same answer; the hidden field and the opening time feed the spam check.
 */
export function LeadEnquiryForm({ slug, boxName, onClose }: { slug: string; boxName: string; onClose: () => void }) {
  const t = useTranslations("LeadEnquiry");
  const ui = useUiTranslations();
  const locale = useLocale();
  const startedAt = useRef(new Date().toISOString());
  const [name, setName] = useState("");
  const [contact, setContact] = useState("");
  const [interests, setInterests] = useState<Interest[]>([]);
  const [message, setMessage] = useState("");
  const [consent, setConsent] = useState(false);
  const [marketing, setMarketing] = useState(false);
  const [website, setWebsite] = useState("");
  const [errors, setErrors] = useState<ReturnType<typeof validateEnquiry>>({});

  const send = useMutation({
    mutationFn: () =>
      sendEnquiry(slug, {
        name: name.trim(),
        ...splitContact(contact),
        ...(message.trim() ? { message: message.trim() } : {}),
        interests,
        locale,
        kind: interests.includes("trial") ? "trial" : "contact",
        source: "form",
        consent: { contact: true, marketing, text_version: ENQUIRY_CONSENT_VERSION },
        website,
        form_started_at: startedAt.current,
      }),
  });

  function submit() {
    const next = validateEnquiry({ name, contact, consent });
    setErrors(next);
    if (Object.keys(next).length === 0) send.mutate();
  }

  if (send.isSuccess) {
    return (
      <Dialog
        onClose={onClose}
        title={t("title")}
        size="md"
        testId="enquiry-dialog"
        footer={
          <DialogButton tone="primary" onClick={onClose}>
            {t("close")}
          </DialogButton>
        }
      >
        <div className="space-y-2 text-center" role="status" data-testid="enquiry-sent">
          <p className="text-lg font-bold" style={{ color: "var(--text)" }}>
            {t("sentTitle")}
          </p>
          <p className="text-sm" style={{ color: "var(--muted)" }}>
            {t("sentBody", { box: boxName })}
          </p>
        </div>
      </Dialog>
    );
  }

  return (
    <Dialog
      onClose={onClose}
      title={t("title")}
      size="md"
      dismissible={!send.isPending}
      testId="enquiry-dialog"
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
      error={send.isError ? localizeError(send.error, ui) : null}
      footer={
        <>
          <DialogButton tone="ghost" onClick={onClose}>
            {t("cancel")}
          </DialogButton>
          <DialogButton tone="primary" type="submit" disabled={send.isPending} testId="enquiry-send">
            {t("send")}
          </DialogButton>
        </>
      }
    >
      <div className="space-y-4">
        <div>
          <FieldLabel htmlFor="enquiry-name" required>
            {t("name")}
          </FieldLabel>
          <input
            id="enquiry-name"
            value={name}
            maxLength={200}
            autoComplete="name"
            onChange={(event) => setName(event.target.value)}
            aria-invalid={Boolean(errors.name)}
            aria-describedby={errors.name ? "enquiry-name-error" : undefined}
            className={fieldClass}
            style={fieldStyle(Boolean(errors.name))}
          />
          <FieldError id="enquiry-name-error">{errors.name ? t("nameRequired") : null}</FieldError>
        </div>
        <div>
          <FieldLabel htmlFor="enquiry-contact" required>
            {t("contact")}
          </FieldLabel>
          <input
            id="enquiry-contact"
            value={contact}
            maxLength={254}
            autoComplete="email"
            onChange={(event) => setContact(event.target.value)}
            aria-invalid={Boolean(errors.contact)}
            aria-describedby={errors.contact ? "enquiry-contact-error" : undefined}
            className={fieldClass}
            style={fieldStyle(Boolean(errors.contact))}
          />
          <FieldError id="enquiry-contact-error">
            {errors.contact === "required" ? t("contactRequired") : errors.contact === "invalid" ? t("contactInvalid") : null}
          </FieldError>
        </div>
        <div>
          <p className="mb-1 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("interest")}
          </p>
          <div className="flex flex-wrap gap-2" role="group" aria-label={t("interest")}>
            {ENQUIRY_INTERESTS.map((value) => {
              const on = interests.includes(value);
              return (
                <button
                  key={value}
                  type="button"
                  aria-pressed={on}
                  onClick={() => setInterests((current) => (on ? current.filter((entry) => entry !== value) : [...current, value]))}
                  className="min-h-10 rounded-xl px-3 text-sm font-semibold"
                  style={
                    on
                      ? { background: "var(--text)", color: "var(--bg)", border: "1px solid var(--text)" }
                      : { background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border)" }
                  }
                >
                  {t(`interestOption.${value}`)}
                </button>
              );
            })}
          </div>
        </div>
        <div>
          <FieldLabel htmlFor="enquiry-message">{t("message")}</FieldLabel>
          <textarea
            id="enquiry-message"
            value={message}
            rows={3}
            maxLength={2000}
            placeholder={t("optional")}
            onChange={(event) => setMessage(event.target.value)}
            className={fieldClass}
            style={fieldStyle(false)}
          />
        </div>

        {/* Spam trap (ADR-345): people never see or fill it. */}
        <div aria-hidden="true" className="absolute -left-[9999px] h-0 w-0 overflow-hidden">
          <input tabIndex={-1} autoComplete="off" value={website} onChange={(event) => setWebsite(event.target.value)} name="website" />
        </div>

        <label className="flex items-start gap-3 rounded-2xl p-3" style={{ background: "var(--panel-muted)", border: errors.consent ? "1px solid var(--danger)" : "1px solid transparent" }}>
          <input
            type="checkbox"
            checked={consent}
            onChange={(event) => {
              setConsent(event.target.checked);
              setErrors((current) => ({ ...current, consent: undefined }));
            }}
            aria-invalid={Boolean(errors.consent)}
            aria-describedby={errors.consent ? "enquiry-consent-error" : undefined}
            className="mt-1 h-4 w-4"
            data-testid="enquiry-consent"
          />
          <span>
            <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
              {t("consentContact")} <span style={{ color: "var(--danger)" }}>*</span>
            </span>
            <span className="block text-xs" style={{ color: "var(--muted)" }}>
              <Link href="/privacy" className="underline">
                {t("privacy")}
              </Link>
            </span>
          </span>
        </label>
        <FieldError id="enquiry-consent-error">{errors.consent ? t("consentRequired") : null}</FieldError>

        <label className="flex items-start gap-3 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }}>
          <input type="checkbox" checked={marketing} onChange={(event) => setMarketing(event.target.checked)} className="mt-1 h-4 w-4" />
          <span>
            <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
              {t("consentMarketing")}
            </span>
            <span className="block text-xs" style={{ color: "var(--muted)" }}>
              {t("consentMarketingHint")}
            </span>
          </span>
        </label>
      </div>
    </Dialog>
  );
}

/** The «Ενδιαφέρομαι» card at the end of the box page's «Σχετικά», for visitors who are not signed in. */
export function EnquiryCard({ slug, boxName }: { slug: string; boxName: string }) {
  const t = useTranslations("LeadEnquiry");
  const { status } = useSession();
  const [open, setOpen] = useState(false);
  if (status === "authenticated") return null;
  return (
    <section className="flex flex-col gap-3 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {t("cardText", { box: boxName })}
      </p>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="min-h-11 rounded-2xl px-4 text-sm font-bold"
        style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        data-testid="enquiry-open"
      >
        {t("title")}
      </button>
      {open ? <LeadEnquiryForm slug={slug} boxName={boxName} onClose={() => setOpen(false)} /> : null}
    </section>
  );
}
