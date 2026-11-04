"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState } from "react";

import {
  approvePayPeriod,
  calculatePayPeriod,
  coachPayKeys,
  createPayPeriod,
  deletePayAdjustment,
  exportPayPeriod,
  fetchPayPeriod,
  fetchPayPeriods,
  fetchPayslipPdf,
  restorePayItem,
  setPayLineBasis,
  type PayLine,
  type PayPeriod,
  type PayPeriodStatus,
  type PayStatement,
} from "@/api/coach-pay";

import { useSession } from "@/components/session-provider";
import { DateInput } from "@/components/ui/DateInput";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { MoreMenu } from "@/components/ui/MoreMenu";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { fieldBorder } from "@/lib/form-errors";

import { groupKeyOf, groupSentence, payFileName, payslipLanguage, isManual, isNet, nextPeriodRange, periodLabel, periodRangeError, primaryAction } from "./coach-pay";
import { PayLineDialog, ReopenDialog } from "./PayLineDialog";
import { FormRow, GrossNet, Initials, NetMark, controlClass, controlStyle, saveFile, useGymToday, useMoney, usePercent } from "./pay-ui";
import { BackButton } from "@/components/ui/BackLink";

const STATUS_TONE: Record<PayPeriodStatus, string> = { draft: "--primary", approved: "--success", exported: "--info" };

export function StatusPill({ status }: { status: PayPeriodStatus }) {
  const t = useTranslations("CoachPay");
  const tone = STATUS_TONE[status];
  return (
    <span
      className="inline-flex shrink-0 items-center rounded-full px-2.5 py-0.5 text-xs font-semibold"
      style={{ background: `color-mix(in srgb, var(${tone}) 12%, transparent)`, color: `var(${tone})`, border: `1px solid var(${tone})` }}
      data-testid="pay-period-status"
    >
      {t(`status_${status}`)}
    </span>
  );
}

/**
 * Οικονομικά › Αμοιβές coaches › Περίοδοι (mockup W1 s5, option A): the
 * periods newest first, each with «Μικτά · Καθαρά»; a period opens into its
 * statements. «Νέα περίοδος» suggests the next month.
 */
export function PayPeriodsView({ canEdit }: { canEdit: boolean }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? "";
  const [openId, setOpenId] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  const query = useQuery({ queryKey: coachPayKeys.periods, enabled: Boolean(token), queryFn: () => fetchPayPeriods(token) });

  if (openId) return <PayPeriodDetail periodId={openId} canEdit={canEdit} onBack={() => setOpenId(null)} />;
  if (query.isLoading) return <p className="text-sm" style={{ color: "var(--dim)" }}>{ui("loading33ce417")}</p>;
  if (query.isError) return <ErrorNotice>{localizeError(query.error, ui)}</ErrorNotice>;
  const periods = query.data?.periods ?? [];

  return (
    <section className="space-y-3" data-testid="pay-periods">
      {canEdit ? (
        <div className="flex justify-end">
          <button
            type="button"
            className="rounded-full px-4 py-2 text-sm font-semibold"
            style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
            onClick={() => setCreating(true)}
            data-testid="pay-new-period"
          >
            {t("newPeriod")}
          </button>
        </div>
      ) : null}
      <div className="overflow-hidden rounded-[1.6rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {periods.length === 0 ? <p className="p-5 text-sm" style={{ color: "var(--dim)" }}>{t("noPeriods")}</p> : null}
        <ul>
          {periods.map((period) => (
            <li key={period.id} className="border-b last:border-b-0" style={{ borderColor: "var(--border)" }}>
              <button type="button" className="flex w-full flex-wrap items-center gap-3 px-4 py-3 text-start" onClick={() => setOpenId(period.id)} data-testid="pay-period-row">
                <span className="min-w-0 flex-1 font-semibold" style={{ color: "var(--text)" }}>{periodLabel(period.starts_on, period.ends_on, locale)}</span>
                <StatusPill status={period.status} />
                <span className="text-sm" style={{ color: "var(--text-soft)" }}>
                  <GrossNet gross={period.gross_cents} net={period.net_cents} currency={period.currency} />
                </span>
              </button>
            </li>
          ))}
        </ul>
      </div>
      {creating ? <NewPeriodDialog periods={periods} onClose={() => setCreating(false)} onCreated={(id) => { setCreating(false); setOpenId(id); }} /> : null}
    </section>
  );
}

