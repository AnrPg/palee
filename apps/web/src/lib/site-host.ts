import { apiOriginForProxy } from "@/lib/organization-slug-alias";

/**
 * A box's website on its own domain (ADR-354, ADR-388). The proxy asks the
 * API which box a host belongs to, serves that box's site pages under the
 * host's root, and sends a secondary domain to the primary one.
 */

export type SiteHost = { slug: string; primaryHost: string | null; primary: boolean };
type CacheEntry = { value: SiteHost | null; expiresAt: number };

const POSITIVE_TTL_MS = 5 * 60_000;
const NEGATIVE_TTL_MS = 60_000;
const defaultCache = new Map<string, CacheEntry>();

/** The site's own pages, served under a custom host's root. */
const SITE_PATHS = /^\/(?:en|privacy|packages)?\/?$/;

/** Hosts the app itself answers on: never looked up as a box's domain. */
export function isAppHost(host: string, env: Record<string, string | undefined> = process.env) {
  const name = host.split(":")[0]!.toLowerCase();
  if (!name || name === "localhost" || name.endsWith(".localhost") || /^[\d.]+$/.test(name) || name.includes("[")) return true;
  if (name === "palee.app" || name.endsWith(".palee.app")) return true;
  const configured = [env.NEXT_PUBLIC_SITE_URL, env.STATUS_HOST, ...(env.PALEE_APP_HOSTS ?? "").split(/[\s,]+/)]
    .map((entry) => entry?.trim())
    .filter(Boolean)
    .map((entry) => {
      try {
        return new URL(entry!.includes("://") ? entry! : `https://${entry}`).hostname.toLowerCase();
      } catch {
        return "";
      }
    });
  return configured.includes(name);
}

/** The app path a custom host's path is served from, or null when the path is not one of the site's. */
export function siteRewritePath(pathname: string, slug: string) {
  if (!SITE_PATHS.test(pathname)) return null;
  const rest = pathname.replace(/\/$/, "");
  return `/b/${slug}${rest}`;
}

/**
 * A page of the app (an event, sign-in, a member screen) opened on a box's
 * own domain moves to the app's address, so the app never runs under the
 * box's name. Files (paths with an extension) stay, the site page needs them.
 */
export function appPageRedirect(pathname: string, search: string, env: Record<string, string | undefined> = process.env) {
  if (/\.[a-z0-9]+$/i.test(pathname) || pathname.startsWith("/_next/")) return null;
  const site = env.NEXT_PUBLIC_SITE_URL;
  if (!site) return null;
  try {
    const target = new URL(pathname + search, site.includes("://") ? site : `https://${site}`);
    return target.toString();
  } catch {
    return null;
  }
}

/** The box whose website a host serves, or null; cached per instance (correctness never depends on it). */
export async function lookupSiteHost(
  host: string,
  { apiOrigin = apiOriginForProxy(), fetchImpl = fetch, now = Date.now, cache = defaultCache }: { apiOrigin?: string; fetchImpl?: typeof fetch; now?: () => number; cache?: Map<string, CacheEntry> } = {},
): Promise<SiteHost | null> {
  const key = host.split(":")[0]!.toLowerCase();
  const cached = cache.get(key);
  if (cached && cached.expiresAt > now()) return cached.value;
  let value: SiteHost | null = null;
  try {
    const response = await fetchImpl(`${apiOrigin}/api/public/sites/by-host/${encodeURIComponent(key)}`, { headers: { accept: "application/json" } });
    if (response.ok) {
      const body = (await response.json()) as { slug: string; primary: boolean; primary_host: string | null };
      value = { slug: body.slug, primary: body.primary, primaryHost: body.primary_host };
    }
  } catch {
    // The API is unreachable: answer as an unknown host and try again soon.
  }
  cache.set(key, { value, expiresAt: now() + (value ? POSITIVE_TTL_MS : NEGATIVE_TTL_MS) });
  return value;
}

/** The origins a box's tags (GA4, GTM, Meta Pixel) reach, allowed only on website pages (ADR-354). */
export const SITE_TAG_ORIGINS = {
  img: "https://www.googletagmanager.com https://*.google-analytics.com https://*.analytics.google.com https://www.facebook.com",
  connect: "https://www.googletagmanager.com https://*.google-analytics.com https://*.analytics.google.com https://www.facebook.com https://connect.facebook.net",
  frame: "https://www.googletagmanager.com",
};

/** Whether a path is a box's website page (where the tags may load after consent). */
export function isSitePath(pathname: string) {
  return /^\/b\/[^/]+(?:\/en|\/privacy)?\/?$/.test(pathname);
}
