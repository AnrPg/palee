import { describe, expect, it } from "vitest";

import ar from "../../../messages/ar.json";
import bg from "../../../messages/bg.json";
import de from "../../../messages/de.json";
import el from "../../../messages/el.json";
import en from "../../../messages/en.json";
import es from "../../../messages/es.json";
import fr from "../../../messages/fr.json";
import he from "../../../messages/he.json";
import itIT from "../../../messages/it.json";
import nl from "../../../messages/nl.json";
import pt from "../../../messages/pt-PT.json";
import ru from "../../../messages/ru.json";
import { MODERATION_CONTACT, TERMS_SECTIONS } from "./termsSections";

const catalogs = { ar, bg, de, el, en, es, fr, he, it: itIT, nl, "pt-PT": pt, ru } as const;
type Terms = Record<string, string>;

describe("terms of use sections", () => {
  it("reads the account first and the changes last, with the v3.2 sections in between", () => {
    expect(TERMS_SECTIONS.map((section) => section.id)).toEqual([
      "account",
      "boxes",
      "business",
      "payments",
      "programmes",
      "content",
      "reviews",
      "health",
      "ai",
      "availability",
      "ending",
      "liability",
      "law",
      "changes",
    ]);
  });

  it("has every heading and paragraph translated in all twelve locales", () => {
    for (const [locale, catalog] of Object.entries(catalogs)) {
      const terms = (catalog as { legal: { terms: Terms } }).legal.terms;
      for (const section of TERMS_SECTIONS) {
        for (const key of [section.heading, ...section.texts]) {
          expect(terms[key], `${locale}.${key}`).toMatch(/\S/);
        }
      }
    }
  });

  // ADR-397 decision 4 and DSA Art. 16(1)/17(3)(f): the notice channel and the redress
  // address are in the text itself, in every language.
  it("names the moderation address in the reviews section of every locale", () => {
    for (const [locale, catalog] of Object.entries(catalogs)) {
      const terms = (catalog as { legal: { terms: Terms } }).legal.terms;
      const reviews = TERMS_SECTIONS.find((section) => section.id === "reviews");
      const text = (reviews?.texts ?? []).map((key) => terms[key]).join(" ");
      expect(text, locale).toContain(MODERATION_CONTACT);
    }
  });

  // ADR-371: the 14 days and the pro rata rule are the buyer's own protection, so they
  // may never go missing from a translation.
  it("keeps the 14-day withdrawal period in the programme section of every locale", () => {
    for (const [locale, catalog] of Object.entries(catalogs)) {
      const terms = (catalog as { legal: { terms: Terms } }).legal.terms;
      expect(terms.programmesBody4, locale).toMatch(/14|١٤/);
      expect(terms.programmesBody3, locale).toContain("60");
    }
  });
});
