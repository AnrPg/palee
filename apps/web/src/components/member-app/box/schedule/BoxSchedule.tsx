"use client";

import { ScheduleConsole } from "@/components/schedule/ScheduleConsole";
import { useSelectedMembershipRole } from "@/lib/membership-role";

import { MemberSchedule } from "./MemberSchedule";

/** Members get the Phase 2 Πρόγραμμα; staff keep the schedule console. */
export function BoxSchedule({
  initialOpenSlotId,
  initialOpenDay = null,
}: {
  initialOpenSlotId: string | null;
  initialOpenDay?: string | null;
}) {
  const { role, isLoading } = useSelectedMembershipRole();
  if (isLoading) return null;
  return role === "admin" ? (
    <ScheduleConsole initialOpenSlotId={initialOpenSlotId} initialOpenDay={initialOpenDay} />
  ) : (
    <MemberSchedule initialOpenSlotId={initialOpenSlotId} initialOpenDay={initialOpenDay} />
  );
}
