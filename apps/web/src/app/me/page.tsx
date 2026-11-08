import { Suspense } from "react";

import { AuthGuard } from "@/components/auth-guard";
import { MyProfile } from "@/components/social/MyProfile";

export const dynamic = "force-dynamic";

export default function MePage() {
  return (
    <AuthGuard roles={["member", "athlete"]} roleRedirects={{ admin: "/admin" }}>
      <Suspense>
        <MyProfile />
      </Suspense>
    </AuthGuard>
  );
}
