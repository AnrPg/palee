"use client";






import {useUiLocale} from "@/i18n/use-ui-locale";
import {useUiTranslations} from "@/i18n/ui";
import { useCallback, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { useRouter, useSearchParams } from "next/navigation";
import { useTranslations } from "next-intl";

import { fetchFinanceQueues, type FinanceRecord } from "@/api/finance";
import { formatDateKey } from "@/lib/local-date";
import { offeredQueues, parseFinanceQueue, type FinanceQueue } from "@/components/admin/finance/finance-queues";
import { FailedChargesList, useFailedCharges } from "@/components/admin/payments/FailedCharges";
import { DeskPackageRequestRows, PackageRuleRolloutList, PersonLink, useDeskPackageRequests } from "@/components/admin/finance/payments/DeskPackageRequests";
import { ReceivePaymentDialog } from "@/components/admin/finance/payments/ReceivePaymentDialog";
import { useStatusLabel } from "@/components/admin/finance/shared/MemberStandingCells";
import { statusTone, toneStyle } from "@/components/admin/finance/shared/member-standing";
import { SemanticLabel } from "@/components/semantic-label";
import { useSession } from "@/components/session-provider";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";
import { useBusinessFeatures } from "@/lib/use-business-features";

type QueueKey = FinanceQueue;

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}

function dateText(uiLocale: string, value: unknown) {
  return formatDateKey(uiLocale, value) ?? "—";
}

