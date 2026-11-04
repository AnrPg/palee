import { AuthGuard } from "@/components/auth-guard";
import { PlatformFoodMissesPage } from "@/components/platform/PlatformFoodMissesPage";

export const dynamic = "force-dynamic";

export default function PlatformFoodMissesRoute() {
  return (
    <AuthGuard>
      <PlatformFoodMissesPage />
    </AuthGuard>
  );
}
