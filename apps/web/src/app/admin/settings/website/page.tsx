import { AuthGuard } from "@/components/auth-guard";
import { WebsiteSettings } from "@/components/box-site/WebsiteSettings";

export const dynamic = "force-dynamic";

/** Ρυθμίσεις › Ιστοσελίδα (ADR-352..354, ADR-388). */
export default function AdminWebsiteSettingsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <WebsiteSettings />
    </AuthGuard>
  );
}
