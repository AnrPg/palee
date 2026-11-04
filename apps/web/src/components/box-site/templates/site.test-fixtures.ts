import type { PublicSiteV2, SiteSection } from "@/api/box-site";
import type { PublicPackage } from "@/api/my-payments";
import type { PublicBoxPage } from "@/api/social";

import { normalizeSite } from "./site-data";

/** Test data for the website (ADR-530): a box with everything filled in. */

export const ALL_SECTIONS = [
  "hero",
  "about",
  "photos",
  "stats",
  "schedule",
  "wod",
  "events",
  "programmes",
  "packages",
  "coaches",
  "location",
  "reviews",
  "faq",
  "trial_form",
  "contact_form",
] as unknown as SiteSection[];

export const BASIC = ["hero", "about", "packages", "location", "trial_form"] as SiteSection[];

/** Wednesday 4 November 2026, 10:00 in Athens (08:00 UTC). */
export const NOW = Date.parse("2026-11-04T08:00:00Z");

export function boxPage(over: Partial<PublicBoxPage> = {}): PublicBoxPage {
  return {
    box: { name: "Box Κυψέλη", slug: "box-kypseli", organization_id: "org", logo_url: null },
    profile: {
      about: "Ένα box της γειτονιάς. Προπονούμαστε μαζί από το 2017.",
      cover: null,
      photos: [],
      disciplines: ["crossfit"],
      coaches: [
        { id: "c1", nickname: "Μαρία", avatar_url: null, class_types: ["CrossFit"] },
        { id: "c2", nickname: "Νίκος", avatar_url: null, class_types: ["Weightlifting"] },
      ],
    },
    rooms: [],
    locations: [
      {
        id: "l1",
        name: "Κυψέλη",
        address: "Φωκίωνος Νέγρη 10",
        city: "Αθήνα",
        neighbourhood: "Κυψέλη",
        latitude: 37.99,
        longitude: 23.74,
        opening_hours: [
          { weekday: 3, opens: "07:00", closes: "22:00" },
          { weekday: 4, opens: "07:00", closes: "22:00" },
        ],
      },
    ],
    ...over,
  } as unknown as PublicBoxPage;
}

export function boxSite(over: Partial<PublicSiteV2> = {}): PublicSiteV2 {
  return normalizeSite({
    slug: "box-kypseli",
    language: "el",
    languages: ["el", "en"],
    canonical_url: "https://palee.app/b/box-kypseli",
    time_zone: "Europe/Athens",
    translation: null,
    about: null,
    texts: {},
    class_type_names: {},
    sections: ALL_SECTIONS,
    faq: [{ question: "Χρειάζομαι εμπειρία;", answer: "Όχι, ξεκινάμε από την αρχή." }],
    forms: { trial: true, contact: true, kinds: ["trial", "contact"] },
    reviews: {
      google: { count: 120, rating: 4.8, fetched_at: "2026-11-01T00:00:00Z", maps_uri: null, name: "Box Κυψέλη", write_review_url: null },
      google_reviews_url: null,
      palee: {
        average: 4.9,
        count: 37,
        latest: [{ id: "r1", author_name: "Ελένη", body: "Υπέροχη ομάδα.", rating: 5, created_at: "2026-10-01T00:00:00Z", edited_at: null, reply: null }],
      },
    },
    events: [
      { id: "e1", title: "Κυψέλη Throwdown", starts_at: "2026-11-21T09:00:00Z", ends_at: "2026-11-21T15:00:00Z", time_zone: null, place_name: "Box Κυψέλη", price_cents: 0, currency: "EUR" },
    ],
    timetable: [
      { id: "t1", name: "CrossFit", scheduled_at: "2026-11-04T15:00:00Z", duration_minutes: 60, class_type_id: null, location_id: null },
      { id: "t2", name: "Weightlifting", scheduled_at: "2026-11-05T05:00:00Z", duration_minutes: 60, class_type_id: null, location_id: null },
    ],
    wod: [{ id: "w1", date: "2026-11-04", title: "Fran", type: "For Time", body: "21-15-9\nThrusters\nPull-ups" }],
    tracking: { banner_version: 1, categories: ["necessary"], consent_required: false, tags: { ga4_measurement_id: null, gtm_container_id: null, meta_pixel_id: null }, validity_days: 180 },
    template: "arena",
    palette: "palee",
    appearance: "auto",
    calm_motion: false,
    photos: { items: [{ id: "p1", url: "https://media.example/p1.jpg", width: 800, height: 600, caption: "Αίθουσα" }], video: null },
    stats: { classes_per_week: 42, prs_this_year: 310, years_open: 9 },
    programmes: [{ id: "pr1", title: "Strength 8", summary: "Οκτώ εβδομάδες δύναμης.", weeks: 8, price_cents: 2500, currency: "EUR", cover_url: null, url: null }],
    phone: "210 000 0000",
    ...over,
  } as Partial<PublicSiteV2>);
}

export const PACKAGES: PublicPackage[] = [
  { id: "k1", name: "Δοκιμαστικό", description: null, package_type: "trial", billing_period: "one_off", base_price_cents: 0, currency: "EUR", services: {} },
  { id: "k2", name: "Unlimited", description: "Όσες φορές θέλεις.", package_type: "membership", billing_period: "monthly", base_price_cents: 7500, currency: "EUR", services: {} },
  { id: "k3", name: "3 φορές", description: null, package_type: "membership", billing_period: "monthly", base_price_cents: 6000, currency: "EUR", services: {} },
] as unknown as PublicPackage[];
