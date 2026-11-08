import type { Metadata } from "next";

import { AuthGuard } from "@/components/auth-guard";
import { ProductOverview } from "@/components/about/ProductOverview";
import { Home } from "@/components/home";
import { GuestHome } from "@/components/landing/GuestHome";
import { loadSiteFacts } from "@/lib/seo/site-facts";

export const dynamic = "force-dynamic";

export const metadata: Metadata = { alternates: { canonical: "/" } };

export default async function HomeRoute() {
  const { facts, faq } = await loadSiteFacts();
  return (
    <>
      {/* The session lives in the browser, so the server cannot tell a guest
          from a member; crawlers that skip JavaScript read the overview here
          instead of the "restoring session" placeholder. */}
      <noscript>
        <ProductOverview faq={faq} features={facts.features} />
      </noscript>
      {/* ADR-555: guests get the landing here instead of a redirect to /login. */}
      <GuestHome>
        <AuthGuard roleRedirects={{ admin: "/admin" }}>
          <Home />
        </AuthGuard>
      </GuestHome>
    </>
  );
}
