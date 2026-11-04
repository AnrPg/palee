import { AuthGuard } from "@/components/auth-guard";
import { PlatformExerciseCandidatesPage } from "@/components/platform/PlatformExerciseCandidatesPage";

export const dynamic = "force-dynamic";

export default function PlatformExerciseCandidatesRoute() {
  return (
    <AuthGuard>
      <PlatformExerciseCandidatesPage />
    </AuthGuard>
  );
}
