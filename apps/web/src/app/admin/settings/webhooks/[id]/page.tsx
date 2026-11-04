import { AuthGuard } from "@/components/auth-guard";
import { WebhookPage } from "@/components/integrations/WebhookPage";

export const dynamic = "force-dynamic";

/** Ρυθμίσεις › Συνδέσεις › Webhooks › one webhook (W10 screen 2 A, ADR-379). */
export default async function AdminWebhookPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;

  return (
    <AuthGuard roles={["admin"]}>
      <WebhookPage endpointId={id} />
    </AuthGuard>
  );
}
