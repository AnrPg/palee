"use client";

import { useQuery } from "@tanstack/react-query";

import { listAdminLocations } from "@/api/facility";
import { fetchFinancePackages } from "@/api/finance";
import { listAdminClassTypes } from "@/api/schedule";
import { fetchGymStaff } from "@/api/staff";
import { useSession } from "@/components/session-provider";

export type DirectoryOption = { value: string; label: string };

export type AnalyticsDirectory = {
  locations: DirectoryOption[];
  classTypes: DirectoryOption[];
  coaches: DirectoryOption[];
  packages: DirectoryOption[];
  /** Package name by code (the revenue-per-package rows carry the code). */
  packageNameByCode: Map<string, string>;
  /** Staff name by user id (coach rows, reset history). */
  staffName: Map<string, string>;
};

function text(value: unknown) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

/**
 * The box's own lists the analytics filters offer (branches, class types,
 * coaches, subscription packages), from the endpoints the console already
 * uses and under their query keys, so they come from the cache. Missing or
 * malformed answers give empty lists.
 */
export function useAnalyticsDirectory(): AnalyticsDirectory {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const enabled = Boolean(token);

  const locations = useQuery({ queryKey: ["admin", "locations"], enabled, queryFn: () => listAdminLocations(token) });
  const classTypes = useQuery({ queryKey: ["admin", "class-types"], enabled, queryFn: () => listAdminClassTypes(token) });
  const staff = useQuery({ queryKey: ["staff", "members"], enabled, queryFn: () => fetchGymStaff(token), staleTime: 5 * 60 * 1000 });
  const packages = useQuery({ queryKey: ["admin", "finance", "packages"], enabled, queryFn: () => fetchFinancePackages(token) });

  const locationRows = Array.isArray(locations.data) ? locations.data : [];
  const classTypeRows = Array.isArray(classTypes.data) ? classTypes.data : [];
  const staffRows = Array.isArray(staff.data) ? staff.data : [];
  const packageRows = Array.isArray(packages.data?.packages) ? packages.data.packages : [];

  const staffName = new Map<string, string>();
  for (const member of staffRows) {
    const name = text(member?.nickname);
    if (member && typeof member.user_id === "string" && name) staffName.set(member.user_id, name);
  }

  const packageNameByCode = new Map<string, string>();
  const packageOptions: DirectoryOption[] = [];
  for (const row of packageRows) {
    const id = text(row?.id);
    const name = text(row?.name);
    const code = text(row?.code);
    if (code && name) packageNameByCode.set(code, name);
    if (id && name && !row?.archived_at) packageOptions.push({ value: id, label: name });
  }

  return {
    locations: locationRows
      .filter((location) => location && !location.archived_at && text(location.name))
      .map((location) => ({ value: location.id, label: location.name })),
    classTypes: classTypeRows
      .filter((type) => type && !type.archived_at && text(type.name))
      .map((type) => ({ value: type.id, label: type.name })),
    coaches: staffRows
      .filter((member) => member && (member.role === "coach" || (Array.isArray(member.roles) && member.roles.includes("coach"))))
      .map((member) => ({ value: member.user_id, label: text(member.nickname) ?? member.user_id })),
    packages: packageOptions,
    packageNameByCode,
    staffName,
  };
}
