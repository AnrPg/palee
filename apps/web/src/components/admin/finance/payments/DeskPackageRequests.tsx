"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useState, type ReactNode } from "react";

import type { ReceivedPayment } from "@/api/finance";
import {
  activateUnpaidPackageRequest,
  COLLECT_METHODS,
  collectPackageRequest,
  DECLINE_REASON_MAX,
  declinePackageRequest,
  deskPackageRequestsKey,
  fetchDeskPackageRequests,
  fetchPackageRuleRollout,
  packageRuleRolloutKey,
  type CollectPaymentMethod,
  type DeskPackageRequest,
} from "@/api/package-requests";
import { holdDateLabel } from "@/components/payments/desk-payment";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { ReceivedView } from "./ReceivePaymentDialog";

/*
 * ADR-291 (mockup «Υποδοχή · Εκκρεμότητες»): «Περιμένουν πληρωμή», the
 * packages people asked for in the app. Each row names the person and opens
 * their account.
 *
 * ADR-633: «Ενεργοποίηση» is either «Εισπράχθηκαν X €» (the money is
 * recorded and the package starts today) or «Εκκρεμεί πληρωμή» (the package
 * starts today and its charge stays owed, so reminders, grace days and the
 * lock follow it). «Απόρριψη» always says why; the member reads it.
 */

export function useDeskPackageRequests(locationIds: string | undefined, enabled = true) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const slug = useOrganizationSlug();
  return useQuery({
    queryKey: deskPackageRequestsKey(slug ?? "none", locationIds ?? null),
    enabled: Boolean(token && slug && enabled),
    queryFn: () => fetchDeskPackageRequests(token!, slug!, locationIds ?? null),
    retry: false,
  });
}

/** The person a row is for, as a link to their account. */
export function PersonLink({ userId, name, handle }: { userId: string | null | undefined; name: string; handle?: string | null }) {
  const slug = useOrganizationSlug();
  if (!userId) return <span className="font-semibold" style={{ color: "var(--text)" }}>{name}</span>;
  return (
    <Link
      href={adminHref(`/admin/users/${encodeURIComponent(userId)}`, slug)}
      className="font-semibold underline-offset-2 hover:underline"
      style={{ color: "var(--text)" }}
      data-testid="queue-person-link"
    >
      {name}
      {handle ? <span className="font-normal" style={{ color: "var(--muted)" }}> @{handle}</span> : null}
    </Link>
  );
}

export function DeskPackageRequestRows({
  rows,
  empty,
  canAct = true,
}: {
  rows: DeskPackageRequest[];
  empty?: ReactNode;
  canAct?: boolean;
}) {
  const t = useTranslations("DeskPay");
  const locale = useUiLocale();
  const [activating, setActivating] = useState<DeskPackageRequest | null>(null);
  const [declining, setDeclining] = useState<DeskPackageRequest | null>(null);

  return (
    <>
      {rows.length === 0 ? empty : null}
      {rows.map((row, index) => {
        const amount = new Intl.NumberFormat(locale, { style: "currency", currency: row.currency }).format(row.price_cents / 100);
        const name = row.person?.display_name || row.person?.handle || t("someone");
        return (
          <div
            key={row.id}
            className="flex flex-wrap items-center justify-between gap-x-5 gap-y-3 px-6 py-4 text-sm"
            style={{ borderBottom: index === rows.length - 1 ? "none" : "1px solid var(--border)" }}
            data-testid={`desk-request-${row.id}`}
          >
            <span className="flex min-w-0 flex-[1_1_16rem] items-center gap-3">
              <Avatar url={row.person?.avatar_url ?? null} name={name} />
              <span className="flex min-w-0 flex-col">
                <PersonLink userId={row.user_id} name={name} handle={row.person?.handle} />
                <span className="text-xs" style={{ color: "var(--muted)" }}>
                  {t("askedOn", { date: new Date(row.requested_at).toLocaleDateString(locale, { day: "numeric", month: "short" }) })}
                </span>
              </span>
            </span>
            <span className="flex min-w-0 flex-[1_1_12rem] flex-col">
              <span className="font-semibold" style={{ color: "var(--text)" }}>{row.package_name} · {amount}</span>
              <span className="text-xs" style={{ color: "var(--muted)" }}>
                {t("removedIn", { days: row.days_left, date: holdDateLabel(locale, row.hold_until) })}
              </span>
              {row.first_class_at ? (
                <span className="text-xs font-semibold" style={{ color: "var(--amber)" }} data-testid={`desk-first-class-${row.id}`}>
                  {t("firstClassBooked")}
                </span>
              ) : null}
            </span>
            {canAct ? (
              <span className="flex flex-wrap gap-2">
                <button
                  type="button"
                  onClick={() => setDeclining(row)}
                  className="min-h-11 rounded-2xl px-4 text-sm font-semibold"
                  style={{ background: "transparent", color: "var(--text-soft)", border: "1px solid var(--border)" }}
                  data-testid={`desk-decline-${row.id}`}
                >
                  {t("decline")}
                </button>
                <button
                  type="button"
                  onClick={() => setActivating(row)}
                  className="min-h-11 rounded-2xl px-4 text-sm font-bold"
                  style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
                  data-testid={`desk-collect-${row.id}`}
                >
                  {t("activate")}
                </button>
              </span>
            ) : null}
          </div>
        );
      })}
      {activating ? <ActivateDialog request={activating} onClose={() => setActivating(null)} /> : null}
      {declining ? <DeclineDialog request={declining} onClose={() => setDeclining(null)} /> : null}
    </>
  );
}

