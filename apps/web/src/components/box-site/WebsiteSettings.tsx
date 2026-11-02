"use client";

import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  addSiteDomain,
  checkSiteDomain,
  getSite,
  getSiteSummary,
  makeSiteDomainPrimary,
  removeSiteDomain,
  saveSite,
  sendSiteDomainInstructions,
  type AdminSite,
  type SiteDomain,
  type SiteFaqEntry,
  type SiteSection,
} from "@/api/box-site";
import { useSession } from "@/components/session-provider";
import { AdvancedDisclosure } from "@/components/settings/AdvancedSettings";
import { inputClass, inputStyle, Pill, secondaryButtonClass, secondaryButtonStyle, StatusText } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { useDraftForm } from "@/components/ui/DraftForms";
import { FieldError } from "@/components/ui/ErrorNotice";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { DnsRecords, DomainStatusLine } from "./DomainParts";
import { sectionOn, toggleSection, moveSection } from "./website-settings-model";

const SITE_KEY = ["admin", "site"] as const;
const SUMMARY_KEY = ["admin", "site", "summary"] as const;
const MAX_DOMAINS = 2;
const MAX_FAQ = 12;

type Draft = {
  section_order: SiteSection[];
  hidden_sections: SiteSection[];
  public_schedule: boolean;
  public_wod: boolean;
  forms_enabled: boolean;
  faq: SiteFaqEntry[];
  about_en: string;
  ga4_measurement_id: string;
  gtm_container_id: string;
  meta_pixel_id: string;
  conversions_api_enabled: boolean;
  conversions_api_token: string;
};

function toDraft(settings: AdminSite["settings"]): Draft {
  return {
    section_order: settings.section_order,
    hidden_sections: settings.hidden_sections,
    public_schedule: settings.public_schedule,
    public_wod: settings.public_wod,
    forms_enabled: settings.forms_enabled,
    faq: settings.faq,
    about_en: settings.about_en ?? "",
    ga4_measurement_id: settings.ga4_measurement_id ?? "",
    gtm_container_id: settings.gtm_container_id ?? "",
    meta_pixel_id: settings.meta_pixel_id ?? "",
    conversions_api_enabled: settings.conversions_api_enabled,
    conversions_api_token: "",
  };
}

const blank = (value: string) => (value.trim() ? value.trim() : null);

/**
 * Ρυθμίσεις › Ιστοσελίδα (ANR s1 A, s2 A; ADR-352..354, ADR-388): the
 * sections with a switch each, in the owner's order; the domain card with
 * its steps and records; the tags and the English texts under «Προχωρημένα».
 */
export function WebsiteSettings() {
  const t = useTranslations("BoxSite");
  const ui = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const slug = useOrganizationSlug();
  const site = useQuery({ queryKey: SITE_KEY, enabled: Boolean(token), queryFn: () => getSite(token) });
  const summary = useQuery({ queryKey: SUMMARY_KEY, enabled: Boolean(token), queryFn: () => getSiteSummary(token), retry: false });

  const primary = site.data?.domains.find((domain) => domain.primary && domain.status === "active");
  const openHref = primary ? `https://${primary.host}` : `/b/${slug}`;

  return (
    <main className="min-h-screen px-4 py-8 md:px-10 md:py-10" style={{ background: "var(--bg)" }} data-testid="website-settings">
      <div className="mx-auto flex max-w-3xl flex-col gap-5">
        <header className="flex flex-col gap-2">
          <Link href={adminHref("/admin/settings", slug)} className="text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            ‹ {t("settings.back")}
          </Link>
          <h1 className="text-3xl font-semibold tracking-tight" style={{ color: "var(--text)" }}>{t("settings.title")}</h1>
          <p className="text-sm" style={{ color: "var(--muted)" }}>{t("settings.intro")}</p>
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm">
            <a href={openHref} target="_blank" rel="noreferrer" className="font-bold" style={{ color: "var(--primary-strong)" }} data-testid="website-open">
              {t("settings.open")} ↗
            </a>
            {summary.data ? (
              <span style={{ color: "var(--text-soft)" }} data-testid="website-summary">
                {t("settings.requests", { count: summary.data.submissions.total, days: summary.data.days })}
              </span>
            ) : null}
          </div>
        </header>

        {site.isPending ? <StatusText tone="muted">{t("settings.loading")}</StatusText> : null}
        {site.isError ? <StatusText tone="error">{localizeError(site.error, ui)}</StatusText> : null}
        {site.data ? <SiteForm token={token} site={site.data} /> : null}
        {site.data ? <DomainsCard token={token} domains={site.data.domains} /> : null}
      </div>
    </main>
  );
}

