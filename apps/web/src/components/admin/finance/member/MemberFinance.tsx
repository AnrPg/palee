"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState, type CSSProperties, type ReactNode } from "react";

import { assignFinancePackage, fetchFinanceMember, fetchFinancePackages, reverseFinancePayment, type FinanceRecord, type PackageRemoval } from "@/api/finance";
import { fetchMemberBenefits, giveMemberBenefit } from "@/api/member-benefits";
import { DeskPackageRequestRows, useDeskPackageRequests } from "@/components/admin/finance/payments/DeskPackageRequests";
import { ReceivePaymentDialog } from "@/components/admin/finance/payments/ReceivePaymentDialog";
import { parseAmountCents, amountInput } from "@/components/admin/finance/payments/receive-payment";
import { InlineAssignPackage } from "@/components/admin/finance/shared/InlineAssignPackage";
import { MoneyConfirmDialog, useMoneyConfirmation } from "@/components/admin/finance/shared/MoneyConfirm";
import { PackageRemovedToast } from "@/components/admin/finance/shared/PackageRemovedToast";
import { RemovePackageDialog } from "@/components/admin/finance/shared/RemovePackageDialog";
import { useBenefitTitle } from "@/components/admin/users/MemberBenefits";
import { StandingBadge } from "@/components/finance/StandingBadge";
import { useSession } from "@/components/session-provider";
import { sharedSubscriptions } from "@/components/staff/staff-helpers";
import { SubscriptionBeneficiaries } from "@/components/staff/SubscriptionBeneficiaries";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice, FieldError } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";
import { fieldBorder, invalidFieldProps } from "@/lib/form-errors";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

import { ChargeDetails } from "./ChargeDetails";
import {
  availableFilters,
  filterMovements,
  heldSubscription,
  heldSubscriptions,
  movements as buildMovements,
  nextCharge,
  openDebtCents,
  type Movement,
  type MovementFilter,
  type MovementKind,
  type PaymentMovement,
} from "./member-finance";
import { NewChargeDialog } from "./NewChargeDialog";

/** Each kind keeps one theme colour: the row is tinted with it and its filter carries it (ANR, mockup v7). */
const KIND_COLOUR: Record<MovementKind, string> = {
  charge: "var(--danger)",
  payment: "var(--success)",
  refund: "var(--warning)",
  gift: "var(--primary)",
  credit: "var(--info)",
};

const FILTER_KEYS: Record<MovementFilter, string> = {
  all: "filterAll",
  charge: "filterCharges",
  payment: "filterPayments",
  refund: "filterRefunds",
  gift: "filterGifts",
  credit: "filterCredits",
};

export function memberFinanceQueryKey(userId: string) {
  return ["admin", "finance", "member-profile", userId];
}

function text(record: FinanceRecord | null | undefined, key: string) {
  const value = record?.[key];
  return value === null || value === undefined ? "" : String(value);
}

function packageName(subscription: FinanceRecord | null | undefined, packages: FinanceRecord[]) {
  const match = packages.find((item) => text(item, "id") === text(subscription, "membership_package_id"));
  return text(match, "name") || text(subscription, "package_name") || text(subscription, "package_code_snapshot") || text(subscription, "package_family_snapshot");
}

/**
 * ADR-784: one place for a person's money (ANR picks 2026-11-28). The same
 * component is the profile's «Οικονομικά» tab and the ledger's side panel:
 * what is owed with «+ Πληρωμή» and «+ Χρέωση για κάτι νέο», the package with
 * change and removal, and one dated list of movements with colour filters,
 * where an open charge has its own «Πληρωμή» and a payment its refund.
 * `more` holds what only the profile shows (dates, freezes, gifts, leaving).
 * What a person may press follows the capabilities they already have.
 */