/** `locationIds`: the page branch filter (ADR-186 §7). */
export function QueuesTab({ locationIds }: { locationIds?: string } = {}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const paymentsT = useTranslations("OnlinePayments");
  const receiveT = useTranslations("ReceivePayment");
  const standingT = useTranslations("MemberStanding");
  const deskT = useTranslations("DeskPay");
  const statusLabel = useStatusLabel();
  const [receiveFrom, setReceiveFrom] = useState<{ userId: string; nickname: string } | null>(null);
  const { membership } = useSelectedMembershipRole();
  const features = useBusinessFeatures({ locationIds });
  // ADR-260: saved-card charges that need a person, for whoever handles billing or takes payments.
  const seesFailedCharges = can(membership, "manage_billing") || can(membership, "take_payments");
  // ADR-274: one «Οφειλές» list (one row per person, oldest debt first)
  // replaces the separate pending-payment and overdue-invoice lists.
  // ADR-291: packages asked for in the app, waiting to be paid at the desk.
  const seesAwaiting = seesFailedCharges || can(membership, "view_finance_reports");
  const { tokens } = useSession();
  const token = tokens?.access_token;
  // The open list lives in the address (`?queue=`), so every alert and notice
  // that links here lands on the rows it counted, also when this tab is
  // already open, and Back returns to the list that was showing.
  const searchParams = useSearchParams();
  const router = useRouter();
  const requested = parseFinanceQueue(searchParams.get("queue"));
  const setActive = useCallback(
    (queue: QueueKey) => {
      const params = new URLSearchParams(searchParams.toString());
      params.set("queue", queue);
      router.replace(`?${params.toString()}`, { scroll: false });
    },
    [router, searchParams],
  );
  const failedQuery = useFailedCharges(token, seesFailedCharges);
  const awaitingQuery = useDeskPackageRequests(locationIds, seesAwaiting);
  const awaiting = awaitingQuery.data?.requests ?? [];

  // Same key and params as the page's attention summary, so both share one read.
  const queuesQuery = useQuery({
    queryKey: ["admin", "finance", "queues", locationIds ?? "all"],
    enabled: Boolean(token),
    queryFn: () =>
      fetchFinanceQueues(token!, { expires_within_days: "30", ...(locationIds ? { location_ids: locationIds } : {}) }),
  });

  const queues = (queuesQuery.data?.queues ?? {}) as Record<string, FinanceRecord[]>;

  const rowsByKey: Record<QueueKey, FinanceRecord[]> = {
    debts: queues.open_charges ?? [],
    expiring: queues.expiring_memberships ?? [],
    failed: (failedQuery.data ?? []) as unknown as FinanceRecord[],
    awaiting: awaiting as unknown as FinanceRecord[],
    rewards: queues.pending_referral_rewards ?? [],
    promos: queues.promotion_redemptions ?? [],
  };

  // ADR-470: only the lists that mean something for this business.
  const labels: Record<QueueKey, string> = {
    debts: standingT("debtsQueue"),
    awaiting: deskT("queueChip"),
    expiring: i18n("expiringb98d672"),
    failed: paymentsT("queueChip"),
    rewards: i18n("pendingRewardse6d6885"),
    promos: i18n("promoRedemptions2388269"),
  };
  const CHIPS = offeredQueues({
    seesFailed: seesFailedCharges,
    seesAwaiting,
    counts: Object.fromEntries(Object.entries(rowsByKey).map(([key, list]) => [key, list.length])) as Record<QueueKey, number>,
    features: features.state,
  }).map((id) => ({ id, label: labels[id] }));
  const offered = (id: QueueKey | null): id is QueueKey => id !== null && CHIPS.some((chip) => chip.id === id);
  const active: QueueKey = offered(requested) ? requested : "debts";
  const rows = rowsByKey[active];

  return (
    <div className="space-y-6">
      {/* Filter chips */}
      <div className="flex flex-wrap gap-2">
        {CHIPS.map(({ id, label }) => (
          <button
            key={id}
            className="rounded-full px-4 py-2 text-sm font-semibold transition-colors"
            style={
              active === id
                ? { background: "var(--text)", color: "var(--bg)" }
                : { background: "var(--panel)", border: "1px solid var(--border)", color: "var(--dim)" }
            }
            onClick={() => setActive(id)}
            aria-pressed={active === id}
            data-queue={id}
            type="button"
          >
            {label}
            {rowsByKey[id].length > 0 && (
              <span
                className="ms-2 rounded-full px-2 py-0.5 text-xs"
                style={{
                  background: active === id ? "color-mix(in srgb, var(--bg) 15%, transparent)" : "color-mix(in srgb, var(--primary) 15%, transparent)",
                  color: active === id ? "var(--bg)" : "var(--primary)",
                }}
              >
                {rowsByKey[id].length}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Queue list */}
      <div className="rounded-[2rem] overflow-hidden" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {active === "failed" ? (
          seesFailedCharges && token ? (
            <FailedChargesList
              token={token}
              charges={failedQuery.data ?? []}
              loading={failedQuery.isLoading}
              canRetry={can(membership, "manage_billing")}
            />
          ) : null
        ) : active === "awaiting" ? (
          awaitingQuery.isLoading ? (
            <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{i18n("loadingQueuea1e2a39")}</p>
          ) : (
            // Stays mounted when the last request is collected, so its receipt shows.
            <>
              <DeskPackageRequestRows
                rows={awaiting}
                canAct={can(membership, "take_payments")}
                empty={<p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }} data-testid="desk-requests-empty">{deskT("queueEmpty")}</p>}
              />
              <PackageRuleRolloutList />
            </>
          )
        ) : queuesQuery.isLoading ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{i18n("loadingQueuea1e2a39")}</p>
        ) : rows.length === 0 ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{i18n("noItemsInThisQueuec992fc9")}</p>
        ) : (
          <div>
            {active === "expiring" && rows.map((row, i) => (
              <QueueRow key={field(row, "id", String(i))} last={i === rows.length - 1}>
                <PersonLink userId={field(row, "user_id")} name={field(row, "user_label", field(row, "nickname"))} />
                <span style={{ color: "var(--muted)" }}>{i18n("expiresa99be3d")} {dateText(uiLocale, row.expires_on)}</span>
              </QueueRow>
            ))}

            {active === "debts" && rows.map((row, i) => {
              const state = field(row, "state");
              const status = state === "overdue" ? "overdue" : state === "unpaid" ? "unpaid" : "";
              return (
                <QueueRow key={field(row, "id", String(i))} last={i === rows.length - 1}>
                  <span className="min-w-0" style={{ color: "var(--text)" }}>
                    <PersonLink userId={field(row, "user_id")} name={field(row, "user_label")} />
                    {row.oldest_due_on ? (
                      <span style={{ color: "var(--muted)" }}> · {standingT("dueSince", { date: dateText(uiLocale, row.oldest_due_on) })}</span>
                    ) : null}
                    <KeptContact contact={row.kept_contact} note={standingT("keptContact")} />
                  </span>
                  <span className="flex flex-wrap items-center justify-end gap-2">
                    {status ? (
                      <span className="rounded-full px-2.5 py-0.5 text-xs font-semibold" data-debt-state={status} style={toneStyle(statusTone(status))}>
                        {statusLabel(status)}
                      </span>
                    ) : null}
                    <span className="font-semibold" style={{ color: "var(--text)" }}>{money(uiLocale, row.balance_due_cents)}</span>
                    <button
                      type="button"
                      onClick={() => setReceiveFrom({ userId: field(row, "user_id"), nickname: field(row, "user_label") })}
                      className="rounded-full px-2.5 py-1 text-xs font-semibold"
                      style={{
                        background: "color-mix(in srgb, var(--success) 12%, transparent)",
                        border: "1px solid color-mix(in srgb, var(--success) 24%, transparent)",
                        color: "var(--success)",
                      }}
                    >
                      {receiveT("rowButton")}
                    </button>
                  </span>
                </QueueRow>
              );
            })}

            {active === "rewards" && rows.map((row, i) => (
              <QueueRow key={field(row, "id", String(i))} last={i === rows.length - 1}>
                <PersonLink userId={field(row, "recipient_user_id")} name={field(row, "user_label", field(row, "nickname"))} />
                <span style={{ color: "var(--muted)" }}><SemanticLabel value={field(row, "reward_type")} /> · {field(row, "reward_value")}</span>
              </QueueRow>
            ))}

            {active === "promos" && rows.map((row, i) => (
              <QueueRow key={field(row, "id", String(i))} last={i === rows.length - 1}>
                <PersonLink userId={field(row, "user_id")} name={field(row, "user_label", deskT("someone"))} />
                <span style={{ color: "var(--muted)" }}>{i18n("discountb524936")} {field(row, "discount_value_snapshot")}</span>
              </QueueRow>
            ))}
          </div>
        )}
      </div>

      {receiveFrom ? (
        <ReceivePaymentDialog userId={receiveFrom.userId} nickname={receiveFrom.nickname} onClose={() => setReceiveFrom(null)} />
      ) : null}
    </div>
  );
}

function QueueRow({ children, last }: { children: React.ReactNode; last: boolean }) {
  
  return (
    <div
      className="flex items-center justify-between gap-4 px-6 py-4 text-sm"
      style={{ borderBottom: last ? "none" : "1px solid var(--border)" }}
    >
      {children}
    </div>
  );
}

/**
 * ADR-450: a person who deleted their account while owing the box. The box
 * keeps the name, email and SMS number only until the debt is paid.
 */
function KeptContact({ contact, note }: { contact: unknown; note: string }) {
  if (!contact || typeof contact !== "object") return null;
  const { email, phone_e164: phone } = contact as { email?: unknown; phone_e164?: unknown };
  const link = { color: "var(--text-soft)" };
  return (
    <span className="mt-0.5 block text-xs" style={{ color: "var(--muted)" }} data-testid="debt-kept-contact">
      {note}
      {typeof email === "string" && email ? (
        <>
          {" · "}
          <a href={`mailto:${email}`} style={link}>{email}</a>
        </>
      ) : null}
      {typeof phone === "string" && phone ? (
        <>
          {" · "}
          <a href={`tel:${phone}`} style={link} dir="ltr">{phone}</a>
        </>
      ) : null}
    </span>
  );
}
