import { AuthGuard } from "@/components/auth-guard";
import { AutomationsSettings } from "@/components/admin/automations/AutomationsSettings";

export const dynamic = "force-dynamic";

export default function AdminAutomationsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <AutomationsSettings />
    </AuthGuard>
  );
}
