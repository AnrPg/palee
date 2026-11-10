"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { fetchFinanceMember, fetchFinancePackages } from "@/api/finance";
import { fetchMemberBenefits, giveMemberBenefit, revokeMemberBenefit, type MemberBenefit } from "@/api/member-benefits";
import {
  BENEFIT_KINDS,
  BENEFIT_PERIODS,
  EMPTY_DRAFT,
  REASON_MAX,
  detail,
  draftReady,
  endPresets,
  grantBody,
  openInvoices,
  revocable,
  type BenefitDraft,
} from "@/components/admin/users/member-benefits";
import { localDay } from "@/components/finance/standing";
import { DateInput } from "@/components/ui/DateInput";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatClock } from "@/lib/clock";
import { formatMinorUnits } from "@/lib/finance-accounting";

const fieldStyle = { background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" };
const STATE_COLOURS: Record<string, string> = {
  active: "var(--success)",
  upcoming: "var(--primary)",
  given: "var(--primary)",
  ended: "var(--muted)",
  revoked: "var(--muted)",
};

function dayText(locale: string, value: string | null | undefined) {
  if (!value) return "";
  const [year, month, day] = value.slice(0, 10).split("-").map(Number);
  return new Date(year, month - 1, day).toLocaleDateString(locale, { day: "numeric", month: "short", year: "numeric" });
}

function momentText(locale: string, value: string | null | undefined) {
  if (!value) return "";
  return formatClock(new Date(value), locale, { dateStyle: "medium", timeStyle: "short" });
}

function Pill({ selected, onClick, children, testId }: { selected: boolean; onClick: () => void; children: React.ReactNode; testId?: string }) {
  return (
    <button
      aria-pressed={selected}
      className="rounded-full px-3 py-1.5 text-xs font-semibold"
      data-testid={testId}
      onClick={onClick}
      style={selected ? { background: "var(--text)", color: "var(--bg)" } : { background: "var(--panel-muted)", color: "var(--text-soft)", border: "1px solid var(--border)" }}
      type="button"
    >
      {children}
    </button>
  );
}

/**
 * ADR-612: «Δώρο ή χάρη» on a member's profile. Staff who take payments give a
 * grace, free access, extra uses, a package for free or cheaper, or forgive a
 * charge; every one is kept with who gave it, when and why, and can be seen
 * (and, where it still counts, revoked) here.
 */
export function MemberBenefits({
  token,
  userId,
  nickname,
  allowances,
  canGive,
  onRefresh,
}: {
  token: string;
  userId: string;
  nickname: string;
  /** The allowances of the member's package that extra uses can add to, with their labels. */
  allowances: Array<{ key: string; label: string }>;
  canGive: boolean;
  onRefresh: () => Promise<unknown>;
}) {
  const t = useTranslations("MemberBenefits");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [revokeTarget, setRevokeTarget] = useState<string | null>(null);
  const [revokeReason, setRevokeReason] = useState("");
  const [revokeKey, setRevokeKey] = useState("");

  const queryKey = ["admin", "users", userId, "benefits"];
  const benefitsQuery = useQuery({ queryKey, queryFn: () => fetchMemberBenefits(token, userId) });
  const benefits = benefitsQuery.data ?? [];

  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey });
    await queryClient.invalidateQueries({ queryKey: ["admin", "finance", "member", userId] });
    await onRefresh();
  };

  const revoke = useMutation({
    mutationFn: (benefit: MemberBenefit) =>
      revokeMemberBenefit(token, userId, benefit.id, { reason: revokeReason.trim() || null, idempotency_key: revokeKey }),
    onSuccess: async () => {
      setRevokeTarget(null);
      setRevokeReason("");
      await refresh();
    },
  });

  const money = (cents: number | null | undefined) => formatMinorUnits(locale, cents ?? 0);

  const title = (benefit: MemberBenefit) => {
    switch (benefit.kind) {
      case "grace":
        return t("titleGrace", { date: dayText(locale, benefit.ends_on) });
      case "free_access":
        return t("titleFreeAccess", { date: dayText(locale, benefit.ends_on) });
      case "extra_uses": {
        const key = detail<string>(benefit, "allowance") ?? "";
        const label = allowances.find((allowance) => allowance.key === key)?.label ?? key;
        return t("titleExtraUses", { count: detail<number>(benefit, "quantity") ?? 0, what: label, from: dayText(locale, benefit.starts_on), to: dayText(locale, benefit.ends_on) });
      }
      case "package":
        return detail<string>(benefit, "pricing") === "price"
          ? t("titlePackagePrice", { name: detail<string>(benefit, "package_name") ?? "", price: money(detail<number>(benefit, "price_cents")) })
          : t("titlePackageFree", { name: detail<string>(benefit, "package_name") ?? "" });
      default:
        return t("titleDebtForgiven", { amount: money(benefit.amount_cents) });
    }
  };

  return (
    <div className="space-y-3 rounded-[1.25rem] p-4" style={{ border: "1px solid var(--border)" }} data-testid="member-benefits">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="font-semibold" style={{ color: "var(--text)" }}>{t("title")}</p>
          <p className="text-xs" style={{ color: "var(--muted)" }}>{t("subtitle")}</p>
        </div>
        {canGive ? (
          <button
            className="rounded-full px-4 py-2 text-xs font-semibold"
            data-testid="member-benefit-open"
            onClick={() => setOpen(true)}
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            type="button"
          >
            {t("give")}
          </button>
        ) : null}
      </div>

      {benefitsQuery.isSuccess && benefits.length === 0 ? <p className="text-xs" style={{ color: "var(--muted)" }}>{t("none")}</p> : null}

      {benefits.map((benefit) => (
        <div className="rounded-xl p-3" key={benefit.id} style={{ background: "var(--panel-muted)" }} data-testid="member-benefit">
          <div className="flex flex-wrap items-start justify-between gap-2">
            <div className="min-w-0">
              <strong style={{ color: benefit.state === "revoked" ? "var(--muted)" : "var(--text)" }}>{title(benefit)}</strong>
              <p className="text-xs" style={{ color: "var(--muted)" }}>
                <span style={{ color: STATE_COLOURS[benefit.state] ?? "var(--muted)" }}>{t(`state_${benefit.state}`)}</span>
                {" · "}
                {benefit.given_by_roles?.includes("system")
                  ? t("givenBySystem", { when: momentText(locale, benefit.given_at) })
                  : t("givenBy", { name: benefit.given_by_name ?? t("someone"), when: momentText(locale, benefit.given_at) })}
              </p>
              {benefit.reason ? (
                <p className="text-xs" style={{ color: "var(--text-soft)" }}>
                  {/* ADR-633: the rollout's own reason is a code, shown in words. */}
                  {t("reasonShown", { reason: benefit.reason === "package_rule_rollout" ? t("reasonRollout") : benefit.reason })}
                </p>
              ) : null}
              {benefit.revocation ? (
                <p className="text-xs" style={{ color: "var(--muted)" }}>
                  {t("revokedBy", { name: benefit.revocation.by_name ?? t("someone"), when: momentText(locale, benefit.revocation.at) })}
                  {benefit.revocation.reason ? ` · ${benefit.revocation.reason}` : ""}
                </p>
              ) : null}
            </div>
            {canGive && revocable(benefit) && revokeTarget !== benefit.id ? (
              <button
                className="text-xs font-semibold"
                onClick={() => { revoke.reset(); setRevokeKey(crypto.randomUUID()); setRevokeTarget(benefit.id); }}
                style={{ color: "var(--danger)" }}
                type="button"
              >
                {t("revoke")}
              </button>
            ) : null}
          </div>
          {revokeTarget === benefit.id ? (
            <div className="mt-3 space-y-2">
              <div className="flex flex-col gap-2 sm:flex-row">
                <input
                  aria-label={t("revokeReason")}
                  className="min-w-0 flex-1 rounded-xl px-3 py-2"
                  maxLength={REASON_MAX}
                  onChange={(event) => setRevokeReason(event.target.value)}
                  placeholder={t("revokeReason")}
                  style={fieldStyle}
                  value={revokeReason}
                />
                <button className="rounded-full px-3 py-2 text-xs font-semibold disabled:opacity-50" disabled={revoke.isPending} onClick={() => revoke.mutate(benefit)} style={{ background: "var(--danger)", color: "var(--danger-contrast)" }} type="button">
                  {t("revokeConfirm")}
                </button>
                <button className="rounded-full px-3 py-2 text-xs font-semibold" onClick={() => setRevokeTarget(null)} style={{ background: "var(--border)", color: "var(--text-soft)" }} type="button">
                  {t("keep")}
                </button>
              </div>
              {revoke.error ? <ErrorNotice variant="field">{localizeError(revoke.error, i18n)}</ErrorNotice> : null}
            </div>
          ) : null}
        </div>
      ))}

      {open ? (
        <GiveSheet
          allowances={allowances}
          nickname={nickname}
          onClose={() => setOpen(false)}
          onGiven={async () => { setOpen(false); await refresh(); }}
          token={token}
          userId={userId}
        />
      ) : null}
    </div>
  );
}