function SiteForm({ token, site }: { token: string; site: AdminSite }) {
  const t = useTranslations("BoxSite");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const settings = site.settings;
  const form = useDraftForm<Draft>({
    server: toDraft(settings),
    testId: "website-save-bar",
    save: async (draft) => {
      const saved = await saveSite(token, {
        lock_version: settings.lock_version,
        section_order: draft.section_order,
        hidden_sections: draft.hidden_sections,
        public_schedule: draft.public_schedule,
        public_wod: draft.public_wod,
        forms_enabled: draft.forms_enabled,
        faq: draft.faq.map((entry) => ({
          question: entry.question.trim(),
          answer: entry.answer.trim(),
          ...(entry.question_en?.trim() ? { question_en: entry.question_en.trim() } : {}),
          ...(entry.answer_en?.trim() ? { answer_en: entry.answer_en.trim() } : {}),
        })),
        about_en: blank(draft.about_en),
        ga4_measurement_id: blank(draft.ga4_measurement_id),
        gtm_container_id: blank(draft.gtm_container_id),
        meta_pixel_id: blank(draft.meta_pixel_id),
        conversions_api_enabled: draft.conversions_api_enabled,
        ...(draft.conversions_api_token.trim() ? { conversions_api_token: draft.conversions_api_token.trim() } : {}),
      });
      queryClient.setQueryData<AdminSite>(SITE_KEY, (current) => (current ? { ...current, settings: saved } : current));
    },
    describeError: (error) => (error instanceof ApiError && error.status === 409 ? t("settings.stale") : localizeError(error, ui)),
  });
  const draft = form.draft;
  const faqErrors = draft.faq.map((entry) => ({ question: !entry.question.trim(), answer: !entry.answer.trim() }));

  return (
    <>
      <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="website-sections">
        <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("settings.sectionsTitle")}</h2>
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("settings.sectionsHint")}</p>
        <ol className="flex flex-col">
          {draft.section_order.map((key, index) => (
            <li key={key} className="flex min-h-12 items-center gap-2 py-1" style={{ borderTop: index === 0 ? undefined : "1px solid var(--border)" }} data-testid={`website-section-${key}`}>
              <span className="flex flex-1 flex-col">
                <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t(`sections.${key}`)}</span>
                {key === "hero" ? <span className="text-xs" style={{ color: "var(--dim)" }}>{t("settings.heroAlways")}</span> : null}
              </span>
              {key !== "hero" ? (
                <>
                  <button
                    type="button"
                    aria-label={t("settings.moveUp", { section: t(`sections.${key}`) })}
                    disabled={index <= 1}
                    onClick={() => form.edit({ section_order: moveSection(draft.section_order, key, -1) })}
                    className="grid h-9 w-9 place-items-center rounded-full disabled:opacity-30"
                    style={{ color: "var(--text-soft)" }}
                  >
                    ↑
                  </button>
                  <button
                    type="button"
                    aria-label={t("settings.moveDown", { section: t(`sections.${key}`) })}
                    disabled={index === draft.section_order.length - 1}
                    onClick={() => form.edit({ section_order: moveSection(draft.section_order, key, 1) })}
                    className="grid h-9 w-9 place-items-center rounded-full disabled:opacity-30"
                    style={{ color: "var(--text-soft)" }}
                  >
                    ↓
                  </button>
                  <input
                    type="checkbox"
                    role="switch"
                    aria-label={t(`sections.${key}`)}
                    checked={sectionOn(draft, key)}
                    disabled={form.saving}
                    onChange={(event) => form.edit(toggleSection(draft, key, event.target.checked))}
                    className="h-5 w-5 shrink-0"
                    style={{ accentColor: "var(--primary)" }}
                  />
                </>
              ) : null}
            </li>
          ))}
        </ol>
      </section>

      {sectionOn(draft, "faq") || draft.faq.length > 0 ? (
        <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="website-faq">
          <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("sections.faq")}</h2>
          {draft.faq.map((entry, index) => (
            <div key={index} className="flex flex-col gap-2 rounded-2xl p-3" style={{ border: "1px solid var(--border)" }}>
              <label className="flex flex-col gap-1">
                <span className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("settings.question")}</span>
                <input
                  value={entry.question}
                  maxLength={200}
                  onChange={(event) => form.edit({ faq: draft.faq.map((item, i) => (i === index ? { ...item, question: event.target.value } : item)) })}
                  aria-invalid={faqErrors[index]!.question || undefined}
                  className={inputClass}
                  style={{ ...inputStyle, ...(faqErrors[index]!.question ? { borderColor: "var(--danger)" } : {}) }}
                />
                {faqErrors[index]!.question ? <FieldError id={`faq-${index}-q`}>{t("settings.required")}</FieldError> : null}
              </label>
              <label className="flex flex-col gap-1">
                <span className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("settings.answer")}</span>
                <textarea
                  value={entry.answer}
                  maxLength={1000}
                  rows={3}
                  onChange={(event) => form.edit({ faq: draft.faq.map((item, i) => (i === index ? { ...item, answer: event.target.value } : item)) })}
                  aria-invalid={faqErrors[index]!.answer || undefined}
                  className={inputClass}
                  style={{ ...inputStyle, ...(faqErrors[index]!.answer ? { borderColor: "var(--danger)" } : {}) }}
                />
                {faqErrors[index]!.answer ? <FieldError id={`faq-${index}-a`}>{t("settings.required")}</FieldError> : null}
              </label>
              <button type="button" onClick={() => form.edit({ faq: draft.faq.filter((_, i) => i !== index) })} className="self-end text-sm font-semibold" style={{ color: "var(--danger)" }}>
                {t("settings.removeQuestion")}
              </button>
            </div>
          ))}
          {draft.faq.length < MAX_FAQ ? (
            <button type="button" onClick={() => form.edit({ faq: [...draft.faq, { question: "", answer: "" }] })} className={`${secondaryButtonClass} self-start`} style={secondaryButtonStyle} data-testid="website-faq-add">
              {t("settings.addQuestion")}
            </button>
          ) : null}
        </section>
      ) : null}

      <AdvancedDisclosure testId="website-advanced">
        <div className="flex flex-col gap-2">
          <h3 className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("settings.englishTitle")}</h3>
          <p className="text-xs" style={{ color: "var(--muted)" }}>{t("settings.englishHint")}</p>
          <label className="flex flex-col gap-1">
            <span className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("settings.aboutEn")}</span>
            <textarea value={draft.about_en} maxLength={4000} rows={4} onChange={(event) => form.edit({ about_en: event.target.value })} className={inputClass} style={inputStyle} data-testid="website-about-en" />
          </label>
          {draft.faq.map((entry, index) => (
            <div key={index} className="grid gap-1 sm:grid-cols-2">
              <input
                value={entry.question_en ?? ""}
                maxLength={200}
                placeholder={entry.question || t("settings.question")}
                aria-label={t("settings.questionEn", { number: index + 1 })}
                onChange={(event) => form.edit({ faq: draft.faq.map((item, i) => (i === index ? { ...item, question_en: event.target.value } : item)) })}
                className={inputClass}
                style={inputStyle}
              />
              <input
                value={entry.answer_en ?? ""}
                maxLength={1000}
                placeholder={entry.answer || t("settings.answer")}
                aria-label={t("settings.answerEn", { number: index + 1 })}
                onChange={(event) => form.edit({ faq: draft.faq.map((item, i) => (i === index ? { ...item, answer_en: event.target.value } : item)) })}
                className={inputClass}
                style={inputStyle}
              />
            </div>
          ))}
        </div>
        <div className="flex flex-col gap-2">
          <h3 className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("settings.tagsTitle")}</h3>
          <p className="text-xs" style={{ color: "var(--muted)" }}>{t("settings.tagsHint")}</p>
          <TagField label="Google Analytics 4" placeholder="G-XXXXXXX" value={draft.ga4_measurement_id} onChange={(value) => form.edit({ ga4_measurement_id: value })} />
          <TagField label="Google Tag Manager" placeholder="GTM-XXXXXX" value={draft.gtm_container_id} onChange={(value) => form.edit({ gtm_container_id: value })} />
          <TagField label="Meta Pixel" placeholder="1234567890" value={draft.meta_pixel_id} onChange={(value) => form.edit({ meta_pixel_id: value })} />
        </div>
        <div className="flex flex-col gap-2">
          <label className="flex min-h-11 items-center justify-between gap-3">
            <span className="flex flex-col">
              <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("settings.capi")}</span>
              <span className="text-xs" style={{ color: "var(--dim)" }}>{t("settings.capiHint")}</span>
            </span>
            <input type="checkbox" role="switch" checked={draft.conversions_api_enabled} onChange={(event) => form.edit({ conversions_api_enabled: event.target.checked })} className="h-5 w-5 shrink-0" style={{ accentColor: "var(--primary)" }} />
          </label>
          {draft.conversions_api_enabled ? (
            <label className="flex flex-col gap-1">
              <span className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{settings.has_conversions_api_token ? t("settings.capiTokenSaved") : t("settings.capiToken")}</span>
              <input type="password" autoComplete="off" value={draft.conversions_api_token} onChange={(event) => form.edit({ conversions_api_token: event.target.value })} className={inputClass} style={inputStyle} />
            </label>
          ) : null}
        </div>
      </AdvancedDisclosure>
      {form.bar}
    </>
  );
}

