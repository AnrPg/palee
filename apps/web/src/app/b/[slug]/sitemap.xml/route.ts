import { siteSitemapXml } from "@/components/box-site/templates/seo";
import { loadWebsite, siteRootUrl } from "@/components/box-site/templates/site-server";

// Reads the box from the API on each request; never prerendered at build time (the API is not there).
export const dynamic = "force-dynamic";

type Context = { params: Promise<{ slug: string }> };

/** ADR-530 §5: every page of a box's website in every language it shows, with hreflang alternates. */
export async function GET(_request: Request, { params }: Context) {
  const { slug } = await params;
  const website = await loadWebsite(slug, "box");
  if (!website) return new Response("Not found", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  const { page, site, visible } = website;
  const root = await siteRootUrl(site, page.box.slug);
  return new Response(siteSitemapXml({ root, languages: site.languages, visible }), {
    headers: { "Content-Type": "application/xml; charset=utf-8", "Cache-Control": "public, max-age=3600" },
  });
}
