import { describe, expect, it } from "vitest";

import { price, siteStructuredData } from "./structured-data";

describe("box site JSON-LD (ADR-352)", () => {
  const data = siteStructuredData({
    name: "CrossFit Ακρόπολη",
    url: "https://www.mybox.gr/",
    description: "Box στο Κουκάκι",
    imageUrls: ["https://media.example/cover.jpg"],
    locations: [
      { address: "Δράκου 5", city: "Αθήνα", country_code: "GR", latitude: 37.96, longitude: 23.72 },
      { name: "Γλυφάδα", address: "Λαζαράκη 1", city: "Γλυφάδα", country_code: "GR" },
    ],
    packages: [{ id: "p1", name: "Μηνιαίο", base_price_cents: 6000, currency: "EUR" }],
    timetable: [{ id: "c1", name: "WOD", scheduled_at: "2026-11-03T16:00:00Z", duration_minutes: 60 }],
    faq: [{ question: "Πού παρκάρω;", answer: "Στον δρόμο." }],
    googleReviewsUrl: "https://www.google.com/maps/place/?q=place_id:ChIJabc",
  });
  const graph = data["@graph"] as Record<string, unknown>[];
  const gym = graph[0];

  it("describes the gym with its address, offers and Google listing", () => {
    expect(gym["@type"]).toBe("ExerciseGym");
    expect(gym["@id"]).toBe("https://www.mybox.gr/#gym");
    expect(gym.address).toEqual({
      "@type": "PostalAddress",
      streetAddress: "Δράκου 5",
      addressLocality: "Αθήνα",
      addressCountry: "GR",
    });
    expect(gym.makesOffer).toEqual([
      expect.objectContaining({ "@type": "Offer", price: "60.00", priceCurrency: "EUR" }),
    ]);
    expect(gym.sameAs).toEqual(["https://www.google.com/maps/place/?q=place_id:ChIJabc"]);
    expect(gym.department).toHaveLength(1);
    expect(gym).not.toHaveProperty("aggregateRating");
    expect(gym).not.toHaveProperty("logo");
  });

  it("adds each class as an Event and the FAQ", () => {
    const event = graph.find((node) => node["@type"] === "Event");
    expect(event).toMatchObject({
      name: "WOD",
      startDate: "2026-11-03T16:00:00.000Z",
      endDate: "2026-11-03T17:00:00.000Z",
      duration: "PT1H",
    });
    expect(graph.find((node) => node["@type"] === "FAQPage")).toBeDefined();
  });

  it("formats cents as a decimal price", () => {
    expect(price(1999)).toBe("19.99");
    expect(price(0)).toBe("0.00");
  });
});