function GiveSheet({
  token,
  userId,
  nickname,
  allowances,
  onClose,
  onGiven,
}: {
  token: string;
  userId: string;
  nickname: string;
  allowances: Array<{ key: string; label: string }>;
  onClose: () => void;
  onGiven: () => Promise<void>;
}) {
  const t = useTranslations("MemberBenefits");
  const i18n = useUiTranslations();
  const locale = useUiLocale();
  const [today] = useState(() => localDay(new Date()));
  // One key per sheet: a double tap gives once.
  const [idempotencyKey] = useState(() => crypto.randomUUID());
  const [draft, setDraft] = useState<BenefitDraft>(EMPTY_DRAFT);
  const [customEnd, setCustomEnd] = useState(false);
  const presets = endPresets(today);
  const edit = (change: Partial<BenefitDraft>) => setDraft((value) => ({ ...value, ...change }));

  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "packages"],
    queryFn: () => fetchFinancePackages(token),
    enabled: draft.kind === "package",
  });
  const memberQuery = useQuery({
    queryKey: ["admin", "finance", "member", userId],
    queryFn: () => fetchFinanceMember(token, userId),
    enabled: draft.kind === "debt_forgiven",
  });
  const packages = (packagesQuery.data?.packages ?? []).filter((item) => item.status !== "archived");
  const invoices = openInvoices(memberQuery.data?.invoices ?? []);

  const give = useMutation({
    mutationFn: () => giveMemberBenefit(token, userId, grantBody(draft, idempotencyKey)),
    onSuccess: onGiven,
  });

  const money = (cents: unknown) => formatMinorUnits(locale, Number(cents ?? 0));
  const ready = draftReady(draft, today);
  const kinds = BENEFIT_KINDS.filter((kind) => kind !== "extra_uses" || allowances.length > 0);

  return (
    <Dialog
      error={give.error ? localizeError(give.error, i18n) : null}
      eyebrow={t("give")}
      footer={
        <>
          <button className="rounded-full px-4 py-2 text-sm font-semibold" onClick={onClose} style={{ background: "var(--border)", color: "var(--text-soft)" }} type="button">
            {t("cancel")}
          </button>
          <button
            className="rounded-full px-4 py-2 text-sm font-semibold disabled:opacity-50"
            data-testid="member-benefit-submit"
            disabled={!ready || give.isPending}
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            type="submit"
          >
            {give.isPending ? t("giving") : t(`submit_${draft.kind ?? "none"}`)}
          </button>
        </>
      }
      onClose={onClose}
      onSubmit={(event) => { event.preventDefault(); if (ready) give.mutate(); }}
      size="lg"
      title={t("sheetTitle", { name: nickname })}
      variant="sheet"
    >
      <p className="text-sm" style={{ color: "var(--muted)" }}>{t("sheetHint")}</p>
      <div className="mt-3 grid gap-2">
        {kinds.map((kind) => (
          <button
            aria-pressed={draft.kind === kind}
            className="rounded-2xl p-3 text-start"
            data-testid={`member-benefit-kind-${kind}`}
            key={kind}
            onClick={() => { give.reset(); setCustomEnd(false); setDraft({ ...EMPTY_DRAFT, reason: draft.reason, kind }); }}
            style={{
              background: draft.kind === kind ? "color-mix(in srgb, var(--primary) 10%, var(--panel))" : "var(--panel-muted)",
              border: `1px solid ${draft.kind === kind ? "var(--primary)" : "var(--border)"}`,
              color: "var(--text)",
            }}
            type="button"
          >
            <span className="block font-semibold">{t(`kind_${kind}`)}</span>
            <span className="block text-xs" style={{ color: "var(--muted)" }}>{t(`kindHint_${kind}`)}</span>
          </button>
        ))}
      </div>

      {draft.kind === "grace" || draft.kind === "free_access" ? (
        <div className="mt-4 space-y-2">
          <p className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{t("lastDay")}</p>
          <div className="flex flex-wrap gap-2">
            <Pill selected={!customEnd && draft.ends_on === presets.week} onClick={() => { setCustomEnd(false); edit({ ends_on: presets.week }); }} testId="member-benefit-end-week">{t("endWeek")}</Pill>
            <Pill selected={!customEnd && draft.ends_on === presets.monthEnd} onClick={() => { setCustomEnd(false); edit({ ends_on: presets.monthEnd }); }}>{t("endMonth", { date: dayText(locale, presets.monthEnd) })}</Pill>
            <Pill selected={customEnd} onClick={() => { setCustomEnd(true); edit({ ends_on: "" }); }}>{t("endDate")}</Pill>
          </div>
          {customEnd ? (
            <DateInput aria-label={t("lastDay")} className="w-full rounded-xl px-3 py-2" min={today} onValueChange={(value) => edit({ ends_on: value })} style={fieldStyle} value={draft.ends_on} />
          ) : null}
          <p className="text-xs" style={{ color: "var(--muted)" }}>{t(draft.kind === "grace" ? "graceNote" : "freeAccessNote")}</p>
        </div>
      ) : null}

      {draft.kind === "extra_uses" ? (
        <div className="mt-4 space-y-3">
          <label className="block text-xs font-semibold" style={{ color: "var(--muted)" }}>
            {t("usesFor")}
            <Select className="mt-1 w-full rounded-xl px-3 py-2 text-sm" data-testid="member-benefit-allowance" onValueChange={(value) => edit({ allowance: value })} placeholder={t("choose")} style={fieldStyle} value={draft.allowance}>
              {allowances.map((allowance) => <option key={allowance.key} value={allowance.key}>{allowance.label}</option>)}
            </Select>
          </label>
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{t("howMany")}</span>
            <button aria-label={t("fewer")} className="h-8 w-8 rounded-full font-semibold disabled:opacity-40" disabled={draft.quantity <= 1} onClick={() => edit({ quantity: draft.quantity - 1 })} style={fieldStyle} type="button">−</button>
            <strong data-testid="member-benefit-quantity" style={{ color: "var(--text)" }}>{draft.quantity}</strong>
            <button aria-label={t("more")} className="h-8 w-8 rounded-full font-semibold" onClick={() => edit({ quantity: draft.quantity + 1 })} style={fieldStyle} type="button">+</button>
          </div>
          <div className="space-y-2">
            <p className="text-xs font-semibold" style={{ color: "var(--muted)" }}>{t("validFor")}</p>
            <div className="flex flex-wrap gap-2">
              {BENEFIT_PERIODS.map((period) => (
                <Pill key={period} selected={draft.period === period} onClick={() => edit({ period })} testId={`member-benefit-period-${period}`}>{t(`period_${period}`)}</Pill>
              ))}
            </div>
          </div>
        </div>
      ) : null}

      {draft.kind === "package" ? (
        <div className="mt-4 space-y-3">
          <label className="block text-xs font-semibold" style={{ color: "var(--muted)" }}>
            {t("package")}
            <Select className="mt-1 w-full rounded-xl px-3 py-2 text-sm" data-testid="member-benefit-package" disabled={packagesQuery.isLoading} onValueChange={(value) => edit({ package_id: value })} placeholder={t("choose")} style={fieldStyle} value={draft.package_id}>
              {packages.map((item) => <option key={String(item.id)} value={String(item.id)}>{String(item.name)} · {money(item.base_price_cents)}</option>)}
            </Select>
          </label>
          <div className="flex flex-wrap gap-2">
            <Pill selected={draft.pricing === "this_period_free"} onClick={() => edit({ pricing: "this_period_free" })} testId="member-benefit-pricing-free">{t("pricingFree")}</Pill>
            <Pill selected={draft.pricing === "price"} onClick={() => edit({ pricing: "price" })} testId="member-benefit-pricing-price">{t("pricingPrice")}</Pill>
          </div>
          {draft.pricing === "price" ? (
            <input aria-label={t("price")} className="w-full rounded-xl px-3 py-2" inputMode="decimal" onChange={(event) => edit({ price: event.target.value })} placeholder={t("price")} style={fieldStyle} value={draft.price} />
          ) : null}
          {draft.pricing ? <p className="text-xs" style={{ color: "var(--muted)" }}>{t(draft.pricing === "price" ? "pricingPriceNote" : "pricingFreeNote")}</p> : null}
        </div>
      ) : null}

      {draft.kind === "debt_forgiven" ? (
        <div className="mt-4 space-y-2">
          {memberQuery.isSuccess && invoices.length === 0 ? <p className="text-sm" style={{ color: "var(--muted)" }}>{t("nothingOwed")}</p> : null}
          {invoices.map((invoice) => {
            const id = String(invoice.id);
            const chosen = draft.invoice_ids.includes(id);
            return (
              <button
                aria-pressed={chosen}
                className="flex w-full flex-wrap items-center justify-between gap-2 rounded-xl px-3 py-2 text-start text-sm"
                key={id}
                onClick={() => edit({ invoice_ids: chosen ? draft.invoice_ids.filter((value) => value !== id) : [...draft.invoice_ids, id] })}
                style={{ background: chosen ? "color-mix(in srgb, var(--primary) 10%, var(--panel))" : "var(--panel-muted)", border: `1px solid ${chosen ? "var(--primary)" : "var(--border)"}`, color: "var(--text)" }}
                type="button"
              >
                <span>{chosen ? "✓ " : ""}{String(invoice.invoice_number ?? "")} · {t("dueOn", { date: dayText(locale, String(invoice.due_date ?? "")) })}</span>
                <strong>{money(invoice.balance_due_cents)}</strong>
              </button>
            );
          })}
          <p className="text-xs" style={{ color: "var(--muted)" }}>{t("forgiveNote")}</p>
        </div>
      ) : null}

      {draft.kind ? (
        <label className="mt-4 block text-xs font-semibold" style={{ color: "var(--muted)" }}>
          {t("reason")}
          <textarea
            className="mt-1 w-full rounded-xl px-3 py-2 text-sm"
            maxLength={REASON_MAX}
            onChange={(event) => edit({ reason: event.target.value })}
            rows={2}
            style={fieldStyle}
            value={draft.reason}
          />
        </label>
      ) : null}
    </Dialog>
  );
}
