import type { Metadata } from "next";
import { getTranslations } from "next-intl/server";
import { Suspense } from "react";

import { StatusPage } from "@/components/status/StatusPage";

// ADR-364 / ADR-366: the public status page. Served at the status host's root
// (proxy.ts rewrites status.palee.app/ here) and at /status as a fallback.
export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations("ServiceStatus");
  const title = t("metaTitle");
  const description = t("metaDescription");
  return {
    title,
    description,
    alternates: { canonical: "/status" },
    openGraph: { title, description, url: "/status" },
  };
}

export default function StatusRoute() {
  return (
    <main className="flex w-full flex-1">
      <Suspense fallback={null}>
        <StatusPage />
      </Suspense>
    </main>
  );
}
