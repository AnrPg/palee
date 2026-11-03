import { AuthGuard } from "@/components/auth-guard";
import { MyRanksPage } from "@/components/body-devices/MyRanksPage";

export const dynamic = "force-dynamic";

export default function RanksPage() {
  return (
    <AuthGuard roles={["member", "athlete"]}>
      <MyRanksPage />
    </AuthGuard>
  );
}
