"use client";

import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { coachPayKeys, fetchPayRules, fetchPayslipPdf, fetchPersonStatements, type PayRule, type StatementPeriod } from "@/api/coach-pay";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { useSelectedMembershipRole } from "@/lib/membership-role";
import { can } from "@/lib/role-navigation";

import { activeRules, payFileName, periodLabel } from "./coach-pay";
import { payslipLanguage, StatusPill } from "./PayPeriodsView";
import { PayRuleForm } from "./PayRuleForm";
import { RuleLine } from "./PayRulesView";
import { GrossNet, saveFile, useGymToday } from "./pay-ui";

/**
 * A staff member's profile › «Αμοιβή» (product owner W1 s4: pay is visible
 * in the coach profile and in Finance): their rules as sentences and their
 * statements by period, «Μικτά · Καθαρά», with the payslip of each closed one.
 * Only billing and finance-report staff see it, as the API allows.
 */
export function StaffPayCard({ userId, name }: { userId: string; name: string }) {
  const { membership } = useSelectedMembershipRole();
  if (!can(membership, "view_finance_reports") && !can(membership, "manage_billing")) return null;
  return <StaffPay userId={userId} name={name} canEdit={can(membership, "manage_billing")} />;
}

function StaffPay({ userId, name, canEdit }: { userId: string; name: string; canEdit: boolean }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? "";
  const today = useGymToday();
  const [editing, setEditing] = useState<{ rule: PayRule | null } | null>(null);

  const rules = useQuery({ queryKey: coachPayKeys.rules, enabled: Boolean(token), queryFn: () => fetchPayRules(token) });
  const statements = useQuery({ queryKey: coachPayKeys.person(userId), enabled: Boolean(token), queryFn: () => fetchPersonStatements(token, userId) });
  const pdf = useMutation({
    mutationFn: (period: StatementPeriod) => fetchPayslipPdf(token, period.id, userId, payslipLanguage(locale)),
    onSuccess: (blob, period) => saveFile(blob, payFileName("pay-statement", period, "pdf")),
  });

  const mine = activeRules(rules.data?.rules ?? [], today).filter((rule) => rule.coach_user_id === userId);
  const list = statements.data?.statements ?? [];

  return (
    <section className="space-y-4 rounded-[2rem] p-6" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="staff-pay">
      <h2 className="text-lg font-semibold" style={{ color: "var(--text)" }}>{t("profileTitle")}</h2>

      <div className="space-y-1.5">
        <p className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{t("viewRules")}</p>
        {rules.isError ? <ErrorNotice variant="field">{localizeError(rules.error, ui)}</ErrorNotice> : null}
        {rules.isSuccess && mine.length === 0 ? (
          <p className="text-sm font-medium" style={{ color: "var(--warning)" }} data-testid="pay-person-no-rule">{t("noRule")}</p>
        ) : null}
        <ul className="space-y-0.5">
          {mine.map((rule) => (
            <li key={rule.id}>
              <RuleLine rule={rule} onOpen={canEdit ? () => setEditing({ rule }) : undefined} />
            </li>
          ))}
        </ul>
        {canEdit ? (
          <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={() => setEditing({ rule: null })} data-testid="pay-add-rule">
            + {t("addRule")}
          </button>
        ) : null}
      </div>

      <div className="space-y-1.5">
        <p className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{t("statements")}</p>
        {statements.isError ? <ErrorNotice variant="field">{localizeError(statements.error, ui)}</ErrorNotice> : null}
        {statements.isSuccess && list.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noStatementsYet")}</p> : null}
        <ul>
          {list.map((statement) => {
            const period = statement.period as unknown as StatementPeriod | null;
            if (!period) return null;
            return (
              <li key={statement.id} className="flex flex-wrap items-center gap-3 border-b py-2 last:border-b-0" style={{ borderColor: "var(--border)" }} data-testid="staff-pay-statement">
                <span className="min-w-0 flex-1 text-sm font-semibold" style={{ color: "var(--text)" }}>{periodLabel(period.starts_on, period.ends_on, locale)}</span>
                <StatusPill status={period.status} />
                <span className="text-sm" style={{ color: "var(--text-soft)" }}>
                  <GrossNet gross={statement.gross_cents} net={statement.net_cents} currency={period.currency} />
                </span>
                {period.status !== "draft" ? (
                  <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} disabled={pdf.isPending} onClick={() => pdf.mutate(period)}>
                    {t("payslipPdf")}
                  </button>
                ) : null}
              </li>
            );
          })}
        </ul>
        {pdf.isError ? <ErrorNotice variant="field">{localizeError(pdf.error, ui)}</ErrorNotice> : null}
      </div>

      {editing ? <PayRuleForm userId={userId} name={name} rule={editing.rule} onClose={() => setEditing(null)} /> : null}
    </section>
  );
}