function TagField({ label, placeholder, value, onChange }: { label: string; placeholder: string; value: string; onChange: (value: string) => void }) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{label}</span>
      <input value={value} placeholder={placeholder} maxLength={40} onChange={(event) => onChange(event.target.value)} className={inputClass} style={inputStyle} />
    </label>
  );
}

function DomainsCard({ token, domains }: { token: string; domains: SiteDomain[] }) {
  const t = useTranslations("BoxSite");
  const ui = useUiTranslations();
  const queryClient = useQueryClient();
  const [host, setHost] = useState("");
  const [instructionsFor, setInstructionsFor] = useState<SiteDomain | null>(null);
  const refresh = () => queryClient.invalidateQueries({ queryKey: SITE_KEY });
  const add = useMutation({
    mutationFn: () => addSiteDomain(token, host.trim().toLowerCase()),
    onSuccess: () => {
      setHost("");
      void refresh();
    },
  });
  const addError = add.error instanceof ApiError && add.error.status === 422 ? t("domains.invalidHost") : add.error ? localizeError(add.error, ui) : null;

  return (
    <section className="flex flex-col gap-4 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="website-domains">
      <div className="flex flex-col gap-1">
        <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("domains.title")}</h2>
        <p className="text-sm" style={{ color: "var(--muted)" }}>{t("domains.hint")}</p>
      </div>
      {domains.map((domain) => (
        <DomainCard key={domain.id} token={token} domain={domain} onChanged={refresh} onInstructions={() => setInstructionsFor(domain)} />
      ))}
      {domains.length < MAX_DOMAINS ? (
        <form
          className="flex flex-col gap-1.5"
          onSubmit={(event) => {
            event.preventDefault();
            if (host.trim()) add.mutate();
          }}
        >
          <label htmlFor="website-domain-host" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {domains.length === 0 ? t("domains.add") : t("domains.addSecond")}
          </label>
          <div className="flex gap-2">
            <input
              id="website-domain-host"
              value={host}
              onChange={(event) => setHost(event.target.value)}
              placeholder="www.mybox.gr"
              inputMode="url"
              autoCapitalize="none"
              aria-invalid={addError ? true : undefined}
              aria-describedby={addError ? "website-domain-host-error" : undefined}
              className={inputClass}
              style={{ ...inputStyle, ...(addError ? { borderColor: "var(--danger)" } : {}) }}
              data-testid="website-domain-input"
            />
            <button type="submit" disabled={add.isPending || !host.trim()} className={`${secondaryButtonClass} shrink-0`} style={secondaryButtonStyle}>
              {t("domains.addButton")}
            </button>
          </div>
          {addError ? <FieldError id="website-domain-host-error">{addError}</FieldError> : null}
        </form>
      ) : null}
      {instructionsFor ? <InstructionsDialog token={token} domain={instructionsFor} onClose={() => setInstructionsFor(null)} /> : null}
    </section>
  );
}

