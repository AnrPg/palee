"use client";

import { useSelectedMembershipRole } from "@/lib/membership-role";
import { MARKETING_CAPABILITIES, type MarketingArea } from "@/lib/marketing-routes";
import { can } from "@/lib/role-navigation";

/** Finance opens for whoever takes payments, bills or reads finance reports. */
const FINANCE_PAGE_CAPABILITIES = ["take_payments", "manage_billing", "view_finance_reports"] as const;

/**
 * Which Marketing areas the selected membership opens. `ready` is false while
 * the memberships load, so nothing shows and then disappears; without a
 * membership (a platform vendor) everything shows, as on the staff home.
 */
export function useMarketingAccess() {
  const { membership, isLoading } = useSelectedMembershipRole();
  const any = (capabilities: readonly string[]) =>
    !isLoading && (!membership || capabilities.some((capability) => can(membership, capability)));
  return {
    ready: !isLoading,
    opens: (area: MarketingArea) => any(MARKETING_CAPABILITIES[area]),
    opensFinance: any(FINANCE_PAGE_CAPABILITIES),
  };
}
