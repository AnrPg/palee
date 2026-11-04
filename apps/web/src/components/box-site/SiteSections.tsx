"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import type { ReactNode } from "react";

import type { PublicSite, SiteSection } from "@/api/box-site";
import { fetchPublicPackages, publicPackagesKey } from "@/api/my-payments";
import type { PublicBoxPage } from "@/api/social";
import { AboutTab, type AboutPart } from "@/components/box-page/AboutTab";
import { GoogleReviews, ReviewItem, ReviewSummary } from "@/components/reviews/ReviewParts";
import { timetableByDay, type SiteLanguage } from "@/lib/public-site";
import { siteTextFor } from "@/lib/site-translations";
import { FRESHNESS } from "@/lib/query-policy";
import { formatCents } from "@/lib/solo-coach";

import { useSiteConsent } from "./SiteConsent";
import { SiteProgrammesSection } from "./SiteProgrammes";

const ABOUT_PARTS: Partial<Record<SiteSection, AboutPart>> = { about: "about", coaches: "coaches", location: "location" };

/**
 * The box's website (ANR s3 A, ADR-388): one page, the sections the owner
 * switched on, in the owner's order. «Ωρολόγιο» shows only with the owner's
 * switch (off by default); «WOD της ημέρας» likewise. A request never books
 * a seat: the trial and contact cards open the request sheet.
 */
export function SiteSections({
  page,
  site,
  language,
  basePath,
  onOpenPhoto,
  onRequest,
}: {
  page: PublicBoxPage;
  site: PublicSite;
  language: SiteLanguage;
  basePath: string;
  onOpenPhoto: (index: number) => void;
  onRequest: (kind: "trial" | "contact") => void;
}) {
  const t = useTranslations("BoxSite");
  const consent = useSiteConsent();

  const render = (key: SiteSection): ReactNode => {
    const part = ABOUT_PARTS[key];
    if (part) {
      return <AboutTab key={key} page={page} onOpenPhoto={onOpenPhoto} parts={[part]} enquiry={false} />;
    }
    switch (key) {
      case "schedule":
        return <TimetableSection key={key} site={site} />;
      case "events":
        return <EventsSection key={key} site={site} />;
      case "wod":
        return <WodSection key={key} site={site} />;
      case "packages":
        return <PackagesSection key={key} site={site} basePath={basePath} />;
      case "programmes":
        return <SiteProgrammesSection key={key} site={site} />;
      case "reviews":
        return <ReviewsSection key={key} site={site} boxName={page.box.name} />;
      case "faq":
        return <FaqSection key={key} site={site} />;
      case "trial_form":
        return site.forms.trial ? (
          <RequestCard key={key} title={t("sections.trial_form")} text={t("trialCardText")} action={t("bookTrial")} onClick={() => onRequest("trial")} testId="site-trial-card" />
        ) : null;
      case "contact_form":
        return site.forms.contact ? (
          <RequestCard key={key} title={t("sections.contact_form")} text={t("contactCardText")} action={t("askSomething")} onClick={() => onRequest("contact")} testId="site-contact-card" />
        ) : null;
      default:
        // «hero» is the page's own header (cover, logo, name).
        return null;
    }
  };

  return (
    <div className="flex flex-col gap-9" data-testid="site-sections">
      {site.sections.map((key) => render(key))}
      <footer className="flex flex-wrap gap-x-5 gap-y-2 pt-4 text-sm" style={{ borderTop: "1px solid var(--border)", color: "var(--text-soft)" }}>
        <Link href={`${basePath}/privacy${language === "box" ? "" : `?lang=${encodeURIComponent(language)}`}`} className="font-semibold">
          {t("privacy")}
        </Link>
        {site.tracking.consent_required ? (
          <button type="button" onClick={consent.open} className="font-semibold">
            {t("cookies")}
          </button>
        ) : null}
        {site.report_contact ? (
          <a href={`mailto:${site.report_contact}`} data-testid="site-report-contact">
            {t("reportContact", { email: site.report_contact })}
          </a>
        ) : null}
        <span style={{ color: "var(--dim)" }}>{t("poweredBy")}</span>
      </footer>
    </div>
  );
}

function SectionTitle({ children }: { children: ReactNode }) {
  return (
    <h2 className="text-lg font-extrabold" style={{ color: "var(--text)" }}>
      {children}
    </h2>
  );
}

