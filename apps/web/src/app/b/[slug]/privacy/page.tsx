import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { getTranslations } from "next-intl/server";

import { isAppLocale } from "@/i18n/locales";
import { loadPublicBox } from "@/lib/public-box";
import { loadPublicSite } from "@/lib/public-site";

type Props = { params: Promise<{ slug: string }>; searchParams: Promise<{ lang?: string }> };

const PARTS = ["controller", "collect", "why", "keep", "cookies", "rights"] as const;

async function texts(slug: string, lang: string | undefined) {
  const page = await loadPublicBox(slug);
  if (!page) return null;
  const site = await loadPublicSite(page.box.slug);
  const wanted = lang === "en" ? "en" : site?.language;
  const locale = isAppLocale(wanted) ? wanted : undefined;
  const t = locale ? await getTranslations({ locale, namespace: "BoxSite.privacyPage" }) : await getTranslations("BoxSite.privacyPage");
  return { page, site, t, locale };
}

export async function generateMetadata({ params, searchParams }: Props): Promise<Metadata> {
  const { slug } = await params;
  const { lang } = await searchParams;
  const loaded = await texts(slug, lang);
  if (!loaded) return {};
  return { title: loaded.t("title", { box: loaded.page.box.name }), robots: { index: false } };
}

/**
 * The website's privacy policy (ANR s4 A): a template filled with the box's
 * name and what the site collects. It needs a lawyer's review before a box
 * relies on it, and says so.
 */
export default async function SitePrivacyRoute({ params, searchParams }: Props) {
  const { slug } = await params;
  const { lang } = await searchParams;
  const loaded = await texts(slug, lang);
  if (!loaded) notFound();
  const { page, site, t, locale } = loaded;
  const box = page.box.name;
  return (
    <main lang={locale} className="mx-auto flex w-full max-w-2xl flex-col gap-6 px-4 py-10" data-testid="site-privacy">
      <h1 className="text-2xl font-extrabold" style={{ color: "var(--text)" }}>{t("title", { box })}</h1>
      <p className="rounded-2xl px-4 py-3 text-sm font-semibold" style={{ background: "var(--panel-muted)", color: "var(--text)", border: "1px solid var(--warning)" }} data-testid="site-privacy-review">
        {t("needsReview")}
      </p>
      {PARTS.filter((part) => part !== "cookies" || site?.tracking.consent_required).map((part) => (
        <section key={part} className="flex flex-col gap-2">
          <h2 className="text-lg font-bold" style={{ color: "var(--text)" }}>{t(`${part}.title`)}</h2>
          <p className="whitespace-pre-line text-sm leading-relaxed" style={{ color: "var(--text-soft)" }}>{t(`${part}.text`, { box })}</p>
        </section>
      ))}
    </main>
  );
}
