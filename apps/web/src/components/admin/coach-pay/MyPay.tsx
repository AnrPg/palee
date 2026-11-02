"use client";

import Link from "next/link";
import { useMutation, useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { coachPayKeys, fetchMyPay, fetchMyPayslipPdf, type MyStatement, type StatementPeriod } from "@/api/coach-pay";
import { DashboardCard } from "@/components/admin/DashboardWidgets";
import { PageHeader } from "@/components/PageHeader";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { payFileName, payslipLanguage, periodLabel } from "./coach-pay";
import { StatementLines } from "./PayPeriodsView";
import { GrossNet, saveFile, useMoney } from "./pay-ui";

const periodOf = (statement: MyStatement) => statement.period as unknown as StatementPeriod;

function useMyPay() {
  const token = useSession().tokens?.access_token ?? "";
  return useQuery({ queryKey: coachPayKeys.mine, enabled: Boolean(token), queryFn: () => fetchMyPay(token), retry: false });
}

/**
 * «Οι αμοιβές μου» (mockup W1 s6, option A): the latest approved period open
 * with its lines and «Μικτά · Καθαρά», its payslip as PDF, and the earlier
 * periods under it, each opening the same way. Only approved periods show.
 */
export function MyPayView() {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const query = useMyPay();
  const statements = (query.data?.statements ?? []).filter((statement) => statement.period);
  const [openId, setOpenId] = useState<string | null>(null);
  const shown = statements.find((statement) => statement.id === openId) ?? statements[0] ?? null;

  return (
    <main className="min-h-screen px-4 py-8 md:px-10" style={{ background: "var(--bg)" }}>
      <div className="mx-auto max-w-2xl space-y-5">
        <PageHeader title={t("myPayTitle")} />
        {query.isLoading ? <p className="text-sm" style={{ color: "var(--dim)" }}>{ui("loading33ce417")}</p> : null}
        {query.isError ? <ErrorNotice>{localizeError(query.error, ui)}</ErrorNotice> : null}
        {query.isSuccess && statements.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }} data-testid="my-pay-empty">{t("myPayEmpty")}</p> : null}
        {shown ? <MyStatementCard statement={shown} /> : null}
        {statements.length > 1 ? (
          <section className="space-y-2" data-testid="my-pay-history">
            <h2 className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{t("earlierPeriods")}</h2>
            <ul className="overflow-hidden rounded-[1.6rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
              {statements
                .filter((statement) => statement.id !== shown?.id)
                .map((statement) => (
                  <li key={statement.id} className="border-b last:border-b-0" style={{ borderColor: "var(--border)" }}>
                    <PeriodLink statement={statement} onOpen={() => setOpenId(statement.id)} />
                  </li>
                ))}
            </ul>
          </section>
        ) : null}
        <p className="text-xs" style={{ color: "var(--dim)" }}>{t("myPayNote")}</p>
      </div>
    </main>
  );
}

function PeriodLink({ statement, onOpen }: { statement: MyStatement; onOpen: () => void }) {
  const locale = useUiLocale();
  const period = periodOf(statement);
  const money = useMoney(period.currency);
  return (
    <button type="button" className="flex w-full items-center gap-3 px-4 py-3 text-start" onClick={onOpen} data-testid="my-pay-period">
      <span className="min-w-0 flex-1 font-semibold" style={{ color: "var(--text)" }}>{periodLabel(period.starts_on, period.ends_on, locale)}</span>
      <span className="text-sm font-semibold tabular-nums" style={{ color: "var(--text)" }}>{money(statement.total_cents)}</span>
      <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
    </button>
  );
}

function MyStatementCard({ statement }: { statement: MyStatement }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? "";
  const period = periodOf(statement);
  const money = useMoney(period.currency);
  const pdf = useMutation({
    mutationFn: () => fetchMyPayslipPdf(token, period.id, payslipLanguage(locale)),
    onSuccess: (blob) => saveFile(blob, payFileName("pay-statement", period, "pdf")),
  });
  return (
    <section className="space-y-3 rounded-[1.6rem] p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="my-pay-statement">
      <p className="text-xs font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>
        {t("myPayEyebrow", { period: periodLabel(period.starts_on, period.ends_on, locale), status: t(`status_${period.status}`) })}
      </p>
      <p className="text-3xl font-semibold tabular-nums" style={{ color: "var(--text)" }} data-testid="my-pay-total">{money(statement.total_cents)}</p>
      <StatementLines period={period} statement={statement} editable={false} />
      <p className="border-t pt-3 text-sm font-semibold" style={{ borderColor: "var(--border)", color: "var(--text)" }}>
        <GrossNet gross={statement.gross_cents} net={statement.net_cents} currency={period.currency} testId="my-pay-gross-net" />
      </p>
      <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} disabled={pdf.isPending} onClick={() => pdf.mutate()} data-testid="my-pay-pdf">
        {t("payslipPdf")}
      </button>
      {pdf.isError ? <ErrorNotice variant="field">{localizeError(pdf.error, ui)}</ErrorNotice> : null}
    </section>
  );
}

/** The staff home card: shown only once there is a statement to see. */
export function MyPayCard() {
  const t = useTranslations("CoachPay");
  const organizationSlug = useOrganizationSlug();
  const query = useMyPay();
  const latest = (query.data?.statements ?? []).find((statement) => statement.period);
  const period = latest ? periodOf(latest) : null;
  const locale = useUiLocale();
  const money = useMoney(period?.currency ?? "EUR");
  if (!latest || !period) return null;
  return (
    <DashboardCard id="home-my-pay" eyebrow={t("myPayTitle")}>
      <Link href={adminHref("/admin/my-pay", organizationSlug)} className="flex items-center gap-3" data-testid="my-pay-card">
        <span className="min-w-0 flex-1 text-sm" style={{ color: "var(--text-soft)" }}>{periodLabel(period.starts_on, period.ends_on, locale)}</span>
        <span className="font-semibold tabular-nums" style={{ color: "var(--text)" }}>{money(latest.total_cents)}</span>
        <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
      </Link>
    </DashboardCard>
  );
}
