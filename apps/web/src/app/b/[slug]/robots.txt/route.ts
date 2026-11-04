import { loadWebsite, siteRootUrl } from "@/components/box-site/templates/site-server";

type Context = { params: Promise<{ slug: string }> };

/**
 * ADR-530 §5: `/robots.txt` on a box's own domain (the proxy serves it from
 * here): everything is open, AI answer engines included, and the sitemap
 * and llms.txt are the box's own.
 */
export async function GET(_request: Request, { params }: Context) {
  const { slug } = await params;
  const website = await loadWebsite(slug, "box");
  if (!website) return new Response("Not found", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  const root = await siteRootUrl(website.site, website.page.box.slug);
  const body = ["User-agent: *", "Allow: /", "", `Sitemap: ${root}/sitemap.xml`, ""].join("\n");
  return new Response(body, { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=3600" } });
}
