import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { PartnerPerksPage } from "@/components/admin/marketing/MarketingAreas";

export const dynamic = "force-dynamic";

export default function AdminMarketingPerksPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <Suspense>
        <PartnerPerksPage />
      </Suspense>
    </AuthGuard>
  );
}
