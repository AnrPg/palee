import { describe, expect, it } from "vitest";

import { languageRoot, llmsText, pageUrl, siteJsonLd, siteSitemapXml } from "./seo";
import { visibleSections } from "./site-data";
import { boxPage, boxSite, PACKAGES } from "./site.test-fixtures";

const ROOT = "https://palee.app/b/box-kypseli";
const NAMES = { home: "Αρχική", schedule: "Πρόγραμμα", packages: "Πακέτα", coaches: "Coaches", space: "Ο χώρος" };
const page = boxPage();
const site = boxSite();
const visible = visibleSections({ site, page, packages: PACKAGES.length, gallery: 1 });

type Node = Record<string, unknown> & { "@type": string };
const graph = (pageKey: Parameters<typeof siteJsonLd>[0]["pageKey"]) =>
  siteJsonLd({ page, site, packages: PACKAGES, visible, pageKey, root: ROOT, names: NAMES })["@graph"] as Node[];
const types = (nodes: Node[]) => nodes.map((node) => node["@type"]);

describe("page URLs", () => {
  it("puts sub-pages under the language's root", () => {
    expect(pageUrl(ROOT, "home")).toBe(ROOT);
    expect(pageUrl(`${ROOT}/`, "schedule")).toBe(`${ROOT}/schedule`);
    expect(languageRoot(ROOT, "pt-PT")).toBe(`${ROOT}/pt-pt`);
    expect(languageRoot(`${ROOT}/`, null)).toBe(ROOT);
  });
});

describe("JSON-LD (ADR-530 §5)", () => {
  it("describes the gym with address, hours, phone and the Google rating", () => {
    const [gym] = graph("home");
    expect(gym).toMatchObject({
      "@type": "ExerciseGym",
      "@id": `${ROOT}#gym`,
      name: "Box Κυψέλη",
      telephone: "210 000 0000",
      address: { "@type": "PostalAddress", streetAddress: "Φωκίωνος Νέγρη 10", addressLocality: "Αθήνα" },
      geo: { latitude: 37.99, longitude: 23.74 },
      aggregateRating: { ratingValue: 4.8, reviewCount: 120, bestRating: 5 },
    });
    expect((gym!.openingHoursSpecification as Node[]).map((spec) => spec.dayOfWeek)).toEqual(["https://schema.org/Wednesday", "https://schema.org/Thursday"]);
  });

  it("leaves the rating out when reviews are hidden", () => {
    const [gym] = siteJsonLd({ page, site, packages: PACKAGES, visible: visible.filter((key) => key !== "reviews"), pageKey: "home", root: ROOT, names: NAMES })["@graph"] as Node[];
    expect(gym!.aggregateRating).toBeUndefined();
  });

  it("lists the packages as offers on the packages page only", () => {
    expect(types(graph("home"))).not.toContain("OfferCatalog");
    const catalog = graph("packages").find((node) => node["@type"] === "OfferCatalog")!;
    expect(catalog.url).toBe(`${ROOT}/packages`);
    expect(catalog.itemListElement).toEqual([
      expect.objectContaining({ "@type": "Offer", name: "Δοκιμαστικό", price: "0.00", priceCurrency: "EUR" }),
      expect.objectContaining({ name: "Unlimited", price: "75.00", description: "Όσες φορές θέλεις." }),
      expect.objectContaining({ name: "3 φορές", price: "60.00" }),
    ]);
  });

  it("adds events, the FAQ and a breadcrumb where those pages show them", () => {
    expect(types(graph("home"))).toEqual(["ExerciseGym", "Event", "FAQPage"]);
    expect(types(graph("schedule"))).toEqual(["ExerciseGym", "Event", "BreadcrumbList"]);
    expect(types(graph("coaches"))).toEqual(["ExerciseGym", "BreadcrumbList"]);
    const crumbs = graph("space").find((node) => node["@type"] === "BreadcrumbList")!;
    expect(crumbs.itemListElement).toEqual([
      { "@type": "ListItem", position: 1, name: "Αρχική", item: ROOT },
      { "@type": "ListItem", position: 2, name: "Ο χώρος", item: `${ROOT}/space` },
    ]);
    const faq = graph("space").find((node) => node["@type"] === "FAQPage")!;
    expect(faq.mainEntity).toEqual([{ "@type": "Question", name: "Χρειάζομαι εμπειρία;", acceptedAnswer: { "@type": "Answer", text: "Όχι, ξεκινάμε από την αρχή." } }]);
  });

  it("carries no empty fields", () => {
    expect(JSON.stringify(graph("home"))).not.toContain("null");
  });
});

describe("llms.txt", () => {
  const text = llmsText({ page, site, packages: PACKAGES, visible, root: ROOT });

  it("summarises the box in Markdown with the same facts as the pages", () => {
    expect(text.startsWith("# Box Κυψέλη\n")).toBe(true);
    expect(text).toContain("> Ένα box της γειτονιάς.");
    expect(text).toContain("- Address: Φωκίωνος Νέγρη 10, Κυψέλη, Αθήνα");
    expect(text).toContain("- Phone: 210 000 0000");
    expect(text).toContain("- Unlimited: 75.00 EUR per month — Όσες φορές θέλεις.");
    expect(text).toContain("- Strength 8: 25.00 EUR (8 weeks)");
    expect(text).toContain(`- [Coaches](${ROOT}/coaches)`);
    expect(text).toContain("### Χρειάζομαι εμπειρία;");
  });

  it("leaves out what the owner hides", () => {
    const basic = llmsText({ page, site, packages: PACKAGES, visible: ["hero", "about", "location"] as never, root: ROOT });
    expect(basic).not.toContain("## Subscription packages");
    expect(basic).not.toContain("## FAQ");
    expect(basic).not.toContain("/schedule");
  });
});

describe("sitemap", () => {
  it("lists each page in each language with hreflang alternates", () => {
    const xml = siteSitemapXml({ root: ROOT, languages: ["el", "en"], visible: ["hero", "about", "packages", "coaches"] as never });
    const locs = [...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((match) => match[1]);
    expect(locs).toEqual([ROOT, `${ROOT}/en`, `${ROOT}/packages`, `${ROOT}/en/packages`, `${ROOT}/coaches`, `${ROOT}/en/coaches`]);
    expect(xml).toContain(`<xhtml:link rel="alternate" hreflang="en" href="${ROOT}/en/packages"/>`);
  });

  it("has no alternates for a site in one language", () => {
    const xml = siteSitemapXml({ root: ROOT, languages: ["el"], visible: ["hero"] as never });
    expect(xml).not.toContain("xhtml:link rel");
    expect([...xml.matchAll(/<loc>/g)]).toHaveLength(1);
  });
});
