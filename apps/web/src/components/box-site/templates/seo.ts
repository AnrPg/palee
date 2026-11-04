import type { PublicSiteV2, SiteSection } from "@/api/box-site";
import type { PublicPackage } from "@/api/my-payments";
import type { PublicBoxPage } from "@/api/social";

import { aboutText, classTypes, hoursSummary, mainLocation, openingSpans, type OpeningSpan } from "./site-data";
import { sitePages, type SitePage } from "./site-model";

/**
 * ADR-530 §5: what search engines and AI answer engines read about a box's
 * website: schema.org JSON-LD per page, the page URLs and `llms.txt`. Built
 * only from the public API's answer.
 */

/** The sections each page shows, whatever the template. */
export const PAGE_SECTIONS: Record<SitePage, SiteSection[]> = {
  home: ["about", "photos", "stats", "schedule", "wod", "events", "programmes", "packages", "coaches", "location", "reviews", "faq"] as SiteSection[],
  schedule: ["schedule", "events", "programmes"] as SiteSection[],
  packages: ["packages", "faq"],
  coaches: ["coaches"],
  space: ["photos", "location", "reviews", "faq"] as SiteSection[],
};

/** A page's absolute URL from the site's root URL in one language. */
export function pageUrl(root: string, page: SitePage) {
  const base = root.replace(/\/$/, "");
  return page === "home" ? base || "/" : `${base}/${page}`;
}

/** The site's root URL in a language: the canonical root, or `/<code>` under it. */
export function languageRoot(canonical: string, code: string | null) {
  const base = canonical.replace(/\/$/, "");
  return code ? `${base}/${code.toLowerCase()}` : base;
}

/** schema.org prices are decimal strings. */
export function schemaPrice(cents: number) {
  return (cents / 100).toFixed(2);
}

const DAY_NAMES = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];

/** The week's hours as `OpeningHoursSpecification`s (ISO weekday, Monday = 1). */
export function openingHoursSpecification(spans: OpeningSpan[]) {
  return spans
    .filter((span) => span.weekday >= 1 && span.weekday <= 7)
    .map((span) => ({
      "@type": "OpeningHoursSpecification",
      dayOfWeek: `https://schema.org/${DAY_NAMES[span.weekday - 1]}`,
      opens: span.opens,
      closes: span.closes,
    }));
}

export type SeoInput = {
  page: PublicBoxPage;
  site: PublicSiteV2;
  packages: PublicPackage[];
  visible: SiteSection[];
  pageKey: SitePage;
  /** The site's root in the page's language (absolute). */
  root: string;
  /** Page names for the breadcrumb. */
  names: Record<SitePage, string>;
};

function rating(site: PublicSiteV2) {
  const google = site.reviews.google;
  if (google?.rating && google.count) return { value: google.rating, count: google.count };
  const palee = site.reviews.palee;
  if (palee?.average && palee.count > 0) return { value: palee.average, count: palee.count };
  return null;
}

/** The `ExerciseGym` of the box, on every page. */
export function gymJsonLd({ page, site, visible, root }: Pick<SeoInput, "page" | "site" | "visible" | "root">) {
  const location = mainLocation(page);
  const on = (key: string) => visible.includes(key as SiteSection);
  const images = [page.profile?.cover?.url, ...site.photos.items.map((photo) => photo.url)].filter(Boolean) as string[];
  const score = on("reviews") ? rating(site) : null;
  const hours = openingHoursSpecification(openingSpans(page));
  const sameAs = [site.reviews.google?.maps_uri, site.reviews.google_reviews_url].filter(Boolean) as string[];
  return {
    "@type": "ExerciseGym",
    "@id": `${root}#gym`,
    name: page.box.name,
    url: root,
    description: aboutText(site, page).slice(0, 500) || undefined,
    logo: page.box.logo_url || undefined,
    image: images.length ? images.slice(0, 6) : undefined,
    telephone: site.phone || undefined,
    address:
      location && (location.address || location.city)
        ? {
            "@type": "PostalAddress",
            streetAddress: location.address ?? undefined,
            addressLocality: location.city ?? undefined,
            addressCountry: location.country_code ?? undefined,
          }
        : undefined,
    geo:
      location && location.latitude != null && location.longitude != null
        ? { "@type": "GeoCoordinates", latitude: location.latitude, longitude: location.longitude }
        : undefined,
    openingHoursSpecification: hours.length ? hours : undefined,
    aggregateRating: score ? { "@type": "AggregateRating", ratingValue: Number(score.value.toFixed(1)), reviewCount: score.count, bestRating: 5 } : undefined,
    sameAs: sameAs.length ? [...new Set(sameAs)] : undefined,
  };
}

