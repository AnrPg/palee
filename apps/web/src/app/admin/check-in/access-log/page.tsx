import { AuthGuard } from "@/components/auth-guard";
import { AccessLogPage } from "@/components/doors/AccessLogPage";

export const dynamic = "force-dynamic";

/** «Ημερολόγιο εισόδων» (W10 screen 6 A, ADR-381): owners, branch managers and the front desk. */
export default function AdminAccessLogPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <AccessLogPage />
    </AuthGuard>
  );
}
