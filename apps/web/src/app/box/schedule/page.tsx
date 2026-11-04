import { AuthGuard } from "@/components/auth-guard";
import { BoxSchedule } from "@/components/member-app/box/schedule/BoxSchedule";
import { scheduleDeepLink } from "@/components/schedule/deep-link";

export const dynamic = "force-dynamic";

export default async function SchedulePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string>>;
}) {
  const link = scheduleDeepLink(await searchParams);
  return (
    <AuthGuard roles={["member", "admin"]}>
      <BoxSchedule initialOpenSlotId={link.slotId} initialOpenDay={link.day} />
    </AuthGuard>
  );
}