function TimetableSection({ site }: { site: PublicSite }) {
  const t = useTranslations("BoxSite");
  const locale = useLocale();
  const days = timetableByDay(site.timetable, site.time_zone, locale);
  if (days.length === 0) return null;
  return (
    <section className="flex flex-col gap-3" data-testid="site-schedule">
      <SectionTitle>{t("sections.schedule")}</SectionTitle>
      <div className="flex flex-col gap-4">
        {days.map((day) => (
          <div key={day.day} className="flex flex-col gap-1.5">
            <h3 className="text-sm font-bold capitalize" style={{ color: "var(--text-soft)" }}>{day.label}</h3>
            <ul className="flex flex-col">
              {day.classes.map((entry) => (
                <li key={entry.id} className="flex items-center gap-3 py-1.5 text-sm" style={{ borderBottom: "1px solid var(--border)" }}>
                  <span className="w-12 font-bold tabular-nums" style={{ color: "var(--text)" }}>{entry.time}</span>
                  <span style={{ color: "var(--text)" }}>{entry.name}</span>
                  <span className="ms-auto text-xs" style={{ color: "var(--dim)" }}>{t("minutes", { count: entry.minutes })}</span>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </section>
  );
}

function EventsSection({ site }: { site: PublicSite }) {
  const t = useTranslations("BoxSite");
  const locale = useLocale();
  if (site.events.length === 0) return null;
  return (
    <section className="flex flex-col gap-3" data-testid="site-events">
      <SectionTitle>{t("sections.events")}</SectionTitle>
      <ul className="grid gap-3 sm:grid-cols-2">
        {site.events.map((event) => {
          const zone = event.time_zone ?? site.time_zone;
          const when = new Intl.DateTimeFormat(locale, { timeZone: zone, weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(new Date(event.starts_at));
          return (
            <li key={event.id}>
              <Link href={`/events/${event.id}`} className="flex flex-col gap-1 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
                <b className="text-sm" style={{ color: "var(--text)" }}>{event.title}</b>
                <span className="text-sm" style={{ color: "var(--text-soft)" }}>
                  {when}
                  {event.place_name ? ` · ${event.place_name}` : ""}
                </span>
                <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                  {event.price_cents > 0 ? formatCents(event.price_cents, event.currency, locale) : t("free")}
                </span>
              </Link>
            </li>
          );
        })}
      </ul>
    </section>
  );
}

function WodSection({ site }: { site: PublicSite }) {
  const t = useTranslations("BoxSite");
  if (site.wod.length === 0) return null;
  return (
    <section className="flex flex-col gap-3" data-testid="site-wod">
      <SectionTitle>{t("sections.wod")}</SectionTitle>
      <div className="flex flex-col gap-3">
        {site.wod.map((workout) => (
          <article key={workout.id} className="flex flex-col gap-1.5 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <b className="text-sm" style={{ color: "var(--text)" }}>{workout.title}</b>
            {workout.body ? <p className="whitespace-pre-line font-mono text-sm" style={{ color: "var(--text)" }}>{workout.body}</p> : null}
          </article>
        ))}
      </div>
    </section>
  );
}

function PackagesSection({ site, basePath }: { site: PublicSite; basePath: string }) {
  const slug = site.slug;
  const t = useTranslations("BoxSite");
  const locale = useLocale();
  const query = useQuery({ queryKey: publicPackagesKey(slug), queryFn: () => fetchPublicPackages(slug), staleTime: FRESHNESS.reference, retry: false });
  const packages = query.data?.packages.slice(0, 4) ?? [];
  if (packages.length === 0) return null;
  return (
    <section className="flex flex-col gap-3" data-testid="site-packages">
      <SectionTitle>{t("sections.packages")}</SectionTitle>
      <ul className="grid gap-3 sm:grid-cols-2">
        {packages.map((item) => (
          <li key={item.id} className="flex flex-col gap-1 rounded-2xl p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <b className="text-sm" style={{ color: "var(--text)" }}>{siteTextFor(site.texts, "package", item.id, "name", item.name)}</b>
            <span className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{formatCents(item.base_price_cents, item.currency, locale)}</span>
            {item.description ? (
              <span className="line-clamp-2 text-sm" style={{ color: "var(--text-soft)" }}>
                {siteTextFor(site.texts, "package", item.id, "description", item.description)}
              </span>
            ) : null}
          </li>
        ))}
      </ul>
      <Link href={`${basePath || ""}/packages`} className="self-start text-sm font-bold" style={{ color: "var(--primary-strong)" }}>
        {t("allPackages")} ›
      </Link>
    </section>
  );
}

function ReviewsSection({ site, boxName }: { site: PublicSite; boxName: string }) {
  const t = useTranslations("BoxSite");
  const palee = site.reviews.palee;
  const google = site.reviews.google;
  const hasPalee = Boolean(palee && palee.count > 0);
  if (!hasPalee && !google) return null;
  return (
    <section className="flex flex-col gap-4" data-testid="site-reviews">
      <SectionTitle>{t("sections.reviews")}</SectionTitle>
      {palee && hasPalee ? (
        <div className="flex flex-col gap-3">
          <ReviewSummary average={palee.average} count={palee.count} testId="site-reviews-average" />
          <ul className="flex flex-col gap-3">
            {palee.latest.map((review) => (
              <ReviewItem key={review.id} review={review} boxName={boxName} />
            ))}
          </ul>
        </div>
      ) : null}
      {google ? <GoogleReviews google={google} /> : null}
    </section>
  );
}

function FaqSection({ site }: { site: PublicSite }) {
  const t = useTranslations("BoxSite");
  // ADR-520: the API answers the FAQ already in the page's language.
  const entries = site.faq;
  if (entries.length === 0) return null;
  return (
    <section className="flex flex-col gap-3" data-testid="site-faq">
      <SectionTitle>{t("sections.faq")}</SectionTitle>
      <div className="flex flex-col gap-2">
        {entries.map((entry, index) => (
          <details key={index} className="rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
            <summary className="cursor-pointer text-sm font-bold" style={{ color: "var(--text)" }}>{entry.question}</summary>
            <p className="mt-2 whitespace-pre-line text-sm" style={{ color: "var(--text-soft)" }}>{entry.answer}</p>
          </details>
        ))}
      </div>
    </section>
  );
}

function RequestCard({ title, text, action, onClick, testId }: { title: string; text: string; action: string; onClick: () => void; testId: string }) {
  // Outlined on purpose: the sticky bar's «Κλείσε δοκιμαστικό» is the page's one filled button.
  return (
    <section className="flex flex-col gap-3 rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid={testId}>
      <SectionTitle>{title}</SectionTitle>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{text}</p>
      <button type="button" onClick={onClick} className="min-h-11 self-start rounded-2xl px-5 text-sm font-bold" style={{ border: "1px solid var(--primary)", color: "var(--primary-strong)" }}>
        {action}
      </button>
    </section>
  );
}
