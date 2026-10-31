/**
 * Builds the help centre's starting articles (ADR-362) from what the app
 * already says about itself, in all 12 locales:
 *
 *   - one article per feature catalog section (lib/seo/feature-catalog.ts):
 *     title and summary from SiteInfo; the English detail lines as the body
 *     (other locales get the translated summary and `complete: false` until
 *     the Palee team translates the details);
 *   - one article per in-app guide (lib/guides/registry.ts): title, summary
 *     and every step from the Guides messages, which exist in every locale.
 *
 * Run from apps/web:  npx tsx scripts/build-help-seed.ts
 * Writes apps/api/priv/help_centre/articles.json. Bump SEED_VERSION whenever
 * the output changes, so `mix palee.help_centre.seed` refreshes untouched rows.
 */
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { FEATURE_SECTIONS } from "../src/lib/seo/feature-catalog";
import { GUIDES } from "../src/lib/guides/registry";

const SEED_VERSION = 1;
const LOCALES = ["en", "el", "ar", "ru", "de", "es", "pt-PT", "he", "it", "bg", "nl", "fr"];

// Screens (app route patterns) each article is linked from, and who it is for.
const FEATURE_LINKS: Record<string, { audience: "staff" | "member" | "all"; screens: string[] }> = {
  social: { audience: "member", screens: ["/clubs", "/around"] },
  partners: { audience: "member", screens: ["/partners"] },
  events: { audience: "all", screens: ["/events"] },
  box: { audience: "member", screens: ["/box"] },
  training: { audience: "member", screens: ["/workouts"] },
  journal: { audience: "member", screens: ["/journal"] },
  body: { audience: "member", screens: [] },
  progress: { audience: "member", screens: [] },
  business: {
    audience: "staff",
    screens: ["/admin", "/admin/schedule", "/admin/class-schedule", "/admin/check-in", "/admin/workouts", "/admin/inventory", "/admin/cleaning", "/admin/reviews", "/admin/users"],
  },
  coaching: { audience: "staff", screens: ["/admin/coaching", "/admin/coaching-assignments"] },
  finance: { audience: "staff", screens: ["/admin/finance", "/admin/collect"] },
  growth: { audience: "staff", screens: ["/admin/public-page", "/admin/trials"] },
  branches: { audience: "staff", screens: ["/admin/settings"] },
  devices: { audience: "member", screens: [] },
  privacy: { audience: "all", screens: ["/privacy"] },
};

const GUIDE_SCREENS: Record<string, string[]> = {
  shop_staff: ["/admin/shop"],
  events_organising: ["/events/hosting"],
  finance_offers: ["/admin/finance"],
  member_club_event: ["/events", "/clubs"],
};

type Messages = Record<string, unknown>;

const messagesDir = join(__dirname, "..", "messages");
const messages: Record<string, Messages> = Object.fromEntries(
  LOCALES.map((locale) => [locale, JSON.parse(readFileSync(join(messagesDir, `${locale}.json`), "utf8"))]),
);

function lookup(locale: string, path: string): string | undefined {
  const value = path.split(".").reduce<unknown>((node, key) => (node as Messages | undefined)?.[key], messages[locale]);
  return typeof value === "string" ? value : undefined;
}

function message(locale: string, path: string): string {
  const value = lookup(locale, path) ?? lookup("en", path);
  if (value === undefined) throw new Error(`missing message ${path}`);
  return value;
}

const slugOf = (id: string) => id.replace(/_/g, "-");

type SeedArticle = {
  slug: string;
  feature_key: string | null;
  guide_id: string | null;
  audience: string;
  screens: string[];
  position: number;
  locales: Record<string, unknown>;
};

const articles: SeedArticle[] = [];

FEATURE_SECTIONS.forEach((section, index) => {
  const links = FEATURE_LINKS[section.id] ?? { audience: "all", screens: [] };
  const locales: Record<string, unknown> = {};

  for (const locale of LOCALES) {
    const summary = message(locale, `SiteInfo.${section.summaryKey}`);
    const body =
      locale === "en" ? `${summary}\n\n${section.details.map((line) => `- ${line}`).join("\n")}` : summary;
    locales[locale] = { title: message(locale, `SiteInfo.${section.titleKey}`), summary, body, complete: locale === "en" };
  }

  articles.push({
    slug: `feature-${slugOf(section.id)}`,
    feature_key: section.id,
    guide_id: null,
    audience: links.audience,
    screens: links.screens,
    position: 100 + index,
    locales,
  });
});

GUIDES.forEach((guide, index) => {
  const locales: Record<string, unknown> = {};

  for (const locale of LOCALES) {
    const steps = guide.steps
      .filter((step) => lookup(locale, `Guides.${guide.id}.${step.id}.title`) ?? lookup("en", `Guides.${guide.id}.${step.id}.title`))
      .map((step, number) => {
        const labels = Object.fromEntries(
          Object.entries(step.labels ?? {}).map(([name, key]) => [name, message(locale, key as string)]),
        );
        const fill = (text: string) => text.replace(/\{(\w+)\}/g, (match, name) => labels[name] ?? match);
        const title = fill(message(locale, `Guides.${guide.id}.${step.id}.title`));
        const body = fill(message(locale, `Guides.${guide.id}.${step.id}.body`));
        return `${number + 1}. **${title}**: ${body}`;
      });

    const summary = message(locale, `Guides.${guide.id}.summary`);
    locales[locale] = { title: message(locale, `Guides.${guide.id}.title`), summary, body: `${summary}\n\n${steps.join("\n")}`, complete: true };
  }

  articles.push({
    slug: `guide-${slugOf(guide.id)}`,
    feature_key: null,
    guide_id: guide.id,
    audience: guide.audience === "member" ? "member" : "staff",
    screens: GUIDE_SCREENS[guide.id] ?? [],
    position: 10 + index,
    locales,
  });
});

const target = join(__dirname, "..", "..", "api", "priv", "help_centre", "articles.json");
writeFileSync(target, `${JSON.stringify({ version: SEED_VERSION, articles }, null, 2)}\n`);
console.log(`wrote ${articles.length} articles × ${LOCALES.length} locales to ${target}`);
