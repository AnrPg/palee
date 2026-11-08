import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { PersonProfile } from "@/components/social/PersonProfile";

export const dynamic = "force-dynamic";

export default async function PersonRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return (
    <AuthGuard roles={["member", "athlete", "admin"]}>
      <Suspense>
        <PersonProfile id={id} />
      </Suspense>
    </AuthGuard>
  );
}
