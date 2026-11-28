"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";

import { acknowledgeMyPackageStart, MY_BILLING_QUERY_KEY, type BillingProvider, type BillingSubscription } from "@/api/my-billing";
import { PackageStartNotice } from "@/components/finance/PackageStartNotice";
import { useSession } from "@/components/session-provider";

/**
 * ADR-795: the member's package waits for their first class or WOD, or
 * changed meanwhile and starts with «Το κατάλαβα».
 */
export function MemberPackageStart({ provider, subscription }: { provider: BillingProvider; subscription: BillingSubscription }) {
  const token = useSession().tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const start = subscription.package_start ?? null;
  const acknowledge = useMutation({
    mutationFn: () => acknowledgeMyPackageStart(token!, provider.slug, start!.id),
    onSettled: () => queryClient.invalidateQueries({ queryKey: MY_BILLING_QUERY_KEY }),
  });
  if (!start) return null;

  return (
    <div className="mt-3">
      <PackageStartNotice
        start={start}
        audience="member"
        onAcknowledge={token ? () => acknowledge.mutate() : undefined}
        pending={acknowledge.isPending}
        error={acknowledge.error}
      />
    </div>
  );
}