function DomainCard({ token, domain, onChanged, onInstructions }: { token: string; domain: SiteDomain; onChanged: () => void; onInstructions: () => void }) {
  const t = useTranslations("BoxSite");
  const ui = useUiTranslations();
  const check = useMutation({ mutationFn: () => checkSiteDomain(token, domain.id), onSuccess: onChanged });
  const primary = useMutation({ mutationFn: () => makeSiteDomainPrimary(token, domain.id), onSuccess: onChanged });
  const remove = useMutation({ mutationFn: () => removeSiteDomain(token, domain.id), onSuccess: onChanged });
  const failure = check.error ?? primary.error ?? remove.error;
  const active = domain.status === "active";
  return (
    <article className="flex flex-col gap-3 rounded-2xl p-4" style={{ border: "1px solid var(--border)" }} data-testid="website-domain">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="flex items-center gap-2">
          <b className="break-all text-base" style={{ color: "var(--text)" }}>{domain.host}</b>
          {domain.primary ? <Pill tone="primary">{t("domains.primary")}</Pill> : null}
        </span>
        <span className="flex items-center gap-1">
          {!active ? (
            <button type="button" onClick={onInstructions} className="min-h-9 px-2 text-sm font-bold" style={{ color: "var(--primary-strong)" }} data-testid="website-domain-instructions">
              {t("domains.sendInstructions")}
            </button>
          ) : null}
          <MoreMenu
            label={t("domains.more", { host: domain.host })}
            items={[
              ...(!domain.primary && active ? [{ label: t("domains.makePrimary"), onSelect: () => primary.mutate() }] : []),
              ...(active ? [{ label: t("domains.sendInstructions"), onSelect: onInstructions }] : []),
              { label: t("domains.remove"), tone: "danger" as const, onSelect: () => remove.mutate(), testId: "website-domain-remove" },
            ]}
          />
        </span>
      </div>
      <DomainStatusLine status={domain.status} lastError={domain.last_error} />
      {!active ? <DnsRecords records={domain.dns_records} /> : null}
      {!active ? (
        <button type="button" onClick={() => check.mutate()} disabled={check.isPending} className={`${secondaryButtonClass} self-start`} style={secondaryButtonStyle} data-testid="website-domain-check">
          {check.isPending ? t("domains.checking") : t("domains.checkNow")}
        </button>
      ) : null}
      {failure ? <StatusText tone="error">{localizeError(failure, ui)}</StatusText> : null}
    </article>
  );
}

