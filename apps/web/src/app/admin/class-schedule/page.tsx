
import {getUiTranslations} from "@/i18n/ui-server";
import { AuthGuard } from "@/components/auth-guard";
import { ScheduleConsole } from "@/components/schedule/ScheduleConsole";
import { scheduleDeepLink } from "@/components/schedule/deep-link";

export const dynamic = "force-dynamic";

export default async function AdminClassSchedulePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string>>;
}) {
  const i18n = await getUiTranslations();
  const link = scheduleDeepLink(await searchParams);
  return (
    <AuthGuard roles={["admin"]}>
      <ScheduleConsole pageTitle={i18n("classesed1846a")} initialOpenSlotId={link.slotId} initialOpenDay={link.day} />
    </AuthGuard>
  );
}
