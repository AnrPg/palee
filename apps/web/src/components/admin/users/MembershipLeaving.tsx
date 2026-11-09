"use client";

import { useMutation } from "@tanstack/react-query";
import { useLocale } from "next-intl";
import { useState } from "react";

import { markFinanceMemberLeft, undoFinanceMemberLeft } from "@/api/finance";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { localIsoDate } from "@/components/admin/users/membership-freezes";
import { packageSubscriptionLabel } from "@/components/admin/users/admin-user-profile";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { ChangedMark } from "@/components/ui/ChangedMark";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

import { leaveRequest, renewableSubscriptions } from "./membership-leaving";

const fieldStyle = { background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" };

/**
 * ADR-220, staff side: each running package's «Αυτόματη ανανέωση» (the box
 * member decides it in the app; staff can change it for them) and ending
 * the box membership (ADR-595): the member's own rules, now; a package in
 * force stays usable to its last day, money owed stays owed, and the
 * member hears of it.
 *
 * ADR-276: the renewal switches are part of the Finance tab's unsaved edits;
 * the parent holds them and saves them with «Αποθήκευση». Leaving and its
 * undo stay their own confirmed steps.
 */
export function MembershipLeaving({
  token,
  userId,
  membership,
  subscriptions,
  autoRenew,
  onAutoRenewChange,
  changedRenewals,
  renewDisabled = false,
  onRefresh,
}: {
  token: string;
  userId: string;
  membership: Record<string, unknown>;
  subscriptions: Array<Record<string, unknown>>;
  /** The edited choice per subscription id. */
  autoRenew: Record<string, boolean>;
  onAutoRenewChange: (subscriptionId: string, next: boolean) => void;
  changedRenewals: ReadonlySet<string>;
  renewDisabled?: boolean;
  onRefresh: () => Promise<unknown>;
}) {
  const i18n = useUiTranslations();
  const locale = useLocale();
  const [form, setForm] = useState<{ reason: string } | null>(null);
  const today = localIsoDate();
  const formatDay = (value: unknown) =>
    typeof value === "string" && value
      ? new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeZone: "UTC" }).format(new Date(Date.parse(value.slice(0, 10))))
      : "—";

  const leave = useMutation({
    mutationFn: () => markFinanceMemberLeft(token, userId, leaveRequest(form!.reason)),
    onSuccess: async () => {
      setForm(null);
      await onRefresh();
    },
  });
  const undo = useMutation({ mutationFn: () => undoFinanceMemberLeft(token, userId), onSuccess: () => onRefresh() });

  const leavingOn = typeof membership.leaving_on === "string" ? membership.leaving_on : null;
  const renewable = renewableSubscriptions(subscriptions);

  return (
    <div className="space-y-3 rounded-[1.25rem] p-4" style={{ border: "1px solid var(--border)" }} data-testid="admin-membership-leaving">
      {renewable.map((subscription) => {
        const id = String(subscription.id);
        const checked = autoRenew[id] ?? subscription.auto_renew === true;
        return (
          <div key={id} data-changed={changedRenewals.has(id) ? "true" : undefined}>
            <Switch
              checked={checked}
              disabled={renewDisabled || Boolean(leavingOn)}
              label={`${i18n("admRenewalTitle")} · ${packageSubscriptionLabel(subscription)}`}
              hint={checked ? i18n("admRenewalOnHint") : i18n("admRenewalOffHint", { date: formatDay(subscription.ends_on) })}
              onChange={(next) => onAutoRenewChange(id, next)}
            />
            {changedRenewals.has(id) ? <ChangedMark /> : null}
            {subscription.renewal_changed_by ? (
              <p className="text-xs" style={{ color: "var(--muted)" }}>
                {i18n("admRenewalChangedBy", { who: String(subscription.renewal_changed_by), date: formatDay(subscription.renewal_changed_at) })}
              </p>
            ) : null}
          </div>
        );
      })}

      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="font-semibold" style={{ color: "var(--text)" }}>{i18n("admLeaveTitle")}</p>
          {leavingOn ? (
            <p className="text-xs" style={{ color: "var(--muted)" }} data-testid="admin-leaving-on">
              {i18n(leavingOn < today ? "admLeftOn" : "admLeavingOn", { date: formatDay(leavingOn) })} ·{" "}
              {i18n("admLeaveBy", { who: String(membership.left_by ?? "staff") })}
              {typeof membership.leave_reason === "string" && membership.leave_reason ? ` · ${membership.leave_reason}` : ""}
            </p>
          ) : null}
        </div>
        {leavingOn ? (
          <button className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50" disabled={undo.isPending} onClick={() => undo.mutate()} style={{ background: "var(--border)", color: "var(--text-soft)" }} type="button">
            {i18n("admLeaveUndo")}
          </button>
        ) : !form ? (
          <button
            className="rounded-full px-4 py-2 text-xs font-semibold"
            onClick={() => { leave.reset(); setForm({ reason: "" }); }}
            style={{ border: "1px solid var(--border)", color: "var(--danger)" }}
            type="button"
            data-testid="admin-leave-open"
          >
            {i18n("admLeaveMark")}
          </button>
        ) : null}
      </div>
      {undo.isError ? <ErrorNotice variant="field">{localizeError(undo.error, i18n)}</ErrorNotice> : null}

      {form ? (
        <form className="space-y-3 rounded-2xl p-4" onSubmit={(event) => { event.preventDefault(); leave.mutate(); }} style={{ border: "1px solid var(--border)" }}>
          <p className="text-xs" style={{ color: "var(--muted)" }}>{i18n("admLeaveHint")}</p>
          <input
            aria-label={i18n("admLeaveReason")}
            className="w-full rounded-xl px-3 py-2"
            maxLength={500}
            onChange={(event) => setForm({ reason: event.target.value })}
            placeholder={i18n("admLeaveReason")}
            style={fieldStyle}
            value={form.reason}
          />
          <div className="flex flex-wrap gap-2">
            <button className="rounded-full px-4 py-2 text-xs font-semibold disabled:opacity-50" disabled={leave.isPending} style={{ background: "var(--danger)", color: "var(--danger-contrast)" }} type="submit" data-testid="admin-leave-confirm">
              {i18n("admLeaveMark")}
            </button>
            <button className="rounded-full px-4 py-2 text-xs font-semibold" onClick={() => setForm(null)} style={{ background: "var(--border)", color: "var(--text-soft)" }} type="button">
              {i18n("cancel77dfd21")}
            </button>
          </div>
          {leave.isError ? <ErrorNotice variant="field">{localizeError(leave.error, i18n)}</ErrorNotice> : null}
        </form>
      ) : null}
    </div>
  );
}
