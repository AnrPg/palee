import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { ReferralsPage } from "@/components/admin/marketing/MarketingAreas";

export const dynamic = "force-dynamic";

export default function AdminMarketingReferralsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <Suspense>
        <ReferralsPage />
      </Suspense>
    </AuthGuard>
  );
}
