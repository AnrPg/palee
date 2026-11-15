"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useState } from "react";

import {
  MY_BILLING_QUERY_KEY,
  setMyAutoRenew,
  type BillingProvider,
  type BillingSubscription,
} from "@/api/my-billing";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { localDay } from "@/components/finance/standing";

import { LeaveBoxDialog } from "@/components/membership/BoxRelation";

import { leaveState } from "./billing-model";

/**
 * ADR-220: the member's own «Αυτόματη ανανέωση» for their current package.
 * Off: the package ends with the period they paid for and no new invoice
 * is issued; they can turn it back on until then.
 */
export function RenewalSwitch({ provider, subscription }: { provider: BillingProvider; subscription: BillingSubscription }) {
  const t = useTranslations("Billing");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const change = useMutation({
    mutationFn: (next: boolean) => setMyAutoRenew(token!, provider.slug, subscription.id, next),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: MY_BILLING_QUERY_KEY }),
  });

  const on = subscription.auto_renew === true;
  const hint = on
    ? t("autoRenewHintOn")
    : t("autoRenewHintOff", { date: formatDate(locale, subscription.ends_on) });

  return (
    <div className="mt-3 border-t pt-3" style={{ borderColor: "var(--border)" }} data-testid="billing-auto-renew">
      <Switch
        checked={on}
        disabled={change.isPending || !token}
        label={t("autoRenew")}
        hint={hint}
        onChange={(next) => change.mutate(next)}
      />
      {change.isError ? <ErrorNotice variant="field">{localizeError(change.error, ui)}</ErrorNotice> : null}
    </div>
  );
}

/**
 * ADR-595: leaving the box (or ending with an independent coach) happens at
 * once: the person is no longer a member and is free to join another box.
 * One dialog says what stays: a package in force stays usable to its last
 * day (a minimum commitment's months stay owed), money owed stays owed and
 * following the box is untouched. There is no undo: they join again from
 * the box's page, keeping the package they have. The dialog itself is the
 * one the box page uses (`membership/BoxRelation`), «Έγινε» step included.
 */
export function LeaveProviderCard({ provider }: { provider: BillingProvider }) {
  const t = useTranslations("Billing");
  const locale = useUiLocale();
  const [open, setOpen] = useState(false);
  const [today] = useState(() => localDay(new Date()));
  const kind = provider.kind === "coach" ? "coach" : "gym";

  const state = leaveState(provider, today);
  // The dialog stays while it shows «Έγινε», although the section already says «left».
  if (open)
    return (
      <LeaveBoxDialog
        box={{ slug: provider.slug, name: provider.name, organizationId: provider.organization_id, kind }}
        provider={provider}
        onClose={() => setOpen(false)}
      />
    );
  if (state.kind === "none") return null;

  if (state.kind === "left") {
    return (
      <HubCard eyebrow={t("leftTitle", { kind })}>
        <div className="flex min-w-0 flex-col gap-1 text-sm" style={{ color: "var(--text)" }} data-testid="billing-leaving">
          <p>{t(state.byStaff ? "leftByProvider" : "leftBody", { kind })}</p>
          {state.packageUntil ? <p>{t("leftPackageUntil", { date: formatDate(locale, state.packageUntil) })}</p> : null}
        </div>
        {kind === "gym" ? (
          <Link
            href={`/b/${encodeURIComponent(provider.slug)}`}
            className="mt-3 flex min-h-11 w-full items-center justify-center rounded-2xl px-4 text-sm font-bold"
            style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            data-testid="billing-rejoin"
          >
            {t("rejoinBox")}
          </Link>
        ) : null}
      </HubCard>
    );
  }

  return (
    <button
      className="flex min-h-11 w-full items-center justify-center rounded-2xl px-4 text-sm font-semibold"
      onClick={() => setOpen(true)}
      style={{ border: "1px solid var(--border)", color: "var(--danger)" }}
      type="button"
      data-testid="billing-leave"
    >
      {t("leaveTitle", { kind })}
    </button>
  );
}
