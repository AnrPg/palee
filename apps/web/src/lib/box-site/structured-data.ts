// ADR-352 §4: schema.org JSON-LD of a box's website, built only from what the
// public API returns. No aggregateRating: Google ignores self-serving reviews
// of a LocalBusiness and the box's own feedback is private.

export type SiteLocation = {
  name?: string | null;
  address?: string | null;
  city?: string | null;
  neighbourhood?: string | null;
  country_code?: string | null;
  latitude?: number | null;
  longitude?: number | null;
};

export type SitePackage = {
  id: string;
  name: string;
  description?: string | null;
  base_price_cents: number;
  currency: string;
};

export type SiteClass = { id: string; name: string; scheduled_at: string; duration_minutes: number };

export type SiteFacts = {
  name: string;
  url: string;
  description?: string | null;
  logoUrl?: string | null;
  imageUrls: string[];
  locations: SiteLocation[];
  packages: SitePackage[];
  timetable: SiteClass[];
  faq: { question: string; answer: string }[];
  googleReviewsUrl?: string | null;
  sameAs?: string[];
};

/** Price as schema.org wants it: a decimal string from integer cents. */
export function price(cents: number) {
  return (cents / 100).toFixed(2);
}

function address(location: SiteLocation) {
  if (!location.address && !location.city) return undefined;
  return {
    "@type": "PostalAddress",
    streetAddress: location.address ?? undefined,
    addressLocality: location.city ?? undefined,
    addressCountry: location.country_code ?? undefined,
  };
}

function geo(location: SiteLocation) {
  if (location.latitude == null || location.longitude == null) return undefined;
  return { "@type": "GeoCoordinates", latitude: location.latitude, longitude: location.longitude };
}

function isoDuration(minutes: number) {
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return `PT${hours ? `${hours}H` : ""}${rest || !hours ? `${rest}M` : ""}`;
}

export function siteStructuredData(facts: SiteFacts) {
  const id = `${facts.url.replace(/\/$/, "")}/#gym`;
  const [first] = facts.locations;
  const sameAs = [...(facts.sameAs ?? []), ...(facts.googleReviewsUrl ? [facts.googleReviewsUrl] : [])];

  const gym: Record<string, unknown> = {
    "@type": "ExerciseGym",
    "@id": id,
    name: facts.name,
    url: facts.url,
    description: facts.description || undefined,
    logo: facts.logoUrl || undefined,
    image: facts.imageUrls.length ? facts.imageUrls : undefined,
    address: first ? address(first) : undefined,
    geo: first ? geo(first) : undefined,
    sameAs: sameAs.length ? sameAs : undefined,
  };

  if (facts.locations.length > 1) {
    gym.department = facts.locations.slice(1).map((location) => ({
      "@type": "ExerciseGym",
      name: location.name ? `${facts.name} ${location.name}` : facts.name,
      address: address(location),
      geo: geo(location),
    }));
  }

  if (facts.packages.length) {
    gym.makesOffer = facts.packages.map((pkg) => ({
      "@type": "Offer",
      name: pkg.name,
      description: pkg.description || undefined,
      price: price(pkg.base_price_cents),
      priceCurrency: pkg.currency,
      availability: "https://schema.org/InStock",
    }));
  }

  const graph: Record<string, unknown>[] = [gym];

  for (const session of facts.timetable) {
    const start = new Date(session.scheduled_at);
    graph.push({
      "@type": "Event",
      name: session.name,
      startDate: start.toISOString(),
      endDate: new Date(start.getTime() + session.duration_minutes * 60_000).toISOString(),
      duration: isoDuration(session.duration_minutes),
      eventAttendanceMode: "https://schema.org/OfflineEventAttendanceMode",
      eventStatus: "https://schema.org/EventScheduled",
      location: { "@id": id },
      organizer: { "@id": id },
    });
  }

  if (facts.faq.length) {
    graph.push({
      "@type": "FAQPage",
      mainEntity: facts.faq.map(({ question, answer }) => ({
        "@type": "Question",
        name: question,
        acceptedAnswer: { "@type": "Answer", text: answer },
      })),
    });
  }

  return { "@context": "https://schema.org", "@graph": JSON.parse(JSON.stringify(graph)) as unknown[] };
}
