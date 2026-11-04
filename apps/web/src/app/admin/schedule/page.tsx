
import { AuthGuard } from "@/components/auth-guard";
import { ScheduleConsole } from "@/components/schedule/ScheduleConsole";
import { scheduleDeepLink } from "@/components/schedule/deep-link";

export const dynamic = "force-dynamic";

export default async function AdminSchedulePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string>>;
}) {
  const link = scheduleDeepLink(await searchParams);

  return (
    <AuthGuard roles={["admin"]}>
      <ScheduleConsole initialOpenSlotId={link.slotId} initialOpenDay={link.day} />
    </AuthGuard>
  );
}