function InstructionsDialog({ token, domain, onClose }: { token: string; domain: SiteDomain; onClose: () => void }) {
  const t = useTranslations("BoxSite");
  const ui = useUiTranslations();
  const [email, setEmail] = useState("");
  const [invalid, setInvalid] = useState(false);
  const send = useMutation({ mutationFn: () => sendSiteDomainInstructions(token, domain.id, email.trim()) });
  const fieldError = invalid || (send.error instanceof ApiError && send.error.status === 422);

  if (send.isSuccess)
    return (
      <Dialog onClose={onClose} title={t("domains.instructionsSent")} size="sm" testId="website-instructions-sent">
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("domains.instructionsSentText", { email: send.data })}</p>
      </Dialog>
    );

  return (
    <Dialog
      onClose={onClose}
      title={t("domains.sendInstructions")}
      description={t("domains.instructionsHint", { host: domain.host })}
      size="sm"
      testId="website-instructions"
      dismissible={!send.isPending}
      onSubmit={() => {
        const ok = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim());
        setInvalid(!ok);
        if (ok) send.mutate();
      }}
      footer={
        <>
          <button type="button" onClick={onClose} className="min-h-11 px-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("form.cancel")}
          </button>
          <button type="submit" disabled={send.isPending} className="min-h-11 rounded-2xl px-5 text-sm font-bold disabled:opacity-60" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
            {t("domains.send")}
          </button>
        </>
      }
    >
      <label className="flex flex-col gap-1.5">
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("domains.instructionsEmail")}</span>
        <input
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          autoComplete="email"
          aria-invalid={fieldError || undefined}
          aria-describedby={fieldError ? "website-instructions-email-error" : undefined}
          className={inputClass}
          style={{ ...inputStyle, ...(fieldError ? { borderColor: "var(--danger)" } : {}) }}
        />
        {fieldError ? <FieldError id="website-instructions-email-error">{t("domains.invalidEmail")}</FieldError> : null}
        {send.error && !fieldError ? <StatusText tone="error">{localizeError(send.error, ui)}</StatusText> : null}
      </label>
    </Dialog>
  );
}

/** Ρυθμίσεις › «Ιστοσελίδα» entry. */
export function WebsiteSettingsLink() {
  const t = useTranslations("BoxSite");
  const slug = useOrganizationSlug();
  return <SettingsEntry href={adminHref("/admin/settings/website", slug)} title={t("settings.title")} hint={t("settings.navHint")} testId="website-settings-link" />;
}

export function SettingsEntry({ href, title, hint, testId }: { href: string; title: string; hint: string; testId: string }) {
  return (
    <Link href={href} data-testid={testId} className="flex items-center justify-between gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}>
      <span className="flex flex-col">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{title}</span>
        <span className="text-sm" style={{ color: "var(--muted)" }}>{hint}</span>
      </span>
      <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
    </Link>
  );
}
