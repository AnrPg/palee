"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { declineFollowerInvite, fetchMyFollowerInvite, myFollowerInviteKey } from "@/api/follower-invites";
import { clientErrorMessage } from "@/components/client/errors";
import { perLabel } from "@/components/payments/BuyPackageSheet";
import { money } from "@/components/payments/PackageCheckout";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

import { Icon } from "./Icon";

/**
 * ADR-580: the box's invitation to someone who follows it, on the box page.
 * It carries the box's words, the package it suggests and whether a trial
 * is offered; «Γίνε μέλος box» and the trial button right below are the way
 * in (ADR-552), so the notice adds only «Όχι, ευχαριστώ», which stops
 * further invitations from this box. Nothing shows without an invitation.
 */
export function FollowerInviteNotice({ token, slug }: { token: string; slug: string }) {
  const t = useTranslations("BoxPage");
  const tPay = useTranslations("Pay");
  const tUi = useUiTranslations();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const invite = useQuery({
    queryKey: myFollowerInviteKey(slug),
    queryFn: () => fetchMyFollowerInvite(token, slug),
  });
  const decline = useMutation({
    mutationFn: () => declineFollowerInvite(token, slug),
    onSuccess: () => queryClient.setQueryData(myFollowerInviteKey(slug), null),
  });
  const data = invite.data;
  if (!data) return null;
  const pkg = data.package;

  return (
    <section
      aria-labelledby="box-invite-title"
      className="mx-4 mt-4 flex flex-col gap-3 rounded-3xl p-4 lg:mx-0"
      style={{
        background: "linear-gradient(135deg, color-mix(in srgb, var(--primary) 22%, var(--panel)), color-mix(in srgb, var(--spark) 14%, var(--panel)))",
        border: "1px solid var(--primary)",
      }}
      data-testid="box-follower-invite"
    >
      <div className="flex items-start gap-3">
        <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}>
          <Icon name="mail" size={18} />
        </span>
        <div className="min-w-0 flex-1">
          <h2 id="box-invite-title" className="text-base font-extrabold" style={{ color: "var(--text)" }}>
            {t("inviteTitle", { box: data.box.name })}
          </h2>
          {data.message ? (
            <p className="whitespace-pre-line text-sm" style={{ color: "var(--text)" }}>«{data.message}»</p>
          ) : null}
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            {data.offer_trial ? t("inviteBodyTrial") : t("inviteBody")}
          </p>
        </div>
      </div>
      {pkg ? (
        <p
          className="flex items-center justify-between gap-3 rounded-2xl px-3 py-2 text-sm"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
          data-testid="box-follower-invite-package"
        >
          <span className="min-w-0 truncate font-bold">{pkg.name}</span>
          <span className="shrink-0 tabular-nums" style={{ color: "var(--text-soft)" }}>
            {money(locale, pkg.price_cents, pkg.currency)}
            {pkg.billing_period ? ` ${perLabel(tPay, pkg.billing_period)}` : ""}
          </span>
        </p>
      ) : null}
      <button
        type="button"
        disabled={decline.isPending}
        onClick={() => decline.mutate()}
        className="min-h-11 self-start rounded-2xl px-4 text-sm font-semibold disabled:opacity-50"
        style={{ border: "1px solid var(--border)", color: "var(--text)", background: "var(--panel)" }}
        data-testid="box-follower-invite-decline"
      >
        {t("inviteDecline")}
      </button>
      {decline.error ? <ErrorNotice>{clientErrorMessage(decline.error, tUi)}</ErrorNotice> : null}
    </section>
  );
}
