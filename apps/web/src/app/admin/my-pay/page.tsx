import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { MyPayView } from "@/components/admin/coach-pay/MyPay";

export const dynamic = "force-dynamic";

// «Οι αμοιβές μου» (ADR-341/382, mockup W1 s6 A): a staff member's own pay statements.
export default function AdminMyPayPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <Suspense>
        <MyPayView />
      </Suspense>
    </AuthGuard>
  );
}
