import { AuthGuard } from "@/components/auth-guard";
import { ProgressResetHistory } from "@/components/member-app/progress/ProgressResetHistory";

export const dynamic = "force-dynamic";

/** Εγώ › Ρυθμίσεις › Τα δεδομένα σου › Ιστορικό μηδενισμών (ADR-462 §5). */
export default function ProgressResetsRoute() {
  return (
    <AuthGuard>
      <ProgressResetHistory />
    </AuthGuard>
  );
}
