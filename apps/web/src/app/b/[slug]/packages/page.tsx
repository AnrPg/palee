import type { Metadata } from "next";
import { notFound, permanentRedirect } from "next/navigation";
import { getTranslations } from "next-intl/server";
import { Suspense } from "react";

import { SiteRoute, siteMetadata } from "@/components/box-site/site-route";
import { pageIsShown } from "@/components/box-site/templates/site-model";
import { loadWebsite } from "@/components/box-site/templates/site-server";
import { SalesPage } from "@/components/payments/SalesPage";
import { loadPublicBox, previewLine } from "@/lib/public-box";

type Props = { params: Promise<{ slug: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };

/**
 * ADR-530: `/b/<slug>/packages` is the website's «Πακέτα συνδρομής» page
 * for guests when the owner shows packages; buying (`?buy=<package>|all`,
 * the website's buttons), signed-in members and boxes without a website get
 * the sales page.
 */
async function websitePackages(slug: string, search: Record<string, string | string[] | undefined>) {
  if (search.buy !== undefined) return false;
  const website = await loadWebsite(slug, "box");
  return Boolean(website && pageIsShown("packages", website.visible));
}

export async function generateMetadata({ params, searchParams }: Props): Promise<Metadata> {
  const { slug } = await params;
  if (await websitePackages(slug, await searchParams)) return siteMetadata(slug, "box", "packages");
  const page = await loadPublicBox(slug);
  if (!page) return {};
  const t = await getTranslations("Pay");
  const title = t("salesTitle", { box: page.box.name });
  return {
    title,
    alternates: { canonical: `/b/${page.box.slug}/packages` },
    openGraph: { title, type: "website", url: `/b/${page.box.slug}/packages` },
  };
}

/**
 * The box's sales page (ADR-248, mockup s5 option C): reached from the
 * public box page, the website's packages and the box's sign-up links.
 */
export default async function SalesRoute({ params, searchParams }: Props) {
  const { slug } = await params;
  const search = await searchParams;
  const page = await loadPublicBox(slug);
  if (!page) notFound();
  if (page.box.slug !== slug) permanentRedirect(`/b/${page.box.slug}/packages`);
  const tags = await getTranslations("BoxTags");
  const line = previewLine(page, (key) => tags(`discipline.${key}`));
  const sales = (
    <Suspense>
      <SalesPage page={page} line={line} />
    </Suspense>
  );
  if (!(await websitePackages(slug, search))) return sales;
  return <SiteRoute slug={slug} language="box" pageKey="packages" appView={sales} />;
}