/** The packages as an `OfferCatalog` of `Offer`s (the packages page). */
export function offerCatalogJsonLd(packages: PublicPackage[], site: PublicSiteV2, root: string, name: string) {
  return {
    "@type": "OfferCatalog",
    name,
    url: pageUrl(root, "packages"),
    itemListElement: packages.map((pkg) => ({
      "@type": "Offer",
      name: site.texts[`package:${pkg.id}:name`]?.trim() || pkg.name,
      description: (site.texts[`package:${pkg.id}:description`]?.trim() || pkg.description) ?? undefined,
      price: schemaPrice(pkg.base_price_cents),
      priceCurrency: pkg.currency,
      availability: "https://schema.org/InStock",
      offeredBy: { "@id": `${root}#gym` },
    })),
  };
}

/** The box's events open to everyone. */
export function eventsJsonLd(site: PublicSiteV2, root: string) {
  return site.events.map((event) => ({
    "@type": "Event",
    name: event.title,
    startDate: event.starts_at,
    endDate: event.ends_at,
    eventAttendanceMode: "https://schema.org/OfflineEventAttendanceMode",
    eventStatus: "https://schema.org/EventScheduled",
    location: event.place_name ? { "@type": "Place", name: event.place_name } : { "@id": `${root}#gym` },
    organizer: { "@id": `${root}#gym` },
    offers: {
      "@type": "Offer",
      price: schemaPrice(event.price_cents),
      priceCurrency: event.currency,
      availability: "https://schema.org/InStock",
    },
  }));
}

export function faqJsonLd(site: PublicSiteV2) {
  return {
    "@type": "FAQPage",
    mainEntity: site.faq.map(({ question, answer }) => ({ "@type": "Question", name: question, acceptedAnswer: { "@type": "Answer", text: answer } })),
  };
}

export function breadcrumbJsonLd(root: string, pageKey: SitePage, names: Record<SitePage, string>) {
  return {
    "@type": "BreadcrumbList",
    itemListElement: [
      { "@type": "ListItem", position: 1, name: names.home, item: pageUrl(root, "home") },
      { "@type": "ListItem", position: 2, name: names[pageKey], item: pageUrl(root, pageKey) },
    ],
  };
}

/** Everything one page says in JSON-LD, as one `@graph`. */
export function siteJsonLd(input: SeoInput) {
  const { site, visible, pageKey, root, packages, names } = input;
  const shows = (key: string) => visible.includes(key as SiteSection) && PAGE_SECTIONS[pageKey].includes(key as SiteSection);
  const graph: Record<string, unknown>[] = [gymJsonLd(input)];
  if (pageKey === "packages" && shows("packages") && packages.length) graph.push(offerCatalogJsonLd(packages, site, root, names.packages));
  if (shows("events")) graph.push(...eventsJsonLd(site, root));
  if (shows("faq")) graph.push(faqJsonLd(site));
  if (pageKey !== "home") graph.push(breadcrumbJsonLd(root, pageKey, names));
  // Drops the `undefined`s, so the markup carries only what the box filled.
  return { "@context": "https://schema.org", "@graph": JSON.parse(JSON.stringify(graph)) as unknown[] };
}

const money = (cents: number, currency: string) => `${schemaPrice(cents)} ${currency}`;
const PERIOD: Record<string, string> = { monthly: "per month", quarterly: "per quarter", semiannual: "per six months", annual: "per year" };

/**
 * https://llmstxt.org: a plain Markdown summary of the box for AI answer
 * engines, with the same name, address, phone and hours as the pages.
 */
