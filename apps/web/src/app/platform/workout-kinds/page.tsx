import { AuthGuard } from "@/components/auth-guard";
import { PlatformWorkoutKinds } from "@/components/platform/PlatformWorkoutKinds";

export const dynamic = "force-dynamic";

export default function PlatformWorkoutKindsRoute() {
  return (
    <AuthGuard>
      <PlatformWorkoutKinds />
    </AuthGuard>
  );
}
