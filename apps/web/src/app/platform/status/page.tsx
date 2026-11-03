import { AuthGuard } from "@/components/auth-guard";
import { PlatformStatusPage } from "@/components/platform/PlatformStatusPage";

export const dynamic = "force-dynamic";

export default function PlatformStatusRoute() {
  return (
    <AuthGuard>
      <PlatformStatusPage />
    </AuthGuard>
  );
}
