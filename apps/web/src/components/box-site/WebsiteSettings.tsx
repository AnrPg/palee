"use client";

import Link from "next/link";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  addSiteDomain,
  checkSiteDomain,
  dismissSiteNotice,
  getSite,
  getSiteSummary,
  makeSiteDomainPrimary,
  removeSiteDomain,
  saveSite,
  sendSiteDomainInstructions,
  type AdminSite,
  type SiteDomain,
  type SiteFaqEntry,
} from "@/api/box-site";
import { useSession } from "@/components/session-provider";
import { AdvancedDisclosure } from "@/components/settings/AdvancedSettings";
import { inputClass, inputStyle, Pill, secondaryButtonClass, secondaryButtonStyle, StatusText } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { DraftFormsProvider, PageSaveBar, useDraftForm, useDraftForms } from "@/components/ui/DraftForms";
import { FieldError } from "@/components/ui/ErrorNotice";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { DnsRecords, DomainStatusLine, isSystemHost } from "./DomainParts";
import { SiteLanguagesCard } from "./SiteLanguagesCard";
import { publishedLook, type LooseSiteSettings } from "./website-draft-model";
import { cardClass, cardStyle, LookCard, NoticeBanner, SectionsCard, SeoCard } from "./WebsiteLook";
import { PREVIEW_KEY, PreviewSheet, PublishBar, SITE_KEY, SitePreview, useSiteDraft, useWideLayout } from "./WebsitePublish";
import { CONVERSIONS_API_LABEL, DOMAIN_PLACEHOLDER, sectionOn, TAG_FIELDS } from "./website-settings-model";
import { BackLink } from "@/components/ui/BackLink";

const SUMMARY_KEY = ["admin", "site", "summary"] as const;
const MAX_DOMAINS = 2;
const MAX_FAQ = 12;

/** The fields that save at once with the save bar; the look and the switches are a draft to publish (ADR-530). */
type Draft = {
  faq: SiteFaqEntry[];
  translation_locales: string[];
  visible_locales: string[];
  ga4_measurement_id: string;
  gtm_container_id: string;
  meta_pixel_id: string;
  conversions_api_enabled: boolean;
  conversions_api_token: string;
};

function toDraft(settings: AdminSite["settings"]): Draft {
  return {
    faq: settings.faq,
    translation_locales: settings.translation_locales,
    visible_locales: settings.visible_locales,
    ga4_measurement_id: settings.ga4_measurement_id ?? "",
    gtm_container_id: settings.gtm_container_id ?? "",
    meta_pixel_id: settings.meta_pixel_id ?? "",
    conversions_api_enabled: settings.conversions_api_enabled,
    conversions_api_token: "",
  };
}

const blank = (value: string) => (value.trim() ? value.trim() : null);

