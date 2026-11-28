import { Suspense } from "react";

import { ActivityLogPage } from "@/components/activity-log/ActivityLogPage";
import { AuthGuard } from "@/components/auth-guard";

export const dynamic = "force-dynamic";

/** Διαχείριση › Αρχείο ενεργειών (ADR-760). */
export default function AdminActivityLogPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <Suspense>
        <ActivityLogPage />
      </Suspense>
    </AuthGuard>
  );
}
