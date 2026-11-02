import { AuthGuard } from "@/components/auth-guard";
import { ReviewsSettings } from "@/components/box-site/ReviewsSettings";

export const dynamic = "force-dynamic";

/** Ρυθμίσεις › Κριτικές (ADR-386, ADR-387). */
export default function AdminReviewsSettingsPage() {
  return (
    <AuthGuard roles={["admin"]}>
      <ReviewsSettings />
    </AuthGuard>
  );
}
