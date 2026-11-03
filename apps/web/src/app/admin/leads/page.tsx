import { AuthGuard } from "@/components/auth-guard";
import { LeadsBoard } from "@/components/admin/leads/LeadsBoard";

export const dynamic = "force-dynamic";

export default function AdminLeadsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <LeadsBoard />
    </AuthGuard>
  );
}
