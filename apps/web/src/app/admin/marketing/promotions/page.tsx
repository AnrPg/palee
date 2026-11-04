import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { BoxPromotionsPage } from "@/components/admin/marketing/MarketingAreas";

export const dynamic = "force-dynamic";

export default function AdminMarketingPromotionsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <Suspense>
        <BoxPromotionsPage />
      </Suspense>
    </AuthGuard>
  );
}
