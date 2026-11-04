import { AuthGuard } from "@/components/auth-guard";
import { PlatformReviewReportsPage } from "@/components/platform/PlatformReviewReportsPage";

export const dynamic = "force-dynamic";

export default function PlatformReviewReportsRoute() {
  return (
    <AuthGuard>
      <PlatformReviewReportsPage />
    </AuthGuard>
  );
}