function NewPeriodDialog({ periods, onClose, onCreated }: { periods: Array<{ ends_on: string }>; onClose: () => void; onCreated: (id: string) => void }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const token = useSession().tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const today = useGymToday();
  const ids = useId();
  const [range, setRange] = useState(() => nextPeriodRange(periods, today));
  const [checked, setChecked] = useState(false);
  const create = useMutation({
    mutationFn: () => createPayPeriod(token, { starts_on: range.startsOn, ends_on: range.endsOn }),
    onSuccess: async ({ period }) => {
      await queryClient.invalidateQueries({ queryKey: coachPayKeys.periods });
      onCreated(period.id);
    },
  });
  const rangeError = checked ? periodRangeError(range.startsOn, range.endsOn) : null;
  const message = rangeError ? t(rangeError) : null;
  return (
    <Dialog
      onClose={onClose}
      title={t("newPeriod")}
      size="sm"
      variant="center"
      testId="pay-new-period-dialog"
      onSubmit={(event) => {
        event.preventDefault();
        setChecked(true);
        if (periodRangeError(range.startsOn, range.endsOn)) return;
        create.mutate();
      }}
      error={create.isError ? <ErrorNotice variant="field">{localizeError(create.error, ui)}</ErrorNotice> : null}
      footer={
        <>
          <DialogButton tone="ghost" onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton type="submit" tone="primary" disabled={create.isPending} testId="pay-new-period-create">
            {t("createPeriod")}
          </DialogButton>
        </>
      }
    >
      <div className="grid gap-4 sm:grid-cols-2">
        <FormRow label={t("from")}>
          <DateInput aria-label={t("from")} className={controlClass} style={{ ...controlStyle, border: fieldBorder(message) }} value={range.startsOn} onValueChange={(startsOn) => setRange({ ...range, startsOn })} />
        </FormRow>
        <FormRow label={t("until")} error={message} errorId={`${ids}-range-error`}>
          <DateInput aria-label={t("until")} className={controlClass} style={{ ...controlStyle, border: fieldBorder(message) }} value={range.endsOn} onValueChange={(endsOn) => setRange({ ...range, endsOn })} />
        </FormRow>
      </div>
      <p className="mt-3 text-xs" style={{ color: "var(--dim)" }}>{t("periodHint")}</p>
    </Dialog>
  );
}

/**
 * One period (mockup s5 A): one primary button per status (Έγκριση, then
 * Εξαγωγή CSV), «Υπολογισμός» and «Άνοιγμα ξανά» beside it, and each
 * person's statement opening into its lines. Net lines carry «Καθαρά»; a
 * clawback reads red. Statements are internal, never fiscal documents.
 */
