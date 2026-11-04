import { llmsText } from "@/components/box-site/templates/seo";
import { packageList } from "@/components/box-site/templates/site-data";
import { loadWebsite, siteRootUrl } from "@/components/box-site/templates/site-server";

// Reads the box from the API on each request; never prerendered at build time (the API is not there).
export const dynamic = "force-dynamic";

type Context = { params: Promise<{ slug: string }> };

/**
 * ADR-530 §5 (https://llmstxt.org): a plain Markdown summary of a box's
 * website for AI answer engines, also at `/llms.txt` on the box's domain.
 */
export async function GET(_request: Request, { params }: Context) {
  const { slug } = await params;
  const website = await loadWebsite(slug, "box");
  if (!website) return new Response("Not found", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } });
  const { page, site, visible, packagesData } = website;
  const root = await siteRootUrl(site, page.box.slug);
  return new Response(llmsText({ page, site, packages: packageList(packagesData), visible, root }), {
    headers: { "Content-Type": "text/markdown; charset=utf-8", "Cache-Control": "public, max-age=3600" },
  });
}