/** ADR-633 «Μετάβαση»: who trains on the rule's 14 free days, and until when. */
export function PackageRuleRolloutList() {
  const t = useTranslations("DeskPay");
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const slug = useOrganizationSlug();
  const query = useQuery({
    queryKey: packageRuleRolloutKey(slug ?? "none"),
    enabled: Boolean(token && slug),
    queryFn: () => fetchPackageRuleRollout(token!, slug!),
    retry: false,
  });
  const people = query.data?.people ?? [];
  const since = query.data?.since;
  if (!since || people.length === 0) return null;

  const day = (iso: string | null | undefined) => (iso ? holdDateLabel(locale, iso) : "");

  return (
    <section className="px-6 py-4" style={{ borderTop: "1px solid var(--border)" }} data-testid="package-rule-rollout">
      <h3 className="text-sm font-bold" style={{ color: "var(--text)" }}>{t("rolloutTitle")}</h3>
      <p className="mt-1 text-xs" style={{ color: "var(--muted)" }}>
        {t("rolloutBody", { date: new Date(since).toLocaleDateString(locale, { day: "numeric", month: "long" }) })}
      </p>
      <ul className="mt-3 flex flex-col gap-2">
        {people.map((person) => (
          <li key={person.user_id} className="flex flex-wrap items-center justify-between gap-2 text-sm" data-testid={`package-rule-person-${person.user_id}`}>
            <PersonLink userId={person.user_id} name={person.display_name || person.handle || t("someone")} handle={person.handle} />
            <span className="text-xs font-semibold" style={{ color: person.has_package ? "var(--success)" : "var(--muted)" }}>
              {person.has_package ? t("rolloutHasPackage") : t("rolloutUntil", { date: day(person.ends_on) })}
            </span>
          </li>
        ))}
      </ul>
    </section>
  );
}

function Avatar({ url, name }: { url: string | null; name: string }) {
  const initials = name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((word) => word.charAt(0).toUpperCase())
    .join("");
  return url ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={url} alt="" className="h-10 w-10 shrink-0 rounded-full object-cover" />
  ) : (
    <span aria-hidden="true" className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-xs font-extrabold" style={{ background: "var(--panel-muted)", color: "var(--text)" }}>
      {initials}
    </span>
  );
}

/**
 * «Ενεργοποίηση»: «Εισπράχθηκαν X €» (how the money was handed over, then
 * the box's receipt or invoice) or «Εκκρεμεί πληρωμή» (the package starts
 * and the charge stays owed). Nothing is picked for staff.
 */