export function MemberFinance({
  userId,
  nickname,
  allowances = [],
  status,
  more,
  compact = false,
}: {
  userId: string;
  nickname: string;
  /** Labels for extra-use gifts; the profile knows the package's allowances. */
  allowances?: Array<{ key: string; label: string }>;
  /** The profile's status cell (with its «set by hand» trace); the standing badge otherwise. */
  status?: ReactNode;
  more?: ReactNode;
  /** The ledger's narrow side panel. */
  compact?: boolean;
}) {
  const t = useTranslations("MemberFinance");
  const tRemoval = useTranslations("PackageRemoval");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const { membership: actor } = useSelectedMembershipRole();
  const takePayments = can(actor, "take_payments");
  const manageBilling = can(actor, "manage_billing");
  const benefitTitle = useBenefitTitle(allowances);

  const profileQuery = useQuery({
    queryKey: memberFinanceQueryKey(userId),
    enabled: Boolean(token && userId),
    queryFn: () => fetchFinanceMember(token, userId),
  });
  const benefitsQuery = useQuery({
    queryKey: ["admin", "users", userId, "benefits"],
    enabled: Boolean(token && userId),
    queryFn: () => fetchMemberBenefits(token, userId),
  });
  // ADR-784 (ANR pick 7): a «Το θέλω» link lands here, so the request is answered here too.
  const requestsQuery = useDeskPackageRequests(undefined, takePayments || can(actor, "view_finance_reports"));
  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages"],
    enabled: Boolean(token),
    queryFn: () => fetchFinancePackages(token),
  });

  const [filter, setFilter] = useState<MovementFilter>("all");
  const [open, setOpen] = useState<string | null>(null);
  const [paying, setPaying] = useState<{ chargeId?: string } | null>(null);
  const [charging, setCharging] = useState(false);
  const [refunding, setRefunding] = useState<PaymentMovement | null>(null);
  const [removing, setRemoving] = useState<string | null>(null);
  const [removed, setRemoved] = useState<PackageRemoval | null>(null);

  const refresh = async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ["admin", "finance"] }),
      queryClient.invalidateQueries({ queryKey: ["admin", "dashboard"] }),
      queryClient.invalidateQueries({ queryKey: ["admin", "users", userId] }),
    ]);
  };

  const assignMutation = useMutation({
    mutationFn: (packageId: string) => assignFinancePackage(token, userId, { membership_package_id: packageId }),
    onSuccess: refresh,
  });
  // ADR-795 «Χωρίς χρέωση»: an ADR-612 free package instead of a made-up payment.
  const giveFreeMutation = useMutation({
    mutationFn: ({ packageId, reason }: { packageId: string; reason: string | null }) =>
      giveMemberBenefit(token, userId, {
        kind: "package",
        package_id: packageId,
        pricing: { mode: "this_period_free" },
        reason,
        idempotency_key: `free-package-${userId}-${packageId}-${Date.now()}`,
      }),
    onSuccess: refresh,
  });

  const profile = profileQuery.data;
  const packages = packagesQuery.data?.packages ?? [];
  const money = (cents: number) => formatMinorUnits(locale, cents);

  if (profileQuery.isLoading) return <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>;
  if (profileQuery.error) return <ErrorNotice>{localizeError(profileQuery.error, i18n)}</ErrorNotice>;
  if (!profile) return null;

  const debt = openDebtCents(profile);
  const upcoming = nextCharge(profile);
  const held = heldSubscription(profile);
  const holdings = heldSubscriptions(profile);
  const list = buildMovements(profile, benefitsQuery.data ?? []);
  const filters = availableFilters(list);
  const shown = filterMovements(list, filters.includes(filter) ? filter : "all");
  const creditBalance = Number(profile.credit_balance ?? 0);

  const requests = (requestsQuery.data?.requests ?? []).filter((request) => request.user_id === userId);

  return (
    <div className={compact ? "space-y-3" : "space-y-4"} data-testid="member-finance" style={{ containerType: "inline-size" }}>
      {requests.length ? (
        <Card title={t("waitingForPayment")}>
          <div className="space-y-2" data-testid="member-finance-requests">
            <DeskPackageRequestRows rows={requests} canAct={takePayments} />
          </div>
        </Card>
      ) : null}
      {/* What is owed now, and the two actions staff reach for most. */}
      <Card>
        <div className="grid gap-2" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(min(100%, 10rem), 1fr))" }}>
          <Figure label={t("owed")}>
            <strong className="text-2xl tabular-nums" style={{ color: debt > 0 ? "var(--danger)" : "var(--text)" }} data-testid="member-finance-owed">
              {money(debt)}
            </strong>
          </Figure>
          <Figure label={t("status")}>
            {status ?? (profile.standing ? <StandingBadge standing={profile.standing} /> : <span style={{ color: "var(--dim)" }}>—</span>)}
          </Figure>
          {upcoming ? (
            <Figure label={t("nextCharge")}>
              <strong className="text-sm" style={{ color: "var(--text)", overflowWrap: "anywhere" }}>
                {t("nextChargeValue", { date: formatDate(locale, upcoming.day), amount: money(upcoming.amountCents) })}
              </strong>
            </Figure>
          ) : null}
          {creditBalance > 0 ? (
            <Figure label={t("creditBalance")}>
              <strong className="text-sm tabular-nums" style={{ color: "var(--text)" }}>{money(creditBalance)}</strong>
            </Figure>
          ) : null}
        </div>
        {takePayments || manageBilling ? (
          <div className="mt-3 flex flex-wrap gap-2">
            {takePayments ? (
              <ActionButton tone="primary" onClick={() => setPaying({})} testId="member-finance-pay">
                {t("pay")}
              </ActionButton>
            ) : null}
            {manageBilling ? (
              <ActionButton onClick={() => setCharging(true)} testId="member-finance-new-charge">
                {t("newCharge")}
              </ActionButton>
            ) : null}
          </div>
        ) : null}
      </Card>

      {/* The package: change and removal are the ledger's own menu. */}
      <Card title={t("package")}>
        <div className="space-y-2">
          {holdings.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noPackage")}</p> : null}
          {holdings.map((subscription) => {
            const period = (subscription.current_period ?? null) as { ends_on?: string | null; renews?: boolean } | null;
            const ends = (period?.ends_on ?? text(subscription, "ends_on")).slice(0, 10);
            const paused = text(subscription, "status") === "paused";
            return (
              <div key={text(subscription, "id")} className="flex flex-wrap items-start justify-between gap-3" data-testid="member-finance-package">
                <div className="min-w-0">
                  <p className="font-semibold" style={{ color: "var(--text)", overflowWrap: "anywhere" }}>
                    {packageName(subscription, packages) || t("packageFallback")} · {money(Number(subscription.price_cents_snapshot ?? 0))}
                  </p>
                  <p className="text-sm" style={{ color: "var(--text-soft)" }}>
                    {paused
                      ? t("packagePaused")
                      : ends
                        ? period?.renews
                          ? t("packageRenews", { date: formatDate(locale, ends) })
                          : t("packageEnds", { date: formatDate(locale, ends) })
                        : t("packageNoEnd")}
                  </p>
                </div>
                {takePayments ? (
                  <button
                    type="button"
                    className="text-sm font-semibold underline-offset-2 hover:underline"
                    style={{ color: "var(--danger)" }}
                    onClick={() => setRemoving(text(subscription, "id"))}
                    data-testid="member-finance-remove-package"
                  >
                    {tRemoval("open")}
                  </button>
                ) : null}
              </div>
            );
          })}
          {takePayments ? (
            <InlineAssignPackage
              userId={userId}
              currentCode={held ? text(held, "package_code_snapshot") || null : null}
              currentLabel={held ? packageName(held, packages) || null : null}
              packages={packages}
              pending={assignMutation.isPending}
              onAssign={(packageId) => assignMutation.mutateAsync(packageId)}
              onReceive={() => setPaying({})}
              onGiveFree={(packageId, reason) => giveFreeMutation.mutateAsync({ packageId, reason })}
            />
          ) : null}
        </div>
        {held && sharedSubscriptions([held]).length > 0 ? (
          <div className="mt-2">
            <SubscriptionBeneficiaries payerUserId={userId} subscription={held} />
          </div>
        ) : null}
      </Card>

      {/* Every movement, newest first, one colour per kind. */}
      <Card title={t("movements")}>
        {list.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noMovements")}</p>
        ) : (
          <>
            <div className="mb-3 flex flex-wrap gap-1.5" role="group" aria-label={t("movementsFilter")}>
              {filters.map((key) => {
                const on = (filters.includes(filter) ? filter : "all") === key;
                const colour = key === "all" ? "var(--primary)" : KIND_COLOUR[key];
                return (
                  <button
                    key={key}
                    type="button"
                    aria-pressed={on}
                    onClick={() => setFilter(key)}
                    className="inline-flex items-center gap-1.5 rounded-[0.7rem] px-3 py-1.5 text-xs font-semibold"
                    style={{
                      background: on ? `color-mix(in srgb, ${colour} 14%, transparent)` : "var(--panel)",
                      color: on ? colour : "var(--text)",
                      border: `1px solid ${on ? colour : "var(--border)"}`,
                    }}
                    data-testid={`member-finance-filter-${key}`}
                  >
                    {key === "all" ? null : <span aria-hidden className="h-2.5 w-2.5 rounded-[3px]" style={{ background: colour }} />}
                    {t(FILTER_KEYS[key])}
                  </button>
                );
              })}
            </div>
            <ul className="grid gap-1.5">
              {shown.map((movement) => (
                <MovementRow
                  key={`${movement.kind}:${movement.id}`}
                  movement={movement}
                  money={money}
                  locale={locale}
                  benefitTitle={benefitTitle}
                  canPay={takePayments}
                  canRefund={manageBilling}
                  expanded={open === `${movement.kind}:${movement.id}`}
                  onToggle={() => setOpen((current) => (current === `${movement.kind}:${movement.id}` ? null : `${movement.kind}:${movement.id}`))}
                  onPay={(chargeId) => setPaying({ chargeId })}
                  onRefund={setRefunding}
                  details={
                    movement.kind === "charge" ? (
                      <ChargeDetails invoice={movement.record} token={token} canManage={manageBilling} onUploaded={() => void refresh()} />
                    ) : null
                  }
                />
              ))}
            </ul>
          </>
        )}
      </Card>

      {more ? (
        <details className="rounded-[1.25rem] px-4 py-1" style={{ border: "1px solid var(--border)" }} data-testid="member-finance-more">
          <summary className="cursor-pointer py-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("more")}
          </summary>
          <div className="pb-4">{more}</div>
        </details>
      ) : null}

      {paying ? <ReceivePaymentDialog userId={userId} nickname={nickname} chargeId={paying.chargeId} onClose={() => setPaying(null)} /> : null}
      {charging ? (
        <NewChargeDialog
          token={token}
          userId={userId}
          nickname={nickname}
          canTakePayment={takePayments}
          onClose={() => setCharging(false)}
          onCharged={(invoice, payNow) => {
            setCharging(false);
            void refresh().then(() => {
              if (payNow) setPaying({ chargeId: text(invoice, "id") });
            });
          }}
        />
      ) : null}
      {refunding ? (
        <RefundDialog
          token={token}
          userId={userId}
          payment={refunding}
          onClose={() => setRefunding(null)}
          onDone={() => {
            setRefunding(null);
            void refresh();
          }}
        />
      ) : null}
      {removing ? (
        <RemovePackageDialog
          userId={userId}
          memberName={nickname}
          subscriptionId={removing}
          onClose={() => setRemoving(null)}
          onOpenRefund={() => {
            setRemoving(null);
            setFilter("payment");
          }}
          onRemoved={(removal) => {
            setRemoving(null);
            setRemoved(removal);
            void refresh();
          }}
        />
      ) : null}
      {removed ? <PackageRemovedToast nickname={nickname} removal={removed} userId={userId} onDone={() => setRemoved(null)} /> : null}
    </div>
  );
}