export function PayPeriodDetail({ periodId, canEdit, onBack }: { periodId: string; canEdit: boolean; onBack: () => void }) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const [open, setOpen] = useState<string | null>(null);
  const [adding, setAdding] = useState<PayStatement | null>(null);
  const [reopening, setReopening] = useState(false);
  const [notice, setNotice] = useState<string | null>(null);

  const query = useQuery({ queryKey: coachPayKeys.period(periodId), enabled: Boolean(token), queryFn: () => fetchPayPeriod(token, periodId) });
  const store = ({ period }: { period: PayPeriod }) => {
    queryClient.setQueryData(coachPayKeys.period(periodId), { period });
    void queryClient.invalidateQueries({ queryKey: coachPayKeys.periods });
  };
  const calculate = useMutation({ mutationFn: () => calculatePayPeriod(token, periodId), onSuccess: (data) => { store(data); setNotice(t("calculated")); } });
  const approve = useMutation({ mutationFn: () => approvePayPeriod(token, periodId), onSuccess: (data) => { store(data); setNotice(null); } });
  const exportCsv = useMutation({
    mutationFn: () => exportPayPeriod(token, periodId),
    onSuccess: async (blob) => {
      const period = query.data?.period;
      if (period) saveFile(blob, payFileName("coach-pay", period, "csv"));
      await queryClient.invalidateQueries({ queryKey: coachPayKeys.period(periodId) });
      void queryClient.invalidateQueries({ queryKey: coachPayKeys.periods });
    },
  });
  const anyError = calculate.error ?? approve.error ?? exportCsv.error;

  if (query.isLoading) return <p className="text-sm" style={{ color: "var(--dim)" }}>{ui("loading33ce417")}</p>;
  if (query.isError || !query.data) return <ErrorNotice>{localizeError(query.error, ui)}</ErrorNotice>;
  const period = query.data.period;
  const statements = period.statements ?? [];
  const action = primaryAction(period.status, canEdit);
  const busy = calculate.isPending || approve.isPending || exportCsv.isPending;

  return (
    <section className="space-y-4" data-testid="pay-period">
      <BackButton onClick={onBack}>{t("periods")}</BackButton>
      <div className="flex flex-wrap items-center gap-3">
        <h3 className="text-xl font-semibold" style={{ color: "var(--text)" }}>{periodLabel(period.starts_on, period.ends_on, locale)}</h3>
        <StatusPill status={period.status} />
        <span className="flex-1" />
        {canEdit && period.status === "draft" ? (
          <button type="button" disabled={busy} className="rounded-full px-4 py-2 text-sm font-semibold" style={{ border: "1px solid var(--border)", color: "var(--text)" }} onClick={() => calculate.mutate()} data-testid="pay-calculate">
            {t("calculate")}
          </button>
        ) : null}
        {canEdit && period.status === "approved" ? (
          <button type="button" className="px-2 py-2 text-sm font-semibold" style={{ color: "var(--text-soft)" }} onClick={() => setReopening(true)} data-testid="pay-reopen">
            {t("reopen")}
          </button>
        ) : null}
        {action === "approve" ? (
          <button type="button" disabled={busy || statements.length === 0} className="rounded-full px-5 py-2 text-sm font-semibold disabled:opacity-50" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} onClick={() => approve.mutate()} data-testid="pay-approve">
            {t("approve")}
          </button>
        ) : null}
        {action === "export" ? (
          <button type="button" disabled={busy} className="rounded-full px-5 py-2 text-sm font-semibold" style={{ background: "var(--primary)", color: "var(--primary-contrast)" }} onClick={() => exportCsv.mutate()} data-testid="pay-export">
            {t("exportCsv")}
          </button>
        ) : null}
        {period.status === "exported" ? <span className="text-sm" style={{ color: "var(--dim)" }}>{t("lockedExported")}</span> : null}
      </div>

      {notice ? <p role="status" className="text-sm" style={{ color: "var(--success)" }}>{notice}</p> : null}
      {anyError ? <ErrorNotice>{localizeError(anyError, ui)}</ErrorNotice> : null}
      {period.reopen_reason && period.status === "draft" ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("reopenedBecause", { reason: period.reopen_reason })}</p>
      ) : null}

      <div className="flex flex-wrap gap-3">
        <div className="rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-lg font-semibold" style={{ color: "var(--text)" }}>
            <GrossNet gross={period.gross_cents} net={period.net_cents} currency={period.currency} testId="pay-period-total" />
          </p>
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("periodTotal")}</p>
        </div>
        <div className="rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
          <p className="text-lg font-semibold" style={{ color: "var(--text)" }}>{statements.length}</p>
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("peopleCount", { count: statements.length })}</p>
        </div>
      </div>

      <div className="overflow-hidden rounded-[1.6rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {statements.length === 0 ? <p className="p-5 text-sm" style={{ color: "var(--dim)" }}>{period.calculated_at ? t("noStatements") : t("notCalculated")}</p> : null}
        <ul>
          {statements.map((statement) => (
            <li key={statement.id} className="border-b last:border-b-0" style={{ borderColor: "var(--border)" }} data-testid="pay-statement">
              <StatementRow
                period={period}
                statement={statement}
                open={open === statement.id}
                canEdit={canEdit}
                onToggle={() => setOpen(open === statement.id ? null : statement.id)}
                onAdd={() => setAdding(statement)}
              />
            </li>
          ))}
        </ul>
      </div>

      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("notFiscal")}</p>

      {adding ? <PayLineDialog period={period} userId={adding.coach_user_id} name={adding.coach_name || t("unnamed")} onClose={() => setAdding(null)} /> : null}
      {reopening ? <ReopenDialog period={period} onClose={() => setReopening(false)} /> : null}
    </section>
  );
}