export function llmsText({ page, site, packages, visible, root }: Omit<SeoInput, "pageKey" | "names">): string {
  const on = (key: string) => visible.includes(key as SiteSection);
  const location = mainLocation(page);
  const about = aboutText(site, page);
  const lines: string[] = [`# ${page.box.name}`, ""];
  if (about) lines.push(`> ${about.replace(/\s+/g, " ").slice(0, 400)}`, "");
  const facts = [
    location ? `- Address: ${[location.address, location.neighbourhood, location.city].filter(Boolean).join(", ")}` : null,
    location?.latitude != null && location.longitude != null ? `- Coordinates: ${location.latitude}, ${location.longitude}` : null,
    site.phone ? `- Phone: ${site.phone}` : null,
    openingSpans(page).length ? `- Opening hours: ${hoursSummary(openingSpans(page), "en")}` : null,
    `- Website: ${root}`,
    site.reviews.google?.rating ? `- Google rating: ${site.reviews.google.rating} (${site.reviews.google.count ?? 0} reviews)` : null,
  ].filter(Boolean) as string[];
  lines.push(...facts, "");

  const types = classTypes(site.timetable);
  const offers = [
    ...(page.profile?.disciplines ?? []).map((value) => `- ${value}`),
    ...(on("schedule") && types.length ? [`- Classes: ${types.map((name) => site.class_type_names[name] ?? name).join(", ")}`] : []),
    ...(on("coaches") ? [`- Coaches: ${(page.profile?.coaches ?? []).map((coach) => coach.nickname).filter(Boolean).join(", ")}`] : []),
  ];
  if (offers.length) lines.push("## What we offer", "", ...offers, "");

  if (on("packages") && packages.length) {
    lines.push("## Subscription packages", "");
    for (const pkg of packages) {
      const name = site.texts[`package:${pkg.id}:name`]?.trim() || pkg.name;
      const period = PERIOD[pkg.billing_period] ? ` ${PERIOD[pkg.billing_period]}` : "";
      const description = site.texts[`package:${pkg.id}:description`]?.trim() || pkg.description;
      lines.push(`- ${name}: ${pkg.base_price_cents > 0 ? money(pkg.base_price_cents, pkg.currency) : "free"}${period}${description ? ` — ${description.replace(/\s+/g, " ")}` : ""}`);
    }
    lines.push("");
  }
  if (on("programmes")) {
    lines.push("## Programmes", "");
    for (const programme of site.programmes) {
      const price = programme.price_cents ? `: ${money(programme.price_cents, programme.currency ?? "EUR")}` : "";
      lines.push(`- ${programme.title}${price}${programme.weeks ? ` (${programme.weeks} weeks)` : ""}`);
    }
    lines.push("");
  }
  if (on("events")) {
    lines.push("## Events", "");
    for (const event of site.events) lines.push(`- ${event.title}: ${event.starts_at}${event.place_name ? `, ${event.place_name}` : ""}`);
    lines.push("");
  }

  const PAGE_NAMES: Record<SitePage, string> = { home: "Home", schedule: "Schedule", packages: "Subscription packages", coaches: "Coaches", space: "The space, location and reviews" };
  lines.push("## Pages", "");
  for (const entry of sitePages(visible)) lines.push(`- [${PAGE_NAMES[entry.key]}](${pageUrl(root, entry.key)})`);
  lines.push("");

  if (on("faq")) {
    lines.push("## FAQ", "");
    for (const entry of site.faq) lines.push(`### ${entry.question}`, "", entry.answer, "");
  }
  return lines.join("\n");
}

const xml = (value: string) => value.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");

/**
 * The site's sitemap: each page in the menu, in each language the owner
 * shows (the first is the box's own, at the root), with its alternates.
 */
export function siteSitemapXml({ root, languages, visible }: { root: string; languages: string[]; visible: SiteSection[] }) {
  const codes = languages.length ? languages : [null];
  const urls = sitePages(visible).flatMap((entry) => {
    const alternates = languages.length > 1 ? languages.map((code, index) => ({ code, href: pageUrl(languageRoot(root, index === 0 ? null : code), entry.key) })) : [];
    return codes.map((code, index) => {
      const loc = pageUrl(languageRoot(root, index === 0 ? null : code), entry.key);
      const links = alternates.map((alt) => `<xhtml:link rel="alternate" hreflang="${xml(alt.code)}" href="${xml(alt.href)}"/>`).join("");
      return `<url><loc>${xml(loc)}</loc>${links}<changefreq>weekly</changefreq><priority>${entry.key === "home" ? "1.0" : "0.7"}</priority></url>`;
    });
  });
  return `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n${urls.join("\n")}\n</urlset>\n`;
}