/** A calendar day (`YYYY-MM-DD`) in the viewer's words, read as a local day so it never shifts. */
function dayDate(value: string) {
  const [year, month, day] = value.slice(0, 10).split("-").map(Number);
  return new Date(year, month - 1, day);
}

function formatDate(locale: string, value: string) {
  return value ? dayDate(value).toLocaleDateString(locale, { day: "numeric", month: "short", year: "numeric" }) : "—";
}

function shortDay(locale: string, value: string) {
  return value ? dayDate(value).toLocaleDateString(locale, { day: "numeric", month: "short" }) : "";
}

function Card({ title, children }: { title?: string; children: ReactNode }) {
  return (
    <section className="rounded-[1.25rem] p-4" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      {title ? <h3 className="mb-3 text-sm font-semibold" style={{ color: "var(--text)" }}>{title}</h3> : null}
      {children}
    </section>
  );
}

function Figure({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="min-w-0 rounded-xl p-3" style={{ background: "var(--panel-muted)" }}>
      <p className="text-xs" style={{ color: "var(--dim)" }}>{label}</p>
      <div className="mt-1 min-w-0">{children}</div>
    </div>
  );
}

function ActionButton({ tone = "secondary", onClick, testId, children }: { tone?: "primary" | "secondary"; onClick: () => void; testId?: string; children: ReactNode }) {
  const style: CSSProperties =
    tone === "primary"
      ? { background: "var(--primary)", color: "var(--primary-contrast)", border: "1px solid var(--primary)" }
      : { background: "transparent", color: "var(--text)", border: "1px solid var(--border)" };
  return (
    <button type="button" onClick={onClick} className="min-h-10 rounded-full px-4 py-2 text-sm font-semibold" style={style} data-testid={testId}>
      {children}
    </button>
  );
}