function ActivateDialog({ request, onClose }: { request: DeskPackageRequest; onClose: () => void }) {
  const t = useTranslations("DeskPay");
  const tReceive = useTranslations("ReceivePayment");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const [how, setHow] = useState<"paid" | "unpaid" | null>(null);
  const [method, setMethod] = useState<CollectPaymentMethod | null>(null);
  const [received, setReceived] = useState<ReceivedPayment | null>(null);
  const name = request.person?.display_name || request.person?.handle || t("someone");
  const money = (cents: number, currency = request.currency) =>
    new Intl.NumberFormat(locale, { style: "currency", currency }).format(cents / 100);
  const amount = money(request.price_cents);

  const refresh = () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: ["admin", "finance"] }),
      queryClient.invalidateQueries({ queryKey: ["admin", "users", request.user_id, "finance"] }),
    ]);

  const mutation = useMutation({
    mutationFn: async () => {
      if (how === "paid") {
        const result = await collectPackageRequest(tokens!.access_token, slug!, request.id, { payment_method: method! });
        return result.received as unknown as ReceivedPayment;
      }
      await activateUnpaidPackageRequest(tokens!.access_token, slug!, request.id);
      return null;
    },
    onSuccess: async (result) => {
      await refresh();
      if (result) setReceived(result);
      else onClose();
    },
  });

  if (received) return <ReceivedView received={received} nickname={name} money={money} onClose={onClose} />;

  const ready = how === "unpaid" || (how === "paid" && method !== null);
  const choice = (value: "paid" | "unpaid", label: string, hint: string) => {
    const on = how === value;
    return (
      <button
        type="button"
        role="radio"
        aria-checked={on}
        onClick={() => setHow(value)}
        className="flex w-full flex-col items-start gap-0.5 rounded-2xl px-4 py-3 text-start"
        style={{ background: on ? "color-mix(in srgb, var(--primary) 12%, transparent)" : "var(--panel)", border: `1px solid ${on ? "var(--primary)" : "var(--border)"}` }}
        data-testid={`desk-activate-${value}`}
      >
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{label}</span>
        <span className="text-xs" style={{ color: "var(--muted)" }}>{hint}</span>
      </button>
    );
  };

  return (
    <Dialog
      onClose={onClose}
      title={t("activateTitle")}
      description={name}
      size="sm"
      variant="center"
      dismissible={!mutation.isPending}
      error={mutation.isError ? localizeError(mutation.error, i18n) : undefined}
      testId="desk-collect"
      footer={
        <div className="flex flex-wrap w-full gap-2">
          <DialogButton onClick={onClose}>{t("close")}</DialogButton>
          <DialogButton tone="primary" disabled={!ready || mutation.isPending} onClick={() => mutation.mutate()} testId="desk-collect-confirm">
            {how === "unpaid" ? t("activateUnpaidConfirm") : t("activatePaid", { amount })}
          </DialogButton>
        </div>
      }
    >
      <div className="flex flex-col gap-3">
        <p className="text-sm" style={{ color: "var(--text)" }}>
          <b>{request.package_name}</b> · {amount}
        </p>
        <div role="radiogroup" aria-label={t("activateTitle")} className="flex flex-col gap-2">
          {choice("paid", t("activatePaid", { amount }), t("collectHint"))}
          {choice("unpaid", t("activateUnpaid"), t("activateUnpaidHint", { amount }))}
        </div>
        {how === "paid" ? (
          <div role="radiogroup" aria-label={tReceive("method")} className="flex flex-wrap gap-2">
            {COLLECT_METHODS.map((option) => {
              const on = option === method;
              return (
                <button
                  key={option}
                  type="button"
                  role="radio"
                  aria-checked={on}
                  onClick={() => setMethod(option)}
                  className="min-h-11 rounded-full px-3.5 text-sm font-semibold"
                  style={
                    on
                      ? { background: "var(--primary)", color: "var(--primary-contrast)", border: "1px solid var(--primary)" }
                      : { background: "transparent", color: "var(--text-soft)", border: "1px solid var(--border)" }
                  }
                  data-testid={`desk-method-${option}`}
                >
                  {tReceive(`method_${option}`)}
                </button>
              );
            })}
          </div>
        ) : null}
      </div>
    </Dialog>
  );
}

/** «Απόρριψη»: the reason is required; the member reads it. */
function DeclineDialog({ request, onClose }: { request: DeskPackageRequest; onClose: () => void }) {
  const t = useTranslations("DeskPay");
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const slug = useOrganizationSlug();
  const queryClient = useQueryClient();
  const [reason, setReason] = useState("");
  const name = request.person?.display_name || request.person?.handle || t("someone");
  const ready = reason.trim().length > 0 && reason.length <= DECLINE_REASON_MAX;

  const mutation = useMutation({
    mutationFn: () => declinePackageRequest(tokens!.access_token, slug!, request.id, { reason: reason.trim() }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
      onClose();
    },
  });

  return (
    <Dialog
      onClose={onClose}
      title={t("declineTitle")}
      description={`${name} · ${request.package_name}`}
      size="sm"
      variant="center"
      dismissible={!mutation.isPending}
      error={mutation.isError ? localizeError(mutation.error, i18n) : undefined}
      testId="desk-decline"
      footer={
        <div className="flex flex-wrap w-full gap-2">
          <DialogButton onClick={onClose}>{t("close")}</DialogButton>
          <DialogButton tone="primary" disabled={!ready || mutation.isPending} onClick={() => mutation.mutate()} testId="desk-decline-confirm">
            {t("declineConfirm")}
          </DialogButton>
        </div>
      }
    >
      <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
        {t("declineReason")}
        <textarea
          className="w-full rounded-xl px-3 py-2 text-sm font-normal"
          maxLength={DECLINE_REASON_MAX}
          onChange={(event) => setReason(event.target.value)}
          rows={3}
          style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" }}
          value={reason}
          data-testid="desk-decline-reason"
        />
      </label>
      <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("declineHint")}</p>
    </Dialog>
  );
}