function StatementRow({
  period,
  statement,
  open,
  canEdit,
  onToggle,
  onAdd,
}: {
  period: PayPeriod;
  statement: PayStatement;
  open: boolean;
  canEdit: boolean;
  onToggle: () => void;
  onAdd: () => void;
}) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? "";
  const name = statement.coach_name || t("unnamed");
  const locked = period.status !== "draft";
  const pdf = useMutation({
    mutationFn: () => fetchPayslipPdf(token, period.id, statement.coach_user_id, payslipLanguage(locale)),
    onSuccess: (blob) => saveFile(blob, payFileName("pay-statement", period, "pdf")),
  });
  return (
    <div>
      <button type="button" aria-expanded={open} className="flex w-full items-center gap-3 px-4 py-3 text-start" onClick={onToggle} data-testid="pay-statement-toggle">
        <Initials name={name} />
        <span className="min-w-0 flex-1">
          <span className="block font-semibold" style={{ color: "var(--text)" }}>{name}</span>
          {statement.net_line_count > 0 ? <span className="text-xs" style={{ color: "var(--info)" }}>{t("netLines", { count: statement.net_line_count })}</span> : null}
        </span>
        <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
          <GrossNet gross={statement.gross_cents} net={statement.net_cents} currency={period.currency} />
        </span>
      </button>
      {open ? (
        <div className="space-y-2 px-4 pb-4 sm:ps-[4.25rem]">
          <StatementLines period={period} statement={statement} editable={canEdit && !locked} />
          <div className="flex flex-wrap items-center gap-3 pt-1">
            {canEdit && !locked ? (
              <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} onClick={onAdd} data-testid="pay-add-line">
                + {t("addLine")}
              </button>
            ) : null}
            {locked ? (
              <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} disabled={pdf.isPending} onClick={() => pdf.mutate()} data-testid="pay-payslip">
                {t("payslipPdf")}
              </button>
            ) : null}
          </div>
          {pdf.isError ? <ErrorNotice variant="field">{localizeError(pdf.error, ui)}</ErrorNotice> : null}
        </div>
      ) : null}
    </div>
  );
}

