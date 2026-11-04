"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useState, type ReactNode } from "react";

import { ApiError } from "@/api/client";
import {
  addPayAdjustment,
  addPayItemLine,
  coachPayKeys,
  createPayItem,
  fetchPayItems,
  fetchPayPeople,
  fetchPayPeriods,
  type PayItem,
} from "@/api/coach-pay";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { fieldBorder, invalidFieldProps } from "@/lib/form-errors";

import {
  OTHER_AMOUNT,
  addableItems,
  defaultDraftPeriod,
  emptyOneOffDraft,
  oneOffErrors,
  oneOffItemBody,
  oneOffTotal,
  overtimeItems,
  parseCents,
  parseHours,
  periodLabel,
  type OneOffDraft,
  type OneOffField,
} from "./coach-pay";
import { FormRow, controlClass, controlStyle, useGymToday, useMoney } from "./pay-ui";

type Kind = PayItem["kind"];

/**
 * «Μία φορά» (ANR 2026-11-04, mockup B): overtime hours or an allowance for
 * one person in one open pay period. Only the rates that apply to the
 * person's roles are offered. «Άλλο ποσό» pays by hand; people who manage
 * settings can keep it as a rate for next time (a new overtime rate is
 * always kept, since overtime lines need one).
 */
export function OneOffLineForm({
  kind,
  title,
  header,
  canSaveRates,
  onAdded,
  onClose,
}: {
  kind: Kind;
  title: string;
  header: ReactNode;
  canSaveRates: boolean;
  onAdded?: (message: string) => void;
  onClose: () => void;
}) {
  const t = useTranslations("CoachPay");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? "";
  const queryClient = useQueryClient();
  const ids = useId();
  const today = useGymToday();

  const people = useQuery({ queryKey: coachPayKeys.people, enabled: Boolean(token), queryFn: () => fetchPayPeople(token) });
  const periods = useQuery({ queryKey: coachPayKeys.periods, enabled: Boolean(token), queryFn: () => fetchPayPeriods(token) });
  const items = useQuery({ queryKey: coachPayKeys.items, enabled: Boolean(token), queryFn: () => fetchPayItems(token) });

  const drafts = (periods.data?.periods ?? []).filter((period) => period.status === "draft");
  const [draft, setDraft] = useState<OneOffDraft>(emptyOneOffDraft);
  const [checked, setChecked] = useState(false);
  const periodId = draft.periodId || defaultDraftPeriod(drafts, today)?.id || "";
  const current = { ...draft, periodId };

  const person = (people.data?.people ?? []).find((entry) => entry.user_id === draft.userId) ?? null;
  const roles = person?.pay_roles ?? [];
  const rates = kind === "overtime" ? overtimeItems(items.data?.items ?? [], roles) : addableItems(items.data?.items ?? [], roles);
  // With no saved rate for the person, the form starts on a new amount.
  const itemId = current.itemId || (person && rates.length === 0 ? OTHER_AMOUNT : rates.length === 1 ? rates[0].id : "");
  const filled = { ...current, itemId };
  const item = rates.find((entry) => entry.id === itemId) ?? null;
  const other = itemId === OTHER_AMOUNT;
  const newOvertimeRate = kind === "overtime" && other;
  const blocked = newOvertimeRate && !canSaveRates;
  const period = drafts.find((entry) => entry.id === periodId) ?? null;
  const money = useMoney(period?.currency ?? "EUR");
  const total = oneOffTotal(kind, filled, item);

  const save = useMutation({
    mutationFn: async () => {
      const keep = other && (kind === "overtime" || filled.keep);
      let rate = item;
      if (keep) rate = (await createPayItem(token, oneOffItemBody(kind, filled, roles))).item;
      const note = filled.note.trim() || null;
      if (kind === "overtime") {
        const typed = filled.rate.trim() === "" ? null : parseCents(filled.rate);
        return addPayItemLine(token, periodId, {
          user_id: filled.userId,
          pay_item_id: rate!.id,
          minutes: parseHours(filled.hours) ?? 0,
          ...(typed !== null && typed !== rate!.amount_cents ? { unit_cents: typed } : {}),
          note,
        });
      }
      if (rate && keep) return addPayItemLine(token, periodId, { user_id: filled.userId, pay_item_id: rate.id, quantity: 1, note });
      if (rate) return addPayItemLine(token, periodId, { user_id: filled.userId, pay_item_id: rate.id, quantity: Number(filled.quantity), note });
      return addPayAdjustment(token, periodId, { coach_user_id: filled.userId, kind: "ad_hoc", amount_cents: parseCents(filled.amount) ?? 0, note: filled.note.trim() });
    },
    onSuccess: ({ period: next }) => {
      queryClient.setQueryData(coachPayKeys.period(next.id), { period: next });
      void queryClient.invalidateQueries({ queryKey: coachPayKeys.periods });
      void queryClient.invalidateQueries({ queryKey: coachPayKeys.items });
      onAdded?.(
        t("oneOffAdded", {
          name: person?.name || t("unnamed"),
          period: periodLabel(next.starts_on, next.ends_on, locale),
          amount: total === null ? "" : money(total),
        }),
      );
      onClose();
    },
  });

  const errors = checked ? oneOffErrors(kind, filled, item) : {};
  const serverFields = save.error instanceof ApiError ? (save.error.payload.errors ?? {}) : {};
  const apiKey: Partial<Record<OneOffField, string>> = { userId: "user_id", itemId: "pay_item_id", hours: "minutes", rate: "unit_cents", quantity: "quantity", amount: "amount_cents", note: "note", name: "name" };
  const message = (field: OneOffField) => (errors[field] ? t(errors[field]!) : apiKey[field] && apiKey[field]! in serverFields ? localizeError(save.error, ui) : null);
  const formError = save.error && Object.keys(serverFields).length === 0 ? localizeError(save.error, ui) : null;
  const errorIdOf = (field: OneOffField) => [ids, field, "error"].join("-");
  const update = (patch: Partial<OneOffDraft>) => setDraft({ ...current, ...patch });
  const input = (field: OneOffField, value: string, onChange: (value: string) => void, extra: { inputMode?: "decimal" | "numeric"; placeholder?: string; narrow?: boolean; testId?: string } = {}) => (
    <input
      id={`${ids}-${field}`}
      inputMode={extra.inputMode}
      className={controlClass + (extra.narrow ? " max-w-[10rem]" : "")}
      style={{ ...controlStyle, border: fieldBorder(message(field)) }}
      placeholder={extra.placeholder}
      value={value}
      onChange={(event) => onChange(event.target.value)}
      data-testid={extra.testId}
      {...invalidFieldProps(message(field), errorIdOf(field))}
    />
  );

  return (
    <Dialog
      onClose={onClose}
      title={title}
      size="md"
      variant="center"
      dismissible={!save.isPending}
      testId="pay-item-dialog"
      onSubmit={(event) => {
        event.preventDefault();
        setChecked(true);
        if (blocked || Object.keys(oneOffErrors(kind, filled, item)).length > 0) return;
        save.mutate();
      }}
      error={formError ? <ErrorNotice variant="field">{formError}</ErrorNotice> : null}
      footer={
        <>
          <DialogButton tone="ghost" onClick={onClose}>{t("cancel")}</DialogButton>
          <DialogButton type="submit" tone="primary" disabled={save.isPending || blocked || drafts.length === 0} testId="pay-item-save">
            {t("addToPeriod")}
          </DialogButton>
        </>
      }
    >
      <div className="space-y-4">
        {header}
        <p className="rounded-xl px-3 py-2 text-xs" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }} data-testid="pay-item-explain">
          {t(`explain_${kind}_oneOff`)}
        </p>
        {periods.isSuccess && drafts.length === 0 ? (
          <ErrorNotice variant="field">{t("noOpenPeriod")}</ErrorNotice>
        ) : null}
        <div className="grid gap-3 sm:grid-cols-2">
          <FormRow label={t("person")} error={message("userId")} errorId={`${ids}-userId-error`}>
            <Select
              aria-label={t("person")}
              className={controlClass}
              style={{ ...controlStyle, border: fieldBorder(message("userId")) }}
              value={filled.userId}
              onValueChange={(userId) => setDraft({ ...current, userId, itemId: "" })}
              data-testid="pay-oneoff-person"
              {...invalidFieldProps(message("userId"), `${ids}-userId-error`)}
            >
              <option value="">{t("pickPerson")}</option>
              {(people.data?.people ?? []).map((entry) => (
                <option key={entry.user_id} value={entry.user_id}>
                  {entry.name || t("unnamed")}
                </option>
              ))}
            </Select>
          </FormRow>
          <FormRow label={t("payPeriod")} hint={t("payPeriodHint")} error={message("periodId")} errorId={`${ids}-periodId-error`}>
            <Select
              aria-label={t("payPeriod")}
              className={controlClass}
              style={{ ...controlStyle, border: fieldBorder(message("periodId")) }}
              value={periodId}
              onValueChange={(value) => update({ periodId: value })}
              data-testid="pay-oneoff-period"
              {...invalidFieldProps(message("periodId"), `${ids}-periodId-error`)}
            >
              <option value="">{t("pickPeriod")}</option>
              {drafts.map((entry) => (
                <option key={entry.id} value={entry.id}>
                  {periodLabel(entry.starts_on, entry.ends_on, locale)}
                </option>
              ))}
            </Select>
          </FormRow>
        </div>

        {person ? (
          <FormRow label={kind === "overtime" ? t("overtimeRate") : t("allowance")} error={message("itemId")} errorId={`${ids}-itemId-error`}>
            <Select
              aria-label={kind === "overtime" ? t("overtimeRate") : t("allowance")}
              className={controlClass}
              style={{ ...controlStyle, border: fieldBorder(message("itemId")) }}
              value={itemId}
              onValueChange={(value) => update({ itemId: value, rate: "" })}
              data-testid="pay-oneoff-item"
              {...invalidFieldProps(message("itemId"), `${ids}-itemId-error`)}
            >
              <option value="">{kind === "overtime" ? t("pickOvertime") : t("pickAllowance")}</option>
              {rates.map((entry) => (
                <option key={entry.id} value={entry.id}>
                  {kind === "overtime" ? `${entry.name} · ${t("perHourAmount", { amount: money(entry.amount_cents) })}` : `${entry.name} · ${money(entry.amount_cents)}`}
                </option>
              ))}
              <option value={OTHER_AMOUNT}>{kind === "overtime" ? t("newRate") : t("otherAmount")}</option>
            </Select>
          </FormRow>
        ) : null}

        {person && blocked ? <ErrorNotice variant="field">{t("noOvertimeRate")}</ErrorNotice> : null}

        {person && kind === "overtime" && !blocked ? (
          <>
            {newOvertimeRate ? (
              <FormRow label={t("itemName")} htmlFor={`${ids}-name`} hint={t("newRateKept")} error={message("name")} errorId={`${ids}-name-error`}>
                {input("name", filled.name, (name) => update({ name }), { placeholder: t("itemNamePlaceholder_overtime") })}
              </FormRow>
            ) : null}
            <div className="grid grid-cols-2 gap-3">
              <FormRow label={t("hours")} htmlFor={`${ids}-hours`} hint={t("hoursHint")} error={message("hours")} errorId={`${ids}-hours-error`}>
                {input("hours", filled.hours, (hours) => update({ hours }), { inputMode: "decimal", testId: "pay-oneoff-hours" })}
              </FormRow>
              <FormRow label={t("ratePerHour")} htmlFor={`${ids}-rate`} error={message("rate")} errorId={`${ids}-rate-error`}>
                {input("rate", filled.rate, (rate) => update({ rate }), { inputMode: "decimal", placeholder: item ? (item.amount_cents / 100).toFixed(2) : undefined, testId: "pay-oneoff-rate" })}
              </FormRow>
            </div>
          </>
        ) : null}

        {person && kind === "allowance" && item?.unit === "per_occurrence" ? (
          <FormRow label={t("times")} htmlFor={`${ids}-quantity`} error={message("quantity")} errorId={`${ids}-quantity-error`}>
            {input("quantity", filled.quantity, (quantity) => update({ quantity }), { inputMode: "numeric", narrow: true })}
          </FormRow>
        ) : null}

        {person && kind === "allowance" && other ? (
          <>
            <FormRow label={t("amount")} htmlFor={`${ids}-amount`} error={message("amount")} errorId={`${ids}-amount-error`}>
              {input("amount", filled.amount, (amount) => update({ amount }), { inputMode: "decimal", narrow: true, testId: "pay-oneoff-amount" })}
            </FormRow>
            {canSaveRates ? (
              <label className="flex items-start gap-2 text-sm" style={{ color: "var(--text-soft)" }}>
                <input type="checkbox" className="mt-0.5" checked={filled.keep} onChange={(event) => update({ keep: event.target.checked })} data-testid="pay-oneoff-keep" />
                <span>{t("keepForNextTime")}</span>
              </label>
            ) : null}
            {filled.keep ? (
              <FormRow label={t("itemName")} htmlFor={`${ids}-name`} error={message("name")} errorId={`${ids}-name-error`}>
                {input("name", filled.name, (name) => update({ name }), { placeholder: t("itemNamePlaceholder_allowance") })}
              </FormRow>
            ) : null}
          </>
        ) : null}

        {person && !blocked ? (
          <FormRow
            label={kind === "overtime" || other ? t("noteRequired") : t("noteOptional")}
            htmlFor={`${ids}-note`}
            error={message("note")}
            errorId={`${ids}-note-error`}
          >
            {input("note", filled.note, (note) => update({ note }), { placeholder: t("notePlaceholder"), testId: "pay-oneoff-note" })}
          </FormRow>
        ) : null}

        {person && total !== null && period ? (
          <p className="flex justify-between gap-2 rounded-xl px-3 py-2 text-sm tabular-nums" style={{ background: "var(--panel-muted)", color: "var(--text)" }} data-testid="pay-oneoff-total">
            <span>{t("lineTotal")}</span>
            <span className="font-semibold">{money(total)}</span>
          </p>
        ) : null}
      </div>
    </Dialog>
  );
}
