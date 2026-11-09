"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useState } from "react";

import {
  leaveProvider,
  MY_BILLING_QUERY_KEY,
  setMyAutoRenew,
  type BillingProvider,
  type BillingSubscription,
} from "@/api/my-billing";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { HubCard } from "@/components/member-app/HubParts";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { localDay } from "@/components/finance/standing";
import { boxChatHref } from "@/components/trials/box-chat-links";
import { ORGANIZATION_MEMBERSHIPS_KEY } from "@/lib/organization-slug";
import { formatMinorUnits } from "@/lib/finance-accounting";

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
 * the box's page, keeping the package they have.
 */
export function LeaveProviderCard({ provider }: { provider: BillingProvider }) {
  const t = useTranslations("Billing");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [askWhy, setAskWhy] = useState(false);
  const [reason, setReason] = useState("");
  const [today] = useState(() => localDay(new Date()));
  const kind = provider.kind === "coach" ? "coach" : "gym";
  const currency = provider.invoices[0]?.currency ?? provider.payments[0]?.currency ?? "EUR";

  const leave = useMutation({
    mutationFn: () => leaveProvider(token!, provider.slug, reason.trim() || null),
    onSuccess: async () => {
      setOpen(false);
      setReason("");
      setAskWhy(false);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: MY_BILLING_QUERY_KEY }),
        queryClient.invalidateQueries({ queryKey: ORGANIZATION_MEMBERSHIPS_KEY }),
      ]);
    },
  });

  const state = leaveState(provider, today);
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

  const chatSlug = provider.contact.box_chat_slug;
  const stays = [
    state.packageUntil ? { icon: "🎟️", text: t("leaveKeepsPackage", { date: formatDate(locale, state.packageUntil) }) } : null,
    state.commitmentUntil ? { icon: "📅", text: t("leaveKeepsCommitment", { date: formatDate(locale, state.commitmentUntil) }) } : null,
    state.owedCents > 0 ? { icon: "💶", text: t("leaveKeepsDebt", { amount: formatMinorUnits(locale, state.owedCents, currency) }) } : null,
    kind === "gym" ? { icon: "👁️", text: t("leaveKeepsFollow") } : null,
  ].filter((entry): entry is { icon: string; text: string } => entry !== null);
  const listed = state.packageUntil || state.commitmentUntil || state.owedCents > 0;

  return (
    <>
      <button
        className="flex min-h-11 w-full items-center justify-center rounded-2xl px-4 text-sm font-semibold"
        onClick={() => { leave.reset(); setOpen(true); }}
        style={{ border: "1px solid var(--border)", color: "var(--danger)" }}
        type="button"
        data-testid="billing-leave"
      >
        {t("leaveTitle", { kind })}
      </button>
      {open ? (
        <Dialog
          onClose={() => setOpen(false)}
          title={t("leaveDialogTitle", { kind, name: provider.name })}
          size="sm"
          footer={
            <>
              <DialogButton onClick={() => setOpen(false)}>{t("leaveCancel")}</DialogButton>
              <DialogButton tone="danger" disabled={leave.isPending || !token} onClick={() => leave.mutate()} testId="billing-leave-confirm">
                {t("leaveNow")}
              </DialogButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text)" }}>{t("leaveNowBody", { kind })}</p>
          {listed ? (
            <div className="mt-3 rounded-xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="billing-leave-stays">
              <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("leaveWhatStays")}</p>
              <ul className="mt-2 flex flex-col gap-2 text-sm" style={{ color: "var(--text)" }}>
                {stays.map((entry) => (
                  <li key={entry.icon} className="flex gap-2">
                    <span aria-hidden="true">{entry.icon}</span>
                    <span className="min-w-0">{entry.text}</span>
                  </li>
                ))}
              </ul>
            </div>
          ) : kind === "gym" ? (
            <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("leaveKeepsFollow")}</p>
          ) : null}
          {askWhy ? (
            <label className="mt-4 block text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
              {t("leaveReason", { kind })}
              <textarea
                autoFocus
                className="mt-1 min-h-20 w-full rounded-xl px-3 py-2 text-sm"
                maxLength={500}
                onChange={(event) => setReason(event.target.value)}
                style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" }}
                value={reason}
              />
            </label>
          ) : (
            <button type="button" className="mt-3 text-xs font-semibold underline" style={{ color: "var(--text-soft)" }} onClick={() => setAskWhy(true)}>
              {t("leaveWhyLink")}
            </button>
          )}
          {chatSlug ? (
            <Link
              href={boxChatHref(chatSlug, "payment")}
              className="mt-4 flex min-h-11 w-full items-center justify-center rounded-2xl px-4 text-sm font-semibold"
              style={{ border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {t("leaveContact", { kind })}
            </Link>
          ) : null}
          {leave.isError ? <ErrorNotice variant="field">{localizeError(leave.error, ui)}</ErrorNotice> : null}
        </Dialog>
      ) : null}
    </>
  );
}
