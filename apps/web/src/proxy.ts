import { NextRequest, NextResponse } from "next/server";

import { configuredMapOrigins } from "@/lib/map-style";
import { retiredOrganizationSlugRedirect } from "@/lib/organization-slug-alias";
import { statusHostRewrite } from "@/lib/service-status";
import { isAppHost, isSitePath, lookupSiteHost, SITE_TAG_ORIGINS, siteRewritePath } from "@/lib/site-host";

type MediaOriginEnv = Record<string, string | undefined>;

export function configuredMediaOrigins(env: MediaOriginEnv = process.env) {
  return (env.NEXT_PUBLIC_MEDIA_ORIGIN ?? env.MINIO_PUBLIC_ENDPOINT ?? "http://media.localhost:18080")
    .split(/[\s,]+/)
    .map((origin) => origin.trim())
    .filter(Boolean)
    .join(" ");
}

export async function proxy(request: NextRequest) {
  // ADR-122: a retired organization slug permanently redirects to the
  // canonical one, preserving the rest of the path and the query.
  const retiredSlugTarget = await retiredOrganizationSlugRedirect(request.method, request.nextUrl);
  if (retiredSlugTarget) {
    return applySecurityHeaders(NextResponse.redirect(retiredSlugTarget, 308));
  }

  // ADR-354, ADR-388: a box's own domain serves its website from the root.
  const host = request.headers.get("host") ?? request.nextUrl.host;
  let siteDestination: string | null = null;
  let siteHost: string | null = null;
  if (!isAppHost(host)) {
    const site = await lookupSiteHost(host);
    if (site && !site.primary && site.primaryHost) {
      const target = new URL(request.nextUrl.toString());
      target.host = site.primaryHost;
      target.port = "";
      target.protocol = "https:";
      return applySecurityHeaders(NextResponse.redirect(target, 308));
    }
    if (site) {
      siteDestination = siteRewritePath(request.nextUrl.pathname, site.slug);
      siteHost = host;
    }
  }

  const nonce = Buffer.from(crypto.randomUUID()).toString("base64");
  const mediaOrigins = configuredMediaOrigins();
  const mapOrigins = configuredMapOrigins();
  const development = process.env.NODE_ENV !== "production";
  const tags = siteDestination || isSitePath(request.nextUrl.pathname) ? SITE_TAG_ORIGINS : null;

  const csp = [
    "default-src 'self'",
    // ADR-164: the anatomy atlas is meshopt-compressed and decoded in WebAssembly;
    // 'wasm-unsafe-eval' allows compiling WebAssembly only, not JavaScript eval.
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic' 'wasm-unsafe-eval'${development ? " 'unsafe-eval'" : ""}`,
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' data: blob: ${mediaOrigins} ${mapOrigins}${tags ? ` ${tags.img}` : ""}`,
    // ADR-157: post videos play from the media origin; compose previews a picked file from a blob.
    `media-src 'self' blob: ${mediaOrigins}`,
    "font-src 'self' data:",
    `connect-src 'self' ${mediaOrigins} ${mapOrigins} ws: wss:${tags ? ` ${tags.connect}` : ""}`,
    "worker-src 'self' blob:",
    ...(tags ? [`frame-src 'self' ${tags.frame}`] : []),
    "manifest-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    ...(development ? [] : ["upgrade-insecure-requests"]),
  ].join("; ");

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("Content-Security-Policy", csp);
  if (siteHost) requestHeaders.set("x-palee-site-host", siteHost);
  else requestHeaders.delete("x-palee-site-host");

  const organizationMatch = request.nextUrl.pathname.match(/^\/org\/[^/]+(\/.*)$/);
  // ADR-366: status.palee.app (STATUS_HOST) serves the status page at its root.
  const statusPage = statusHostRewrite(
    request.nextUrl.hostname,
    request.nextUrl.pathname,
    process.env.STATUS_HOST ?? "status.palee.app",
  );
  // The status emails' links carry ?confirm= / ?unsubscribe=, so keep the query.
  const destination = statusPage
    ? statusPage + request.nextUrl.search
    : (siteDestination ?? organizationMatch?.[1]);

  const response = destination
    ? NextResponse.rewrite(new URL(destination, request.url), {
        request: { headers: requestHeaders },
      })
    : NextResponse.next({ request: { headers: requestHeaders } });
  response.headers.set("Content-Security-Policy", csp);
  return applySecurityHeaders(response, destination ?? request.nextUrl.pathname);
}

/** ADR-206: pages a reset link opens never leak their URL to another site. */
const NO_REFERRER_PAGES = /^\/(?:reset-password|forgot-password)\/?$/;

function applySecurityHeaders(response: NextResponse, pathname = "") {
  response.headers.set(
    "Referrer-Policy",
    NO_REFERRER_PAGES.test(pathname) ? "no-referrer" : "strict-origin-when-cross-origin",
  );
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("Permissions-Policy", "camera=(self), microphone=(self), geolocation=(self)");
  return response;
}

export const config = {
  matcher: [
    {
      source: "/((?!api|socket|_next/static|_next/image|favicon.ico|sw-|manifest.webmanifest).*)",
    },
  ],
};