function MovementRow({
  movement,
  money,
  locale,
  benefitTitle,
  canPay,
  canRefund,
  expanded,
  onToggle,
  onPay,
  onRefund,
  details,
}: {
  movement: Movement;
  money: (cents: number) => string;
  locale: string;
  benefitTitle: ReturnType<typeof useBenefitTitle>;
  canPay: boolean;
  canRefund: boolean;
  expanded: boolean;
  onToggle: () => void;
  onPay: (chargeId: string) => void;
  onRefund: (payment: PaymentMovement) => void;
  details: ReactNode;
}) {
  const t = useTranslations("MemberFinance");
  const tReceive = useTranslations("ReceivePayment");
  const colour = KIND_COLOUR[movement.kind];
  const voided = movement.kind === "charge" && movement.voided;

  let title = "";
  let detail = "";
  let amount: ReactNode = null;
  let action: ReactNode = null;

  switch (movement.kind) {
    case "charge":
      title = voided ? t("chargeVoided") : t("charge");
      detail = [movement.description, movement.number, movement.paidCents > 0 && movement.open ? t("chargePaidSoFar", { amount: money(movement.paidCents) }) : ""]
        .filter(Boolean)
        .join(" · ");
      amount = movement.open ? (
        <strong style={{ color: "var(--danger)" }}>{t("chargeLeft", { amount: money(movement.balanceCents) })}</strong>
      ) : (
        <span style={{ color: voided ? "var(--dim)" : "var(--text)", textDecoration: voided ? "line-through" : undefined }}>{money(movement.totalCents)}</span>
      );
      if (movement.open && canPay) {
        action = (
          <button
            type="button"
            className="min-h-9 rounded-full px-4 py-1.5 text-sm font-semibold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            onClick={() => onPay(movement.id)}
            data-testid="member-finance-charge-pay"
          >
            {t("payCharge")}
          </button>
        );
      }
      break;
    case "payment": {
      title = t("payment");
      const method = movement.method ? tReceive(`method_${movement.method}` as "method_cash") : "";
      detail = [method, movement.chargeNumber ? t("paymentFor", { number: movement.chargeNumber }) : "", movement.notes].filter(Boolean).join(" · ");
      amount = <span style={{ color: "var(--success)" }}>−{money(movement.amountCents)}</span>;
      if (canRefund && movement.refundableCents > 0) {
        action = (
          <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => onRefund(movement)} data-testid="member-finance-refund">
            {t("refund")}
          </button>
        );
      }
      break;
    }
    case "refund":
      title = t("refundRow");
      detail = movement.reason;
      amount = <span style={{ color: "var(--text)" }}>{money(movement.amountCents)}</span>;
      break;
    case "gift":
      title = t("gift");
      detail = [benefitTitle(movement.benefit), movement.benefit.given_by_name ?? "", movement.benefit.reason ?? ""].filter(Boolean).join(" · ");
      break;
    case "credit":
      title = t("credit");
      detail = movement.description;
      amount = <span style={{ color: "var(--text)" }}>{money(movement.amountCents)}</span>;
      break;
  }

  const hasDetails = Boolean(details);
  return (
    <li
      className="rounded-xl px-3 py-2.5"
      style={{ background: `color-mix(in srgb, ${colour} ${voided ? 5 : 10}%, transparent)` }}
      data-testid="member-finance-movement"
      data-kind={movement.kind}
    >
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5">
        <span className="w-14 shrink-0 text-xs tabular-nums" style={{ color: "var(--dim)" }}>
          {shortDay(locale, movement.day)}
        </span>
        <div className="min-w-0 flex-[1_1_12rem]">
          {hasDetails ? (
            <button type="button" className="text-start text-sm font-semibold" style={{ color: colour }} aria-expanded={expanded} onClick={onToggle}>
              {title}
            </button>
          ) : (
            <p className="text-sm font-semibold" style={{ color: colour }}>{title}</p>
          )}
          {detail ? <p className="text-xs" style={{ color: "var(--text-soft)", overflowWrap: "anywhere" }}>{detail}</p> : null}
        </div>
        <div className="ms-auto flex flex-wrap items-center justify-end gap-2 text-sm tabular-nums">
          {amount}
          {action}
        </div>
      </div>
      {expanded && hasDetails ? <div className="mt-2">{details}</div> : null}
    </li>
  );
}