/** The groups of a statement (each rule or item with its terms), then the lines added by hand with their notes. */
export function StatementLines({
  period,
  statement,
  editable,
}: {
  period: Pick<PayPeriod, "id" | "currency"> & Partial<Pick<PayPeriod, "item_skips">>;
  statement: Pick<PayStatement, "groups" | "lines"> & Partial<Pick<PayStatement, "coach_user_id">>;
  editable: boolean;
}) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const token = useSession().tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const money = useMoney(period.currency);
  const percent = usePercent();
  const store = ({ period: next }: { period: PayPeriod }) => {
    queryClient.setQueryData(coachPayKeys.period(period.id), { period: next });
    void queryClient.invalidateQueries({ queryKey: coachPayKeys.periods });
  };
  const basis = useMutation({ mutationFn: (line: PayLine) => setPayLineBasis(token, period.id, line.id, isNet(line) ? "gross" : "net"), onSuccess: store });
  const remove = useMutation({ mutationFn: (line: PayLine) => deletePayAdjustment(token, period.id, line.id), onSuccess: store });
  const restore = useMutation({ mutationFn: (skipId: string) => restorePayItem(token, period.id, skipId), onSuccess: store });

  // ADR-510: lines added by hand (one-off overtime and allowances too) are
  // listed with their notes and can be removed; calculated ones are grouped.
  const calculated = statement.groups.filter((group) => !group.key.startsWith("manual:"));
  const manual = statement.lines.filter((line) => isManual(line));
  const groupLines = (key: string) => statement.lines.filter((line) => !isManual(line) && groupKeyOf(line) === key);
  const skipped = (Array.isArray(period.item_skips) ? period.item_skips : []).filter((skip) => skip.user_id === statement.coach_user_id);

  return (
    <div className="space-y-1.5" data-testid="pay-statement-lines">
      {calculated.map((group) => {
        const sentence = groupSentence(group, money, percent);
        const lines = groupLines(group.key);
        return (
          <div key={group.key} className="flex flex-wrap items-center gap-2 text-sm">
            <span className="min-w-0 flex-1" style={{ color: "var(--text-soft)" }}>{t(sentence.key, sentence.values)}</span>
            {group.amount_basis === "net" ? <NetMark /> : null}
            <span className="font-semibold tabular-nums" style={{ color: group.amount_cents < 0 ? "var(--danger)" : "var(--text)" }}>{money(group.amount_cents)}</span>
            {editable && lines.length > 0 ? (
              <MoreMenu
                label={t("lineActions")}
                items={[
                  {
                    label: group.amount_basis === "net" ? t("markGross") : t("markNet"),
                    onSelect: () => lines.forEach((line) => basis.mutate(line)),
                  },
                  // A recurring allowance can be taken off this person for this period (ADR-510).
                  ...(group.kind === "allowance" && lines[0]?.source_type === "pay_item"
                    ? [{ label: t("skipForPeriod"), tone: "danger" as const, onSelect: () => remove.mutate(lines[0]) }]
                    : []),
                ]}
              />
            ) : null}
          </div>
        );
      })}
      {manual.map((line) => (
        <div key={line.id} className="flex flex-wrap items-center gap-2 text-sm" data-testid="pay-manual-line">
          <span className="min-w-0 flex-1" style={{ color: "var(--text-soft)" }}>
            {t(`kind_${line.kind}`)}
            {["overtime", "allowance"].includes(line.kind) && line.description ? <span> · {line.description}</span> : null}
            {line.kind === "overtime" && line.quantity_divisor ? <span> · {t("hoursCount", { count: Math.round((line.quantity / line.quantity_divisor) * 100) / 100 })}</span> : null}
            {line.note ? <span style={{ color: "var(--dim)" }}> · {line.note}</span> : null}
          </span>
          {isNet(line) ? <NetMark /> : null}
          <span className="font-semibold tabular-nums" style={{ color: line.amount_cents < 0 ? "var(--danger)" : "var(--text)" }}>{money(line.amount_cents)}</span>
          {editable ? (
            <MoreMenu
              label={t("lineActions")}
              items={[
                { label: isNet(line) ? t("markGross") : t("markNet"), onSelect: () => basis.mutate(line) },
                { label: t("removeLine"), tone: "danger", onSelect: () => remove.mutate(line) },
              ]}
            />
          ) : null}
        </div>
      ))}
      {skipped.map((skip) => (
        <div key={skip.id} className="flex flex-wrap items-center gap-2 text-sm" data-testid="pay-skipped-item">
          <span className="min-w-0 flex-1" style={{ color: "var(--dim)" }}>{t("skippedThisPeriod", { name: skip.name ?? t("kind_allowance") })}</span>
          {editable ? (
            <button type="button" className="text-sm font-semibold" style={{ color: "var(--primary)" }} disabled={restore.isPending} onClick={() => restore.mutate(skip.id)} data-testid="pay-restore-item">
              {t("restoreItem")}
            </button>
          ) : null}
        </div>
      ))}
      {statement.groups.length === 0 && manual.length === 0 && skipped.length === 0 ? <p className="text-sm" style={{ color: "var(--dim)" }}>{t("noLines")}</p> : null}
      {basis.isError || remove.isError || restore.isError ? <ErrorNotice variant="field">{localizeError(basis.error ?? remove.error ?? restore.error, ui)}</ErrorNotice> : null}
    </div>
  );
}