/**
 * Ρυθμίσεις › Ιστοσελίδα (ANR s1 A, s2 A; ADR-352..354, ADR-388, ADR-530):
 * «Εμφάνιση» (template, colours, light or dark, motion) and «Τι δείχνει η
 * ιστοσελίδα» (a switch per section, no order) are a draft until
 * «Δημοσίευση», with a live preview beside them; «Γλώσσες ιστοσελίδας»
 * (ADR-520) with each translation's progress and the way to «Μεταφράσεις»;
 * the domain card with its steps and records; the tags under «Προχωρημένα».
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
      <div className="mx-auto flex max-w-3xl flex-col gap-5 min-[1100px]:max-w-[90rem]">
        <header className="flex flex-col gap-2">
          <BackLink href={adminHref("/admin/settings", slug)} className="self-start text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("settings.back")}
          </BackLink>
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
        {site.data ? <SiteEditor token={token} slug={slug ?? ""} site={site.data} /> : null}
      </div>
    </main>
  );
}

function SiteEditor({ token, slug, site }: { token: string; slug: string; site: AdminSite }) {
  const queryClient = useQueryClient();
  const settings = site.settings as LooseSiteSettings;
  const draft = useSiteDraft(token, settings);
  const forms = useDraftForms();
  const wide = useWideLayout();
  const [sheet, setSheet] = useState(false);
  const notice = useMutation({
    mutationFn: () => dismissSiteNotice(token),
    onSuccess: (data) => queryClient.setQueryData<AdminSite>(SITE_KEY, (current) => (current ? { ...current, settings: data.settings } : current)),
  });
  const look = draft.effective;
  const preview = <SitePreview token={token} slug={slug} look={{ template: look.template, palette: look.palette, appearance: look.appearance, calm_motion: look.calm_motion }} />;

  return (
    <div className="grid items-start gap-5 min-[1100px]:grid-cols-[minmax(0,46rem)_minmax(0,1fr)]">
      <div className="flex min-w-0 flex-col gap-5">
        {settings.template_notice && !notice.isPending && !notice.isSuccess ? (
          <NoticeBanner template={publishedLook(settings).template} onClose={() => notice.mutate()} />
        ) : null}
        <LookCard look={look} onChange={draft.change} />
        <SectionsCard state={look} onChange={draft.change} />
        <SeoCard hasDomain={site.domains.some((domain) => domain.status === "active")} />
        <DraftFormsProvider value={forms.context}>
          <SiteForm token={token} site={site} faqOn={sectionOn(look, "faq")} />
        </DraftFormsProvider>
        <DomainsCard token={token} domains={site.domains} />
        <div className="sticky z-(--z-sticky) flex flex-col gap-2" style={{ bottom: "calc(var(--bottom-float-inset) + 0.75rem)" }}>
          <PageSaveBar bar={forms.bar} testId="website-save-bar" />
          <PublishBar token={token} draft={draft} onPreview={wide ? undefined : () => setSheet(true)} />
        </div>
      </div>
      {wide ? (
        <aside className="sticky" style={{ top: "calc(var(--top-bar-space) + 1rem)" }}>
          <div className={cardClass} style={cardStyle}>{preview}</div>
        </aside>
      ) : null}
      {sheet && !wide ? <PreviewSheet onClose={() => setSheet(false)}>{preview}</PreviewSheet> : null}
    </div>
  );
}

/** FAQ, languages and tags: they save at once with the save bar, as before. */
function SiteForm({ token, site, faqOn }: { token: string; site: AdminSite; faqOn: boolean }) {
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
        // The id keeps an entry's translations with it (ADR-520).
        faq: draft.faq.map((entry) => ({ ...(entry.id ? { id: entry.id } : {}), question: entry.question.trim(), answer: entry.answer.trim() })),
        translation_locales: draft.translation_locales,
        visible_locales: draft.visible_locales,
        ga4_measurement_id: blank(draft.ga4_measurement_id),
        gtm_container_id: blank(draft.gtm_container_id),
        meta_pixel_id: blank(draft.meta_pixel_id),
        conversions_api_enabled: draft.conversions_api_enabled,
        ...(draft.conversions_api_token.trim() ? { conversions_api_token: draft.conversions_api_token.trim() } : {}),
      });
      queryClient.setQueryData<AdminSite>(SITE_KEY, (current) => (current ? { ...current, settings: saved.settings, languages: saved.languages } : current));
    },
    onSaved: () => queryClient.invalidateQueries({ queryKey: PREVIEW_KEY }),
    describeError: (error) => (error instanceof ApiError && error.status === 409 ? t("settings.stale") : localizeError(error, ui)),
  });
  const draft = form.draft;
  const faqErrors = draft.faq.map((entry) => ({ question: !entry.question.trim(), answer: !entry.answer.trim() }));

  return (
    <>
      <SiteLanguagesCard
        languages={site.languages}
        value={{ translation_locales: draft.translation_locales, visible_locales: draft.visible_locales }}
        onChange={(next) => form.edit(next)}
        disabled={form.saving}
      />

      {faqOn || draft.faq.length > 0 ? (
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
          <h3 className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("settings.tagsTitle")}</h3>
          <p className="text-xs" style={{ color: "var(--muted)" }}>{t("settings.tagsHint")}</p>
          {TAG_FIELDS.map((field) => (
            <TagField key={field.key} label={field.label} placeholder={field.placeholder} value={draft[field.key]} onChange={(value) => form.edit({ [field.key]: value })} />
          ))}
        </div>
        <div className="flex flex-col gap-2">
          <label className="flex min-h-11 items-center justify-between gap-3">
            <span className="flex flex-col">
              <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{CONVERSIONS_API_LABEL}</span>
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
  const [systemHost, setSystemHost] = useState(false);
  const [instructionsFor, setInstructionsFor] = useState<SiteDomain | null>(null);
  const refresh = () => queryClient.invalidateQueries({ queryKey: SITE_KEY });
  const add = useMutation({
    mutationFn: () => addSiteDomain(token, host.trim().toLowerCase()),
    onSuccess: () => {
      setHost("");
      void refresh();
    },
  });
  // ADR-398: a system domain is refused before it is sent, never left for the cluster to refuse.
  const addError = systemHost
    ? t("domains.platformHost")
    : add.error instanceof ApiError && add.error.status === 422
      ? t(add.error.payload?.code === "platform_hostname" ? "domains.platformHost" : "domains.invalidHost")
      : add.error
        ? localizeError(add.error, ui)
        : null;

  return (
    <section id="website-domains" className="flex scroll-mt-24 flex-col gap-4 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="website-domains">
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
            if (!host.trim()) return;
            if (isSystemHost(host)) {
              add.reset();
              setSystemHost(true);
              return;
            }
            add.mutate();
          }}
        >
          <label htmlFor="website-domain-host" className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {domains.length === 0 ? t("domains.add") : t("domains.addSecond")}
          </label>
          <div className="flex gap-2">
            <input
              id="website-domain-host"
              value={host}
              onChange={(event) => {
                setHost(event.target.value);
                setSystemHost(false);
              }}
              placeholder={DOMAIN_PLACEHOLDER}
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
      <DomainStatusLine status={domain.status} lastError={domain.last_error} certificateStatus={domain.certificate_status} certificateError={domain.certificate_error} />
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
