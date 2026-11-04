import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { SiteTranslations } from "@/components/box-site/SiteTranslations";

export const dynamic = "force-dynamic";

/** Ρυθμίσεις › Ιστοσελίδα › Μεταφράσεις (ADR-520). */
export default function AdminWebsiteTranslationsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <Suspense>
        <SiteTranslations />
      </Suspense>
    </AuthGuard>
  );
}
