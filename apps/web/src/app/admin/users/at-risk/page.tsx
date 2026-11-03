import { AuthGuard } from "@/components/auth-guard";
import { MembersAtRisk } from "@/components/admin/at-risk/MembersAtRisk";

export const dynamic = "force-dynamic";

export default function AdminMembersAtRiskPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <MembersAtRisk />
    </AuthGuard>
  );
}
