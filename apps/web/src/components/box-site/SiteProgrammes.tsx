"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import type { PublicSite } from "@/api/box-site";
import { ProgrammeTile, type TileProgramme } from "@/components/programmes/ProgrammeTile";

export const SITE_PROGRAMMES_ANCHOR = "site-programmes";

/**
 * The website's programmes (ADR-543): up to three cards on sale, newest
 * first, and how many there are. The site payload carries them as the
 * `programmes` list (ADR-530) and `programmes_total`; a payload without them
 * (an older API, a stub answering `{}`) reads as none.
 */
export function siteProgrammes(
  site: (Pick<PublicSite, "programmes"> & { programmes_total?: unknown }) | null | undefined,
): { items: (TileProgramme & { id: string })[]; total: number } {
  const block = site?.programmes as unknown;
  const items = Array.isArray(block) ? block : block && typeof block === "object" ? (block as { items?: unknown }).items : undefined;
  const total = Array.isArray(block) ? site?.programmes_total : block && typeof block === "object" ? (block as { total?: unknown }).total : undefined;
  const list = (Array.isArray(items) ? items : [])
    .filter((item): item is TileProgramme & { id: string } => Boolean(item && typeof item === "object" && typeof (item as { id?: unknown }).id === "string"))
    .slice(0, 3);
  const count = typeof total === "number" && Number.isFinite(total) ? Math.max(Math.floor(total), list.length) : list.length;
  return { items: list, total: count };
}

/** Whether the site shows the section: the owner keeps it on and the box has a programme on sale. */
export function showsSiteProgrammes(site: Pick<PublicSite, "programmes" | "sections"> | null | undefined) {
  return Boolean(site && Array.isArray(site.sections) && site.sections.includes("programmes") && siteProgrammes(site).items.length > 0);
}

/**
 * «Προγράμματα» on the box website (board 4κ/4μ A): phone, the cards
 * stacked; desktop, three columns; «Όλα τα προγράμματα (N)» when the box
 * sells more than it shows. Hidden when the box has none on sale.
 */
export function SiteProgrammesSection({ site }: { site: PublicSite }) {
  const t = useTranslations("BoxSite");
  const { items, total } = siteProgrammes(site);
  if (items.length === 0) return null;
  const slug = encodeURIComponent(site.slug);
  return (
    <section id={SITE_PROGRAMMES_ANCHOR} className="flex scroll-mt-24 flex-col gap-4" data-testid="site-programmes">
      <div className="flex flex-col gap-1">
        <p className="text-xs font-bold uppercase tracking-[0.14em]" style={{ color: "var(--primary-strong)" }}>{t("programmesSection.eyebrow")}</p>
        <h2 className="text-lg font-extrabold lg:text-2xl" style={{ color: "var(--text)" }}>{t("programmesSection.title")}</h2>
      </div>
      <div className="grid gap-3 lg:grid-cols-3 lg:gap-4">
        {items.map((programme) => (
          <ProgrammeTile key={programme.id} programme={programme} href={`/b/${slug}/programmes/${encodeURIComponent(programme.id)}`} testId={`site-programme-${programme.id}`} />
        ))}
      </div>
      {total > items.length ? (
        <Link
          href={`/b/${slug}/programmes`}
          className="flex min-h-11 w-full items-center justify-center rounded-2xl px-5 text-sm font-bold lg:w-auto lg:self-start"
          style={{ border: "1px solid var(--border)", background: "var(--panel)", color: "var(--text)" }}
          data-testid="site-programmes-all"
        >
          {t("programmesSection.all", { count: total })}
        </Link>
      ) : null}
    </section>
  );
}

/** «Προγράμματα» in the website's menu on a large screen (board 4μ A). */
export function SiteProgrammesNavLink({ site }: { site: PublicSite | null }) {
  const t = useTranslations("BoxSite");
  if (!showsSiteProgrammes(site)) return null;
  return (
    <nav aria-label={t("programmesSection.nav")} className="hidden lg:block">
      <a href={`#${SITE_PROGRAMMES_ANCHOR}`} className="flex min-h-11 items-center text-sm font-bold" style={{ color: "var(--primary-strong)" }} data-testid="site-nav-programmes">
        {t("programmesSection.nav")}
      </a>
    </nav>
  );
}
