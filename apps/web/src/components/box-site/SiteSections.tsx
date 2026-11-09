"use client";

import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { useLocale, useTranslations } from "next-intl";
import { useId, useState, useSyncExternalStore, type ReactNode } from "react";

import type { PublicSite, SiteSection } from "@/api/box-site";
import { fetchPublicPackages, publicPackagesKey } from "@/api/my-payments";
import type { PublicBoxPage } from "@/api/social";
import { ABOUT_GROUP, AboutTab, type AboutPart } from "@/components/box-page/AboutTab";
import { BoxBento, type BentoItem } from "@/components/box-page/BoxBento";
import { GoogleReviews, ReviewItem, ReviewSummary } from "@/components/reviews/ReviewParts";
import { nextSlotAt, timetableByDay, type SiteLanguage } from "@/lib/public-site";
import { siteTextFor } from "@/lib/site-translations";
import { FRESHNESS } from "@/lib/query-policy";
import { formatCents } from "@/lib/solo-coach";

import { useSiteConsent } from "./SiteConsent";
import { SiteProgrammesSection } from "./SiteProgrammes";

const ABOUT_PARTS: Partial<Record<SiteSection, AboutPart>> = { coaches: "coaches", location: "location" };
/** Desktop (ANR 2026-11-09): these sit in the narrow right column; the rest are wide. */
const NARROW = new Set<string>(["coaches", "location", "trial_form", "contact_form", "photos", "facts"]);

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
  aside = null,
}: {
  page: PublicBoxPage;
  site: PublicSite;
  language: SiteLanguage;
  basePath: string;
  onOpenPhoto: (index: number) => void;
  onRequest: (kind: "trial" | "contact") => void;
  /** Desktop: the card on top of the right column (map, address, hours). */
  aside?: ReactNode;
}) {
  const t = useTranslations("BoxSite");
  const consent = useSiteConsent();

  const render = (key: SiteSection): ReactNode => {
    const part = ABOUT_PARTS[key];
    if (part) {
      return <AboutTab page={page} onOpenPhoto={onOpenPhoto} parts={[part]} enquiry={false} />;
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

  // «Σχετικά» becomes one card per part on desktop (text, photos, clubs, rooms, facts).
  const items: BentoItem[] = site.sections.flatMap((key): BentoItem[] => {
    if (key === "about")
      return ABOUT_GROUP.map((part) => ({
        key: part,
        size: NARROW.has(part) ? "narrow" : "wide",
        node: <AboutTab page={page} onOpenPhoto={onOpenPhoto} parts={[part]} enquiry={false} />,
      }));
    // The desktop info card already shows a single location.
    return [{ key, size: NARROW.has(key) ? "narrow" : "wide", node: render(key), desktopHidden: key === "location" && page.locations.length <= 1 }];
  });

  return (
    <div className="flex flex-col gap-9" data-testid="site-sections">
      <BoxBento items={items} aside={aside} />
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

// «Επόμενο» depends on the visitor's clock: none on the server, then the
// minute it is in the browser (re-read every minute).
function subscribeMinute(onChange: () => void) {
  const timer = window.setInterval(onChange, 60_000);
  return () => window.clearInterval(timer);
}
const readMinute = () => Math.floor(Date.now() / 60_000) * 60_000;
const serverMinute = () => null;

/**
 * «Ωρολόγιο» (ANR 2026-11-09): a strip of days, then that day's classes as
 * rounded tiles in time order, top to bottom. Classes that start together
 * share one row of fixed width, side by side; the next one to start is
 * outlined and says «Επόμενο».
 */
function TimetableSection({ site }: { site: PublicSite }) {
  const t = useTranslations("BoxSite");
  const locale = useLocale();
  const days = timetableByDay(site.timetable, site.time_zone, locale);
  const [picked, setPicked] = useState<string | null>(null);
  const now = useSyncExternalStore(subscribeMinute, readMinute, serverMinute);
  const panelId = useId();
  if (days.length === 0) return null;
  const day = days.find((entry) => entry.day === picked) ?? days[0]!;
  const next = now === null ? null : nextSlotAt(days, now);
  return (
    <section className="flex flex-col gap-4" data-testid="site-schedule">
      <SectionTitle>{t("sections.schedule")}</SectionTitle>
      {days.length > 1 ? (
        <div role="tablist" aria-label={t("scheduleDays")} className="-mx-1 flex gap-1.5 overflow-x-auto px-1 pb-1">
          {days.map((entry) => (
            <button
              key={entry.day}
              type="button"
              role="tab"
              aria-selected={entry.day === day.day}
              aria-controls={panelId}
              aria-label={entry.label}
              onClick={() => setPicked(entry.day)}
              className="flex min-h-12 min-w-13 shrink-0 flex-col items-center justify-center rounded-2xl px-2 text-xs leading-tight"
              style={entry.day === day.day ? undefined : { border: "1px solid var(--border)", color: "var(--dim)" }}
              data-testid="site-schedule-day"
            >
              <span className="capitalize">{entry.weekday}</span>
              <b className="text-base tabular-nums">{entry.date}</b>
            </button>
          ))}
        </div>
      ) : (
        <h3 className="text-sm font-bold capitalize" style={{ color: "var(--text-soft)" }}>{day.label}</h3>
      )}
      <ol id={panelId} role={days.length > 1 ? "tabpanel" : undefined} aria-label={day.label} className="flex flex-col gap-2">
        {day.slots.map((slot) => {
          const isNext = slot.at === next;
          return (
            <li key={slot.at} className="grid grid-cols-[3.25rem_minmax(0,1fr)] items-center gap-3" data-testid="site-schedule-slot">
              <span className="text-base font-extrabold tabular-nums" style={{ color: "var(--text)" }}>{slot.time}</span>
              <div className="grid gap-2" style={{ gridTemplateColumns: `repeat(${slot.classes.length}, minmax(0, 1fr))` }}>
                {slot.classes.map((entry) => (
                  <div
                    key={entry.id}
                    className="flex min-w-0 flex-col rounded-2xl px-3 py-2"
                    style={{
                      background: "var(--panel)",
                      border: `1px solid ${isNext ? "var(--text)" : "var(--border)"}`,
                      boxShadow: isNext ? "inset 0 0 0 1px var(--text)" : undefined,
                    }}
                  >
                    <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }} title={entry.name}>{entry.name}</span>
                    <span className="truncate text-xs" style={{ color: "var(--dim)" }}>
                      {t("minutes", { count: entry.minutes })}
                      {isNext ? (
                        <>
                          {" · "}
                          <b style={{ color: "var(--text)" }}>{t("nextClass")}</b>
                        </>
                      ) : null}
                    </span>
                  </div>
                ))}
              </div>
            </li>
          );
        })}
      </ol>
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
  // ADR-596: the box's «Προτεινόμενο» package comes first and stands out.
  const packages = featuredFirst(query.data?.packages ?? []).slice(0, 4);
  if (packages.length === 0) return null;
  return (
    <section className="flex flex-col gap-3" data-testid="site-packages">
      <SectionTitle>{t("sections.packages")}</SectionTitle>
      <ul className="grid gap-3 sm:grid-cols-2">
        {packages.map((item) => {
          const featured = item.featured === true;
          return (
            <li
              key={item.id}
              className="flex flex-col gap-1 rounded-2xl p-4"
              style={featured ? { background: "var(--deep)", color: "var(--deep-contrast)" } : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
              data-featured={featured || undefined}
              data-testid="site-package"
            >
              {featured ? (
                <span className="self-start rounded-full px-2.5 py-0.5 text-xs font-bold" style={{ background: "var(--spark)", color: "var(--spark-contrast)" }}>
                  {t("featured")}
                </span>
              ) : null}
              <b className="text-sm">{siteTextFor(site.texts, "package", item.id, "name", item.name)}</b>
              <span className="text-2xl font-extrabold tracking-tight">{formatCents(item.base_price_cents, item.currency, locale)}</span>
              {item.description ? (
                <span className="line-clamp-2 text-sm" style={{ opacity: 0.75 }}>
                  {siteTextFor(site.texts, "package", item.id, "description", item.description)}
                </span>
              ) : null}
            </li>
          );
        })}
      </ul>
      <Link href={`${basePath || ""}/packages`} className="self-start text-sm font-bold" style={{ color: "var(--primary-strong)" }}>
        {t("allPackages")} ›
      </Link>
    </section>
  );
}

function featuredFirst<T extends { featured?: boolean }>(packages: T[]): T[] {
  return [...packages.filter((item) => item.featured === true), ...packages.filter((item) => item.featured !== true)];
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