/** Money given back from one payment: how much (all that is left by default) and why. */
function RefundDialog({
  token,
  userId,
  payment,
  onClose,
  onDone,
}: {
  token: string;
  userId: string;
  payment: PaymentMovement;
  onClose: () => void;
  onDone: () => void;
}) {
  const t = useTranslations("MemberFinance");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const ids = useId();
  const [amount, setAmount] = useState(amountInput(payment.refundableCents));
  const [reason, setReason] = useState("");
  const [checked, setChecked] = useState(false);
  const [requestId] = useState(() => crypto.randomUUID());
  const cents = parseAmountCents(amount);
  const amountError = checked
    ? cents === null
      ? t("refundAmountInvalid")
      : cents > payment.refundableCents
        ? t("refundAmountTooHigh", { amount: formatMinorUnits(locale, payment.refundableCents) })
        : null
    : null;

  // ADR-795: «Έδωσες πραγματικά … σε μετρητά;» before a cash refund, unless skipped today.
  const cashConfirmation = useMoneyConfirmation("cash_refund");
  const [confirmingCash, setConfirmingCash] = useState(false);
  const cash = payment.method === "cash" && payment.status !== "waived";

  const mutation = useMutation({
    mutationFn: () =>
      reverseFinancePayment(token, userId, payment.id, {
        amount_cents: cents,
        reversal_type: payment.status === "waived" ? "waiver_reversal" : "payment_reversal",
        reason: reason.trim() || i18n("refundOrReversePayment9d232b2"),
        request_id: requestId,
      }),
    onSuccess: onDone,
  });

  if (confirmingCash) {
    return (
      <MoneyConfirmDialog
        kind="cash_refund"
        amount={formatMinorUnits(locale, cents ?? 0)}
        pending={mutation.isPending}
        onBack={() => setConfirmingCash(false)}
        onConfirm={() => {
          setConfirmingCash(false);
          mutation.mutate();
        }}
      />
    );
  }

  return (
    <Dialog
      onClose={onClose}
      title={t("refundTitle")}
      description={t("refundHint", { amount: formatMinorUnits(locale, payment.refundableCents) })}
      size="sm"
      variant="center"
      dismissible={!mutation.isPending}
      testId="member-finance-refund-dialog"
      onSubmit={(event) => {
        event.preventDefault();
        setChecked(true);
        if (cents === null || cents > payment.refundableCents) return;
        if (cash && cashConfirmation.ask) setConfirmingCash(true);
        else mutation.mutate();
      }}
      error={mutation.error ? <ErrorNotice variant="field">{localizeError(mutation.error, i18n)}</ErrorNotice> : null}
      footer={
        <DialogButton type="submit" tone="primary" disabled={mutation.isPending}>
          {t("refundSave")}
        </DialogButton>
      }
    >
      <div className="space-y-4">
        <div className="space-y-1.5">
          <p className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("refundAmount")}</p>
          <input
            aria-label={t("refundAmount")}
            className="w-full rounded-xl px-3 py-2.5 text-sm outline-none"
            style={{ background: "var(--panel)", color: "var(--text)", border: fieldBorder(amountError) }}
            inputMode="decimal"
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            {...invalidFieldProps(amountError, `${ids}-amount`)}
          />
          <FieldError id={`${ids}-amount`}>{amountError}</FieldError>
        </div>
        <div className="space-y-1.5">
          <p className="text-xs font-semibold" style={{ color: "var(--dim)" }}>{t("refundReason")}</p>
          <input
            aria-label={t("refundReason")}
            className="w-full rounded-xl px-3 py-2.5 text-sm outline-none"
            style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" }}
            value={reason}
            maxLength={500}
            onChange={(event) => setReason(event.target.value)}
          />
        </div>
      </div>
    </Dialog>
  );
}
